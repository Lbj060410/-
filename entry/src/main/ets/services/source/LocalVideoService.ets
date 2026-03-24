/**
 * 代码指南：
 * 文件： services/source/LocalVideoService.ets
 * 用途： 视频/帧源管理（HTTP截图、RTSP、本地视频切换）。
 * 何时修改： 修改源处理流程或新增源类型时。
 * 相关文件： services/recognition/* 及 page2 视图/协调器。
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

