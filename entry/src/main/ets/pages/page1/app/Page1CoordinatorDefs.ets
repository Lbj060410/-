/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorDefs.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorDefs.ets
 * 用途： 定义 Page1Coordinator 共享常量、类型与中间状态结构。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'

export interface NormPoint {
  xNorm: number
  yNorm: number
}

export interface SegmentPoseMatch {
  aId: string
  bId: string
  ax: number
  ay: number
  bx: number
  by: number
  px: number
  py: number
  t: number
  d2: number
}

export interface SegmentPlanDecision {
  fromId: string
  targetId: string
  t: number
  score: number
}

export interface PendingAckMotion {
  action: Page1Action
  fromId: string
  toId: string
  nextAction?: Page1Action
  motionMs: number
  advancePathOnFinish: boolean
  useReverseSpeed: boolean
  customLogTag: string
}


export enum VisionLabelKind {
  OBSTACLE = 0,
  TASK = 1,
  TRAFFIC = 2,
  IGNORE = 3
}

export enum EdgeSide {
  NONE = 0,
  TOP = 1,
  BOTTOM = 2,
  LEFT = 3,
  RIGHT = 4
}


export const P1C = {
  PAUSE_REPLAN_MS: 350,
  REPLAN_COOLDOWN_MS: 700,
  YOLO_COOLDOWN_MS: 1200,
  AHEAD_VISION_REPLAN_MS: 1500,
  FRAME_DEST_APPLY_DELAY_MS: 2000,
  ULTRASONIC_WAIT_MS: 500,
  ULTRASONIC_RESPONSE_CONTEXT_MS: 1800,
  GATE_DEPART_ALIGN_WAIT_MS: 2000,
  GATE_DEPART_DEDUP_MS: 8000,
  BARRIER_INFO_LOG_COOLDOWN_MS: 1200,
  SIM_TICK_MS: 80,
  START_CONNECT_DEFER_MS: 180,
  VISION_LOG_COOLDOWN_MS: 1200,
  AUTO_SEND_DEDUP_LOG_COOLDOWN_MS: 1200,
  MANUAL_GO_DEDUP_MS: 3500,
  LIGHT_QUERY_MIN_INTERVAL_MS: 900,
  PATH_ACK_TIMEOUT_MS: 8000,
  PATH_ACK_WAIT_LOG_COOLDOWN_MS: 1000,
  PATH_DOT_MOTION_MS: 900,
  MAP_PREVIEW_TICK_MS: 60,
  MANUAL_MAP_MOVE_MS: 640,
  MANUAL_MAP_TURN_MS: 320,
  MANUAL_MAP_STEP_NORM: 0.085,
  PARK_HANDOFF_REVERSE_MAP_MS: 1300
} as const


