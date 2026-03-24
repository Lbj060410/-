/**
 * 代码指南：
 * 文件： services/source/LocalVideoService.ets
 * 用途： Video/frame source management (HTTP snapshot, RTSP, local video switch).
 * 何时修改： changing source pipeline or adding a new source type.
 * 相关文件： services/recognition/* and page2 view/coordinator.
 */
import media from '@ohos.multimedia.media'
import resourceManager from '@ohos.resourceManager'

export class LocalVideoService {
  async setLocalFromRawfile(player: media.AVPlayer, rm: resourceManager.ResourceManager, rawfileName: string): Promise<void> {
    const fd = await rm.getRawFd(rawfileName)
    const avFd: media.AVFileDescriptor = { fd: fd.fd, offset: fd.offset, length: fd.length }
    try {
      player.reset()
    } catch (e) {}
    player.fdSrc = avFd
  }
}

