/**
 * 代码指南：
 * 文件： services/source/FrameSourceManager.ets
 * 用途： 视频/帧源管理（HTTP截图、RTSP、本地视频切换）。
 * 何时修改： 修改源处理流程或新增源类型时。
 * 相关文件： services/recognition/* 及 page2 视图/协调器。
 */
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap
import { HttpSnapshotService } from './HttpSnapshotService'
import { VideoStore } from '../../state/VideoStore'

export enum FrameSourceType {
  HTTP = 0
}

export interface VideoFrame {
  source: FrameSourceType
  tsMs: number
  jpeg: ArrayBuffer
}

export type FrameListener = (frame: VideoFrame, pixelMap: PixelMap) => void
export type FrameHealthListener = (ok: boolean, reason: string, failStreak: number) => void

export class FrameSourceManager {
  private readonly store: VideoStore
  private readonly http: HttpSnapshotService

  private timerId: number = -1
  private running: boolean = false
  private inFlightSession: number = -1
  private sessionToken: number = 0
  private httpIntervalMs: number = 150
  private dynamicIntervalMs: number = 150
  private readonly minIntervalMs: number = 70
  private readonly maxIntervalMs: number = 380
  private readonly minRequestTimeoutMs: number = 420
  private readonly maxRequestTimeoutMs: number = 1200
  private fpsWindowStartMs: number = Date.now()
  private fpsWindowCount: number = 0
  private lastLiveSizeProbeAtMs: number = 0
  private lastDiagPushAtMs: number = 0
  private readonly diagPushMinIntervalMs: number = 500
  private lastOkLogAtMs: number = 0
  private lastFailLogAtMs: number = 0
  private lastFailText: string = ''
  private consecutiveHttpOkCount: number = 0
  private consecutiveHttpFailCount: number = 0

  private onFrame?: FrameListener
  private onFrameHealth?: FrameHealthListener

  constructor(store: VideoStore) {
    this.store = store
    this.http = new HttpSnapshotService()
  }

  setOnFrame(listener?: FrameListener): void {
    this.onFrame = listener
  }

  setOnFrameHealth(listener?: FrameHealthListener): void {
    this.onFrameHealth = listener
  }

  async pullHttpFrame(url: string, timeoutMs: number): Promise<VideoFrame> {
    const jpeg: ArrayBuffer = await this.http.fetchJpeg(url, timeoutMs)
    return { source: FrameSourceType.HTTP, tsMs: Date.now(), jpeg }
  }

  startHttp(url: string, intervalMs: number): void {
    this.stop()
    this.sessionToken += 1
    const token: number = this.sessionToken
    this.running = true
    this.httpIntervalMs = Math.max(50, Math.min(1000, intervalMs))
    this.dynamicIntervalMs = Math.max(this.minIntervalMs, Math.min(this.maxIntervalMs, this.httpIntervalMs))
    this.fpsWindowStartMs = Date.now()
    this.fpsWindowCount = 0
    this.lastLiveSizeProbeAtMs = 0
    this.lastDiagPushAtMs = 0
    this.lastOkLogAtMs = 0
    this.lastFailLogAtMs = 0
    this.lastFailText = ''
    this.consecutiveHttpOkCount = 0
    this.consecutiveHttpFailCount = 0
    this.scheduleNextLoop(url, token, 0)
  }

  stop(): void {
    this.running = false
    this.sessionToken += 1
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    this.inFlightSession = -1
  }

  private isSessionActive(token: number): boolean {
    return this.running && token === this.sessionToken
  }

