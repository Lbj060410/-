/**
 * 代码指南：
 * 文件： pages/page2/Page2Coordinator.ets
 * 用途： Page2 用于视频 / 控制交互的业务协调器.
 * 何时修改： 添加 Page2 行为、轮询或动作分发时.
 * 相关文件： pages/page2/Page2View.ets、components/PtzControlPanel.ets、services/camera/*.
 */
import resourceManager from '@ohos.resourceManager'
import image from '@ohos.multimedia.image'
import fs from '@ohos.file.fs'
import util from '@ohos.util'

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
import { RecognitionTaskKind } from '../../services/recognition/RecognitionTask'
import { RecogEngineType } from '../../services/recognition/RecognitionConfig'
import { BBoxNorm, RecognitionResult } from '../../services/recognition/RecognitionResult'
import { page2ReplayService } from '../../services/replay/Page2ReplayService'
import { page1Store } from '../page1/app/Page1UiStore'

const PAGE2_LAST_ENDPOINT_PATH: string = '/data/storage/el2/base/haps/entry/files/page2_last_endpoint.json'

export class Page2Coordinator {
  readonly frames: FrameSourceManager
  readonly rtsp: RtspPlayerService
  readonly switcher: RtspHttpSwitchManager

  private lifeToken: number = 0
  private readonly snapshotProbe: HttpSnapshotService = new HttpSnapshotService()
  // 全局识别中心单例（跨页面复用），Page2 在此投喂实时帧。
  private readonly recog: RecognitionScheduler = ensureRecognitionCenter()
  // Page2 实时识别节流间隔（自适应）：
  // - 负载高时自动拉大，优先保障 UI/视频流畅
  // - 负载低时缓慢回落，恢复识别响应速度
  private readonly page2LiveIntervalMinMs: number = 80
  private readonly page2LiveIntervalMaxMs: number = 420
  private currentLiveIntervalMs: number = 120
  private readonly liveCadenceTuneStepUpMs: number = 20
  private readonly liveCadenceTuneStepDownMs: number = 10
  private readonly liveCadenceTuneWindowMs: number = 1200
  private lastLiveCadenceTuneAtMs: number = 0
  private lastRecogFailCount: number = 0
  // Page2 模型互斥：
  // - yolov26barrier 默认开启，持续识别；
  // - traffic 开启后仅在指定点位+方向门控命中时执行识别。
  private readonly trafficCascadeMinIntervalMs: number = 500
  private lastTrafficCascadeAtMs: number = 0
  private trafficCascadeBusy: boolean = false
  // 防止在上一帧“解码为识别输入”尚未完成时重复进入。
  private liveDecodeBusy: boolean = false
  // 最近一次投喂识别的时间戳（毫秒）。
  private lastLiveSubmitAtMs: number = 0
  private lastAutoSnapTaskId: string = ''
  private lastAutoSnapAtMs: number = 0
  private autoSnapBusy: boolean = false
  private readonly autoSnapMinIntervalMs: number = 1200
  private recognitionPauseUntilMs: number = 0
  private activeSnapshotUrl: string = ''
  private started: boolean = false
  private starting: boolean = false
  private prewarming: boolean = false
  private prewarmed: boolean = false
  private readonly prewarmHttpIntervalMs: number = 280
  private lastGoodSnapshotUrl: string = ''
  private lastGoodCameraHost: string = ''
  private lastPerfPulseLogAtMs: number = 0
  private pulseTimerId: number = -1
  private readonly pulseTimerIntervalMs: number = 2000
  private readonly replayIngestMinIntervalMs: number = 180
  private readonly replayIngestMaxIntervalMs: number = 420
  private dynamicReplayIngestIntervalMs: number = 180
  private readonly replayCadenceTuneWindowMs: number = 1200
  private lastReplayCadenceTuneAtMs: number = 0
  private lastReplayIngestAtMs: number = 0
  private readonly shigongReplaySubmitMinIntervalMs: number = 500
  private lastShigongReplaySubmitAtMs: number = 0
  private lastShigongReplayTaskId: string = ''
  private readonly snapshotRecoverFailThreshold: number = 3
  private readonly snapshotRecoverCooldownMs: number = 8000
  private lastSnapshotRecoverAtMs: number = 0
  private snapshotRecovering: boolean = false
  private lastHttpSoftRestartAtMs: number = 0
  private readonly httpSoftRestartCooldownMs: number = 3500
  private readonly frameStallThresholdMs: number = 2600
  private lastLiveFrameSignature: number = 0
  private lastLiveSignatureAtMs: number = 0
  private readonly liveUnchangedSkipWindowMs: number = 1200

