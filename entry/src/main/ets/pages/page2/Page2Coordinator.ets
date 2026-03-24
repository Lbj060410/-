/**
 * 代码指南：
 * 文件： pages/page2/Page2Coordinator.ets
 * 用途： Page2 用于视频 / 控制交互的业务协调器.
 * 何时修改： 添加 Page2 行为、轮询或动作分发时.
 * 相关文件： pages/page2/Page2View.ets、components/PtzControlPanel.ets、services/camera/*.
 */
import resourceManager from '@ohos.resourceManager'
import image from '@ohos.multimedia.image'

import { buildCameraSnapshotUrl, CAR_CAMERA_IP, defaultCameraHost } from '../../config/DeviceNetworkConfig'
import { videoStore, DisplayMode } from '../../state/VideoStore'
import { recogStore } from '../../state/RecogStore'
import { FrameSourceManager, VideoFrame } from '../../services/source/FrameSourceManager'
import { HttpSnapshotService } from '../../services/source/HttpSnapshotService'
import { RtspPlayerService } from '../../services/source/RtspPlayerService'
import { RtspHttpSwitchManager } from '../../services/source/RtspHttpSwitchManager'
import { deviceNetworkResolver } from '../../services/network/DeviceNetworkResolver'
import { ensureRecognitionCenter } from '../../services/recognition/RecognitionCenter'
import { RecognitionScheduler } from '../../services/recognition/RecognitionScheduler'
import { RecognitionSubtype, RecognitionTaskSource, RoiNorm } from '../../services/recognition/RecognitionTask'
import { RecogEngineType } from '../../services/recognition/RecognitionConfig'
import { BBoxNorm, RecognitionResult } from '../../services/recognition/RecognitionResult'
import { page1Store } from '../page1/app/Page1UiStore'

export class Page2Coordinator {
  readonly frames: FrameSourceManager
  readonly rtsp: RtspPlayerService
  readonly switcher: RtspHttpSwitchManager

  private lifeToken: number = 0
  private readonly snapshotProbe: HttpSnapshotService = new HttpSnapshotService()
  // 全局识别中心单例（跨页面复用），Page2 在此投喂实时帧。
  private readonly recog: RecognitionScheduler = ensureRecognitionCenter()
  // Page2 实时识别节流间隔：降低以减少识别结果拖尾。
  private readonly page2LiveIntervalMs: number = 80
  // Page2 模型互斥：
  // - barrier 默认开启，持续识别；
  // - traffic 开启后仅在指定点位+方向门控命中时执行识别。
  private readonly trafficCascadeMinIntervalMs: number = 500
  private lastTrafficCascadeAtMs: number = 0
  private trafficCascadeBusy: boolean = false
  // 防止在上一帧“解码为识别输入”尚未完成时重复进入。
  private liveDecodeBusy: boolean = false
  // 最近一次投喂识别的时间戳（毫秒）。
  private lastLiveSubmitAtMs: number = 0
  // 自动截图间隔：每 10 秒刷新一次“原始截图区”。
  private readonly autoSnapshotIntervalMs: number = 10000
  private nextAutoSnapshotAtMs: number = 0
  private autoSnapshotBusy: boolean = false
  private activeSnapshotUrl: string = ''
  private started: boolean = false
  private starting: boolean = false
  private prewarming: boolean = false
  private prewarmed: boolean = false
  private readonly prewarmHttpIntervalMs: number = 280

  constructor() {
    this.frames = new FrameSourceManager(videoStore)
    this.rtsp = new RtspPlayerService(videoStore)
    this.switcher = new RtspHttpSwitchManager(videoStore, this.rtsp, this.frames)

    this.frames.setOnFrame((frame, pm: image.PixelMap): void => {
      // Page2 帧处理入口：
      // 1) 每 10 秒自动更新一次截图区（可按识别结果裁剪）
      // 2) 实时识别只在识别开关开启时工作
      // 3) 识别任务按时间节流并防重入，避免抢占预览线程
      const now: number = Date.now()
      this.maybeAutoCaptureSnapshot(frame, now)

      if (!videoStore.recognitionEnabled) return

      if (now - this.lastLiveSubmitAtMs < this.page2LiveIntervalMs) return
      if (this.liveDecodeBusy) return

      this.lastLiveSubmitAtMs = now
      this.liveDecodeBusy = true
      void this.dispatchLiveRecognition(frame, pm).finally((): void => {
        this.liveDecodeBusy = false
      })
    })
  }

