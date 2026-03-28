/**
 * 代码指南：
 * 文件： services/recognition/RecognitionConfig.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
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
  offlineModelName: 'yolov26barrier',
  offlineConfThresh: 0.3
}