  constructor() {
    this.loadPersistedSnapshotEndpoint()
    this.frames = new FrameSourceManager(videoStore)
    this.rtsp = new RtspPlayerService(videoStore)
    this.switcher = new RtspHttpSwitchManager(videoStore, this.rtsp, this.frames)

    this.frames.setOnFrameHealth((ok: boolean, reason: string, failStreak: number): void => {
      this.onFrameHealth(ok, reason, failStreak)
    })

    this.frames.setOnFrame((frame, pm: image.PixelMap): void => {
      // Page2 帧处理入口：
      // 1) 实时识别只在识别开关开启时工作
      // 2) 识别任务按时间节流并防重入，避免抢占预览线程
      const now: number = Date.now()
      const overloaded: boolean = this.isVideoOverloaded()
      this.tuneReplayIngestCadence(now)
      if (now - this.lastReplayIngestAtMs >= this.dynamicReplayIngestIntervalMs) {
        this.lastReplayIngestAtMs = now
        page2ReplayService.ingestFrameJpeg(frame.jpeg, now)
      }
      if (!overloaded) {
        this.maybeAutoSnapshotFromVision(pm, now)
        this.maybeRecordShigongReplay(now)
      }
      if (!videoStore.recognitionEnabled) return
      this.tuneLiveRecognitionCadence(now)
      this.refreshRecognitionPause(now)
      if (now < this.recognitionPauseUntilMs) return
      if (this.shouldSkipLiveRecognition(frame, now)) return

      if (now - this.lastLiveSubmitAtMs < this.currentLiveIntervalMs) return
      if (this.liveDecodeBusy) return

      this.lastLiveSubmitAtMs = now
      this.liveDecodeBusy = true
      void this.dispatchLiveRecognition(frame, pm).finally((): void => {
        this.liveDecodeBusy = false
      })
    })
  }

  private onFrameHealth(ok: boolean, reason: string, failStreak: number): void {
    if (ok) return
    const nowMs: number = Date.now()
    this.recognitionPauseUntilMs = Math.max(this.recognitionPauseUntilMs, nowMs + 1200)
    if (!this.started || this.starting || this.prewarming) return
    if (failStreak >= 2) {
      this.maybeSoftRestartHttpPipeline(nowMs, `frame fail streak=${failStreak}`)
    }
    if (failStreak < this.snapshotRecoverFailThreshold) return
    if (this.snapshotRecovering) return
    if (nowMs - this.lastSnapshotRecoverAtMs < this.snapshotRecoverCooldownMs) return
    this.lastSnapshotRecoverAtMs = nowMs
    void this.tryRecoverSnapshotEndpoint(reason)
  }

  private maybeSoftRestartHttpPipeline(nowMs: number, reason: string): void {
    if (!this.started || this.starting || this.prewarming) return
    if (this.activeSnapshotUrl.length <= 0) return
    if (nowMs - this.lastHttpSoftRestartAtMs < this.httpSoftRestartCooldownMs) return
    this.lastHttpSoftRestartAtMs = nowMs
    const baseIntervalMs: number = Math.max(120, Math.trunc(videoStore.diagVideoPullIntervalMs || 120))
    this.frames.startHttp(this.activeSnapshotUrl, baseIntervalMs)
    console.warn(`[Page2] http soft restart reason=${reason} url=${this.activeSnapshotUrl} interval=${baseIntervalMs}`)
    videoStore.setStatus('Camera stream unstable, auto restarting...')
  }