  bindSurface(surfaceId: string): void {
    this.rtsp.setSurfaceId(surfaceId)
  }

  bindResourceManager(rm: resourceManager.ResourceManager): void {
    this.switcher.bindResourceManager(rm)
  }

  private async prepareVideoEndpoint(): Promise<void> {
    const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
    if (gatewayIp.length > 0) {
      videoStore.setStatus(`WiFi gateway: ${gatewayIp}`)
    }

    const cameraIp: string = await deviceNetworkResolver.resolveCameraIp(5000)
    const candidates: string[] = []
    candidates.push(`${CAR_CAMERA_IP}:81`)
    if (cameraIp.length > 0) candidates.push(deviceNetworkResolver.buildCameraHost(cameraIp))
    if (gatewayIp.length > 0) candidates.push(deviceNetworkResolver.buildCameraHost(gatewayIp))
    this.appendGatewayCameraCandidates(candidates, gatewayIp)
    candidates.push('192.168.1.101:81')
    candidates.push('192.168.16.20:81')
    candidates.push(defaultCameraHost())

    let lastError: string = ''
    const tried: Record<string, boolean> = {}
    for (const host of candidates) {
      if (tried[host] === true) continue
      tried[host] = true

      const urls: Array<string> = this.snapshotUrlCandidates(host)
      for (let i: number = 0; i < urls.length; i++) {
        const probeUrl: string = urls[i]
        try {
          const jpeg: ArrayBuffer = await this.snapshotProbe.fetchJpeg(probeUrl, 1500)
          if (jpeg.byteLength > 0) {
            videoStore.cameraHost = host
            videoStore.rtspUrl = deviceNetworkResolver.buildRtspUrl(host.split(':')[0])
            this.activeSnapshotUrl = probeUrl
            videoStore.setStatus(`Camera connected: ${host}`)
            return
          }
        } catch (e) {
          lastError = e instanceof Error ? e.message : 'probe failed'
          console.error(`[Page2] camera probe failed host=${host} url=${probeUrl} err=${lastError}`)
        }
      }
    }

    if (lastError.length > 0) {
      videoStore.setError(lastError)
      videoStore.setStatus(`Camera probe failed, tried: ${candidates.join(', ')}`)
    }
  }

  private snapshotUrlCandidates(host: string): Array<string> {
    const out: Array<string> = []
    const pushUnique = (url: string): void => {
      const x: string = url.trim()
      if (x.length <= 0) return
      for (let i: number = 0; i < out.length; i++) {
        if (out[i] === x) return
      }
      out.push(x)
    }

    const u: string = encodeURIComponent(videoStore.cameraUser.trim())
    const p: string = encodeURIComponent(videoStore.cameraPass.trim())
    pushUnique(buildCameraSnapshotUrl(host, videoStore.cameraUser, videoStore.cameraPass))
    pushUnique(`http://${host}/snapshot.cgi?user=${u}&pwd=${p}&res=0`)
    pushUnique(`http://${host}/snapshot.cgi?username=${u}&password=${p}&res=0`)
    pushUnique(`http://${host}/snapshot.cgi`)
    pushUnique(`http://${host}/shot.jpg`)
    pushUnique(`http://${host}/image.jpg`)
    pushUnique(`http://${host}/capture.jpg`)
    return out
  }

  private appendGatewayCameraCandidates(candidates: string[], gatewayIp: string): void {
    if (gatewayIp.length <= 0) return

    const lastDot: number = gatewayIp.lastIndexOf('.')
    if (lastDot <= 0) return

    const prefix: string = gatewayIp.substring(0, lastDot)
    candidates.push(`${prefix}.101:81`)
    candidates.push(`${prefix}.20:81`)
  }

