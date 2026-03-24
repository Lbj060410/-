/**
 * 代码指南：
 * 文件： services/recognition/RecognitionLoop.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap
import { recogStore, RecogStore } from '../../state/RecogStore'
import { RecognitionScheduler } from './RecognitionScheduler'
import { RecognitionFactory } from './RecognitionFactory'
import { IRecognitionService } from './RecognitionService'

export class RecognitionLoop {
  private scheduler?: RecognitionScheduler = undefined
  private store?: RecogStore = undefined

  start(store: RecogStore): void {
    this.stop()
    this.store = store

    const factory: RecognitionFactory = new RecognitionFactory()
    const svc: IRecognitionService = factory.create({
      engineType: recogStore.recogEngineType,
      httpEndpoint: recogStore.recogHttpEndpoint,
      offlineModelName: recogStore.recogOfflineModelName,
      offlineConfThresh: recogStore.recogOfflineConfThresh
    })

    this.scheduler = new RecognitionScheduler(store, svc)
    this.scheduler.start()
  }

  stop(): void {
    if (this.scheduler) {
      this.scheduler.stop()
      this.scheduler = undefined
    }
    this.store = undefined
  }

  pushFrame(pm: PixelMap): void {
    if (!this.scheduler) return
    this.scheduler.pushFrame(pm)
  }
}
