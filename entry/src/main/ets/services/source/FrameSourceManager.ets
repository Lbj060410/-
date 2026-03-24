/**
 * 代码指南：
 * 文件： services/source/FrameSourceManager.ets
 * 用途： Video/frame source management (HTTP snapshot, RTSP, local video switch).
 * 何时修改： changing source pipeline or adding a new source type.
 * 相关文件： services/recognition/* and page2 view/coordinator.
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

export class FrameSourceManager {
  private readonly store: VideoStore
  private readonly http: HttpSnapshotService

  private timerId: number = -1
  private running: boolean = false
  private inFlightSession: number = -1
  private sessionToken: number = 0
  private httpIntervalMs: number = 150
  private fpsWindowStartMs: number = Date.now()
  private fpsWindowCount: number = 0

  private onFrame?: FrameListener

  constructor(store: VideoStore) {
    this.store = store
    this.http = new HttpSnapshotService()
  }

  setOnFrame(listener?: FrameListener): void {
    this.onFrame = listener
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
    this.fpsWindowStartMs = Date.now()
    this.fpsWindowCount = 0

    this.timerId = setInterval(() => {
      void this.loopOnce(url, token)
    }, this.httpIntervalMs) as number
  }

  stop(): void {
    this.running = false
    this.sessionToken += 1
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
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

    try {
      const reqStartAtMs: number = Date.now()
      const requestUrl: string = this.withNoCache(url)
      // 低延迟优先：进一步收紧到 0.45s，宁可丢帧也不要拖尾。
      const frame: VideoFrame = await this.pullHttpFrame(requestUrl, 450)
      const pm: PixelMap = await this.jpegToPixelMap(frame.jpeg)
      if (!this.isSessionActive(token)) {
        try { pm.release() } catch (_) {}
        return
      }
      try {
        // 同步记录当前实时帧分辨率，供 page2 叠加识别框按比例换算坐标。
        const info: image.ImageInfo = await pm.getImageInfo()
        this.store.setLiveFrameSize(info.size.width, info.size.height)
      } catch (_) {
        this.store.setLiveFrameSize(0, 0)
      }
      if (!this.isSessionActive(token)) {
        try { pm.release() } catch (_) {}
        return
      }

      this.store.setLivePixelMap(pm)
      this.store.markFrame(true, 'http ok')
      this.updateDiag(Date.now() - reqStartAtMs)
      console.info(`[HTTP] frame ok bytes=${frame.jpeg.byteLength} ts=${frame.tsMs}`)

      const cb = this.onFrame
      if (cb) cb(frame, pm)
    } catch (e) {
      if (!this.isSessionActive(token)) return
      const msg: string = e instanceof Error ? e.message : 'http frame failed'
      this.store.markFrame(false, msg)
      this.store.setError(msg)
      this.updateDiag(0)
      console.error(`[HTTP] frame fail ${msg}`)
    } finally {
      if (this.inFlightSession === token) {
        this.inFlightSession = -1
      }
    }
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
      this.store.setDiagVideo(fps, latencyMs > 0 ? latencyMs : this.store.diagVideoLatencyMs)
      return
    }

    if (latencyMs > 0) {
      this.store.setDiagVideo(this.store.diagVideoFps, latencyMs)
    }
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