  private async loopOnce(url: string, token: number): Promise<void> {
    if (!this.isSessionActive(token)) return
    if (this.inFlightSession === token) return
    this.inFlightSession = token
    const loopStartAtMs: number = Date.now()
    let fetchOk: boolean = false

    try {
      const reqStartAtMs: number = Date.now()
      const requestUrl: string = this.withNoCache(url)
      const timeoutMs: number = this.resolveRequestTimeoutMs()
      const frame: VideoFrame = await this.pullHttpFrame(requestUrl, timeoutMs)
      const pm: PixelMap = await this.jpegToPixelMap(frame.jpeg)
      if (!this.isSessionActive(token)) {
        try { pm.release() } catch (_) {}
        return
      }
      this.updateLiveSizeIfNeeded(pm, reqStartAtMs)
      if (!this.isSessionActive(token)) {
        try { pm.release() } catch (_) {}
        return
      }

      this.store.setLivePixelMap(pm)
      this.store.markFrame(true, 'http ok')
      this.consecutiveHttpOkCount += 1
      this.consecutiveHttpFailCount = 0
      this.updateDiag(Date.now() - reqStartAtMs)
      this.maybeLogFrameOk(frame, reqStartAtMs)
      this.notifyFrameHealth(true, 'http ok')
      fetchOk = true

      const cb = this.onFrame
      if (cb) cb(frame, pm)
    } catch (e) {
      if (!this.isSessionActive(token)) return
      const msg: string = e instanceof Error ? e.message : 'http frame failed'
      this.store.markFrame(false, msg)
      this.consecutiveHttpFailCount += 1
      this.consecutiveHttpOkCount = 0
      if (this.consecutiveHttpFailCount >= 2) {
        this.store.setError(msg)
      }
      this.updateDiag(0)
      this.maybeLogFrameFail(msg)
      this.notifyFrameHealth(false, msg)
    } finally {
      if (this.inFlightSession === token) {
        this.inFlightSession = -1
      }
      if (this.isSessionActive(token)) {
        const elapsedMs: number = Date.now() - loopStartAtMs
        const nextDelayMs: number = fetchOk
          ? Math.max(12, this.dynamicIntervalMs - elapsedMs)
          : this.resolveFailRetryDelayMs(elapsedMs)
        this.scheduleNextLoop(url, token, nextDelayMs)
      }
    }
  }

  private resolveRequestTimeoutMs(): number {
    const dyn: number = Math.max(this.minIntervalMs, Math.trunc(this.dynamicIntervalMs))
    const recentLatency: number = Math.max(0, Math.trunc(this.store.diagVideoLatencyMs))
    let timeoutMs: number = Math.max(this.minRequestTimeoutMs, dyn * 2 + 140)
    if (recentLatency > 0) {
      timeoutMs = Math.max(timeoutMs, recentLatency + 180)
    }
    if (this.consecutiveHttpFailCount >= 3) {
      timeoutMs += 180
    } else if (this.consecutiveHttpFailCount >= 1) {
      timeoutMs += 100
    }
    return Math.max(this.minRequestTimeoutMs, Math.min(this.maxRequestTimeoutMs, timeoutMs))
  }

  private resolveFailRetryDelayMs(elapsedMs: number): number {
    const dyn: number = Math.max(this.minIntervalMs, Math.trunc(this.dynamicIntervalMs))
    const elapsed: number = Math.max(0, Math.trunc(elapsedMs))
    let targetMs: number = Math.max(dyn, 120)
    if (this.consecutiveHttpFailCount >= 6) {
      targetMs += 160
    } else if (this.consecutiveHttpFailCount >= 3) {
      targetMs += 100
    } else {
      targetMs += 60
    }
    return Math.max(60, targetMs - Math.min(elapsed, targetMs - 40))
  }

  private scheduleNextLoop(url: string, token: number, delayMs: number): void {
    if (!this.isSessionActive(token)) return
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    const safeDelayMs: number = Math.max(0, Math.trunc(delayMs))
    this.timerId = setTimeout(() => {
      this.timerId = -1
      if (!this.isSessionActive(token)) return
      void this.loopOnce(url, token)
    }, safeDelayMs) as number
  }

