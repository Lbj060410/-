/**
 * 代码指南：
 * 文件： services/recognition/HttpYoloRecognitionService.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap

import { HttpYoloEngine } from './HttpYoloEngine'
import { RecognitionCoreResult } from './RecognitionResult'
import { IRecognitionService } from './RecognitionService'

export class HttpYoloRecognitionService implements IRecognitionService {
  readonly name: string = 'http-yolo'
  private readonly engine: HttpYoloEngine

  constructor(endpoint: string) {
    this.engine = new HttpYoloEngine(endpoint)
  }

  async recognize(pm: PixelMap): Promise<RecognitionCoreResult> {
    const jpeg: ArrayBuffer = await this.pixelMapToJpeg(pm, 90)
    return await this.engine.detectJpeg(jpeg)
  }

  private async pixelMapToJpeg(pm: PixelMap, quality: number): Promise<ArrayBuffer> {
    const packer: image.ImagePacker = image.createImagePacker()
    const opt: image.PackingOption = {
      format: 'image/jpeg',
      quality: quality
    }

    try {
      const data: ArrayBuffer = await packer.packing(pm, opt)
      return data
    } finally {
      try { packer.release() } catch (e) {}
    }
  }
}

