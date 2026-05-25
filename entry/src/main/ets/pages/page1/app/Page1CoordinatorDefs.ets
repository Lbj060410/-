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
import { Page1UiStore } from './Page1UiStore'
import { CarTcpService } from '../../../services/control/CarTcpService'
import { CarProtocolService } from '../../../services/control/CarProtocolService'
import { CarProtoStreamDecoder } from '../net/CarRx55StreamDecoder'
import { ActionTimingRegistry } from './ActionTimingRegistry'
import { VehicleMotionPlayer } from './VehicleMotionPlayer'
import { SchedulerSnapshot, VehicleActionScheduler, VehicleActionSchedulerDeps } from './VehicleActionScheduler'

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
  YOLOV26BARRIER_INFO_LOG_COOLDOWN_MS: 1200,
  SIM_TICK_MS: 40,
  START_CONNECT_DEFER_MS: 180,
  VISION_LOG_COOLDOWN_MS: 1200,
  AUTO_SEND_DEDUP_LOG_COOLDOWN_MS: 1200,
  MANUAL_GO_DEDUP_MS: 3500,
  LIGHT_QUERY_MIN_INTERVAL_MS: 900,
  LIGHT_QUERY_WAIT_TIMEOUT_MS: 3500,
  PATH_DOT_MOTION_MS: 1700,
  MAP_PREVIEW_TICK_MS: 60,
  MANUAL_MAP_MOVE_MS: 640,
  MANUAL_MAP_TURN_MS: 320,
  MANUAL_MAP_STEP_NORM: 0.085,
  PARK_HANDOFF_REVERSE_MAP_MS: 1300
} as const


export interface IPage1CoordinatorOps {
  store?: Page1UiStore

  readonly tcp: CarTcpService
  readonly proto: CarProtocolService
  readonly timingRegistry: ActionTimingRegistry
  readonly motionPlayer: VehicleMotionPlayer
  readonly actionScheduler: VehicleActionScheduler

  frameDestApplyTimerId: number
  pendingFrameDestNodeId: string
  readonly rxDecoder: CarProtoStreamDecoder
  rawNoFrameLastLogAtMs: number

  parkingInProgress: boolean
  pauseUntilMs: number
  lastReplanAtMs: number
  lastYoloTriggerAtMs: number
  aheadVisionPending: boolean
  aheadVisionReadyAtMs: number
  aheadVisionEdgeId: string
  lastVisionLogAtMs: number
  replanTransitionBusy: boolean
  replanTransitionToken: number

  manualGoLastSentAtMs: number
  routeStartVoicePlayed: boolean
  logicalHeadingDeg: number
  logicalHeadingInited: boolean
  destFromFrame: boolean
  carAstarMode: boolean

  parkingUltrasonicPending: boolean
  parkingUltrasonicRequestAtMs: number
  parkingUltrasonicExpireAtMs: number
  lastAutoActionFingerprint: string
  lastAutoActionDedupLogAtMs: number
  lastSchedulerSnapshot?: SchedulerSnapshot

  emergencyCommandSeq: number
  realSendConnectKickAtMs: number

  connectTcp(ip: string, port: number): Promise<void>
  canRealSend(): boolean
  sendDriveActionDirect(a: Page1Action): Promise<boolean>
  isTurnAction(a: Page1Action | undefined): boolean
  resetRouteVoiceFlags(): void
  pathDotMotionTimingMs(suggestedMs?: number): number
  maybePlayRouteStartVoice(): Promise<void>

  stopActiveMotion(): void
  motionRunning(): boolean
  schedulerDeps(): VehicleActionSchedulerDeps
  maybeHandleMotionArrive(toId: string): Promise<void>
  uploadTrajectoryNode(nodeId: string): void
  setTrajectoryPlanEndpoints(startPoint: string, endPoint: string): void
  updatePoseAndTelemetryForDisplay(xNorm: number, yNorm: number, headingDeg: number, speed: number): void
  updateHeadingOnlyAtCurrentPose(headingDeg: number): void

  beginMapPoseAnimation(): number
  isMapPoseAnimationActive(token: number): boolean
  previewManualActionOnMap(action: Page1Action): void
  cancelParkingSequence(): void

  frontRouteEdgeIdForDriving(): string
  maybeHandleDrivingUltrasonicObstacle(nowMs: number, edgeOverride?: string): void
  maybeReplanOnObstacle(): void
  nearestNodeIdByPose(): string
  headingDegFromTo(ax: number, ay: number, bx: number, by: number): number
  segMidMinTValue(s: Page1UiStore): number
  segMidMaxTValue(s: Page1UiStore): number
  segHeadingPenaltyWeightValue(s: Page1UiStore): number
  clearAheadVisionReplanState(): void
  resetGarageFlowState(): void
  maybeStartAheadVisionReplan(fromId: string, toId: string, nowMs: number): boolean
  maybeHandleAheadVisionReplan(nowMs: number): boolean
  maybeHandleYolov26BarrierEmergencyStop(nowMs: number): boolean
  isReverseParkingGoal(id: string): boolean

  resolveStartNodeId(): string
  syncLogicalHeadingWithCurrentState(): void
  segmentHeadingDeg(fromId: string, toId: string): number
  normToCardinal(v: number): number

  norm360(v: number): number
  headingErrorDeg(curDeg: number, desiredDeg: number): number
  findNode(id: string): NormPoint | undefined
  sleep(ms: number): Promise<void>

  planPath(dest: string): void
  canSendMotionCommand(commandKey: string, sourceTag: string): boolean
  acquireMotionDispatch(owner: string): Promise<void>
  leaveMotionDispatch(owner: string): void
}
