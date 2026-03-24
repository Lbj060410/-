/**
 * 代码指南：
 * 文件： services/recognition/RecognitionTypes.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
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
