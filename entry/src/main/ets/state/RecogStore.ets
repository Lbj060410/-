/**
 * 代码指南：
 * 文件： state/RecogStore.ets
 * 用途： 应用级共享状态/存储模块。
 * 何时修改： 新增跨页面状态或调整全局数据结构时。
 * 相关文件： 读写状态存储值的页面视图、协调器及各类服务。
 */
// entry/src/main/ets/state/RecogStore.ets
import { RecognitionResult } from '../services/recognition/RecognitionResult'
import { RecogStatus } from '../services/recognition/RecognitionResult'
import { RecognitionTaskEvent, RecognitionTaskRecord } from '../services/recognition/RecognitionTask'
import { RecognitionTaskState } from '../services/recognition/RecognitionTask'
import { RecogEngineType } from '../services/recognition/RecognitionConfig'

@Observed
export class RecogStore {
  // ==== 识别状态 ====
  recogStatus: RecogStatus = 0 as RecogStatus
  recogText: string = ''
  recogOk: number = 0
  recogFail: number = 0
  lastRecog?: RecognitionResult

  // ==== 识别统计 ====
  recogFps: number = 0
  recogLastCostMs: number = 0
  recogDroppedFrames: number = 0
  recogProcessedFrames: number = 0
  recogBusy: boolean = false

  // ==== Milestone 2：识别任务中枢（Page2） ====
  recogTasksMax: number = 30
  recogEventsMax: number = 200
  recogTasks: Array<RecognitionTaskRecord> = []
  recogEvents: Array<RecognitionTaskEvent> = []
  lastSnapshotRecog?: RecognitionResult

  // ==== 可选：统一结果回传开关 ====
  autoReportEnabled: boolean = true
  autoReportThreshold: number = 0.85

  // ==== 识别引擎选择 ====
  // 默认使用本地 NCNN，避免 page2 实时识别误走 HTTP 端点。
  recogEngineType: RecogEngineType = RecogEngineType.OFFLINE_NCNN
  recogHttpEndpoint: string = 'http://192.168.1.100:5000/detect'  // 修改为你的电脑IP
  recogOfflineModelName: string = 'barrier'
  recogOfflineConfThresh: number = 0.35  // 匹配安卓 MINIMUM_CONFIDENCE_TF_OD_API = 0.3

  setRecogStatus(s: RecogStatus): void { this.recogStatus = s }
  setRecogText(t: string): void { this.recogText = t }
  setRecogResult(r: RecognitionResult): void { this.lastRecog = r }
  bumpRecogOk(): void { this.recogOk += 1 }
  bumpRecogFail(): void { this.recogFail += 1 }

  setRecogStat(fps: number, lastCostMs: number, droppedFrames: number, processedFrames: number, busy: boolean): void {
    this.recogFps = fps
    this.recogLastCostMs = lastCostMs
    this.recogDroppedFrames = droppedFrames
    this.recogProcessedFrames = processedFrames
    this.recogBusy = busy
  }

  clearRecogStats(): void {
    this.recogOk = 0
    this.recogFail = 0
    this.recogText = ''
    this.lastRecog = undefined
    this.recogFps = 0
    this.recogLastCostMs = 0
    this.recogDroppedFrames = 0
    this.recogProcessedFrames = 0
    this.recogBusy = false
  }

  setAutoReportEnabled(enabled: boolean): void { this.autoReportEnabled = enabled }
  setAutoReportThreshold(v: number): void {
    const x: number = Math.max(0, Math.min(1, v))
    this.autoReportThreshold = x
  }

  setLastSnapshotResult(r: RecognitionResult): void { this.lastSnapshotRecog = r }

  addOrUpdateRecogTask(task: RecognitionTaskRecord): void {
    const idx: number = this.indexOfRecogTask(task.id)
    const arr: Array<RecognitionTaskRecord> = this.recogTasks.slice()

    if (idx >= 0) {
      arr[idx] = task
    } else {
      arr.unshift(task)
    }

    if (arr.length > this.recogTasksMax) {
      arr.splice(this.recogTasksMax, arr.length - this.recogTasksMax)
    }
    this.recogTasks = arr
  }

  updateRecogTaskState(id: string, state: RecognitionTaskState, errorText: string): void {
    const idx: number = this.indexOfRecogTask(id)
    if (idx < 0) return

    const now: number = Date.now()
    const src: RecognitionTaskRecord = this.recogTasks[idx]
    const nextTask: RecognitionTaskRecord = this.cloneRecogTaskRecord(src)

    nextTask.state = state
    nextTask.errorText = errorText

    if (state === RecognitionTaskState.RUNNING && nextTask.startAtMs <= 0) {
      nextTask.startAtMs = now
    }

    if (state === RecognitionTaskState.SUCCESS ||
      state === RecognitionTaskState.FAILED ||
      state === RecognitionTaskState.CANCELED ||
      state === RecognitionTaskState.TIMEOUT ||
      state === RecognitionTaskState.DROPPED) {
      nextTask.endAtMs = now
    }

    const arr: Array<RecognitionTaskRecord> = this.recogTasks.slice()
    arr[idx] = nextTask
    this.recogTasks = arr
  }