  async start(): Promise<void> {
    if (this.started || this.starting) {
      videoStore.setStatus(`Page2 keep-alive, source=HTTP, mode=${this.modeText()}`)
      return
    }
    this.starting = true
    const token: number = ++this.lifeToken
    this.ensurePage2RecognitionConfig()

    try {
      if (this.activeSnapshotUrl.length <= 0) {
        await this.prepareVideoEndpoint()
      }
      if (token !== this.lifeToken) return

      const httpUrl: string = this.activeSnapshotUrl.length > 0
        ? this.activeSnapshotUrl
        : buildCameraSnapshotUrl(videoStore.cameraHost, videoStore.cameraUser, videoStore.cameraPass)
      console.info(`[Page2] start http host=${videoStore.cameraHost}`)

      videoStore.setDisplayMode(DisplayMode.HTTP, 'startup')
      // 平衡预览新鲜度和控制路径稳定性。
      this.frames.startHttp(httpUrl, 120)
      this.recog.setLiveIntervalMs(this.page2LiveIntervalMs)
      this.lastLiveSubmitAtMs = 0
      this.lastTrafficCascadeAtMs = 0
      this.liveDecodeBusy = false
      this.autoSnapshotBusy = false
      this.nextAutoSnapshotAtMs = Date.now() + this.autoSnapshotIntervalMs

      // 保持 HarmonyOS 与当前 HTTP 预览路径对齐。
      this.switcher.stop()

      this.started = true
      this.prewarmed = false
      videoStore.setStatus(`Page2 started, camera=${videoStore.cameraHost}, source=HTTP, mode=${this.modeText()}`)
    } finally {
      if (token === this.lifeToken) this.starting = false
    }
  }

  async prewarm(): Promise<void> {
    if (this.started || this.starting || this.prewarming || this.prewarmed) return

    this.prewarming = true
    const token: number = this.lifeToken
    try {
      await this.prepareVideoEndpoint()
      if (token !== this.lifeToken || this.started || this.starting) return

      const httpUrl: string = this.activeSnapshotUrl.length > 0
        ? this.activeSnapshotUrl
        : buildCameraSnapshotUrl(videoStore.cameraHost, videoStore.cameraUser, videoStore.cameraPass)
      console.info(`[Page2] prewarm http host=${videoStore.cameraHost}`)

      videoStore.setDisplayMode(DisplayMode.HTTP, 'prewarm')
      this.frames.startHttp(httpUrl, this.prewarmHttpIntervalMs)
      this.lastLiveSubmitAtMs = 0
      this.liveDecodeBusy = false
      this.autoSnapshotBusy = false
      this.nextAutoSnapshotAtMs = Date.now() + this.autoSnapshotIntervalMs
      this.switcher.stop()

      this.prewarmed = true
      videoStore.setStatus(`Page2 低风险预热完成, camera=${videoStore.cameraHost}`)
    } catch (e) {
      const errMsg: string = e instanceof Error ? e.message : 'prewarm failed'
      console.error('[Page2] prewarm failed:', errMsg)
    } finally {
      if (token === this.lifeToken) this.prewarming = false
    }
  }

  stop(): void {
    this.lifeToken += 1
    console.info('[Page2] STOP CALLED')
    this.starting = false
    this.prewarming = false
    this.prewarmed = false
    this.started = false
    this.liveDecodeBusy = false
    this.lastTrafficCascadeAtMs = 0
    this.autoSnapshotBusy = false
    this.nextAutoSnapshotAtMs = 0

    this.switcher.stop()
    this.frames.stop()
    this.rtsp.pause().catch((e: Error): void => {
      console.error('[Page2] rtsp pause error:', e.message)
    })

    videoStore.setStatus('Page2 stopped')
  }

  private ensurePage2RecognitionConfig(): void {
    // Page2 实时识别固定走本地 NCNN，防止仍使用 HTTP 引擎导致“有画面但无识别”。
    if (recogStore.recogEngineType !== RecogEngineType.OFFLINE_NCNN) {
      recogStore.setRecogEngineType(RecogEngineType.OFFLINE_NCNN)
    }
    // 根据模型开关设置阈值：barrier 略低，traffic 略高以减少误检。
    const wantedConf: number = videoStore.page2BarrierExperimentalEnabled ? 0.1 : 0.28
    if (Math.abs(recogStore.recogOfflineConfThresh - wantedConf) > 0.001) {
      recogStore.setRecogOfflineConfThresh(wantedConf)
    }
  }

