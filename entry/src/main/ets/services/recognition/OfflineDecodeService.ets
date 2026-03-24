/**
 * 代码指南：
 * 文件： services/recognition/OfflineDecodeService.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
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

