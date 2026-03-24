/**
 * 代码指南：
 * 文件： services/recognition/RecognitionEngine.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
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
