/**
 * 代码指南：
 * 文件： services/recognition/RecognitionLoop.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
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
