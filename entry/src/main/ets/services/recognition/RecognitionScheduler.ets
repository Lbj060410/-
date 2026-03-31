/**
 * 代码指南：
 * 文件： services/recognition/RecognitionScheduler.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/RecognitionScheduler.ets
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap
import fs from '@ohos.file.fs'

import { RecogStore } from '../../state/RecogStore'
import { videoStore } from '../../state/VideoStore'
import { buildCameraSnapshotUrl } from '../../config/DeviceNetworkConfig'
import { HttpSnapshotService } from '../source/HttpSnapshotService'
import { CarProtocolService } from '../control/CarProtocolService'
import { RecognitionFactory } from './RecognitionFactory'
import { RecogEngineType } from './RecognitionConfig'
import { IRecognitionService } from './RecognitionService'
import { RecognitionCoreResult, RecognitionResult } from './RecognitionResult'
import { RecogStatus } from './RecognitionResult'
import {
  RecognitionInputType,
  RecognitionPriority,
  RecognitionStage,
  RecognitionSubtype,
  RecognitionTask,
  RecognitionTaskEvent,
  RecognitionTaskKind,
  RecognitionTaskRecord,
  RecognitionTaskSource,
  RecognitionTaskState,
  RoiNorm
} from './RecognitionTask'
import { RecognitionReportService } from './RecognitionReportService'
import { CarTaskSnapshotArchiveService } from './CarTaskSnapshotArchiveService'
import { replayArchiveService } from '../replay/ReplayArchiveService'

class CancelledError extends Error {
  constructor() {
    super('cancelled')
  }
}

class TimeoutError extends Error {
  constructor() {
    super('timeout')
  }
}

/**
 * Milestone 2：统一识别调度与任务队列
 * - LIVE：忙则丢，不排队
 * - SNAPSHOT：排队执行，支持优先级、取消/超时
 */
export class RecognitionScheduler {
  private store: RecogStore
  private service: IRecognitionService

  private readonly factory: RecognitionFactory = new RecognitionFactory()
  private readonly snapshot: HttpSnapshotService = new HttpSnapshotService()
  private readonly reporter: RecognitionReportService

  private enabled: boolean = false
  private inFlight: boolean = false
  private inFlightTaskId: string = ''
  private inFlightTaskToken: number = 0
  private runToken: number = 0

  private seq: number = 0

  // ===== LIVE 控制 =====
  private liveIntervalMs: number = 200
  private lastLiveStartAtMs: number = 0
  private liveEnabled: boolean = true
  private liveSubtype: RecognitionSubtype = RecognitionSubtype.OBSTACLE

  // ===== Queue =====
  private readonly queue: Array<RecognitionTask> = []
  private readonly cancelSet: Set<string> = new Set<string>()
  private readonly snapshotQueueMax: number = 24

  // ===== 统计（用于 Page4/Diagnostics）=====
  private lastCostMs: number = 0
  private fpsWindowStartMs: number = 0
  private processedInWindow: number = 0
  private fps: number = 0
  private processedFrames: number = 0
  private droppedLiveFrames: number = 0

  // ===== 引擎动态切换 =====
  private cachedEngineType: RecogEngineType
  private cachedHttpEndpoint: string
  private cachedOfflineModelName: string
  private cachedOfflineConfThresh: number
  private liveService?: IRecognitionService
  private liveServiceSubtype?: RecognitionSubtype
  private liveServiceConf: number = -1
  private liveServiceEngineType?: RecogEngineType
  private readonly carTaskArchive: CarTaskSnapshotArchiveService = new CarTaskSnapshotArchiveService()

  constructor(store: RecogStore, service: IRecognitionService) {
    this.store = store
    this.service = service

    this.cachedEngineType = store.recogEngineType
    this.cachedHttpEndpoint = store.recogHttpEndpoint
    this.cachedOfflineModelName = store.recogOfflineModelName
    this.cachedOfflineConfThresh = store.recogOfflineConfThresh

    this.reporter = new RecognitionReportService(store)
  }

  bindStore(store: RecogStore): void {
    this.store = store
  }

  bindProtocolService(proto: CarProtocolService): void {
    this.reporter.bindProtocolService(proto)
  }

  start(): void {
    this.enabled = true
    this.runToken += 1
    this.clearQueuedTasks()
    this.cancelSet.clear()

    this.fpsWindowStartMs = Date.now()
    this.processedInWindow = 0
    this.fps = 0
    this.processedFrames = 0
    this.droppedLiveFrames = 0
    this.lastCostMs = 0

    this.store.setRecogStatus(RecogStatus.RUNNING)
    this.syncStatToStore()
  }

