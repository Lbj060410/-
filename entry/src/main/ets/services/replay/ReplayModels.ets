/**
 * 代码指南：
 * 文件： services/replay/ReplayModels.ets
 * 用途： 定义“全过程复盘”会话与时间线数据结构。
 */

export type ReplayTriggerType =
  'ULTRASONIC' |
  'VISION_YOLOV26BARRIER' |
  'VISION_BARRIER' |
  'TRAFFIC_LIGHT' |
  'REPLAN'

export type ReplaySessionOrigin =
  'PAGE1' |
  'PAGE2' |
  'PAGE4' |
  'GALLERY' |
  'CAR' |
  'UNKNOWN'

export interface ReplayDetectionBox {
  label: string
  score: number
  x: number
  y: number
  w: number
  h: number
}

export interface ReplayTimelineItem {
  tsMs: number
  kind: string
  text: string
}

export interface ReplaySession {
  id: string
  triggerType: ReplayTriggerType
  origin: ReplaySessionOrigin
  startAtMs: number
  endAtMs: number
  durationMs: number
  title: string
  coverImagePath: string
  snapshotPaths: Array<string>
  oldPath: Array<string>
  newPath: Array<string>
  actions: Array<string>
  detections: Array<ReplayDetectionBox>
  timeline: Array<ReplayTimelineItem>
}