  private withNoCache(url: string): string {
    const ts: number = Date.now()
    const sep: string = url.indexOf('?') >= 0 ? '&' : '?'
    return `${url}${sep}_ts=${ts}`
  }

  private updateDiag(latencyMs: number): void {
    const now: number = Date.now()
    if (latencyMs > 0) {
      this.fpsWindowCount += 1
    }

    if (now - this.fpsWindowStartMs >= 1000) {
      const sec: number = (now - this.fpsWindowStartMs) / 1000
      const fps: number = sec > 0 ? Math.round(this.fpsWindowCount / sec) : 0
      this.fpsWindowStartMs = now
      this.fpsWindowCount = 0
      this.store.setDiagVideo(
        fps,
        latencyMs > 0 ? latencyMs : this.store.diagVideoLatencyMs,
        this.dynamicIntervalMs
      )
      this.lastDiagPushAtMs = now
      return
    }

    if (latencyMs > 0 && now - this.lastDiagPushAtMs >= this.diagPushMinIntervalMs) {
      this.store.setDiagVideo(this.store.diagVideoFps, latencyMs, this.dynamicIntervalMs)
      this.lastDiagPushAtMs = now
    }
    this.tuneDynamicInterval(latencyMs)
  }

  private tuneDynamicInterval(latencyMs: number): void {
    let nextMs: number = this.dynamicIntervalMs
    if (this.consecutiveHttpFailCount >= 4) {
      nextMs += 80
    } else if (this.consecutiveHttpFailCount >= 2) {
      nextMs += 60
    } else if (latencyMs <= 0) {
      nextMs += 45
    } else if (latencyMs >= 420) {
      nextMs += 40
    } else if (latencyMs > this.dynamicIntervalMs + 120) {
      nextMs += 25
    } else if (this.consecutiveHttpOkCount >= 4 && latencyMs < this.dynamicIntervalMs - 80) {
      nextMs -= 15
    } else if (latencyMs < this.dynamicIntervalMs - 60) {
      nextMs -= 10
    }
    nextMs = Math.max(this.minIntervalMs, Math.min(this.maxIntervalMs, nextMs))
    this.dynamicIntervalMs = nextMs
  }

  private notifyFrameHealth(ok: boolean, reason: string): void {
    const cb = this.onFrameHealth
    if (!cb) return
    cb(ok, reason, this.consecutiveHttpFailCount)
  }

  private updateLiveSizeIfNeeded(pm: PixelMap, nowMs: number): void {
    const needProbe: boolean =
      this.store.liveFrameWidth <= 0 ||
      this.store.liveFrameHeight <= 0 ||
      (nowMs - this.lastLiveSizeProbeAtMs >= 1000)
    if (!needProbe) return

    this.lastLiveSizeProbeAtMs = nowMs
    void pm.getImageInfo().then((info: image.ImageInfo): void => {
      this.store.setLiveFrameSize(info.size.width, info.size.height)
    }).catch((_): void => {
      this.store.setLiveFrameSize(0, 0)
    })
  }

  private maybeLogFrameOk(frame: VideoFrame, nowMs: number): void {
    if (nowMs - this.lastOkLogAtMs < 3000) return
    this.lastOkLogAtMs = nowMs
    console.info(`[HTTP] frame ok bytes=${frame.jpeg.byteLength} ts=${frame.tsMs}`)
  }

  private maybeLogFrameFail(msg: string): void {
    const nowMs: number = Date.now()
    const changed: boolean = msg !== this.lastFailText
    if (!changed && nowMs - this.lastFailLogAtMs < 2000) return
    this.lastFailLogAtMs = nowMs
    this.lastFailText = msg
    console.error(`[HTTP] frame fail ${msg}`)
  }

  private async jpegToPixelMap(jpeg: ArrayBuffer): Promise<PixelMap> {
    const src: image.ImageSource = image.createImageSource(jpeg)
    try {
      return await src.createPixelMap()
    } finally {
      src.release()
    }
  }
}