  private async dispatchLiveRecognition(frame: VideoFrame, recogPm: image.PixelMap): Promise<void> {
    void frame
    try {
      const liveSubtype: RecognitionSubtype | undefined = this.currentLiveSubtype()
      if (liveSubtype === undefined) return
      if (videoStore.page2BarrierExperimentalEnabled && liveSubtype === RecognitionSubtype.BARRIER) {
        // 不要用级联快照/裁剪工作阻塞实时提交。
        void this.maybeEnqueueTrafficCascade(recogPm)
      }
      // live PixelMap 与预览共用，避免重复 JPEG 解码；releaseAfterUse=false 由 VideoStore 管理释放。
      this.recog.enqueueLiveOnceFromPage2(recogPm, liveSubtype, false)
    } catch (e) {
      const errMsg: string = e instanceof Error ? e.message : 'page2 live recognition frame decode failed'
      console.error('[Page2] dispatchLiveRecognition error:', errMsg)
    }
  }

  private async jpegToPixelMap(jpeg: ArrayBuffer): Promise<image.PixelMap> {
    const src: image.ImageSource = image.createImageSource(jpeg)
    try {
      return await src.createPixelMap()
    } finally {
      try { src.release() } catch (_) {}
    }
  }

  private async maybeEnqueueTrafficCascade(currentPm: image.PixelMap): Promise<void> {
    const nowMs: number = Date.now()
    if (nowMs - this.lastTrafficCascadeAtMs < this.trafficCascadeMinIntervalMs) return
    if (this.trafficCascadeBusy) return
    this.trafficCascadeBusy = true

    try {
      const last: RecognitionResult | undefined = recogStore.lastRecog
      const marker: BBoxNorm | undefined = this.pickTrafficLightMarkerFromBarrier(last)
      if (!marker) return

      const info: image.ImageInfo = await currentPm.getImageInfo()
      const roi: RoiNorm | undefined = this.boxToRoiNorm(marker, info.size.width, info.size.height)
      if (!roi) return

      const snapPm: image.PixelMap | undefined = await this.clonePixelMap(currentPm)
      if (!snapPm) return

      this.recog.enqueueSnapshotFromPixelMapWithRoi(
        snapPm,
        roi,
        RecognitionSubtype.TRAFFIC_LIGHT,
        RecognitionTaskSource.PAGE2_BUTTON,
        true
      )
      this.lastTrafficCascadeAtMs = nowMs
    } finally {
      this.trafficCascadeBusy = false
    }
  }

  onModelSwitchChanged(): void {
    this.lastLiveSubmitAtMs = 0
    this.lastTrafficCascadeAtMs = 0
    this.liveDecodeBusy = false
    this.ensurePage2RecognitionConfig()
    videoStore.setStatus(`Page2 mode switched: ${this.modeText()}`)
  }

  onBarrierModeChanged(): void {
    this.onModelSwitchChanged()
  }

  private pickTrafficLightMarkerFromBarrier(result: RecognitionResult | undefined): BBoxNorm | undefined {
    if (!result || !result.ok) return undefined
    if (result.subtype !== RecognitionSubtype.BARRIER) return undefined
    if (result.boxes.length <= 0) return undefined

    let best: BBoxNorm | undefined = undefined
    for (let i: number = 0; i < result.boxes.length; i++) {
      const one: BBoxNorm = result.boxes[i]
      if (!this.isTrafficLightMarkerLabel(one.label)) continue
      if (!best || one.score > best.score) best = one
    }
    return best
  }

  private isTrafficLightMarkerLabel(label: string): boolean {
    const normalized: string = label.trim().toLowerCase()
    if (normalized.length <= 0) return false
    if (normalized === 'trafficlight') return true
    if (normalized === 'traffic_light') return true
    if (normalized.indexOf('trafficlight') >= 0) return true
    if (normalized.indexOf('traffic') >= 0 && normalized.indexOf('light') >= 0) return true
    if (label.indexOf('交通灯') >= 0) return true
    return false
  }

