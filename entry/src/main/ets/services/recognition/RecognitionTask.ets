/**
 * 代码指南：
 * 文件： services/recognition/RecognitionTask.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/RecognitionTask.ets
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap
import { RecognitionResult } from './RecognitionResult'

/**
 * 识别任务类型（Milestone 2）
 * - LIVE：实时帧（忙则丢，不排队）
 * - SNAPSHOT：截图高精（必须执行，可超时，可取消）
 */
export enum RecognitionTaskKind {
  LIVE = 1,
  SNAPSHOT = 2
}

/**
 * 识别子类型（可扩展）
 * - YOLO：通用目标检测（默认用于 LIVE 叠加框）
 * - PLATE / QR / BARCODE / FACE ...：业务子任务
 */
export enum RecognitionSubtype {
  YOLO = 0,
  PLATE = 1,
  QR = 2,
  BARCODE = 3,
  FACE = 4,
  HAND = 5,
  LED = 6,
  // 沙盘立体标志物（page4 障碍物检测）
  OBSTACLE = 7,
  // 前置摄像头口罩检测
  MASK = 8,
  // TFT 屏幕定位（先截屏再识别内容）
  SCREEN_LOCATE = 9,
  // TFT 屏幕内容识别
  TRAFFIC_LIGHT = 10,
  COLOR = 11,
    BARRIER = 12,
  VEHICLE = 13,

}

/**
 * 任务来源（统一入口）
 */
export enum RecognitionTaskSource {
  PAGE2_BUTTON = 0,
  CAR_FRAME_TRIGGER = 1,
  GALLERY = 2,
  PAGE4_TAP = 3,
  PAGE4_LIVE = 4
}

/**
 * 任务状态（Page2 展示）
 */
export enum RecognitionTaskState {
  QUEUED = 0,
  RUNNING = 1,
  SUCCESS = 2,
  FAILED = 3,
  CANCELED = 4,
  TIMEOUT = 5,
  DROPPED = 6
}

/**
 * 统一优先级规则：
 * SNAPSHOT > AutoSnapshot(triggered) > LIVE
 */
export enum RecognitionPriority {
  LIVE = 10,
  AUTO_SNAPSHOT = 20,
  SNAPSHOT = 30
}

/**
 * ROI：归一化坐标（0~1）
 */
export interface RoiNorm {
  x: number
  y: number
  w: number
  h: number
}

export enum RecognitionInputType {
  PIXEL_MAP = 0,
  HTTP_SNAPSHOT = 1,
  GALLERY_URI = 2
}

export interface RecognitionTaskInput {
  type: RecognitionInputType
  pixelMap?: PixelMap
  // Scheduler owns this PixelMap and will release it after inference.
  releaseAfterUse?: boolean
  httpUrl?: string
  galleryUri?: string
}

export interface RecognitionTask {
  id: string
  kind: RecognitionTaskKind
  subtype: RecognitionSubtype
  source: RecognitionTaskSource

  /** 数字越大优先级越高 */
  priority: number

  createdAtMs: number
  timeoutMs: number

  roi?: RoiNorm
  input: RecognitionTaskInput
}

/**
 * 存储到 AppStore（供 Page2/调试展示）的任务记录（不保存 PixelMap）
 */
export interface RecognitionTaskRecord {
  id: string
  kind: RecognitionTaskKind
  subtype: RecognitionSubtype
  source: RecognitionTaskSource
  priority: number

  state: RecognitionTaskState

  createdAtMs: number
  startAtMs: number
  endAtMs: number
  timeoutMs: number

  roi?: RoiNorm

  engine: string
  costMs: number
  errorText: string
  snapshotUri?: string

  result?: RecognitionResult
}

/**
 * 过程事件流（可折叠）
 */
export enum RecognitionStage {
  ENQUEUE = 0,
  START = 1,
  PREPROCESS = 2,
  INFER = 3,
  POSTPROCESS = 4,
  REPORT = 5,
  DONE = 6
}

export interface RecognitionTaskEvent {
  tsMs: number
  taskId: string
  stage: RecognitionStage
  text: string
}

