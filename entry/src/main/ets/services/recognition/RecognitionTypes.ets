/**
 * 代码指南：
 * 文件： services/recognition/RecognitionTypes.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/RecognitionTypes.ets
//
// ✅ 兼容层：Milestone 2 起推荐直接使用：
// - RecognitionResult.ets（强类型结果）
// - RecognitionTask.ets（任务/队列模型）
//
// 仍保留本文件，避免历史 import 断裂。

export type { BBoxNorm as YoloBox, RecognitionResult } from './RecognitionResult'
export { RecogStatus } from './RecognitionResult'
