/**
 * 代码指南：
 * 文件： services/recognition/RecognitionCenter.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
// entry/src/main/ets/services/recognition/RecognitionCenter.ets
import { recogStore } from '../../state/RecogStore'
import { RecognitionFactory } from './RecognitionFactory'
import { RecognitionScheduler } from './RecognitionScheduler'
import { IRecognitionService } from './RecognitionService'

let schedulerSingleton: RecognitionScheduler | undefined = undefined

/**
 * 全局识别调度中心（单例）
 * - Page4 推实时帧 / 点击 ROI 触发 snapshot
 * - Page2 触发 snapshot / gallery 任务
 * - 引擎配置变更时调用 rebuildRecognitionCenter() 热切换
 */
export function ensureRecognitionCenter(): RecognitionScheduler {
  if (schedulerSingleton) {
    return schedulerSingleton
  }

  const factory: RecognitionFactory = new RecognitionFactory()
  const svc: IRecognitionService = factory.create({
    engineType: recogStore.recogEngineType,
    httpEndpoint: recogStore.recogHttpEndpoint,
    offlineModelName: recogStore.recogOfflineModelName,
    offlineConfThresh: recogStore.recogOfflineConfThresh
  })

  const scheduler: RecognitionScheduler = new RecognitionScheduler(recogStore, svc)
  scheduler.start()

  schedulerSingleton = scheduler
  return schedulerSingleton
}

/**
 * 热切换引擎：stop 旧 scheduler，用当前 recogStore 配置重建。
 * 在 recogEngineType / recogHttpEndpoint / recogOfflineModelName 变更后调用。
 */
export function rebuildRecognitionCenter(): RecognitionScheduler {
  if (schedulerSingleton) {
    schedulerSingleton.stop()
    schedulerSingleton = undefined
  }
  return ensureRecognitionCenter()
}

export function getRecognitionCenter(): RecognitionScheduler | undefined {
  return schedulerSingleton
}

export function shutdownRecognitionCenter(): void {
  if (schedulerSingleton) {
    schedulerSingleton.stop()
    schedulerSingleton = undefined
  }
}