  private boxToRoiNorm(box: BBoxNorm, imgW: number, imgH: number): RoiNorm | undefined {
    if (imgW <= 0 || imgH <= 0) return undefined

    const normalizedBox: boolean =
      box.x >= 0 && box.y >= 0 && box.w > 0 && box.h > 0 &&
      box.x <= 1 && box.y <= 1 && box.w <= 1 && box.h <= 1

    let x0: number = normalizedBox ? box.x : box.x / imgW
    let y0: number = normalizedBox ? box.y : box.y / imgH
    let x1: number = normalizedBox ? (box.x + box.w) : (box.x + box.w) / imgW
    let y1: number = normalizedBox ? (box.y + box.h) : (box.y + box.h) / imgH

    x0 = Math.max(0, Math.min(x0, 1))
    y0 = Math.max(0, Math.min(y0, 1))
    x1 = Math.max(0, Math.min(x1, 1))
    y1 = Math.max(0, Math.min(y1, 1))
    if (x1 <= x0 || y1 <= y0) return undefined

    const padX: number = Math.min(0.12, Math.max(0.02, (x1 - x0) * 0.15))
    const padY: number = Math.min(0.12, Math.max(0.02, (y1 - y0) * 0.15))

    const rx0: number = Math.max(0, x0 - padX)
    const ry0: number = Math.max(0, y0 - padY)
    const rx1: number = Math.min(1, x1 + padX)
    const ry1: number = Math.min(1, y1 + padY)
    if (rx1 <= rx0 || ry1 <= ry0) return undefined

    return {
      x: rx0,
      y: ry0,
      w: rx1 - rx0,
      h: ry1 - ry0
    }
  }