  private async tryRecoverSnapshotEndpoint(reason: string): Promise<void> {
    if (this.snapshotRecovering) return
    this.snapshotRecovering = true
    try {
      const host: string = videoStore.cameraHost.trim()
      if (host.length <= 0) return
      const candidates: Array<string> = this.snapshotUrlCandidates(host)
      let switched: boolean = false
      for (let i: number = 0; i < candidates.length; i++) {
        const one: string = candidates[i]
        if (one === this.activeSnapshotUrl) continue
        try {
          const jpeg: ArrayBuffer = await this.snapshotProbe.fetchJpeg(one, 1200)
          const ok: boolean = await this.isValidJpegSnapshot(jpeg)
          if (!ok) continue
          this.activeSnapshotUrl = one
          this.lastGoodSnapshotUrl = one
          this.lastGoodCameraHost = host
          this.persistSnapshotEndpoint(host, one)
          this.frames.startHttp(one, 120)
          videoStore.setStatus(`Camera endpoint recovered: ${one}`)
          console.warn(`[Page2] snapshot endpoint switched reason=${reason} url=${one}`)
          switched = true
          break
        } catch (_) {}
      }
      if (!switched) {
        console.warn(`[Page2] snapshot endpoint recover skipped: no better url, reason=${reason}`)
      }
    } finally {
      this.snapshotRecovering = false
    }
  }

  private shouldSkipLiveRecognition(frame: VideoFrame, nowMs: number): boolean {
    const sig: number = this.quickFrameSignature(frame.jpeg)
    if (this.lastLiveSignatureAtMs <= 0) {
      this.lastLiveSignatureAtMs = nowMs
      this.lastLiveFrameSignature = sig
      return false
    }
    const unchanged: boolean = sig === this.lastLiveFrameSignature
    this.lastLiveFrameSignature = sig
    if (!unchanged) {
      this.lastLiveSignatureAtMs = nowMs
      return false
    }
    if (nowMs - this.lastLiveSignatureAtMs < this.liveUnchangedSkipWindowMs) {
      return true
    }
    this.lastLiveSignatureAtMs = nowMs
    return false
  }

  private quickFrameSignature(jpeg: ArrayBuffer): number {
    const bytes: Uint8Array = new Uint8Array(jpeg)
    const n: number = bytes.length
    if (n <= 0) return 0
    const step: number = Math.max(1, Math.trunc(n / 64))
    let acc: number = n & 0x7fffffff
    for (let i: number = 0; i < n; i += step) {
      acc = ((acc << 5) - acc + (bytes[i] & 0xff)) & 0x7fffffff
    }
    return acc
  }

