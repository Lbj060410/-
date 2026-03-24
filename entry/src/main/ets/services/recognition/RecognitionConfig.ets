/**
 * 代码指南：
 * 文件： services/recognition/RecognitionConfig.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
// entry/src/main/ets/services/recognition/RecognitionConfig.ets
export enum RecogEngineType {
  MOCK = 0,
  HTTP_YOLO = 1,
  // OFFLINE_MS = 2,      // 已移除：MindSpore Lite 不可用
  // OFFLINE_ONNX = 3,    // 已移除：ONNX Runtime 不可用
  OFFLINE_NCNN = 4
}

export interface RecognitionConfig {
  engineType: RecogEngineType
  httpEndpoint: string
  offlineModelName: string
  offlineConfThresh: number
}

export const defaultRecognitionConfig: RecognitionConfig = {
  engineType: RecogEngineType.OFFLINE_NCNN,  // 默认使用 ncnn
  httpEndpoint: '',
  offlineModelName: 'barrier',
  offlineConfThresh: 0.3
}

