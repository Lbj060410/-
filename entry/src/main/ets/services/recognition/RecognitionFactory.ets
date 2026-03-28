/**
 * 代码指南：
 * 文件： services/recognition/RecognitionFactory.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
import { RecognitionConfig, RecogEngineType } from './RecognitionConfig'
import { IRecognitionService, MockRecognitionService } from './RecognitionService'
import { HttpYoloRecognitionService } from './HttpYoloRecognitionService'
import { NcnnRecognitionService } from './NcnnRecognitionService'
import { RecognitionSubtype } from './RecognitionTask'

const DEFAULT_YOLOV26BARRIER_MODEL: string = 'yolov26barrier'

// 模型标签表（仅保留当前项目内置可用模型）
const MODEL_LABELS: Record<string, string[]> = {
  'honglvdeng': ['red', 'yellow', 'green'],
  'yolov26barrier': ['shigong', 'TrafficLight', 'GetOffTheCar']
}

/**
 * subtype → 离线模型名映射
 * - 仅映射当前保留模型，其他 subtype 统一回退到默认障碍模型。
 */
export const SUBTYPE_MODEL: Record<number, string> = {
  [RecognitionSubtype.OBSTACLE]: DEFAULT_YOLOV26BARRIER_MODEL,
  [RecognitionSubtype.YOLO]: DEFAULT_YOLOV26BARRIER_MODEL,
  [RecognitionSubtype.TRAFFIC_LIGHT]: 'honglvdeng',
  [RecognitionSubtype.YOLOV26BARRIER]: DEFAULT_YOLOV26BARRIER_MODEL
}

export class RecognitionFactory {
  private createOfflineService(engineType: RecogEngineType, modelName: string, labels: string[], conf: number): IRecognitionService {
    if (engineType === RecogEngineType.OFFLINE_NCNN) {
      const ncnnConf: number = conf > 0 ? conf : 0.3
      const fallbackModelName: string = modelName === 'yolov26barrier' ? 'barrier' : ''
      return new NcnnRecognitionService(modelName, labels, ncnnConf, 0.5, fallbackModelName)
    }

    // MS 和 ONNX 已移除，降级到 MOCK
    console.warn(`[RecognitionFactory] Unsupported engine type: ${engineType}, fallback to MOCK`)
    return new MockRecognitionService()
  }

  create(cfg: RecognitionConfig): IRecognitionService {
    if (cfg.engineType === RecogEngineType.HTTP_YOLO) {
      const endpoint: string = cfg.httpEndpoint
      if (endpoint.length <= 0) {
        return new MockRecognitionService()
      }
      return new HttpYoloRecognitionService(endpoint)
    }

    if (cfg.engineType === RecogEngineType.OFFLINE_NCNN) {
      const modelName: string = cfg.offlineModelName || DEFAULT_YOLOV26BARRIER_MODEL
      const labels: string[] = MODEL_LABELS[modelName] ?? []
      return this.createOfflineService(cfg.engineType, modelName, labels, cfg.offlineConfThresh)
    }

    return new MockRecognitionService()
  }

  /** 根据 subtype 直接创建对应离线服务（Page2 快捷触发用） */
  createForSubtype(
    subtype: RecognitionSubtype,
    conf: number = 0.4,
    engineType: RecogEngineType = RecogEngineType.OFFLINE_NCNN
  ): IRecognitionService {
    const modelName: string = SUBTYPE_MODEL[subtype] ?? DEFAULT_YOLOV26BARRIER_MODEL
    const labels: string[] = MODEL_LABELS[modelName] ?? []
    return this.createOfflineService(engineType, modelName, labels, conf)
  }
}
