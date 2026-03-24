/**
 * 代码指南：
 * 文件： services/recognition/RecognitionService.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/RecognitionService.ets
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap
import { BBoxNorm, RecognitionCoreResult } from './RecognitionResult'

export interface IRecognitionService {
  readonly name: string
  recognize(pm: PixelMap): Promise<RecognitionCoreResult>
}

export class MockRecognitionService implements IRecognitionService {
  readonly name: string = 'mock'

  async recognize(pm: PixelMap): Promise<RecognitionCoreResult> {
    void pm

    const t0: number = Date.now()

    // 模拟耗时
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 60))

    const box: BBoxNorm = {
      label: 'mock/plate',
      score: 0.92,
      x: 0.35,
      y: 0.35,
      w: 0.30,
      h: 0.30
    }

    const r: RecognitionCoreResult = {
      tsMs: Date.now(),
      costMs: Date.now() - t0,
      boxes: [box],
      texts: [],
      engine: this.name,
      ok: true,
      errorText: ''
    }
    return r
  }
}