  private loadPersistedSnapshotEndpoint(): void {
    let f: fs.File | undefined = undefined
    try {
      f = fs.openSync(PAGE2_LAST_ENDPOINT_PATH, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(PAGE2_LAST_ENDPOINT_PATH)
      const size: number = Number(st.size)
      if (!Number.isFinite(size) || size <= 0 || size > 4096) return
      const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
      const readLen: number = fs.readSync(f.fd, buf)
      if (readLen <= 0) return
      const bytes: Uint8Array = new Uint8Array(buf, 0, readLen)
      const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
      const parsed: Record<string, string> = JSON.parse(txt) as Record<string, string>
      const host: string = String(parsed['host'] ?? '').trim()
      const url: string = String(parsed['url'] ?? '').trim()
      if (host.length > 0) this.lastGoodCameraHost = host
      if (url.length > 0) this.lastGoodSnapshotUrl = url
    } catch (_) {
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  private persistSnapshotEndpoint(host: string, url: string): void {
    const safeHost: string = host.trim()
    const safeUrl: string = url.trim()
    if (safeHost.length <= 0 || safeUrl.length <= 0) return
    let f: fs.File | undefined = undefined
    try {
      const txt: string = JSON.stringify({ host: safeHost, url: safeUrl })
      try { fs.unlinkSync(PAGE2_LAST_ENDPOINT_PATH) } catch (_) {}
      f = fs.openSync(PAGE2_LAST_ENDPOINT_PATH, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(f.fd, txt)
    } catch (_) {
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  bindSurface(surfaceId: string): void {
    this.rtsp.setSurfaceId(surfaceId)
  }

  bindResourceManager(rm: resourceManager.ResourceManager): void {
    this.switcher.bindResourceManager(rm)
  }

  private async prepareVideoEndpoint(): Promise<boolean> {
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
    if (this.lastGoodCameraHost.length > 0) {
      candidates.unshift(this.lastGoodCameraHost)
    }

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
          const okJpeg: boolean = await this.isValidJpegSnapshot(jpeg)
          if (okJpeg) {
            videoStore.cameraHost = host
            videoStore.rtspUrl = deviceNetworkResolver.buildRtspUrl(host.split(':')[0])
            this.activeSnapshotUrl = probeUrl
            this.lastGoodSnapshotUrl = probeUrl
            this.lastGoodCameraHost = host
            this.persistSnapshotEndpoint(host, probeUrl)
            videoStore.setStatus(`Camera connected: ${host}`)
            return true
          }
          lastError = 'probe returned non-image payload'
          console.error(`[Page2] camera probe invalid image host=${host} url=${probeUrl}`)
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
    return false
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
    if (this.lastGoodCameraHost === host && this.lastGoodSnapshotUrl.length > 0) {
      pushUnique(this.lastGoodSnapshotUrl)
    }
    pushUnique(`http://${host}/snapshot.cgi?user=${u}&pwd=${p}&res=0`)
    pushUnique(`http://${host}/snapshot.cgi?username=${u}&password=${p}&res=0`)
    pushUnique(buildCameraSnapshotUrl(host, videoStore.cameraUser, videoStore.cameraPass))
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
      this.activeSnapshotUrl = ''
      if (this.activeSnapshotUrl.length <= 0) {
        const found: boolean = await this.prepareVideoEndpoint()
        if (!found || this.activeSnapshotUrl.length <= 0) {
          console.error(`[Page2] start blocked: camera probe unresolved (found=${found}, url=${this.activeSnapshotUrl})`)
          videoStore.setStatus('Page2 启动失败：未发现可用摄像头快照地址')
          return
        }
      }
      if (token !== this.lifeToken) return

      const httpUrl: string = this.activeSnapshotUrl.length > 0
        ? this.activeSnapshotUrl
        : buildCameraSnapshotUrl(videoStore.cameraHost, videoStore.cameraUser, videoStore.cameraPass)
      console.info(`[Page2] start http host=${videoStore.cameraHost} url=${httpUrl}`)

      videoStore.setDisplayMode(DisplayMode.HTTP, 'startup')
      // 平衡预览新鲜度和控制路径稳定性。
      this.frames.startHttp(httpUrl, 120)
      this.ensurePulseTimer()
      this.currentLiveIntervalMs = 120
      this.lastLiveCadenceTuneAtMs = 0
      this.lastRecogFailCount = recogStore.recogFail
      this.recog.setLiveIntervalMs(this.currentLiveIntervalMs)
      this.lastLiveSubmitAtMs = 0
      this.lastTrafficCascadeAtMs = 0
      this.liveDecodeBusy = false
      this.recognitionPauseUntilMs = 0
      this.dynamicReplayIngestIntervalMs = this.replayIngestMinIntervalMs
      this.lastReplayCadenceTuneAtMs = 0
      this.lastReplayIngestAtMs = 0
      this.lastShigongReplaySubmitAtMs = 0
      this.lastShigongReplayTaskId = ''
      this.snapshotRecovering = false
      this.lastSnapshotRecoverAtMs = 0

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
      this.activeSnapshotUrl = ''
      const found: boolean = await this.prepareVideoEndpoint()
      if (!found || this.activeSnapshotUrl.length <= 0) {
        console.error(`[Page2] prewarm blocked: camera probe unresolved (found=${found}, url=${this.activeSnapshotUrl})`)
        return
      }
      if (token !== this.lifeToken || this.started || this.starting) return

      const httpUrl: string = this.activeSnapshotUrl.length > 0
        ? this.activeSnapshotUrl
        : buildCameraSnapshotUrl(videoStore.cameraHost, videoStore.cameraUser, videoStore.cameraPass)
      console.info(`[Page2] prewarm http host=${videoStore.cameraHost} url=${httpUrl}`)

      videoStore.setDisplayMode(DisplayMode.HTTP, 'prewarm')
      this.frames.startHttp(httpUrl, this.prewarmHttpIntervalMs)
      this.ensurePulseTimer()
      this.currentLiveIntervalMs = 120
      this.lastLiveCadenceTuneAtMs = 0
      this.lastRecogFailCount = recogStore.recogFail
      this.lastLiveSubmitAtMs = 0
      this.liveDecodeBusy = false
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
    this.snapshotRecovering = false
    this.lastSnapshotRecoverAtMs = 0

    this.switcher.stop()
    this.frames.stop()
    this.stopPulseTimer()
    this.rtsp.pause().catch((e: Error): void => {
      console.error('[Page2] rtsp pause error:', e.message)
    })

    videoStore.setStatus('Page2 stopped')
  }

  private ensurePulseTimer(): void {
    if (this.pulseTimerId !== -1) return
    this.pulseTimerId = setInterval((): void => {
      this.maybeLogPerfPulse(Date.now())
    }, this.pulseTimerIntervalMs) as number
  }

  private stopPulseTimer(): void {
    if (this.pulseTimerId === -1) return
    clearInterval(this.pulseTimerId)
    this.pulseTimerId = -1
  }

  private ensurePage2RecognitionConfig(): void {
    // Page2 实时识别固定走本地 NCNN，防止仍使用 HTTP 引擎导致“有画面但无识别”。
    if (recogStore.recogEngineType !== RecogEngineType.OFFLINE_NCNN) {
      recogStore.setRecogEngineType(RecogEngineType.OFFLINE_NCNN)
    }
    // 根据模型开关设置阈值：yolov26barrier 略低，traffic 略高以减少误检。
    // Speed-first tuning: raise yolov26barrier confidence to cut proposals and postprocess cost.
    const wantedConf: number = videoStore.page2Yolov26BarrierExperimentalEnabled ? 0.25 : 0.28
    if (Math.abs(recogStore.recogOfflineConfThresh - wantedConf) > 0.001) {
      recogStore.setRecogOfflineConfThresh(wantedConf)
    }
  }

  private async dispatchLiveRecognition(frame: VideoFrame, recogPm: image.PixelMap): Promise<void> { 
    try {
      const liveSubtype: RecognitionSubtype | undefined = this.currentLiveSubtype()
      if (liveSubtype === undefined) return
      if (videoStore.page2Yolov26BarrierExperimentalEnabled && liveSubtype === RecognitionSubtype.YOLOV26BARRIER) {
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

  private async isValidJpegSnapshot(data: ArrayBuffer): Promise<boolean> {
    if (!data || data.byteLength <= 64) return false
    let pm: image.PixelMap | undefined = undefined
    try {
      pm = await this.jpegToPixelMap(data)
      const info: image.ImageInfo = await pm.getImageInfo()
      return info.size.width > 0 && info.size.height > 0
    } catch (_) {
      return false
    } finally {
      if (pm) {
        try { pm.release() } catch (_) {}
      }
    }
  }

  private async maybeEnqueueTrafficCascade(currentPm: image.PixelMap): Promise<void> {
    const nowMs: number = Date.now()
    if (nowMs - this.lastTrafficCascadeAtMs < this.trafficCascadeMinIntervalMs) return
    if (this.trafficCascadeBusy) return
    this.trafficCascadeBusy = true

    try {
      const last: RecognitionResult | undefined = recogStore.lastRecog
      const marker: BBoxNorm | undefined = this.pickTrafficLightMarkerFromYolov26Barrier(last)
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
    this.recognitionPauseUntilMs = 0
    this.currentLiveIntervalMs = 120
    this.lastLiveCadenceTuneAtMs = 0
    this.lastRecogFailCount = recogStore.recogFail
    this.recog.setLiveIntervalMs(this.currentLiveIntervalMs)
    this.dynamicReplayIngestIntervalMs = this.replayIngestMinIntervalMs
    this.lastReplayCadenceTuneAtMs = 0
    this.ensurePage2RecognitionConfig()
    videoStore.setStatus(`Page2 mode switched: ${this.modeText()}`)
  }

  private tuneReplayIngestCadence(nowMs: number): void {
    if (nowMs - this.lastReplayCadenceTuneAtMs < this.replayCadenceTuneWindowMs) return
    this.lastReplayCadenceTuneAtMs = nowMs

    const videoLatencyMs: number = Math.max(0, Math.trunc(videoStore.diagVideoLatencyMs))
    let nextMs: number = this.dynamicReplayIngestIntervalMs
    if (videoLatencyMs >= 300) {
      nextMs += 60
    } else if (videoLatencyMs >= 220 || recogStore.ncnnWorkerBypass) {
      nextMs += 40
    } else if (videoLatencyMs <= 120 && !recogStore.recogBusy) {
      nextMs -= 20
    }
    nextMs = Math.max(this.replayIngestMinIntervalMs, Math.min(this.replayIngestMaxIntervalMs, nextMs))
    this.dynamicReplayIngestIntervalMs = nextMs
  }

  private tuneLiveRecognitionCadence(nowMs: number): void {
    if (nowMs - this.lastLiveCadenceTuneAtMs < this.liveCadenceTuneWindowMs) return
    this.lastLiveCadenceTuneAtMs = nowMs

    const costMs: number = Math.max(0, Math.trunc(recogStore.recogLastCostMs))
    const videoLatencyMs: number = Math.max(0, Math.trunc(videoStore.diagVideoLatencyMs))
    const failDelta: number = Math.max(0, recogStore.recogFail - this.lastRecogFailCount)
    this.lastRecogFailCount = recogStore.recogFail

    let nextMs: number = this.currentLiveIntervalMs
    if (videoLatencyMs >= 280) {
      nextMs += this.liveCadenceTuneStepUpMs * 2
    } else if (failDelta > 0 || costMs >= 260) {
      nextMs += this.liveCadenceTuneStepUpMs * 2
    } else if (costMs >= 180 || recogStore.recogBusy || videoLatencyMs >= 190) {
      nextMs += this.liveCadenceTuneStepUpMs
    } else if (costMs <= 90 && videoLatencyMs <= 120) {
      nextMs -= this.liveCadenceTuneStepDownMs * 2
    } else if (costMs <= 120 && videoLatencyMs <= 150) {
      nextMs -= this.liveCadenceTuneStepDownMs
    }

    nextMs = Math.max(this.page2LiveIntervalMinMs, Math.min(this.page2LiveIntervalMaxMs, nextMs))
    if (nextMs === this.currentLiveIntervalMs) return
    this.currentLiveIntervalMs = nextMs
    this.recog.setLiveIntervalMs(this.currentLiveIntervalMs)
    console.info(
      `[Page2] live cadence tuned interval=${this.currentLiveIntervalMs}ms cost=${costMs}ms videoLatency=${videoLatencyMs}ms failDelta=${failDelta}`
    )
  }

  private maybeLogPerfPulse(nowMs: number): void {
    this.maybeHealFramePipeline(nowMs)
    if (nowMs - this.lastPerfPulseLogAtMs < 2000) return
    this.lastPerfPulseLogAtMs = nowMs
    const total: number = Math.max(0, recogStore.ncnnTotalDetect)
    const fallback: number = Math.max(0, recogStore.ncnnFallbackUsed)
    const fallbackRate: number = total > 0 ? (fallback * 100.0 / total) : 0
    const fallbackRateText: string = fallbackRate.toFixed(1)
    console.info(
      `[PERF][pulse] vFps=${videoStore.diagVideoFps} vLat=${videoStore.diagVideoLatencyMs}ms pull=${videoStore.diagVideoPullIntervalMs}ms rFps=${recogStore.recogFps} rCost=${recogStore.recogLastCostMs}ms liveInt=${this.currentLiveIntervalMs}ms repInt=${this.dynamicReplayIngestIntervalMs}ms rPause=${Date.now() < this.recognitionPauseUntilMs ? 1 : 0} wkCost=${recogStore.ncnnWorkerCostMs}ms wkFail=${recogStore.ncnnWorkerFail} fallback=${recogStore.ncnnFallbackUsed}/${recogStore.ncnnTotalDetect}(${fallbackRateText}%) bypass=${recogStore.ncnnWorkerBypass ? 1 : 0}`
    )
  }

  private maybeHealFramePipeline(nowMs: number): void {
    if (!this.started || this.starting || this.prewarming) return
    if (this.activeSnapshotUrl.length <= 0) return
    const lastOkAtMs: number = Math.max(0, Math.trunc(videoStore.lastOkFrameTimeMs))
    if (lastOkAtMs <= 0) return
    if (nowMs - lastOkAtMs < this.frameStallThresholdMs) return
    this.maybeSoftRestartHttpPipeline(nowMs, `frame stall ${nowMs - lastOkAtMs}ms`)
  }

  onYolov26BarrierModeChanged(): void {
    this.onModelSwitchChanged()
  }

  private pickTrafficLightMarkerFromYolov26Barrier(result: RecognitionResult | undefined): BBoxNorm | undefined {
    if (!result || !result.ok) return undefined
    if (result.subtype !== RecognitionSubtype.YOLOV26BARRIER) return undefined
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

  enqueueSnapshotRecognitionFromPixelMap(
    pm: image.PixelMap,
    source: RecognitionTaskSource,
    forceSubtype?: RecognitionSubtype,
    releaseAfterUse: boolean = true
  ): string {
    const subtype: RecognitionSubtype = forceSubtype !== undefined ? forceSubtype : this.preferredSnapshotSubtype()
    const fullRoi: RoiNorm = { x: 0, y: 0, w: 1, h: 1 }
    return this.recog.enqueueSnapshotFromPixelMapWithRoi(pm, fullRoi, subtype, source, releaseAfterUse)
  }

  enqueueSnapshotRecognitionFromGalleryUri(uri: string, forceSubtype: RecognitionSubtype = RecognitionSubtype.YOLOV26BARRIER): string {
    return this.recog.enqueueSnapshotFromGalleryUri(uri, forceSubtype)
  }

  private preferredSnapshotSubtype(): RecognitionSubtype {
    if (videoStore.page2TrafficEnabled) return RecognitionSubtype.TRAFFIC_LIGHT
    return RecognitionSubtype.YOLOV26BARRIER
  }

  private maybeAutoSnapshotFromVision(currentPm: image.PixelMap, nowMs: number): void {
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.boxes.length <= 0) return
    if (r.source !== RecognitionTaskSource.PAGE2_BUTTON) return
    if (r.kind !== RecognitionTaskKind.LIVE) return
    if (r.subtype !== RecognitionSubtype.YOLOV26BARRIER && r.subtype !== RecognitionSubtype.TRAFFIC_LIGHT) return
    if (r.taskId.length > 0 && r.taskId === this.lastAutoSnapTaskId) return
    if (nowMs - this.lastAutoSnapAtMs < this.autoSnapMinIntervalMs) return
    if (this.autoSnapBusy) return

    this.lastAutoSnapTaskId = r.taskId
    this.lastAutoSnapAtMs = nowMs
    this.autoSnapBusy = true
    void this.captureOriginalFromRecognition(currentPm, r).finally((): void => {
      this.autoSnapBusy = false
    })
    void page2ReplayService.onVisionObstacleDetected(r)
  }

  private async captureOriginalFromRecognition(pm: image.PixelMap, r: RecognitionResult): Promise<void> {
    let previewPm: image.PixelMap | undefined = undefined
    let galleryPm: image.PixelMap | undefined = undefined
    try {
      previewPm = await this.clonePixelMap(pm)
      galleryPm = await this.clonePixelMap(pm)
      if (previewPm) {
        videoStore.setSnapshot(previewPm)
        previewPm = undefined
      }
      if (galleryPm) {
        const tag: string = r.subtype === RecognitionSubtype.TRAFFIC_LIGHT ? 'traffic' : 'yolov26barrier'
        await page2ReplayService.archiveOriginalSnapshotToGallery(galleryPm, tag)
      }
    } finally {
      if (previewPm) {
        try { previewPm.release() } catch (_) {}
      }
      if (galleryPm) {
        try { galleryPm.release() } catch (_) {}
      }
    }
  }

  private maybeRecordShigongReplay(nowMs: number): void {
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok) return
    if (r.subtype !== RecognitionSubtype.YOLOV26BARRIER) return
    if (r.taskId.length > 0 && r.taskId === this.lastShigongReplayTaskId) return
    if (nowMs - this.lastShigongReplaySubmitAtMs < this.shigongReplaySubmitMinIntervalMs) return
    this.lastShigongReplaySubmitAtMs = nowMs
    this.lastShigongReplayTaskId = r.taskId
    void page2ReplayService.onShigongRecognition(r)
  }

  private refreshRecognitionPause(nowMs: number): void {
    const videoLatencyMs: number = Math.max(0, Math.trunc(videoStore.diagVideoLatencyMs))
    const pullMs: number = Math.max(0, Math.trunc(videoStore.diagVideoPullIntervalMs))
    const vFps: number = Math.max(0, Math.trunc(videoStore.diagVideoFps))
    if (videoLatencyMs >= 1200) {
      this.recognitionPauseUntilMs = Math.max(this.recognitionPauseUntilMs, nowMs + 1800)
      return
    }
    if (videoLatencyMs >= 800) {
      this.recognitionPauseUntilMs = Math.max(this.recognitionPauseUntilMs, nowMs + 900)
      return
    }
    if (pullMs >= 300 || vFps <= 1) {
      this.recognitionPauseUntilMs = Math.max(this.recognitionPauseUntilMs, nowMs + 800)
    }
  }

  private isVideoOverloaded(): boolean {
    const videoLatencyMs: number = Math.max(0, Math.trunc(videoStore.diagVideoLatencyMs))
    const pullMs: number = Math.max(0, Math.trunc(videoStore.diagVideoPullIntervalMs))
    const vFps: number = Math.max(0, Math.trunc(videoStore.diagVideoFps))
    if (videoLatencyMs >= 800) return true
    if (pullMs >= 300) return true
    return vFps <= 1
  }

  private currentLiveSubtype(): RecognitionSubtype | undefined {
    if (videoStore.page2TrafficEnabled) {
      return this.isTrafficGatePoseMatched() ? RecognitionSubtype.TRAFFIC_LIGHT : undefined
    }
    if (videoStore.page2Yolov26BarrierExperimentalEnabled) return RecognitionSubtype.YOLOV26BARRIER
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
    if (videoStore.page2Yolov26BarrierExperimentalEnabled) return 'yolov26barrier'
    return 'none'
  }
}

export const page2Coordinator: Page2Coordinator = new Page2Coordinator()
