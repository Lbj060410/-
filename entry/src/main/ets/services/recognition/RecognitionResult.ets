/**
 * 代码指南：
 * 文件： services/recognition/RecognitionResult.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
// entry/src/main/ets/services/recognition/RecognitionResult.ets
import { RoiNorm, RecognitionTaskKind, RecognitionTaskSource, RecognitionSubtype } from './RecognitionTask'

/**
 * bbox：归一化坐标（0~1），方便适配不同分辨率 / 不同输入源
 */
export interface BBoxNorm {
  label: string
  score: number
  x: number
  y: number
  w: number
  h: number
}

export interface RecognitionTextItem {
  text: string
  score: number
}

/**
 * 引擎输出（不包含任务上下文）
 */
export interface RecognitionCoreResult {
  tsMs: number
  costMs: number
  engine: string

  boxes: Array<BBoxNorm>
  texts: Array<RecognitionTextItem>

  ok: boolean
  errorText: string
}

/**
 * 统一识别结果（强类型，含任务上下文）
 */
export interface RecognitionResult extends RecognitionCoreResult {
  taskId: string
  kind: RecognitionTaskKind
  subtype: RecognitionSubtype
  source: RecognitionTaskSource
  roi?: RoiNorm
}

export enum RecogStatus {
  IDLE = 0,
  RUNNING = 1,
  ERROR = 2
}
