/**
 * 代码指南：
 * 文件： services/recognition/OfflineDecodeService.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap

import { resolveLibEntryApi } from './LibEntryBridge'

export class OfflineDecodeService {
  async decodeQr(pm: PixelMap): Promise<string> {
    try {
      const info: image.ImageInfo = await pm.getImageInfo()
      const w: number = info.size.width
      const h: number = info.size.height
      if (w <= 0 || h <= 0) return ''

      const buf: ArrayBuffer = new ArrayBuffer(w * h * 4)
      await pm.readPixelsToBuffer(buf)

      const libentry = resolveLibEntryApi()
      if (!libentry) return ''
      const raw: string = libentry.decodeQr(buf, w, h)
      return this.cleanDecodedText(raw)
    } catch (_) {
      return ''
    }
  }

  private cleanDecodedText(v: string): string {
    const s: string = (v ?? '').trim()
    if (s.length < 1) return ''
    if (s.length > 256) return s.substring(0, 256)
    return s
  }
}