  stop(): void {
    // ✅ 关键：切 token，杜绝 inFlight finally 后写 store
    this.runToken += 1
    this.enabled = false
    this.clearQueuedTasks()
    if (this.inFlightTaskId.length > 0) {
      this.cancelSet.add(this.inFlightTaskId)
    } else {
      this.cancelSet.clear()
    }

    this.store.setRecogStatus(RecogStatus.IDLE)
    this.store.setRecogText('recognition stopped')
    this.syncStatToStore()
  }

  isRunning(): boolean {
    return this.enabled
  }

  setLiveEnabled(enabled: boolean): void {
    this.liveEnabled = enabled
  }

  setLiveSubtype(subtype: RecognitionSubtype): void {
    this.liveSubtype = subtype
  }

  setLiveIntervalMs(ms: number): void {
    const v: number = Math.max(50, Math.min(5000, ms))
    this.liveIntervalMs = v
  }

  // 兼容旧接口：Milestone 1 的 RecognitionLoop.pushFrame
  pushFrame(pm: PixelMap): void {
    this.pushLiveFrame(pm, false)
  }

  /**
   * Page4 推入实时帧
   * - 忙则丢（不保留 pending、不排队）
   * - 若有 snapshot/autoSnapshot 队列，LIVE 直接让路
   */
  pushLiveFrame(pm: PixelMap, releaseAfterUse: boolean = false, subtype?: RecognitionSubtype): void {
    if (!this.enabled) {
      this.releaseLiveFrameIfOwned(pm, releaseAfterUse)
      return
    }
    if (!videoStore.recognitionEnabled) {
      this.releaseLiveFrameIfOwned(pm, releaseAfterUse)
      return
    }
    if (!this.liveEnabled) {
      this.releaseLiveFrameIfOwned(pm, releaseAfterUse)
      return
    }

    // Queue has snapshot work; drop this live frame.
    if (this.queue.length > 0) {
      this.dropLive('queue busy')
      this.releaseLiveFrameIfOwned(pm, releaseAfterUse)
      return
    }

    const now: number = Date.now()
    if (now - this.lastLiveStartAtMs < this.liveIntervalMs) {
      // 频率控制：丢
      this.dropLive('interval')
      this.releaseLiveFrameIfOwned(pm, releaseAfterUse)
      return
    }

    if (this.inFlight) {
      this.dropLive('inFlight')
      this.releaseLiveFrameIfOwned(pm, releaseAfterUse)
      return
    }

    this.lastLiveStartAtMs = now

    const id: string = this.nextId('live')
    const liveSubtype: RecognitionSubtype = (subtype !== undefined) ? subtype : this.liveSubtype
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.LIVE,
      subtype: liveSubtype,
      source: RecognitionTaskSource.PAGE4_LIVE, // LIVE 来自 Page4 常流
      priority: RecognitionPriority.LIVE,
      createdAtMs: now,
      timeoutMs: 1200,
      input: { type: RecognitionInputType.PIXEL_MAP, pixelMap: pm, releaseAfterUse }
    }

