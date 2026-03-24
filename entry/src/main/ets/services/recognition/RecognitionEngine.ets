/**
 * 代码指南：
 * 文件： services/recognition/RecognitionEngine.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/RecognitionEngine.ets
import { BBoxNorm, RecognitionCoreResult } from './RecognitionResult'

export interface IRecognitionEngine {
  readonly name: string
  detectJpeg(jpeg: ArrayBuffer): Promise<RecognitionCoreResult>
}

export class MockRecognitionEngine implements IRecognitionEngine {
  readonly name: string = 'mock'

  async detectJpeg(jpeg: ArrayBuffer): Promise<RecognitionCoreResult> {
    void jpeg

    const t0: number = Date.now()

    // 模拟耗时
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 80))

    const box: BBoxNorm = {
      label: 'mock/object',
      score: 0.88,
      x: 0.35,
      y: 0.35,
      w: 0.30,
      h: 0.30
    }

    const result: RecognitionCoreResult = {
      tsMs: Date.now(),
      costMs: Date.now() - t0,
      boxes: [box],
      texts: [],
      engine: this.name,
      ok: true,
      errorText: ''
    }
    return result
  }
}
