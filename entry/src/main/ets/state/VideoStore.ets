/**
 * 代码指南：
 * 文件： state/VideoStore.ets
 * 用途： 应用级共享状态/存储模块。
 * 何时修改： 新增跨页面状态或调整全局数据结构时。
 * 相关文件： 读写状态存储值的页面视图、协调器及各类服务。
 */
// entry/src/main/ets/state/VideoStore.ets
import image from '@ohos.multimedia.image'
import { CAR_CAMERA_PASS, CAR_CAMERA_USER, defaultCameraHost, defaultRtspUrl } from '../config/DeviceNetworkConfig'
type PixelMap = image.PixelMap

export enum DisplayMode {
  RTSP = 0,
  HTTP = 1,
  LOCAL = 2
}

export enum RtspState {
  IDLE = 0,
  PREPARING = 1,
  READY = 2,
  ERROR = 3
}

@Observed
export class VideoStore {
  // ==== 摄像头配置 ====
  cameraHost: string = defaultCameraHost()
  cameraUser: string = CAR_CAMERA_USER
  cameraPass: string = CAR_CAMERA_PASS
  rtspUrl: string = defaultRtspUrl()
  rawfileName: string = 'text.mp4'

  // ==== 显示/切换 ====
  displayMode: DisplayMode = DisplayMode.HTTP
  autoSwitchEnabled: boolean = true
  switchCooldownMs: number = 2500
  lastSwitchAtMs: number = 0
  lastSwitchReason: string = '-'

  // ==== RTSP 状态 ====
  rtspState: RtspState = RtspState.IDLE
  rtspStateText: string = 'idle'

  // ==== HTTP/Rtsp 帧统计 ====
  diagVideoFps: number = 0
  diagVideoLatencyMs: number = 0
  diagVideoPullIntervalMs: number = 0
  lastFrameTimeMs: number = 0
  lastOkFrameTimeMs: number = 0
  lastFailFrameTimeMs: number = 0
  frameOkCount: number = 0
  frameFailCount: number = 0
  consecutiveFrameOkCount: number = 0
  consecutiveFrameFailCount: number = 0
  statusText: string = ''
  lastErrorText: string = ''

  // ==== HTTP 显示画面 ====
  livePixelMap?: PixelMap
  // 最近一帧画面的原始分辨率（用于识别框坐标换算）
  // 改这两个值会直接影响 page2 叠加框在画面上的位置/尺寸。
  liveFrameWidth: number = 0
  liveFrameHeight: number = 0

  // ==== Snapshot ====
  snapshotPixelMap?: PixelMap
  snapshotAtMs: number = 0
  // ==== Page2 自动预览（来自 Page4），与业务快照解耦 ====
  page2AutoPreviewPixelMap?: PixelMap
  page2AutoPreviewAtMs: number = 0

  // ==== 识别调度预留 ====
  recognitionEnabled: boolean = true
  lastRecognizeAtMs: number = 0
  recognizeIntervalMs: number = 200
  // Page2 yolov26barrier 模型开关：默认开启。
  page2Yolov26BarrierExperimentalEnabled: boolean = true
  // Page2 traffic 模型开关：默认关闭。
  // 与 yolov26barrier 互斥：traffic 开启时 yolov26barrier 自动关闭。
  page2TrafficEnabled: boolean = false

  // ==== RTSP 状态方法 ====
  setRtspState(s: RtspState, text: string): void {
    this.rtspState = s
    this.rtspStateText = text
  }

  markSwitch(mode: DisplayMode, reason: string): void {
    this.displayMode = mode
    this.lastSwitchAtMs = Date.now()
    this.lastSwitchReason = reason
  }

  setDisplayMode(mode: DisplayMode, reason: string): void {
    this.markSwitch(mode, reason)
  }

  // 统一入口：替换前先 release 旧 PixelMap，避免原生内存泄漏
  setLivePixelMap(pm: PixelMap): void {
    const old: PixelMap | undefined = this.livePixelMap
    this.livePixelMap = pm
    if (old && old !== pm) this.releasePixelMapLater(old)
  }

  setLiveFrameSize(width: number, height: number): void {
    const safeWidth: number = Math.max(0, Math.floor(width))
    const safeHeight: number = Math.max(0, Math.floor(height))
    this.liveFrameWidth = safeWidth
    this.liveFrameHeight = safeHeight
  }

  setSnapshot(pm?: PixelMap): void {
    const old: PixelMap | undefined = this.snapshotPixelMap
    this.snapshotPixelMap = pm
    this.snapshotAtMs = Date.now()
    if (old && old !== pm) this.releasePixelMapLater(old)
  }

  setPage2AutoPreview(pm?: PixelMap): void {
    const old: PixelMap | undefined = this.page2AutoPreviewPixelMap
    this.page2AutoPreviewPixelMap = pm
    this.page2AutoPreviewAtMs = Date.now()
    if (old && old !== pm) this.releasePixelMapLater(old)
    // 强制触发状态更新
    this.statusText = `Page2已更新 ${this.page2AutoPreviewAtMs}`
  }

  private releasePixelMapLater(pm: PixelMap): void {
    // Avoid immediate free while UI/render thread may still reference previous frame.
    setTimeout((): void => {
      try { pm.release() } catch (_) {}
    }, 1500)
  }

  setStatus(text: string): void { this.statusText = text }

  setError(text: string): void { this.lastErrorText = text }

  markFrame(ok: boolean, reason: string): void {
    const now: number = Date.now()
    this.lastFrameTimeMs = now
    if (ok) {
      this.lastOkFrameTimeMs = now
      this.frameOkCount += 1
      this.consecutiveFrameOkCount += 1
      this.consecutiveFrameFailCount = 0
    } else {
      this.lastFailFrameTimeMs = now
      this.frameFailCount += 1
      this.consecutiveFrameFailCount += 1
      this.consecutiveFrameOkCount = 0
      this.lastErrorText = reason
    }
  }

  clearHttpStats(): void {
    this.frameOkCount = 0
    this.frameFailCount = 0
    this.consecutiveFrameOkCount = 0
    this.consecutiveFrameFailCount = 0
  }

  setRecognitionEnabled(enabled: boolean): void { this.recognitionEnabled = enabled }

  setRecognizeIntervalMs(ms: number): void { this.recognizeIntervalMs = ms }
  setPage2Yolov26BarrierEnabled(enabled: boolean): void {
    if (enabled) {
      this.page2Yolov26BarrierExperimentalEnabled = true
      this.page2TrafficEnabled = false
      return
    }
    this.page2Yolov26BarrierExperimentalEnabled = false
    this.page2TrafficEnabled = true
  }

  setPage2TrafficEnabled(enabled: boolean): void {
    if (enabled) {
      this.page2TrafficEnabled = true
      this.page2Yolov26BarrierExperimentalEnabled = false
      return
    }
    this.page2TrafficEnabled = false
    this.page2Yolov26BarrierExperimentalEnabled = true
  }

  // Compatibility: keep old API name, now mapped to yolov26barrier toggle semantics.
  setPage2Yolov26BarrierExperimentalEnabled(enabled: boolean): void { this.setPage2Yolov26BarrierEnabled(enabled) }

  setDiagVideo(fps: number, latencyMs: number, pullIntervalMs?: number): void {
    this.diagVideoFps = fps
    this.diagVideoLatencyMs = latencyMs
    if (typeof pullIntervalMs === 'number' && Number.isFinite(pullIntervalMs)) {
      this.diagVideoPullIntervalMs = Math.max(0, Math.trunc(pullIntervalMs))
    }
  }
}

export const videoStore: VideoStore = new VideoStore()
