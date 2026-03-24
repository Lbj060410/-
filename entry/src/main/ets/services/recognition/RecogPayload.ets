/**
 * 代码指南：
 * 文件： services/recognition/RecogPayload.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/RecogPayload.ets

/**
 * 回传载荷（12B / payload 8 bytes）强类型模型
 * 注意：payload 只有 8 字节，适合回传“短信息”或摘要。
 */
export enum RecogPayloadKind {
  PLATE = 1,
  QR = 2,
  TRAFFIC_LIGHT = 3
}

export interface RecogPayload {
  kind: RecogPayloadKind
  /** 0.0 ~ 1.0 */
  confidence: number
  /** 尽量使用 ASCII（便于 8B 裁剪） */
  text: string
}

export interface EncodedPayload12B {
  /** CarFrameCodec.build12 的第二字节 h */
  headerH: number
  payload8: Uint8Array
  tag: string
}