  updateRecogTaskCost(id: string, costMs: number): void {
    const idx: number = this.indexOfRecogTask(id)
    if (idx < 0) return
    const t: RecognitionTaskRecord = this.recogTasks[idx]
    const nextTask: RecognitionTaskRecord = {
      id: t.id,
      kind: t.kind,
      subtype: t.subtype,
      source: t.source,
      priority: t.priority,
      state: t.state,
      createdAtMs: t.createdAtMs,
      startAtMs: t.startAtMs,
      endAtMs: t.endAtMs,
      timeoutMs: t.timeoutMs,
      roi: t.roi,
      engine: t.engine,
      costMs: costMs,
      errorText: t.errorText,
      snapshotUri: t.snapshotUri,
      result: t.result
    }
    const arr: Array<RecognitionTaskRecord> = this.recogTasks.slice()
    arr[idx] = nextTask
    this.recogTasks = arr
  }

  updateRecogTaskResult(id: string, result: RecognitionResult, costMsTotal: number): void {
    const idx: number = this.indexOfRecogTask(id)
    if (idx < 0) return
    const now: number = Date.now()
    const t: RecognitionTaskRecord = this.recogTasks[idx]
    const nextState: RecognitionTaskState = result.ok ? RecognitionTaskState.SUCCESS : RecognitionTaskState.FAILED
    const startAtMs: number = t.startAtMs > 0 ? t.startAtMs : now

    const nextTask: RecognitionTaskRecord = {
      id: t.id,
      kind: t.kind,
      subtype: t.subtype,
      source: t.source,
      priority: t.priority,
      state: nextState,
      createdAtMs: t.createdAtMs,
      startAtMs,
      endAtMs: now,
      timeoutMs: t.timeoutMs,
      roi: t.roi,
      engine: result.engine,
      costMs: costMsTotal,
      errorText: result.ok ? '' : (result.errorText || '识别失败'),
      snapshotUri: t.snapshotUri,
      result
    }

    const arr: Array<RecognitionTaskRecord> = this.recogTasks.slice()
    arr[idx] = nextTask
    this.recogTasks = arr
  }

  appendRecogEvent(e: RecognitionTaskEvent): void {
    const arr: Array<RecognitionTaskEvent> = this.recogEvents.slice()
    arr.unshift(e)
    if (arr.length > this.recogEventsMax) {
      arr.splice(this.recogEventsMax, arr.length - this.recogEventsMax)
    }
    this.recogEvents = arr
  }

  clearRecogHub(): void {
    this.recogTasks = []
    this.recogEvents = []
  }

  updateRecogTaskSnapshotUri(id: string, snapshotUri: string): void {
    const idx: number = this.indexOfRecogTask(id)
    if (idx < 0) return

    const src: RecognitionTaskRecord = this.recogTasks[idx]
    const nextTask: RecognitionTaskRecord = this.cloneRecogTaskRecord(src)
    nextTask.snapshotUri = snapshotUri

    const arr: Array<RecognitionTaskRecord> = this.recogTasks.slice()
    arr[idx] = nextTask
    this.recogTasks = arr
  }

  setRecogEngineType(t: RecogEngineType): void {
    // 只接受 NCNN, HTTP_YOLO, MOCK
    if (t === RecogEngineType.OFFLINE_NCNN ||
        t === RecogEngineType.HTTP_YOLO ||
        t === RecogEngineType.MOCK) {
      this.recogEngineType = t
      return
    }
    // 默认使用 NCNN
    this.recogEngineType = RecogEngineType.OFFLINE_NCNN
  }
  setRecogHttpEndpoint(url: string): void { this.recogHttpEndpoint = url }
  setRecogOfflineModelName(name: string): void { this.recogOfflineModelName = name }
  setRecogOfflineConfThresh(v: number): void {
    this.recogOfflineConfThresh = Math.max(0.1, Math.min(1.0, v))
  }

  private indexOfRecogTask(id: string): number {
    for (let i: number = 0; i < this.recogTasks.length; i++) {
      if (this.recogTasks[i].id === id) return i
    }
    return -1
  }

  private cloneRecogTaskRecord(src: RecognitionTaskRecord): RecognitionTaskRecord {
    return {
      id: src.id,
      kind: src.kind,
      subtype: src.subtype,
      source: src.source,
      priority: src.priority,
      state: src.state,
      createdAtMs: src.createdAtMs,
      startAtMs: src.startAtMs,
      endAtMs: src.endAtMs,
      timeoutMs: src.timeoutMs,
      roi: src.roi,
      engine: src.engine,
      costMs: src.costMs,
      errorText: src.errorText,
      snapshotUri: src.snapshotUri,
      result: src.result
    }
  }
}

export const recogStore: RecogStore = new RecogStore()