    // Keep a LIVE task record for diagnostics UI.
    this.store.addOrUpdateRecogTask(this.toRecordQueued(task))
    this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.START, 'LIVE start'))

    void this.runTask(task, this.runToken)
  }

  /**
   * Page2：手动触发一次 LIVE 任务（支持 subtype）
   * - 忙则丢（不排队）
   */
  enqueueLiveOnceFromPage2(pm: PixelMap, subtype: RecognitionSubtype, releaseAfterUse: boolean = false): string {
    if (!this.enabled) this.start()

    const id: string = this.nextId('live')
    const now: number = Date.now()
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.LIVE,
      subtype,
      source: RecognitionTaskSource.PAGE2_BUTTON,
      priority: RecognitionPriority.LIVE,
      createdAtMs: now,
      timeoutMs: 1200,
      input: { type: RecognitionInputType.PIXEL_MAP, pixelMap: pm, releaseAfterUse }
    }

    // SNAPSHOT 队列或引擎忙：LIVE 直接丢弃
    if (this.queue.length > 0 || this.inFlight) {
      this.store.addOrUpdateRecogTask(this.toRecordQueued(task))
      this.store.updateRecogTaskState(task.id, RecognitionTaskState.DROPPED, 'busy drop')
      this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.DONE, 'DROPPED'))
      this.dropLive('page2 live busy')
      if (releaseAfterUse) {
        try { pm.release() } catch (e) {}
      }
      return id
    }

    this.store.addOrUpdateRecogTask(this.toRecordQueued(task))
    this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.START, 'LIVE(page2) start'))

    void this.runTask(task, this.runToken)
    return id
  }

  /**
   * Page4：点击 bbox 触发一次 Snapshot 高精识别（带 ROI）
   * - 优先取 HTTP snapshot（更清晰）
   * - HTTP 不可达时 fallback 用传入的 live pixelMap
   */
  enqueueSnapshotFromTap(
    fallbackLivePm: PixelMap,
    roi: RoiNorm,
    subtype: RecognitionSubtype,
    source: RecognitionTaskSource = RecognitionTaskSource.PAGE4_TAP
  ): string {
    const id: string = this.nextId('snap')
    const url: string = this.buildHttpSnapshotUrl()
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype,
      source,
      priority: RecognitionPriority.SNAPSHOT,
      createdAtMs: Date.now(),
      timeoutMs: 6000,
      roi,
      input: { type: RecognitionInputType.HTTP_SNAPSHOT, httpUrl: url, pixelMap: fallbackLivePm }
    }
    this.enqueue(task, 'tap snapshot')
    return id
  }

  /**
   * Page2/图库：直接基于当前 PixelMap 进行 ROI 快照识别（不走 HTTP 抓拍）
   */
  enqueueSnapshotFromPixelMapWithRoi(
    pm: PixelMap,
    roi: RoiNorm,
    subtype: RecognitionSubtype,
    source: RecognitionTaskSource = RecognitionTaskSource.PAGE2_BUTTON,
    releaseAfterUse: boolean = false
  ): string {
    const id: string = this.nextId('snap')
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype,
      source,
      priority: RecognitionPriority.SNAPSHOT,
      createdAtMs: Date.now(),
      timeoutMs: 8000,
      roi,
      input: { type: RecognitionInputType.PIXEL_MAP, pixelMap: pm, releaseAfterUse }
    }
    this.enqueue(task, 'pixelmap roi snapshot')
    return id
  }

  /**
   * Page2：手动 Snapshot（最高优先级）
   */
  enqueueSnapshotFromPage2(subtype: RecognitionSubtype): string {
    const id: string = this.nextId('snap')
    const url: string = this.buildHttpSnapshotUrl()
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype,
      source: RecognitionTaskSource.PAGE2_BUTTON,
      priority: RecognitionPriority.SNAPSHOT,
      createdAtMs: Date.now(),
      timeoutMs: 6000,
      input: { type: RecognitionInputType.HTTP_SNAPSHOT, httpUrl: url }
    }
    this.enqueue(task, 'page2 snapshot')
    return id
  }

  /**
   * 指令常驻触发：AutoSnapshot（中优先级）
   * - 当前项目尚未绑定到具体车端协议；保留统一入口即可
   */
  enqueueAutoSnapshotTriggered(subtype: RecognitionSubtype): string {
    const id: string = this.nextId('auto')
    const url: string = this.buildHttpSnapshotUrl()
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype,
      source: RecognitionTaskSource.CAR_FRAME_TRIGGER,
      priority: RecognitionPriority.AUTO_SNAPSHOT,
      createdAtMs: Date.now(),
      timeoutMs: 6000,
      input: { type: RecognitionInputType.HTTP_SNAPSHOT, httpUrl: url }
    }
    this.enqueue(task, 'auto snapshot')
    return id
  }

  /**
   * 图库触发：把 PixelMap 直接作为输入（无需 HTTP）
   */
  enqueueSnapshotFromGallery(pm: PixelMap, subtype: RecognitionSubtype): string {
    const id: string = this.nextId('gal')
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype,
      source: RecognitionTaskSource.GALLERY,
      priority: RecognitionPriority.SNAPSHOT,
      createdAtMs: Date.now(),
      timeoutMs: 8000,
      input: { type: RecognitionInputType.PIXEL_MAP, pixelMap: pm }
    }
    this.enqueue(task, 'gallery snapshot')
    return id
  }

  enqueueSnapshotFromGalleryUri(uri: string, subtype: RecognitionSubtype): string {
    const id: string = this.nextId('gal')
    const task: RecognitionTask = {
      id,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype,
      source: RecognitionTaskSource.GALLERY,
      priority: RecognitionPriority.SNAPSHOT,
      createdAtMs: Date.now(),
      timeoutMs: 8000,
      input: { type: RecognitionInputType.GALLERY_URI, galleryUri: uri }
    }
    this.enqueue(task, 'gallery uri snapshot')
    return id
  }

  cancel(taskId: string): void {
    this.cancelSet.add(taskId)

    // queued：直接出队并标记取消
    const before: number = this.queue.length
    const next: Array<RecognitionTask> = []
    for (let i: number = 0; i < this.queue.length; i++) {
      const t: RecognitionTask = this.queue[i]
      if (t.id !== taskId) {
        next.push(t)
      } else {
        this.releaseTaskInputIfOwned(t)
      }
    }
    this.queue.length = 0
    for (let i: number = 0; i < next.length; i++) this.queue.push(next[i])

    const removed: boolean = (before !== this.queue.length)
    if (removed) {
      this.store.updateRecogTaskState(taskId, RecognitionTaskState.CANCELED, '用户取消（队列）')
      this.store.appendRecogEvent(this.toEvent(taskId, RecognitionStage.DONE, 'CANCELED (queued)'))
      this.cancelSet.delete(taskId)
    } else {
      // Running task: mark canceled and let in-flight cleanup finish.
      this.store.updateRecogTaskState(taskId, RecognitionTaskState.CANCELED, 'canceled (running)')
      this.store.appendRecogEvent(this.toEvent(taskId, RecognitionStage.DONE, 'CANCELED (running)'))
    }
  }

  // ===== 内部：入队 =====
  private enqueue(task: RecognitionTask, reason: string): void {
    if (!this.enabled) this.start()

    this.store.addOrUpdateRecogTask(this.toRecordQueued(task))
    this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.ENQUEUE, reason))

    if (task.kind === RecognitionTaskKind.SNAPSHOT) {
      const snapshotQueued: number = this.snapshotQueueSize()
      if (snapshotQueued >= this.snapshotQueueMax) {
        this.store.updateRecogTaskState(task.id, RecognitionTaskState.DROPPED, 'snapshot queue full')
        this.store.appendRecogEvent(
          this.toEvent(task.id, RecognitionStage.DONE, `DROPPED(queue full:${snapshotQueued}/${this.snapshotQueueMax})`)
        )
        this.releaseTaskInputIfOwned(task)
        return
      }
    }

    this.queue.push(task)
    this.sortQueue()

    this.pump()
  }

  private snapshotQueueSize(): number {
    let n: number = 0
    for (let i: number = 0; i < this.queue.length; i++) {
      if (this.queue[i].kind === RecognitionTaskKind.SNAPSHOT) {
        n += 1
      }
    }
    return n
  }

  private sortQueue(): void {
    this.queue.sort((a: RecognitionTask, b: RecognitionTask): number => {
      if (a.priority !== b.priority) return b.priority - a.priority
      return a.createdAtMs - b.createdAtMs
    })
  }

  private pump(): void {
    if (!this.enabled) return
    if (this.inFlight) return
    if (this.queue.length <= 0) return

    const task: RecognitionTask | undefined = this.queue.shift()
    if (!task) return

    void this.runTask(task, this.runToken)
  }

  private async runTask(task: RecognitionTask, token: number): Promise<void> {
    if (!this.enabled) return
    if (this.inFlight) return
    this.inFlight = true
    this.inFlightTaskId = task.id
    this.inFlightTaskToken = token

    const startAt: number = Date.now()
    this.store.updateRecogTaskState(task.id, RecognitionTaskState.RUNNING, '')
    this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.START, 'RUNNING'))

    // busy 标识：Page4 overlay/面板显示
    this.syncStatToStore()

    try {
      this.throwIfCancelled(task.id)
      await this.captureCarTaskSnapshot(task)

      const result: RecognitionResult = await this.withTimeout<RecognitionResult>(
        this.computeResult(task),
        task.timeoutMs
      )

      // stop() 后的 late result 不写 store
      if (token !== this.runToken) return
      if (!this.enabled) return

      const endAt: number = Date.now()
      const costMsTotal: number = endAt - startAt

      // Write task result back to store for Page2/diagnostics.
      this.store.updateRecogTaskResult(task.id, result, costMsTotal)
      const kindText: string = String(task.kind)
      const sourceText: string = String(task.source)
      const subtypeText: string = String(task.subtype)
      if (result.ok) {
        this.store.setRecogText(
          `ok k=${kindText} s=${sourceText} t=${subtypeText} engine=${result.engine} boxes=${result.boxes.length} cost=${result.costMs}ms`
        )
      } else {
        const failText: string = result.errorText.length > 0 ? result.errorText : '识别失败'
        this.store.setRecogText(`fail k=${kindText} s=${sourceText} t=${subtypeText} err=${failText}`)
      }

      // LIVE keeps lastRecog for overlays and fusion.
      if (task.kind === RecognitionTaskKind.LIVE) {
        if (result.ok) {
          this.store.setRecogResult(result)
          this.store.bumpRecogOk()
          replayArchiveService.onRecognition(result)
        } else {
          this.store.bumpRecogFail()
        }
        this.updateLiveStats(result.costMs)
      } else {
        // SNAPSHOT：保存最近一次（Page4 下方截图预览也会被更新）
        this.store.setLastSnapshotResult(result)
        if (result.ok) {
          replayArchiveService.onRecognition(result)
        }
      }

      // Optional: auto report should not break task flow.
      try {
        await this.reporter.maybeAutoReport(result)
      } catch (e) {
        void e
        // 回传失败不影响任务主流程
      }

      this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.DONE, result.ok ? 'SUCCESS' : 'FAILED'))
    } catch (e) {
      if (token !== this.runToken) return
      if (!this.enabled) return

      const endAt: number = Date.now()
      const costMsTotal: number = endAt - startAt

      if (e instanceof CancelledError) {
        this.store.updateRecogTaskState(task.id, RecognitionTaskState.CANCELED, '取消')
        this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.DONE, 'CANCELED'))
        this.store.setRecogText('任务已取消')
      } else if (e instanceof TimeoutError) {
        this.store.updateRecogTaskState(task.id, RecognitionTaskState.TIMEOUT, '超时')
        this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.DONE, 'TIMEOUT'))
        this.store.setRecogText('识别超时')
      } else {
        const msg: string = (e instanceof Error) ? e.message : '识别失败'
        this.store.updateRecogTaskState(task.id, RecognitionTaskState.FAILED, msg)
        this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.DONE, `FAILED: ${msg}`))
        this.store.setRecogText(msg)
      }

      // 失败也要记 cost
      this.store.updateRecogTaskCost(task.id, costMsTotal)
    } finally {
      this.cancelSet.delete(task.id)
      if (this.inFlightTaskId === task.id && this.inFlightTaskToken === token) {
        this.inFlight = false
        this.inFlightTaskId = ''
        this.inFlightTaskToken = 0
      }

      this.syncStatToStore()

      // Pull next queued task (including after token switch on stop/start).
      if (this.enabled) {
        this.pump()
      }
    }
  }

  private async computeResult(task: RecognitionTask): Promise<RecognitionResult> {
    this.throwIfCancelled(task.id)
    const inferService: IRecognitionService = this.resolveServiceForTask(task)

    let pm: PixelMap
    let releaseAfterUse: boolean = false
    let allowCropOnInput: boolean = true

    if (task.input.type === RecognitionInputType.HTTP_SNAPSHOT) {
      this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'HTTP snapshot fetch'))

      const url: string | undefined = task.input.httpUrl
      if (!url) {
        throw new Error('snapshot url empty')
      }

      try {
        const jpeg: ArrayBuffer = await this.snapshot.fetchJpeg(url, 2500)
        pm = await this.jpegToPixelMap(jpeg)
        videoStore.setSnapshot(pm)
      } catch (e) {
        const fallback: PixelMap | undefined = task.input.pixelMap
        if (!fallback) {
          const msg: string = (e instanceof Error) ? e.message : 'http snapshot failed'
          throw new Error(msg)
        }

        const copied: PixelMap | undefined = await this.clonePixelMap(fallback)
        if (copied) {
          pm = copied
          videoStore.setSnapshot(pm)
        } else {
          // Shared fallback frame cannot be safely mutated by ROI crop.
          pm = fallback
          allowCropOnInput = false
          this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'fallback shared frame'))
        }
      }
    } else if (task.input.type === RecognitionInputType.PIXEL_MAP) {
      const v: PixelMap | undefined = task.input.pixelMap
      if (!v) throw new Error('pixelMap undefined')
      pm = v
      releaseAfterUse = !!task.input.releaseAfterUse
    } else if (task.input.type === RecognitionInputType.GALLERY_URI) {
      const uri: string | undefined = task.input.galleryUri
      if (!uri || uri.trim().length <= 0) throw new Error('gallery uri empty')
      const one: PixelMap | undefined = await this.createPixelMapFromGalleryUri(uri)
      if (!one) throw new Error('gallery uri decode failed')
      pm = one
      videoStore.setSnapshot(pm)
    } else {
      throw new Error('unsupported input type')
    }

    try {
      this.throwIfCancelled(task.id)

      if (task.roi) {
        if (allowCropOnInput) {
          this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'crop ROI'))
          await this.cropPixelMapByRoi(pm, task.roi)
        } else {
          this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'skip ROI on shared frame'))
        }
      }

      this.throwIfCancelled(task.id)

      this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.INFER, `engine=${inferService.name}`))
      const core: RecognitionCoreResult = await inferService.recognize(pm)

      this.throwIfCancelled(task.id)

      const result: RecognitionResult = {
        taskId: task.id,
        kind: task.kind,
        subtype: task.subtype,
        source: task.source,
        roi: task.roi,
        tsMs: core.tsMs,
        costMs: core.costMs,
        engine: core.engine,
        boxes: core.boxes,
        texts: core.texts,
        ok: core.ok,
        errorText: core.errorText
      }
      return result
    } finally {
      if (releaseAfterUse) {
        try { pm.release() } catch (e) {}
      }
    }
  }

  private refreshServiceIfNeeded(): void {
    const t: RecogEngineType = this.store.recogEngineType
    const ep: string = this.store.recogHttpEndpoint
    const mn: string = this.store.recogOfflineModelName
    const cf: number = this.store.recogOfflineConfThresh

    if (t === this.cachedEngineType &&
      ep === this.cachedHttpEndpoint &&
      mn === this.cachedOfflineModelName &&
      cf === this.cachedOfflineConfThresh) return

    this.cachedEngineType = t
    this.cachedHttpEndpoint = ep
    this.cachedOfflineModelName = mn
    this.cachedOfflineConfThresh = cf

    const svc: IRecognitionService = this.factory.create({
      engineType: t,
      httpEndpoint: ep,
      offlineModelName: mn,
      offlineConfThresh: cf
    })
    this.service = svc
    this.store.setRecogText(`engine switched => ${svc.name}`)
  }

  private resolveServiceForTask(task: RecognitionTask): IRecognitionService {
    // 离线 NCNN：所有任务都按 subtype 选模型，避免 SNAPSHOT/GALLERY 误用默认模型。
    if (this.store.recogEngineType === RecogEngineType.OFFLINE_NCNN) {
      const subtype: RecognitionSubtype = task.subtype
      // Gallery/Snapshot 更容易出现漏检，单独使用更低阈值；实时流保持当前阈值。
      const defaultConf: number = this.store.recogOfflineConfThresh
      const conf: number = this.confForTask(task, defaultConf)
      const engineType: RecogEngineType = this.store.recogEngineType
      if (!this.liveService ||
        this.liveServiceSubtype !== subtype ||
        this.liveServiceConf !== conf ||
        this.liveServiceEngineType !== engineType) {
        this.liveService = this.factory.createForSubtype(subtype, conf, engineType)
        this.liveServiceSubtype = subtype
        this.liveServiceConf = conf
        this.liveServiceEngineType = engineType
      }
      return this.liveService
    }

    this.refreshServiceIfNeeded()
    return this.service
  }

  private confForTask(task: RecognitionTask, defaultConf: number): number {
    if (task.subtype === RecognitionSubtype.YOLOV26BARRIER &&
      task.kind === RecognitionTaskKind.SNAPSHOT &&
      (task.source === RecognitionTaskSource.GALLERY || task.source === RecognitionTaskSource.PAGE2_BUTTON)) {
      return Math.min(defaultConf, 0.12)
    }
    return defaultConf
  }

  private releaseLiveFrameIfOwned(pm: PixelMap, releaseAfterUse: boolean): void {
    if (!releaseAfterUse) return
    try { pm.release() } catch (e) {}
  }

  private releaseTaskInputIfOwned(task: RecognitionTask): void {
    if (task.input.type !== RecognitionInputType.PIXEL_MAP) return
    if (!task.input.releaseAfterUse) return
    const pm: PixelMap | undefined = task.input.pixelMap
    if (!pm) return
    task.input.pixelMap = undefined
    try { pm.release() } catch (_) {}
  }

  private clearQueuedTasks(): void {
    if (this.queue.length <= 0) return
    for (let i: number = 0; i < this.queue.length; i++) {
      this.releaseTaskInputIfOwned(this.queue[i])
    }
    this.queue.length = 0
  }

  private async captureCarTaskSnapshot(task: RecognitionTask): Promise<void> {
    if (task.source !== RecognitionTaskSource.CAR_FRAME_TRIGGER) return

    let snapPm: PixelMap | undefined = undefined
    const livePm: PixelMap | undefined = videoStore.livePixelMap
    if (livePm) {
      snapPm = await this.clonePixelMap(livePm)
      if (!snapPm) {
        this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'car snapshot clone failed'))
      }
    }

    if (!snapPm) {
      const url: string = this.buildHttpSnapshotUrl()
      try {
        const jpeg: ArrayBuffer = await this.snapshot.fetchJpeg(url, 1500)
        snapPm = await this.jpegToPixelMap(jpeg)
      } catch (e) {
        void e
      }
    }

    if (!snapPm) {
      this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'car snapshot unavailable'))
      return
    }

    try {
      const uri: string = await this.carTaskArchive.save(task.id, task.subtype, snapPm)
      if (uri.length > 0) {
        this.store.updateRecogTaskSnapshotUri(task.id, uri)
        this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'car snapshot saved'))
      } else {
        this.store.appendRecogEvent(this.toEvent(task.id, RecognitionStage.PREPROCESS, 'car snapshot save failed'))
      }
    } finally {
      try { snapPm.release() } catch (e) {}
    }
  }

  private throwIfCancelled(id: string): void {
    if (this.cancelSet.has(id)) throw new CancelledError()
  }

  private dropLive(reason: string): void {
    this.droppedLiveFrames += 1
    this.store.setRecogText(`LIVE dropped: ${reason}`)
    this.syncStatToStore()
  }

  private updateLiveStats(costMs: number): void {
    const now: number = Date.now()

    this.lastCostMs = costMs
    this.processedFrames += 1
    this.processedInWindow += 1

    if (now - this.fpsWindowStartMs >= 1000) {
      const seconds: number = (now - this.fpsWindowStartMs) / 1000.0
      this.fps = seconds > 0 ? Math.round(this.processedInWindow / seconds) : 0
      this.fpsWindowStartMs = now
      this.processedInWindow = 0
    }

    this.syncStatToStore()
  }

  private syncStatToStore(): void {
    this.store.setRecogStat(
      this.fps,
      this.lastCostMs,
      this.droppedLiveFrames,
      this.processedFrames,
      this.enabled && this.inFlight
    )
  }

  private nextId(prefix: string): string {
    this.seq += 1
    return `${prefix}-${Date.now()}-${this.seq}`
  }

  private toRecordQueued(task: RecognitionTask): RecognitionTaskRecord {
    const r: RecognitionTaskRecord = {
      id: task.id,
      kind: task.kind,
      subtype: task.subtype,
      source: task.source,
      priority: task.priority,
      state: RecognitionTaskState.QUEUED,
      createdAtMs: task.createdAtMs,
      startAtMs: 0,
      endAtMs: 0,
      timeoutMs: task.timeoutMs,
      roi: task.roi,
      engine: '-',
      costMs: 0,
      errorText: '',
      snapshotUri: '',
      result: undefined
    }
    return r
  }

  private toEvent(taskId: string, stage: RecognitionStage, text: string): RecognitionTaskEvent {
    return { tsMs: Date.now(), taskId, stage, text }
  }

  private buildHttpSnapshotUrl(): string {
    return buildCameraSnapshotUrl(videoStore.cameraHost, videoStore.cameraUser, videoStore.cameraPass)
  }

  private async jpegToPixelMap(jpeg: ArrayBuffer): Promise<PixelMap> {
    const src: image.ImageSource = image.createImageSource(jpeg)
    try {
      return await src.createPixelMap()
    } finally {
      try { src.release() } catch (e) {}
    }
  }

  private async clonePixelMap(pm: PixelMap): Promise<PixelMap | undefined> {
    const packer: image.ImagePacker = image.createImagePacker()
    try {
      const data: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 92 })
      return await this.jpegToPixelMap(data)
    } catch (e) {
      void e
      return undefined
    } finally {
      try { packer.release() } catch (e) {}
    }
  }

  /**
   * 使用 PixelMap.crop 进行 ROI 裁剪（API12+）
   * - 原地裁剪，会改变原 PixelMap
   */
  private async cropPixelMapByRoi(pm: PixelMap, roi: RoiNorm): Promise<void> {
    try {
      const info: image.ImageInfo = await pm.getImageInfo()
      const w: number = info.size.width
      const h: number = info.size.height

      const region: image.Region = this.roiToRegion(roi, w, h)
      await pm.crop(region)
    } catch (e) {
      void e
      // ROI crop failure should not block inference.
    }
  }

  private roiToRegion(roi: RoiNorm, imgW: number, imgH: number): image.Region {
    const x0: number = Math.max(0, Math.min(roi.x, 1))
    const y0: number = Math.max(0, Math.min(roi.y, 1))
    const x1: number = Math.max(0, Math.min(roi.x + roi.w, 1))
    const y1: number = Math.max(0, Math.min(roi.y + roi.h, 1))

    const px: number = Math.floor(x0 * imgW)
    const py: number = Math.floor(y0 * imgH)
    const pw: number = Math.max(1, Math.floor((x1 - x0) * imgW))
    const ph: number = Math.max(1, Math.floor((y1 - y0) * imgH))

    // 防止越界
    const safeW: number = Math.max(1, Math.min(pw, imgW - px))
    const safeH: number = Math.max(1, Math.min(ph, imgH - py))

    return {
      x: px,
      y: py,
      size: { width: safeW, height: safeH }
    }
  }

  private async withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
    const timeoutMs: number = Math.max(0, ms)
    if (timeoutMs <= 0) return await p

    return await new Promise<T>((resolve, reject) => {
      const id: number = setTimeout(() => {
        reject(new TimeoutError())
      }, timeoutMs) as number

      p.then((v: T) => {
        try { clearTimeout(id) } catch (e) {}
        resolve(v)
      }).catch((err: object) => {
        try { clearTimeout(id) } catch (e) {}
        reject(err)
      })
    })
  }

  private createImageSourceFromGalleryUri(uri: string): image.ImageSource | undefined {
    const raw: string = uri.trim()
    const noQuery: string = this.stripUriQuery(raw)
    if (raw.length <= 0) return undefined

    const candidates: Array<string> = []
    let firstErr: string = ''
    const pushUnique = (s: string): void => {
      const one: string = s.trim()
      if (one.length <= 0) return
      for (let i: number = 0; i < candidates.length; i++) {
        if (candidates[i] === one) return
      }
      candidates.push(one)
    }

    pushUnique(raw)
    pushUnique(noQuery)
    try { pushUnique(decodeURIComponent(raw)) } catch (_) {}
    try { pushUnique(decodeURIComponent(noQuery)) } catch (_) {}

    const lower: string = noQuery.toLowerCase()
    if (lower.startsWith('file://')) {
      const pathRaw: string = noQuery.substring('file://'.length)
      pushUnique(pathRaw)
      try { pushUnique(decodeURIComponent(pathRaw)) } catch (_) {}
    }

    for (let i: number = 0; i < candidates.length; i++) {
      try {
        const src: image.ImageSource = image.createImageSource(candidates[i])
        if (src) return src
      } catch (e) {
        if (firstErr.length <= 0) firstErr = this.errorToText(e)
      }
    }

    // Fallback: some gallery URIs cannot be passed to createImageSource directly.
    // Try open+read bytes and decode from ArrayBuffer.
    const maxBytes: number = 40 * 1024 * 1024
    for (let i: number = 0; i < candidates.length; i++) {
      let f: fs.File | undefined = undefined
      try {
        f = fs.openSync(candidates[i], fs.OpenMode.READ_ONLY)
        const st = fs.statSync(candidates[i])
        const size: number = Number(st.size)
        if (!Number.isFinite(size) || size <= 0 || size > maxBytes) continue
        const buf: ArrayBuffer = new ArrayBuffer(size)
        const readLen: number = fs.readSync(f.fd, buf)
        if (!Number.isFinite(readLen) || readLen <= 0) continue
        const bytes: ArrayBuffer = readLen === size ? buf : buf.slice(0, readLen)
        const src: image.ImageSource = image.createImageSource(bytes)
        if (src) return src
      } catch (e) {
        if (firstErr.length <= 0) firstErr = this.errorToText(e)
      } finally {
        if (f) {
          try { fs.closeSync(f.fd) } catch (_) {}
        }
      }
    }
    if (firstErr.length > 0) {
      throw new Error(`gallery uri decode failed: ${firstErr}`)
    }
    return undefined
  }

  private async createPixelMapFromGalleryUri(uri: string): Promise<PixelMap | undefined> {
    const raw: string = uri.trim()
    let f: fs.File | undefined = undefined
    let srcByFd: image.ImageSource | undefined = undefined
    try {
      f = fs.openSync(raw, fs.OpenMode.READ_ONLY)
      srcByFd = image.createImageSource(f.fd)
      if (srcByFd) {
        return await srcByFd.createPixelMap()
      }
    } catch (_) {
      // fallback below
    } finally {
      if (srcByFd) {
        try { srcByFd.release() } catch (_) {}
      }
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }

    const src: image.ImageSource | undefined = this.createImageSourceFromGalleryUri(uri)
    if (!src) return undefined
    try {
      return await src.createPixelMap()
    } finally {
      try { src.release() } catch (_) {}
    }
  }

  private stripUriQuery(uri: string): string {
    const qPos: number = uri.indexOf('?')
    const hPos: number = uri.indexOf('#')
    let end: number = uri.length
    if (qPos >= 0 && qPos < end) end = qPos
    if (hPos >= 0 && hPos < end) end = hPos
    return uri.substring(0, end)
  }

  private errorToText(e: Object): string {
    if (e instanceof Error) return e.message.length > 0 ? e.message : 'unknown error'
    try {
      const txt: string = JSON.stringify(e)
      return txt.length > 0 ? txt : 'unknown error'
    } catch (_) {
      return 'unknown error'
    }
  }
}
