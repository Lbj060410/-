/**
 * 代码指南：
 * 文件： services/media/MediaPlayerService.ets
 * 用途： Media playback helper service.
 * 何时修改： playback controls or media lifecycle behavior changes.
 * 相关文件： page views that trigger media output.
 */
import media from '@ohos.multimedia.media'
import resourceManager from '@ohos.resourceManager'

export class MediaPlayerService {
  private avPlayer: media.AVPlayer | undefined = undefined
  private surfaceId: string = ''

  private readyResolver: ((ok: boolean) => void) | null = null
  private ready: boolean = false

  async initIfNeeded(surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId

    if (this.avPlayer) {
      this.avPlayer.surfaceId = this.surfaceId
      return
    }

    const player: media.AVPlayer = await media.createAVPlayer()
    this.avPlayer = player

    player.on('error', (err) => {
      console.error(`AVPlayer error: ${err.code}, ${err.message}`)
      this.ready = false
      if (this.readyResolver) {
        this.readyResolver(false)
        this.readyResolver = null
      }
      try {
        player.reset()
      } catch (e) {
        console.error('player.reset failed')
      }
    })

    player.on('stateChange', (state: string) => {
      console.info(`AVPlayer stateChange: ${state}`)

      if (!this.avPlayer) {
        return
      }

      if (state === 'initialized') {
        this.avPlayer.surfaceId = this.surfaceId
        try {
          this.avPlayer.prepare()
        } catch (e) {
          console.error('player.prepare failed')
        }
        return
      }

      if (state === 'prepared') {
        try {
          this.avPlayer.play()
        } catch (e) {
          console.error('player.play failed')
        }
        return
      }

      if (state === 'playing') {
        this.ready = true
        if (this.readyResolver) {
          this.readyResolver(true)
          this.readyResolver = null
        }
      }
    })
  }

  async setSourceFromUrl(url: string): Promise<void> {
    if (!this.avPlayer) {
      throw new Error('avPlayer not initialized')
    }
    this.ready = false
    this.avPlayer.url = url
  }

  async setSourceFromRawfile(rm: resourceManager.ResourceManager, rawfileName: string): Promise<void> {
    if (!this.avPlayer) {
      throw new Error('avPlayer not initialized')
    }
    this.ready = false
    const fd = await rm.getRawFd(rawfileName)
    const avFd: media.AVFileDescriptor = { fd: fd.fd, offset: fd.offset, length: fd.length }
    this.avPlayer.fdSrc = avFd
  }

  reset(): void {
    if (!this.avPlayer) {
      return
    }
    this.ready = false
    try {
      this.avPlayer.reset()
    } catch (e) {
      console.error('player.reset failed')
    }
  }

  play(): void {
    try {
      this.avPlayer?.play()
    } catch (e) {
      console.error('player.play failed')
    }
  }

  pause(): void {
    try {
      this.avPlayer?.pause()
    } catch (e) {
      console.error('player.pause failed')
    }
  }

  async waitForPlaybackReady(timeoutMs: number): Promise<boolean> {
    if (this.ready) {
      return true
    }
    return await new Promise<boolean>((resolve) => {
      let done: boolean = false
      const timerId: number = setTimeout(() => {
        if (done) return
        done = true
        this.readyResolver = null
        resolve(false)
      }, timeoutMs) as number

      this.readyResolver = (ok: boolean) => {
        if (done) return
        done = true
        clearTimeout(timerId)
        resolve(ok)
      }
    })
  }
}

