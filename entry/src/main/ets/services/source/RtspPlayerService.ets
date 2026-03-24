/**
 * 代码指南：
 * 文件： services/source/RtspPlayerService.ets
 * 用途： Video/frame source management (HTTP snapshot, RTSP, local video switch).
 * 何时修改： changing source pipeline or adding a new source type.
 * 相关文件： services/recognition/* and page2 view/coordinator.
 */
// entry/src/main/ets/services/source/RtspPlayerService.ets
import media from '@ohos.multimedia.media'
import resourceManager from '@ohos.resourceManager'
import { VideoStore, RtspState } from '../../state/VideoStore'

export class RtspPlayerService {
  private store: VideoStore
  private player?: media.AVPlayer
  private surfaceId: string = ''
  private initInFlight: boolean = false

  constructor(store: VideoStore) {
    this.store = store
  }

  // ✅ 兼容 Page4：initIfNeeded()
  async initIfNeeded(): Promise<void> {
    if (this.player) return
    // 防止并发调用（快速切页/重启）时创建多个 AVPlayer 实例
    if (this.initInFlight) return
    this.initInFlight = true
    try {
      this.player = await media.createAVPlayer()
      this.player.on('error', (err) => {
        const msg = `${err.code}: ${err.message}`
        this.store.setRtspState(RtspState.ERROR, 'error')
        this.store.setError(msg)
      })
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'createAVPlayer failed'
      throw new Error(msg)
    } finally {
      this.initInFlight = false
    }
  }

  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId
  }

  async playRtsp(url: string): Promise<boolean> {
    await this.initIfNeeded()
    if (!this.player) return false

    try {
      this.store.setRtspState(RtspState.PREPARING, 'preparing')
      await this.player.reset()

      this.player.url = url
      if (this.surfaceId.length > 0) {
        this.player.surfaceId = this.surfaceId
      }

      await this.player.prepare()
      await this.player.play()
      this.store.setRtspState(RtspState.READY, 'ready')
      return true
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'playRtsp failed'
      this.store.setRtspState(RtspState.ERROR, 'error')
      this.store.setError(msg)
      return false
    }
  }

  // ✅ 本地兜底：必须 getRawFd + fdSrc（并且不碰 deprecated）
  async playLocalRawfile(rm: resourceManager.ResourceManager, name: string): Promise<boolean> {
    await this.initIfNeeded()
    if (!this.player) return false

    try {
      this.store.setRtspState(RtspState.PREPARING, 'local preparing')
      await this.player.reset()

      const fd = await rm.getRawFd(name)
      this.player.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length }

      if (this.surfaceId.length > 0) {
        this.player.surfaceId = this.surfaceId
      }

      await this.player.prepare()
      await this.player.play()
      this.store.setRtspState(RtspState.READY, 'local ready')
      return true
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'playLocal failed'
      this.store.setRtspState(RtspState.ERROR, 'local error')
      this.store.setError(msg)
      return false
    }
  }

  // ✅ 兼容 Page4：pause()
  async pause(): Promise<void> {
    if (!this.player) return
    try {
      await this.player.pause()
    } catch (_) {
      // ignore
    }
  }

  async stop(): Promise<void> {
    if (!this.player) return
    try {
      await this.player.stop()
    } catch (_) {
      // ignore
    }
  }
}
