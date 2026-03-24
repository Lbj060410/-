/**
 * 代码指南：
 * 文件： services/source/RtspHttpSwitchManager.ets
 * 用途： Video/frame source management (HTTP snapshot, RTSP, local video switch).
 * 何时修改： changing source pipeline or adding a new source type.
 * 相关文件： services/recognition/* and page2 view/coordinator.
 */
import resourceManager from '@ohos.resourceManager'
import { VideoStore, DisplayMode, RtspState } from '../../state/VideoStore'
import { RtspPlayerService } from './RtspPlayerService'
import { FrameSourceManager } from './FrameSourceManager'

export class RtspHttpSwitchManager {
  private readonly store: VideoStore
  private readonly rtsp: RtspPlayerService
  private readonly frames: FrameSourceManager

  private rm?: resourceManager.ResourceManager

  private timerId: number = -1
  private running: boolean = false
  private rtspRetryInFlight: boolean = false
  private rtspDisabled: boolean = false
  private rtspFailCount: number = 0

  private rtspStartAtMs: number = 0

  constructor(store: VideoStore, rtsp: RtspPlayerService, frames: FrameSourceManager) {
    this.store = store
    this.rtsp = rtsp
    this.frames = frames
  }

  bindResourceManager(rm: resourceManager.ResourceManager): void {
    this.rm = rm
  }

  startAutoSwitch(rtspUrl: string, httpUrl: string, tickMs: number): void {
    // HTTP frames are pulled by FrameSourceManager.
    void httpUrl
    this.stop()

    this.running = true
    this.rtspRetryInFlight = false
    this.rtspDisabled = false
    this.rtspFailCount = 0

    // Try RTSP once on startup; if it is unsupported, disable retry.
    this.rtspStartAtMs = Date.now()
    void this.tryStartRtsp(rtspUrl, 'startup')

    this.timerId = setInterval(() => {
      this.tick(rtspUrl)
    }, tickMs) as number
  }

  stop(): void {
    this.running = false
    this.rtspRetryInFlight = false
    this.rtspFailCount = 0
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private tick(rtspUrl: string): void {
    if (!this.running) return
    if (!this.store.autoSwitchEnabled) return

    const now: number = Date.now()
    const sinceLastSwitch: number = now - this.store.lastSwitchAtMs
    if (sinceLastSwitch < this.store.switchCooldownMs) return

    // If UI is on RTSP but RTSP is not ready for too long, fallback to HTTP.
    if (this.store.displayMode === DisplayMode.RTSP) {
      const rtspNotReady: boolean = this.store.rtspState !== RtspState.READY
      if (rtspNotReady && (now - this.rtspStartAtMs) > 5000) {
        this.store.setDisplayMode(DisplayMode.HTTP, 'rtsp not ready >5s')
        this.store.setStatus('RTSP not ready, fallback to HTTP')
        return
      }
    }

    // If HTTP is stale and RTSP is ready, switch back to RTSP.
    if (this.store.displayMode === DisplayMode.HTTP) {
      const httpStale: boolean = (now - this.store.lastFrameTimeMs) > 3000
      const rtspReady: boolean = !this.rtspDisabled && this.store.rtspState === RtspState.READY
      if (httpStale && rtspReady) {
        this.store.setDisplayMode(DisplayMode.RTSP, 'http stale & rtsp ready')
        this.store.setStatus('HTTP stale, switch to RTSP')
        return
      }
    }

    // Retry RTSP only when allowed.
    if (this.store.rtspState === RtspState.ERROR &&
      !this.rtspRetryInFlight &&
      !this.rtspDisabled) {
      void this.tryStartRtsp(rtspUrl, 'retry')
    }
  }

  private async tryStartRtsp(rtspUrl: string, source: string): Promise<void> {
    if (this.rtspRetryInFlight || this.rtspDisabled) return

    this.rtspRetryInFlight = true
    this.rtspStartAtMs = Date.now()
    try {
      const ok: boolean = await this.rtsp.playRtsp(rtspUrl)
      if (ok) {
        this.rtspFailCount = 0
        return
      }

      this.rtspFailCount += 1
      const err: string = this.store.lastErrorText
      const unsupported: boolean = err.indexOf('not fd:// or network address') >= 0 ||
        err.indexOf('Invalid Parameter') >= 0
      if (unsupported || this.rtspFailCount >= 2) {
        this.rtspDisabled = true
        this.store.setDisplayMode(DisplayMode.HTTP, 'rtsp disabled')
        this.store.setStatus(`RTSP unavailable, use HTTP (${source})`)
      }
    } finally {
      this.rtspRetryInFlight = false
    }
  }
}

