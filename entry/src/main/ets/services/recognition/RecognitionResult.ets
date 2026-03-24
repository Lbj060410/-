/**
 * 代码指南：
 * 文件： services/recognition/RecognitionResult.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
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