  private async clonePixelMap(pm: image.PixelMap): Promise<image.PixelMap | undefined> {
    const packer: image.ImagePacker = image.createImagePacker()
    try {
      const data: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 })
      return await this.jpegToPixelMap(data)
    } catch (e) {
      void e
      return undefined
    } finally {
      try { packer.release() } catch (_) {}
    }
  }

  private maybeAutoCaptureSnapshot(frame: VideoFrame, nowMs: number): void {
    if (this.autoSnapshotBusy) return
    if (this.nextAutoSnapshotAtMs <= 0) {
      this.nextAutoSnapshotAtMs = nowMs + this.autoSnapshotIntervalMs
      return
    }
    if (nowMs < this.nextAutoSnapshotAtMs) return

    this.autoSnapshotBusy = true
    void this.captureAutoSnapshotFromFrame(frame).finally((): void => {
      this.autoSnapshotBusy = false
    })
  }

  private pickBestRecogBoxForAutoSnapshot(result: RecognitionResult | undefined): BBoxNorm | undefined {
    if (!result || !result.ok) return undefined
    if (result.boxes.length <= 0) return undefined

    let best: BBoxNorm | undefined = undefined
    let bestScore: number = 0
    for (let i: number = 0; i < result.boxes.length; i++) {
      const box: BBoxNorm = result.boxes[i]
      if (!best || box.score > bestScore) {
        best = box
        bestScore = box.score
      }
    }
    return best
  }

  private boxToCropRegion(box: BBoxNorm, imgW: number, imgH: number): image.Region | undefined {
    if (imgW <= 0 || imgH <= 0) return undefined

    const normalized: boolean =
      box.x >= 0 && box.y >= 0 && box.w > 0 && box.h > 0 &&
      box.x <= 1 && box.y <= 1 && box.w <= 1 && box.h <= 1

    let x0: number = normalized ? box.x * imgW : box.x
    let y0: number = normalized ? box.y * imgH : box.y
    let x1: number = normalized ? (box.x + box.w) * imgW : (box.x + box.w)
    let y1: number = normalized ? (box.y + box.h) * imgH : (box.y + box.h)

    x0 = Math.max(0, Math.min(x0, imgW))
    y0 = Math.max(0, Math.min(y0, imgH))
    x1 = Math.max(0, Math.min(x1, imgW))
    y1 = Math.max(0, Math.min(y1, imgH))

    if (x1 <= x0 || y1 <= y0) return undefined

    const bw: number = x1 - x0
    const bh: number = y1 - y0
    const padX: number = Math.max(2, Math.floor(bw * 0.10))
    const padY: number = Math.max(2, Math.floor(bh * 0.10))

    let px0: number = Math.max(0, Math.floor(x0 - padX))
    let py0: number = Math.max(0, Math.floor(y0 - padY))
    let px1: number = Math.min(imgW, Math.ceil(x1 + padX))
    let py1: number = Math.min(imgH, Math.ceil(y1 + padY))

    if (px1 <= px0 || py1 <= py0) return undefined

    return {
      x: px0,
      y: py0,
      size: {
        width: Math.max(1, px1 - px0),
        height: Math.max(1, py1 - py0)
      }
    }
  }

  private async captureAutoSnapshotFromFrame(frame: VideoFrame): Promise<void> {
    let pm: image.PixelMap | undefined = undefined
    const captureAtMs: number = Date.now()
    let usedRecogCrop: boolean = false

    try {
      pm = await this.jpegToPixelMap(frame.jpeg)
      const info: image.ImageInfo = await pm.getImageInfo()
      const bestBox: BBoxNorm | undefined = this.pickBestRecogBoxForAutoSnapshot(recogStore.lastRecog)
      if (bestBox) {
        const region: image.Region | undefined = this.boxToCropRegion(bestBox, info.size.width, info.size.height)
        if (region) {
          try {
            await pm.crop(region)
            usedRecogCrop = true
          } catch (e) {
            void e
          }
        }
      }

      videoStore.setSnapshot(pm)
      pm = undefined
      this.nextAutoSnapshotAtMs = captureAtMs + this.autoSnapshotIntervalMs
      if (usedRecogCrop) {
        videoStore.setStatus('Auto snapshot updated (recognition crop)')
      } else {
        videoStore.setStatus('Auto snapshot updated (full frame)')
      }
    } catch (e) {
      const errMsg: string = e instanceof Error ? e.message : 'auto snapshot failed'
      videoStore.setError(errMsg)
      this.nextAutoSnapshotAtMs = captureAtMs + this.autoSnapshotIntervalMs
    } finally {
      if (pm) {
        try { pm.release() } catch (_) {}
      }
    }
  }

  private currentLiveSubtype(): RecognitionSubtype | undefined {
    if (videoStore.page2TrafficEnabled) {
      return this.isTrafficGatePoseMatched() ? RecognitionSubtype.TRAFFIC_LIGHT : undefined
    }
    if (videoStore.page2BarrierExperimentalEnabled) return RecognitionSubtype.BARRIER
    return undefined
  }

  private isTrafficGatePoseMatched(): boolean {
    const snapId: string = page1Store.currentSnapNodeId.trim().toUpperCase()
    if (snapId.length <= 0) return false

    const headingCardinal: number = this.normToCardinal(page1Store.pose.headingDeg)
    if (snapId === 'B4' && headingCardinal === 90) return true
    if (snapId === 'D6' && headingCardinal === 0) return true
    return false
  }

  private normToCardinal(v: number): number {
    let x: number = v % 360
    if (x < 0) x += 360

    const cands: number[] = [0, 90, 180, 270]
    let best: number = cands[0]
    let bestErr: number = 360
    for (let i: number = 0; i < cands.length; i++) {
      const c: number = cands[i]
      const d: number = Math.abs(x - c)
      const err: number = Math.min(d, 360 - d)
      if (err < bestErr) {
        bestErr = err
        best = c
      }
    }
    return best
  }

  private modeText(): string {
    if (videoStore.page2TrafficEnabled) return 'traffic-gated(B4->B6|D6->F6)'
    if (videoStore.page2BarrierExperimentalEnabled) return 'barrier'
    return 'none'
  }
}

export const page2Coordinator: Page2Coordinator = new Page2Coordinator()




