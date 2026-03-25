/**
 * 代码指南：
 * 文件：pages/page1/app/Page1Coordinator.ets
 * 用途：主要车辆工作流（TCP 接收、路径规划触发、自动跟随、停车序列、超声波分支）。
 * 何时修改：添加驾驶行为、命令时序、停车/到达逻辑或路线重规划策略时。
 * 相关文件：app/PathPlannerAStar.ets、app/Page1UiStore.ets、app/ActionTimingRegistry.ets、
 *          app/VehicleActionScheduler.ets、app/VehicleMotionPlayer.ets、
 *          services/control/CarProtocolService.ets。
 */
import { Page1UiStore, RouteObstaclePoint } from './Page1UiStore'
import { Page1Action, CarTelemetry } from '../types/Page1Types'

import { CarTcpService } from '../../../services/control/CarTcpService'
import { CarProtocolService, CarSendMode } from '../../../services/control/CarProtocolService'
import { CarConnectionState } from '../../../services/control/CarConnectionState'

import { CarRx55StreamDecoder, CarFrame55 } from '../net/CarRx55StreamDecoder'

import { AStarPlanResult, GridIdCodec } from './PathPlannerAStar'
import { GridNode } from '../types/SandboxGridTypes'
import { ensureRecognitionCenter } from '../../../services/recognition/RecognitionCenter'
import { RecognitionResult, BBoxNorm } from '../../../services/recognition/RecognitionResult'
import {
  RecognitionSubtype,
} from '../../../services/recognition/RecognitionTask'
import { deviceNetworkResolver } from '../../../services/network/DeviceNetworkResolver'
import { saveCarTrajectoryByNode } from '../../../services/webpageinteraction/webconnect'

import { commStore } from '../../../state/CommStore'
import { recogStore } from '../../../state/RecogStore'
import { PoseSource } from '../types/PoseTypes'
import { ActionTimingRegistry, MotionTimingProfile } from './ActionTimingRegistry'
import {
  MotionPhaseChangedEvent,
  MotionPhaseTuning,
  MotionStateSnapshot,
  VehicleMotionHooks,
  VehicleMotionPlayer
} from './VehicleMotionPlayer'
import {
  ScheduledActionWindow,
  SchedulerCadenceState,
  SchedulerSnapshot,
  VehicleActionScheduler,
  VehicleActionSchedulerDeps
} from './VehicleActionScheduler'
import {
  EdgeSide,
  NormPoint,
  P1C,
  PendingAckMotion,
  SegmentPlanDecision,
  SegmentPoseMatch,
  VisionLabelKind
} from './Page1CoordinatorDefs'
import { Page1CoordinatorGridUtils } from './Page1CoordinatorGridUtils'
import {
  classifyLabel,
  clamp01Value,
  findNearestRouteSegmentByPose,
  findPendingRouteObstacleOnEdge,
  frontRouteEdgeIdForDriving,
  isNextNodeBlocked,
  markRouteObstaclePointOnEdge,
  maybeHandleAheadVisionReplan,
  maybeHandleDrivingUltrasonicObstacle,
  maybeLogVisionTaskOrTraffic,
  maybeReplanOnObstacle,
  maybeStartAheadVisionReplan,
  maybeTriggerRoutePointObstacle,
  nearestNodeIdByPose,
  playMapReverseParkingAnimation,
  promoteBlockedEdgePairsToBlockedNodes,
  previewManualActionOnMap,
  syncCurrentSnapNodeByPose,
  turnDeltaDegValue,
  tryBuildSegmentAwarePath,
  chooseSegmentEndpointForGoal,
  yoloSuggestBlockedNodeId,
  animateMapPoseTransition
} from './Page1CoordinatorMapObstacleOps'
import {
  runHandleGateDepartOnArrival,
  runParkingBeforeFinalEdgeArrival,
  simAmbientBackCm,
  simAmbientFrontCm,
  simAmbientIrCm,
  simAmbientLux,
  simulateOnceLoop,
  sleepMs,
  startSimulatorLoop,
  stopSimulatorLoop
} from './Page1CoordinatorParkingSimOps'
import {
  actionForHeadingTransition,
  buildPathViaWaypoint,
  canSendNextCommand,
  followPathOnce,
  gateForcedWaypoint,
  isInsideGateInnerSideNode,
  isParkingInnerRowNode,
  normToCardinal,
  peekNextActionAfterCurrentStep,
  predictActionForPair,
  predictedHeadingAfterAction,
  resolveStartNodeId,
  segmentHeadingDeg,
  sendAutoActionWithTiming,
  syncLogicalHeadingWithCurrentState
} from './Page1CoordinatorPathOps'
import {
  appendDiagKeyRxFrame as appendDiagKeyRxFrameOp,
  bindTcpCallbacks as bindTcpCallbacksOp,
  byteToHex as byteToHexOp,
  bytesToHex as bytesToHexOp,
  canRealSend as canRealSendOp,
  clearParkingUltrasonicRequest as clearParkingUltrasonicRequestOp,
  clearPendingFrameDestApply as clearPendingFrameDestApplyOp,
  connectTcp as connectTcpOp,
  decodeLuxFromBbFrame as decodeLuxFromBbFrameOp,
  disconnectTcp as disconnectTcpOp,
  isParkingUltrasonicResponseContext as isParkingUltrasonicResponseContextOp,
  logFrame55 as logFrame55Op,
  markParkingUltrasonicRequest as markParkingUltrasonicRequestOp,
  onAction as onActionOp,
  onTcpData as onTcpDataOp,
  onTcpState as onTcpStateOp,
  parseTelemetryFrom55 as parseTelemetryFrom55Op,
  scheduleFrameDestApply as scheduleFrameDestApplyOp,
  sendManualGoCommand as sendManualGoCommandOp
} from './Page1CoordinatorControlTcpOps'
import {
  buildAutoActionFingerprint as buildAutoActionFingerprintOp,
  canSendPathCommandNow as canSendPathCommandNowOp,
  flushDrivingUltrasonicObstacleAfterAck as flushDrivingUltrasonicObstacleAfterAckOp,
  gateDepartSendKey as gateDepartSendKeyOp,
  isMoveAction as isMoveActionOp,
  isPathMotionAction as isPathMotionActionOp,
  isTurnAction as isTurnActionOp,
  markPathCommandSent as markPathCommandSentOp,
  onPathAckFrame as onPathAckFrameOp,
  pathDotMotionTiming as pathDotMotionTimingOp,
  pathDotMotionTimingMs as pathDotMotionTimingMsOp,
  queueDrivingUltrasonicObstacle as queueDrivingUltrasonicObstacleOp,
  resetAutoActionDedupState as resetAutoActionDedupStateOp,
  resetGateDepartDedupState as resetGateDepartDedupStateOp,
  resetPathAckState as resetPathAckStateOp,
  resetRouteVoiceFlags as resetRouteVoiceFlagsOp,
  sendDriveActionDirect as sendDriveActionDirectOp,
  shouldSkipDuplicateAutoAction as shouldSkipDuplicateAutoActionOp,
  stageMotionWaitAckComplete as stageMotionWaitAckCompleteOp,
  startMotionNow as startMotionNowOp,
  startPendingAckMotionOnComplete as startPendingAckMotionOnCompleteOp,
  waitForCurrentPathAckComplete as waitForCurrentPathAckCompleteOp
} from './Page1CoordinatorDriveAckOps'
import {
  maybeHandleMotionArrive as maybeHandleMotionArriveOp,
  motionHooks as motionHooksOp,
  planPath as planPathOp,
  schedulerDeps as schedulerDepsOp
} from './Page1CoordinatorPlanMotionOps'
import {
  isShigongBarrierLabelKey,
  normalizeBarrierLabelKey
} from './TrafficBarrierLabelPolicy'

export class Page1Coordinator {
  private store?: Page1UiStore

  private readonly tcp: CarTcpService = new CarTcpService()
  private readonly proto: CarProtocolService = new CarProtocolService()
  private readonly timingRegistry: ActionTimingRegistry = new ActionTimingRegistry()
  private readonly motionPlayer: VehicleMotionPlayer = new VehicleMotionPlayer(this.timingRegistry)
  private readonly actionScheduler: VehicleActionScheduler = new VehicleActionScheduler()

  private simTimerId: number = -1
  private simTick: number = 0
  private simLoopBusy: boolean = false
  private connectDeferredTimerId: number = -1
  private frameDestApplyTimerId: number = -1
  private pendingFrameDestNodeId: string = ''

  private readonly rxDecoder: CarRx55StreamDecoder = new CarRx55StreamDecoder()

  private parkingInProgress: boolean = false
  private parkingSequenceToken: number = 0
  private readonly parkingLock: object = {}

  private pauseUntilMs: number = 0
  private lastReplanAtMs: number = 0
  private lastYoloTriggerAtMs: number = 0
  private aheadVisionPending: boolean = false
  private aheadVisionReadyAtMs: number = 0
  private aheadVisionEdgeId: string = ''
  private lastVisionLogAtMs: number = 0


  private manualGoGateToken: number = 0
  private manualGoGateActive: boolean = false
  private manualGoLastSentAtMs: number = 0

  private routeStartVoicePlayed: boolean = false

  private gateDepartInProgress: boolean = false
  private gateDepartLastSentKey: string = ''
  private gateDepartLastSentAtMs: number = 0
  private readonly gateDepartLastSentAtByFlowKey: Map<string, number> = new Map<string, number>()

  private logicalHeadingDeg: number = 0
  private logicalHeadingInited: boolean = false

  private destFromFrame: boolean = false

  private lastUltrasonicP1: number = -1
  private lastUltrasonicAtMs: number = 0
  private parkingUltrasonicPending: boolean = false
  private parkingUltrasonicRequestAtMs: number = 0
  private parkingUltrasonicExpireAtMs: number = 0
  private lastAutoActionFingerprint: string = ''
  private lastAutoActionDedupLogAtMs: number = 0
  private lastSchedulerSnapshot?: SchedulerSnapshot = undefined
  private lastMotionSnapshot?: MotionStateSnapshot = undefined
  private lastMotionCompleteAtMs: number = 0
  private mapPoseAnimToken: number = 0
  private pathAckFirstCommandSent: boolean = false
  private pathAckAwaitingComplete: boolean = false
  private pathAckBlocked: boolean = false
  private pathAckLastSendAtMs: number = 0
  private pathAckLastStatusCode: number = 0
  private pathAckLastCommandText: string = ''
  private pathAckLastWaitLogAtMs: number = 0
  private pathAckRetryTimerId: number = -1
  private pathAckRetrySentCount: number = 0
  private pathAckCommandKey: string = ''
  private pendingAckMotion?: PendingAckMotion = undefined
  private suppressNextAckCompleteMotion: boolean = false
  private suppressAckCompleteEdgeId: string = ''
  private pendingDrivingUltrasonicObstacleEdgeId: string = ''
  private pendingDrivingUltrasonicObstacleAtMs: number = 0
  private garageDepartStopSent: boolean = false
  private garageDepartReady03: boolean = false
  private garageFinalCarportSent: boolean = false
  private garageWaitingParkDone04: boolean = false
  private garagePendingCarportLevel: number = 0
  private garageCarportAckWatchTimerId: number = -1
  private garageCarportAckPending: boolean = false
  private garageCarportAckRetryDone: boolean = false
  private garageCarportAckPendingLevel: number = 0
  private garageCarportAckSentAtMs: number = 0
  private trafficGateWaiting: boolean = false
  private trafficGateEdgeKey: string = ''
  private trafficGateLastLogAtMs: number = 0
  private gateBillingRunning: boolean = false
  private gateBillingStartAtMs: number = 0
  private gateBillingElapsedMs: number = 0
  private motionCommandBlockUntilMs: number = 0
  private motionCommandBlockReason: string = ''
  private motionCommandBlockLastLogAtMs: number = 0
  private emergencyAlarmTimerId: number = -1
  private barrierEmergencyBusy: boolean = false
  private metricSpeedAnimTimerId: number = -1
  private metricSpeedAnimToken: number = 0
  private metricHeadingAnimTimerId: number = -1
  private metricHeadingAnimToken: number = 0
  private metricHeadingTargetDeg: number = 0
  private metricDistanceAckAnimTimerId: number = -1
  private metricDistanceAckAnimToken: number = 0
  private metricDistanceTotalCm: number = 0
  private metricDistanceAckKey: string = ''
  private metricDistanceAckTargetCm: number = 0
  private metricDistanceMotionKey: string = ''
  private metricDistanceMotionBaseCm: number = 0
  private simLightBaseLux: number = 0
  private lightMetricQueryEnabled: boolean = false
  private lightMetricReady: boolean = false
  private lastBarrierEmergencyTaskId: string = ''
  private lastBarrierEmergencyTsMs: number = 0
  private started: boolean = false
  private starting: boolean = false

  constructor() {
    this.actionScheduler.setCallbacks({
      onReset: (snapshot: SchedulerSnapshot): void => {
        this.lastSchedulerSnapshot = snapshot
      },
      onActionWindowStart: (_window: ScheduledActionWindow, snapshot: SchedulerSnapshot): void => {
        this.lastSchedulerSnapshot = snapshot
      },
      onActionWindowClear: (_window: ScheduledActionWindow, snapshot: SchedulerSnapshot): void => {
        this.lastSchedulerSnapshot = snapshot
      },
      onCadenceStateChange: (_prev: SchedulerCadenceState, _next: SchedulerCadenceState, snapshot: SchedulerSnapshot): void => {
        this.lastSchedulerSnapshot = snapshot
      }
    })
    this.motionPlayer.setCallbacks({
      onBegin: (snapshot: MotionStateSnapshot): void => {
        this.lastMotionSnapshot = snapshot
      },
      onPhaseChanged: (event: MotionPhaseChangedEvent): void => {
        this.lastMotionSnapshot = event.snapshot
      },
      onTick: (snapshot: MotionStateSnapshot): void => {
        this.lastMotionSnapshot = snapshot
      },
      onComplete: (snapshot: MotionStateSnapshot): void => {
        this.lastMotionSnapshot = snapshot
        this.lastMotionCompleteAtMs = snapshot.nowMs
      },
      onReset: (snapshot: MotionStateSnapshot): void => {
        this.lastMotionSnapshot = snapshot
      }
    })
  }

  private clearMetricSpeedAnimation(): void {
    this.metricSpeedAnimToken += 1
    if (this.metricSpeedAnimTimerId >= 0) {
      clearTimeout(this.metricSpeedAnimTimerId)
      this.metricSpeedAnimTimerId = -1
    }
  }

  private clearMetricHeadingAnimation(): void {
    this.metricHeadingAnimToken += 1
    if (this.metricHeadingAnimTimerId >= 0) {
      clearTimeout(this.metricHeadingAnimTimerId)
      this.metricHeadingAnimTimerId = -1
    }
  }

  private clearMetricDistanceAckAnimation(): void {
    this.metricDistanceAckAnimToken += 1
    if (this.metricDistanceAckAnimTimerId >= 0) {
      clearTimeout(this.metricDistanceAckAnimTimerId)
      this.metricDistanceAckAnimTimerId = -1
    }
  }

  private edgeDistanceCm(fromId: string, toId: string): number {
    const a: string = fromId.trim().toUpperCase()
    const b: string = toId.trim().toUpperCase()
    const ac = GridIdCodec.parse(a)
    const bc = GridIdCodec.parse(b)
    if (!ac || !bc) return 57

    const rowA: number = Number.parseInt(a.slice(1), 10)
    const rowB: number = Number.parseInt(b.slice(1), 10)
    const colA: string = a[0]
    const colB: string = b[0]

    if (ac.col === bc.col) {
      const topBottom: boolean =
        (rowA === 1 && rowB === 2) || (rowA === 2 && rowB === 1) ||
        (rowA === 7 && rowB === 6) || (rowA === 6 && rowB === 7)
      return topBottom ? 37 : 57
    }

    if (ac.row === bc.row) {
      const sideEdge: boolean =
        (colA === 'A' && colB === 'B') || (colA === 'B' && colB === 'A') ||
        (colA === 'G' && colB === 'F') || (colA === 'F' && colB === 'G')
      return sideEdge ? 47 : 71
    }
    return 57
  }

  private pendingAckDistanceInfo(): { key: string, segCm: number } | undefined {
    const req: PendingAckMotion | undefined = this.pendingAckMotion
    if (!req) return undefined
    const fromId: string = req.fromId.trim().toUpperCase()
    const toId: string = req.toId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(fromId) || !GridIdCodec.isValidId(toId)) return undefined
    const segCm: number = this.edgeDistanceCm(fromId, toId)
    return { key: `${fromId}->${toId}`, segCm: segCm }
  }

  private startMetricDistanceAckRise(key: string, segCm: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (segCm <= 0) return
    if (this.metricDistanceAckKey === key && this.metricDistanceAckAnimTimerId >= 0) return

    this.clearMetricDistanceAckAnimation()
    this.metricDistanceAckKey = key
    this.metricDistanceAckTargetCm = this.metricDistanceTotalCm + segCm
    const token: number = this.metricDistanceAckAnimToken
    const startAtMs: number = Date.now()
    const durationMs: number = 900
    const startCm: number = this.metricDistanceTotalCm

    const tick = (): void => {
      if (token !== this.metricDistanceAckAnimToken) return
      const ss: Page1UiStore | undefined = this.store
      if (!ss) return
      const tRaw: number = (Date.now() - startAtMs) / durationMs
      const t: number = tRaw < 0 ? 0 : (tRaw > 1 ? 1 : tRaw)
      const cur: number = startCm + (this.metricDistanceAckTargetCm - startCm) * t
      ss.setMetricDistanceCm(cur)
      if (t >= 1) {
        this.metricDistanceAckAnimTimerId = -1
        return
      }
      this.metricDistanceAckAnimTimerId = setTimeout(tick, 40) as number
    }

    tick()
  }

  private finalizeMetricDistanceAck(): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (this.metricDistanceAckKey.length <= 0) {
      const info = this.pendingAckDistanceInfo()
      if (!info) return
      this.metricDistanceTotalCm += info.segCm
      s.setMetricDistanceCm(this.metricDistanceTotalCm)
      return
    }

    this.clearMetricDistanceAckAnimation()
    this.metricDistanceTotalCm = this.metricDistanceAckTargetCm
    s.setMetricDistanceCm(this.metricDistanceTotalCm)
    this.metricDistanceAckKey = ''
    this.metricDistanceAckTargetCm = this.metricDistanceTotalCm
  }

  private normToEightHeading(v: number): number {
    const n: number = this.norm360(v)
    return this.norm360(Math.round(n / 45) * 45)
  }

  private startMetricSpeedRiseAndHoldFromAck01(targetSpeedCms: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const target: number = Number.isFinite(targetSpeedCms) ? Math.max(0, targetSpeedCms) : 0
    if (target <= 0) return

    this.clearMetricSpeedAnimation()
    const token: number = this.metricSpeedAnimToken
    const startAtMs: number = Date.now()
    const riseMs: number = 420

    const tick = (): void => {
      if (token !== this.metricSpeedAnimToken) return
      const ss: Page1UiStore | undefined = this.store
      if (!ss) return

      const elapsedMs: number = Date.now() - startAtMs
      let speedCms: number = 0
      if (elapsedMs < riseMs) {
        speedCms = target * (elapsedMs / riseMs)
      } else {
        speedCms = target
      }
      if (speedCms < 0) speedCms = 0
      ss.setMetricSpeedCms(speedCms)

      this.metricSpeedAnimTimerId = setTimeout(tick, 40) as number
    }

    tick()
  }

  private animateMetricHeadingTo(headingDeg: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    this.metricHeadingTargetDeg = this.normToEightHeading(headingDeg)
    if (this.metricHeadingAnimTimerId >= 0) return

    const token: number = this.metricHeadingAnimToken
    const tick = (): void => {
      if (token !== this.metricHeadingAnimToken) return
      const ss: Page1UiStore | undefined = this.store
      if (!ss) return

      const cur: number = ss.metricHeadingDeg
      const target: number = this.metricHeadingTargetDeg
      const err: number = this.headingErrorDeg(cur, target)
      const absErr: number = Math.abs(err)
      if (absErr <= 1) {
        ss.setMetricHeadingDeg(target)
        this.metricHeadingAnimTimerId = -1
        return
      }

      const maxStepDeg: number = 10
      const stepDeg: number = absErr <= maxStepDeg ? err : (err > 0 ? maxStepDeg : -maxStepDeg)
      ss.setMetricHeadingDeg(this.norm360(cur + stepDeg))
      this.metricHeadingAnimTimerId = setTimeout(tick, 40) as number
    }

    this.metricHeadingAnimTimerId = setTimeout(tick, 40) as number
  }

  private onPathAckStatusForDashboard(status: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (!s.realSendEnabled) {
      s.setMetricSpeedCms(0)
      s.setMetricDistanceCm(0)
      return
    }
    const cmd: string = this.pathAckLastCommandText
    const isMoveCmd: boolean = cmd === '前进' || cmd === '后退'
    const isTurnCmd: boolean =
      cmd === '左转' || cmd === '右转' || cmd === '左半转' || cmd === '右半转' || cmd === '掉头'
    if (!isMoveCmd && !isTurnCmd) return

    if (status === 0x01) {
      this.startMetricSpeedRiseAndHoldFromAck01(isMoveCmd ? 20 : 10)
      const info = this.pendingAckDistanceInfo()
      if (isMoveCmd && info) this.startMetricDistanceAckRise(info.key, info.segCm)
      return
    }
    if (status === 0x02) {
      this.clearMetricSpeedAnimation()
      s.setMetricSpeedCms(0)
      if (isMoveCmd) this.finalizeMetricDistanceAck()
    }
  }

  private initialHeadingByPoseAndPath(s: Page1UiStore): number {
    if (s.pathNodes.length > 1 && s.pathIndex >= 0 && s.pathIndex < s.pathNodes.length - 1) {
      const fromId: string = s.pathNodes[s.pathIndex].trim().toUpperCase()
      const toId: string = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
      return this.normToEightHeading(this.segmentHeadingDeg(fromId, toId))
    }

    let minY: number = s.pose.yNorm
    let maxY: number = s.pose.yNorm
    if (s.gridNodes.length > 0) {
      minY = s.gridNodes[0].yNorm
      maxY = s.gridNodes[0].yNorm
      for (let i: number = 1; i < s.gridNodes.length; i++) {
        const y: number = s.gridNodes[i].yNorm
        if (y < minY) minY = y
        if (y > maxY) maxY = y
      }
    }
    const edgeBand: number = Math.max(s.gridSnapThresholdNorm + 0.02, 0.075)
    if (s.pose.yNorm >= maxY - edgeBand) return 270
    if (s.pose.yNorm <= minY + edgeBand) return 90
    const midY: number = (minY + maxY) / 2
    return s.pose.yNorm <= midY ? 90 : 270
  }

  private armLightMetricQuery(): void {
    this.lightMetricQueryEnabled = true
    this.lightMetricReady = false
    this.simLightBaseLux = 0
    const s: Page1UiStore | undefined = this.store
    if (s) s.setMetricLightLux(0)
  }

  private onLightLuxReceived(lux: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s || !s.realSendEnabled) return
    if (!this.lightMetricQueryEnabled) return
    if (!Number.isFinite(lux) || lux < 0) return
    this.lightMetricReady = true
    this.simLightBaseLux = Math.round(lux)
    s.setMetricLightLux(this.simLightBaseLux)
  }

  private onSimTelemetryTick(speed: number, headingDeg: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (!s.realSendEnabled) {
      s.setMetricSpeedCms(0)
      s.setMetricHeadingDeg(0)
      s.setMetricDistanceCm(0)
      s.setMetricLightLux(0)
      return
    }
    void speed
    this.animateMetricHeadingTo(headingDeg)
  }

  bind(store: Page1UiStore): void {
    this.store = store
    this.clearMetricSpeedAnimation()
    this.clearMetricHeadingAnimation()
    this.clearMetricDistanceAckAnimation()
    this.simLightBaseLux = 0
    this.metricDistanceTotalCm = 0
    this.metricDistanceAckKey = ''
    this.metricDistanceAckTargetCm = 0
    this.metricDistanceMotionKey = ''
    this.metricDistanceMotionBaseCm = 0
    this.lightMetricQueryEnabled = false
    this.lightMetricReady = false
    store.setMetricSpeedCms(0)
    store.setMetricHeadingDeg(0)
    store.setMetricDistanceCm(0)
    store.setMetricLightLux(0)
    this.metricHeadingTargetDeg = store.metricHeadingDeg
    this.proto.bindTcp(this.tcp)
    this.bindTcpCallbacks()
  }

  async start(): Promise<void> {
    if (this.started || this.starting) return
    this.starting = true
    const s: Page1UiStore | undefined = this.store
    if (!s) {
      this.starting = false
      return
    }

    try {
      this.startSimulator()
      this.bootstrapRecognitionCenter()

      const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
      const configuredIp: string = s.connIp.trim()
      if (gatewayIp.length > 0 && configuredIp.length > 0 && configuredIp !== gatewayIp) {
        s.pushLog(`WiFi网关=${gatewayIp}，TCP目标保持手动配置=${configuredIp}`)
      }

      this.logicalHeadingDeg = this.normToCardinal(s.pose.headingDeg)
      this.logicalHeadingInited = true

      this.clearDeferredConnect()
      this.connectDeferredTimerId = setTimeout((): void => {
        this.connectDeferredTimerId = -1
        void this.connectTcp(s.connIp, s.connPort)
      }, P1C.START_CONNECT_DEFER_MS) as number
      this.started = true
    } finally {
      this.starting = false
    }
  }

  async stop(): Promise<void> {
    this.starting = false
    this.started = false
    this.clearDeferredConnect()
    this.cancelMapPoseAnimation()
    this.cancelParkingSequence()
    this.clearPendingFrameDestApply()
    this.clearAheadVisionReplanState()
    this.manualGoGateToken += 1
    this.manualGoGateActive = false
    this.gateDepartInProgress = false
    this.resetGateDepartDedupState()
    this.resetAutoActionDedupState()
    this.resetPathAckState()
    this.resetGarageFlowState()
    this.trafficGateWaiting = false
    this.trafficGateEdgeKey = ''
    this.trafficGateLastLogAtMs = 0
    this.clearMetricSpeedAnimation()
    this.clearMetricHeadingAnimation()
    this.clearMetricDistanceAckAnimation()
    this.lightMetricQueryEnabled = false
    this.lightMetricReady = false
    this.simLightBaseLux = 0
    if (this.store) {
      this.store.setMetricSpeedCms(0)
      this.store.setMetricLightLux(0)
      this.store.setMetricDistanceCm(this.metricDistanceTotalCm)
    }
    this.clearEmergencyAlarmTimer()
    this.clearMotionCommandBlock()
    this.stopActiveMotion()
    this.actionScheduler.reset()
    this.stopSimulator()
    this.rxDecoder.reset()
    await this.disconnectTcp()
  }

  pausePage(): void {
    this.starting = false
    this.started = false
    this.clearDeferredConnect()
    this.cancelMapPoseAnimation()
    this.cancelParkingSequence()
    this.clearPendingFrameDestApply()
    this.clearAheadVisionReplanState()
    this.manualGoGateToken += 1
    this.manualGoGateActive = false
    this.gateDepartInProgress = false
    this.resetGateDepartDedupState()
    this.resetAutoActionDedupState()
    this.resetPathAckState()
    this.resetGarageFlowState()
    this.trafficGateWaiting = false
    this.trafficGateEdgeKey = ''
    this.trafficGateLastLogAtMs = 0
    this.clearMetricSpeedAnimation()
    this.clearMetricHeadingAnimation()
    this.clearMetricDistanceAckAnimation()
    this.lightMetricQueryEnabled = false
    this.lightMetricReady = false
    this.simLightBaseLux = 0
    if (this.store) {
      this.store.setMetricSpeedCms(0)
      this.store.setMetricLightLux(0)
      this.store.setMetricDistanceCm(this.metricDistanceTotalCm)
    }
    this.clearEmergencyAlarmTimer()
    this.clearMotionCommandBlock()
    this.stopActiveMotion()
    this.actionScheduler.reset()
    this.stopSimulator()
    this.rxDecoder.reset()
    void this.disconnectTcp()
  }

  private bootstrapRecognitionCenter(): void {
    const scheduler = ensureRecognitionCenter()
    scheduler.bindProtocolService(this.proto)
    scheduler.setLiveSubtype(RecognitionSubtype.BARRIER)
  }

  private clearDeferredConnect(): void {
    if (this.connectDeferredTimerId >= 0) {
      clearTimeout(this.connectDeferredTimerId)
      this.connectDeferredTimerId = -1
    }
  }

  async stepFollowOnce(): Promise<void> {
    const now: number = Date.now()
    await this.followPathOnce(now, true)
  }

  private bindTcpCallbacks(): void {
    bindTcpCallbacksOp(this as object)
  }

  private onTcpState(state: CarConnectionState, text: string): void {
    onTcpStateOp(this as object, state, text)
  }

  private onTcpData(data: Uint8Array): void {
    onTcpDataOp(this as object, data)
  }

  private parseTelemetryFrom55(prev: CarTelemetry, f: CarFrame55): CarTelemetry | undefined {
    return parseTelemetryFrom55Op(this as object, prev, f)
  }

  private clearPendingFrameDestApply(): void {
    clearPendingFrameDestApplyOp(this as object)
  }

  private scheduleFrameDestApply(destNodeId: string): void {
    scheduleFrameDestApplyOp(this as object, destNodeId)
  }

  private logFrame55(s: Page1UiStore, f: CarFrame55): void {
    logFrame55Op(this as object, s, f)
  }

  private byteToHex(v: number): string {
    return byteToHexOp(v)
  }

  private bytesToHex(data: Uint8Array): string {
    return bytesToHexOp(data)
  }

  private markParkingUltrasonicRequest(nowMs: number): void {
    markParkingUltrasonicRequestOp(this as object, nowMs)
  }

  private clearParkingUltrasonicRequest(): void {
    clearParkingUltrasonicRequestOp(this as object)
  }

  private isParkingUltrasonicResponseContext(nowMs: number): boolean {
    return isParkingUltrasonicResponseContextOp(this as object, nowMs)
  }

  private decodeLuxFromBbFrame(f: CarFrame55): number {
    return decodeLuxFromBbFrameOp(f)
  }

  private appendDiagKeyRxFrame(f: CarFrame55, summary: string): void {
    appendDiagKeyRxFrameOp(this as object, f, summary)
  }

  private async connectTcp(ip: string, port: number): Promise<void> {
    await connectTcpOp(this as object, ip, port)
  }

  private async disconnectTcp(): Promise<void> {
    await disconnectTcpOp(this as object)
  }

  private canRealSend(): boolean {
    return canRealSendOp(this as object)
  }

  private async sendManualGoCommand(actionText: string): Promise<void> {
    await sendManualGoCommandOp(this as object, actionText)
  }

  async onAction(a: Page1Action): Promise<void> {
    await onActionOp(this as object, a)
  }

  private async sendDriveActionDirect(a: Page1Action): Promise<boolean> {
    return await sendDriveActionDirectOp(this as object, a)
  }

  private buildAutoActionFingerprint(action: Page1Action): string {
    return buildAutoActionFingerprintOp(this as object, action)
  }

  private shouldSkipDuplicateAutoAction(action: Page1Action, actionText: string): boolean {
    return shouldSkipDuplicateAutoActionOp(this as object, action, actionText)
  }

  private isTurnAction(a: Page1Action | undefined): boolean {
    return isTurnActionOp(a)
  }

  private isMoveAction(a: Page1Action | undefined): boolean {
    return isMoveActionOp(a)
  }

  private resetRouteVoiceFlags(): void {
    resetRouteVoiceFlagsOp(this as object)
  }

  private resetAutoActionDedupState(): void {
    resetAutoActionDedupStateOp(this as object)
  }

  private resetPathAckState(): void {
    resetPathAckStateOp(this as object)
  }

  private isPathMotionAction(action: Page1Action): boolean {
    return isPathMotionActionOp(action)
  }

  private canSendPathCommandNow(nextActionText: string): boolean {
    return canSendPathCommandNowOp(this as object, nextActionText)
  }

  private markPathCommandSent(actionText: string): void {
    markPathCommandSentOp(this as object, actionText)
  }

  private onPathAckFrame(f: CarFrame55): void {
    onPathAckFrameOp(this as object, f)
  }

  private pathDotMotionTimingMs(suggestedMs?: number): number {
    return pathDotMotionTimingMsOp(suggestedMs)
  }

  private pathDotMotionTiming(suggestedMs?: number): MotionTimingProfile {
    return pathDotMotionTimingOp(suggestedMs)
  }

  private async waitForCurrentPathAckComplete(maxWaitMs: number, waitTag: string): Promise<boolean> {
    return await waitForCurrentPathAckCompleteOp(this as object, maxWaitMs, waitTag)
  }

  private stageMotionWaitAckComplete(req: PendingAckMotion): void {
    stageMotionWaitAckCompleteOp(this as object, req)
  }

  private startMotionNow(req: PendingAckMotion): void {
    startMotionNowOp(this as object, req)
  }

  private startPendingAckMotionOnComplete(): void {
    startPendingAckMotionOnCompleteOp(this as object)
  }

  private queueDrivingUltrasonicObstacle(nowMs: number): void {
    queueDrivingUltrasonicObstacleOp(this as object, nowMs)
  }

  private flushDrivingUltrasonicObstacleAfterAck(): void {
    flushDrivingUltrasonicObstacleAfterAckOp(this as object)
  }

  private resetGateDepartDedupState(): void {
    resetGateDepartDedupStateOp(this as object)
  }

  private gateDepartSendKey(curId: string, nextId: string): string {
    return gateDepartSendKeyOp(curId, nextId)
  }

  private async maybePlayRouteStartVoice(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (this.routeStartVoicePlayed) return

    this.routeStartVoicePlayed = true
    s.pushLog('VOICE: 出发前播报最优路径')
    if (!this.canRealSend()) return

    // await this.proto.voicefour()
    s.pushLog('VOICE: 已注释出发语音发送')
  }

  private stopActiveMotion(): void {
    this.motionPlayer.reset()
  }

  private motionRunning(): boolean {
    return this.motionPlayer.running()
  }

  private motionHooks(): VehicleMotionHooks {
    return motionHooksOp(this as object) as VehicleMotionHooks
  }

  private schedulerDeps(): VehicleActionSchedulerDeps {
    return schedulerDepsOp(this as object) as VehicleActionSchedulerDeps
  }

  private async maybeHandleMotionArrive(toId: string): Promise<void> {
    await maybeHandleMotionArriveOp(this as object, toId)
  }

  private gateBillingIntervalMs(nowMs: number): number {
    if (this.gateBillingRunning && this.gateBillingStartAtMs > 0) {
      return Math.max(0, nowMs - this.gateBillingStartAtMs)
    }
    return Math.max(0, this.gateBillingElapsedMs)
  }

  private uploadTrajectoryNode(nodeId: string): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = nodeId.trim().toUpperCase()
    if (id.length <= 0) return
    const intervalMs: number = this.gateBillingIntervalMs(Date.now())
    void saveCarTrajectoryByNode(id, intervalMs)
      .then((ok: boolean): void => {
        if (!ok) s.pushLog(`WEB_CONNECT: 上报跳过 node=${id}`)
      })
      .catch((err: Object): void => {
        const message: string = (err as Error).message
        s.pushLog(`WEB_CONNECT: 上报失败 node=${id} err=${message}`)
      })
  }

  private updatePoseAndTelemetryForDisplay(xNorm: number, yNorm: number, headingDeg: number, speed: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    const nowMs: number = Date.now()
    s.setPose({
      tsMs: nowMs,
      xNorm: xNorm,
      yNorm: yNorm,
      headingDeg: headingDeg,
      confidence: s.pose.confidence,
      source: PoseSource.MANUAL
    })

    s.setTelemetry({
      tsMs: nowMs,
      speed: speed,
      headingDeg: headingDeg,
      odomMm: s.telemetry.odomMm,
      ultraFrontCm: s.telemetry.ultraFrontCm,
      ultraBackCm: s.telemetry.ultraBackCm,
      irDistCm: s.telemetry.irDistCm,
      lightLux: s.telemetry.lightLux,
      rfid: s.telemetry.rfid
    })
    this.animateMetricHeadingTo(headingDeg)
  }

  private updateHeadingOnlyAtCurrentPose(headingDeg: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    this.updatePoseAndTelemetryForDisplay(
      s.pose.xNorm,
      s.pose.yNorm,
      headingDeg,
      0
    )
  }

  private clamp01(v: number): number {
    return clamp01Value(v)
  }

  private cancelMapPoseAnimation(): void {
    this.mapPoseAnimToken += 1
  }

  private beginMapPoseAnimation(): number {
    this.mapPoseAnimToken += 1
    return this.mapPoseAnimToken
  }

  private isMapPoseAnimationActive(token: number): boolean {
    return token === this.mapPoseAnimToken
  }

  private turnDeltaDeg(action: Page1Action): number {
    return turnDeltaDegValue(action)
  }

  private syncCurrentSnapNodeByPose(xNorm: number, yNorm: number): void {
    syncCurrentSnapNodeByPose(this as object, xNorm, yNorm)
  }

  private async animateMapPoseTransition(
    fromXNorm: number,
    fromYNorm: number,
    toXNorm: number,
    toYNorm: number,
    fromHeadingDeg: number,
    toHeadingDeg: number,
    speed: number,
    durationMs: number,
    token: number
  ): Promise<void> {
    await animateMapPoseTransition(
      this as object,
      fromXNorm,
      fromYNorm,
      toXNorm,
      toYNorm,
      fromHeadingDeg,
      toHeadingDeg,
      speed,
      durationMs,
      token
    )
  }

  private previewManualActionOnMap(action: Page1Action): void {
    previewManualActionOnMap(this as object, action)
  }

  private playMapReverseParkingAnimation(arrivedId: string, goalId: string, headingDeg: number): void {
    playMapReverseParkingAnimation(this as object, arrivedId, goalId, headingDeg)
  }

  private cancelParkingSequence(): void {
    this.parkingSequenceToken += 1
    this.parkingInProgress = false
  }

  private isParkingSequenceActive(token: number): boolean {
    return this.parkingInProgress && token === this.parkingSequenceToken
  }

  private tryStartParkingSequence(): number | null {
    if (this.parkingInProgress) return null
    const token: number = this.parkingSequenceToken + 1
    this.parkingSequenceToken = token
    this.parkingInProgress = true
    return token
  }

  private endParkingSequence(token: number): void {
    if (token === this.parkingSequenceToken) {
      this.parkingInProgress = false
    }
  }

  private startsWithAny(s: string, prefixes: Array<string>): boolean {
    for (let i: number = 0; i < prefixes.length; i++) {
      if (s.startsWith(prefixes[i])) return true
    }
    return false
  }

  private classifyLabel(label: string): VisionLabelKind {
    return classifyLabel(label)
  }

  private maybeLogVisionTaskOrTraffic(nowMs: number): void {
    maybeLogVisionTaskOrTraffic(this as object, nowMs)
  }


  private yoloSuggestBlockedNodeId(nowMs: number): string {
    return yoloSuggestBlockedNodeId(this as object, nowMs)
  }

  private maybeTriggerRoutePointObstacle(): boolean {
    return maybeTriggerRoutePointObstacle(this as object)
  }

  private frontRouteEdgeIdForDriving(): string {
    return frontRouteEdgeIdForDriving(this as object)
  }

  private markRouteObstaclePointOnEdge(edgeId: string, nowMs: number): void {
    markRouteObstaclePointOnEdge(this as object, edgeId, nowMs)
  }

  private promoteBlockedEdgePairsToBlockedNodes(): Array<string> {
    return promoteBlockedEdgePairsToBlockedNodes(this as object)
  }

  private maybeHandleDrivingUltrasonicObstacle(nowMs: number, edgeOverride: string = ''): void {
    maybeHandleDrivingUltrasonicObstacle(this as object, nowMs, edgeOverride)
  }

  private maybeReplanOnObstacle(): void {
    maybeReplanOnObstacle(this as object)
  }

  private isNextNodeBlocked(): boolean {
    return isNextNodeBlocked(this as object)
  }

  private nearestNodeIdByPose(): string {
    return nearestNodeIdByPose(this as object)
  }

  private findNearestRouteSegmentByPose(): SegmentPoseMatch | undefined {
    return findNearestRouteSegmentByPose(this as object)
  }

  private headingDegFromTo(ax: number, ay: number, bx: number, by: number): number {
    const rad: number = Math.atan2(by - ay, bx - ax)
    const deg: number = rad * 180.0 / Math.PI
    return this.norm360(deg)
  }

  private segMidMinTValue(s: Page1UiStore): number {
    const raw: number = s.segMidMinT
    if (!Number.isFinite(raw)) return 0.12
    if (raw < 0.0) return 0.0
    if (raw > 0.49) return 0.49
    return raw
  }

  private segMidMaxTValue(s: Page1UiStore): number {
    const minT: number = this.segMidMinTValue(s)
    const raw: number = s.segMidMaxT
    let v: number = Number.isFinite(raw) ? raw : 0.88
    if (v < minT + 0.02) v = minT + 0.02
    if (v > 1.0) v = 1.0
    return v
  }

  private segHeadingPenaltyWeightValue(s: Page1UiStore): number {
    const raw: number = s.segHeadingPenaltyWeight
    if (!Number.isFinite(raw)) return 0.55
    if (raw < 0.0) return 0.0
    if (raw > 2.0) return 2.0
    return raw
  }

  private chooseSegmentEndpointForGoal(
    seg: SegmentPoseMatch,
    goal: string,
    blocked: Array<string>,
    blockedEdges: Array<string>
  ): SegmentPlanDecision | undefined {
    return chooseSegmentEndpointForGoal(this as object, seg, goal, blocked, blockedEdges)
  }

  private tryBuildSegmentAwarePath(goal: string, blocked: Array<string>, blockedEdges: Array<string>): Array<string> | undefined {
    return tryBuildSegmentAwarePath(this as object, goal, blocked, blockedEdges)
  }

  private clearAheadVisionReplanState(): void {
    this.aheadVisionPending = false
    this.aheadVisionReadyAtMs = 0
    this.aheadVisionEdgeId = ''
  }

  private resetGarageFlowState(): void {
    this.clearGarageCarportAckWatch()
    this.garageDepartStopSent = false
    this.garageDepartReady03 = false
    this.garageFinalCarportSent = false
    this.garageWaitingParkDone04 = false
    this.garagePendingCarportLevel = 0
    this.gateBillingRunning = false
    this.gateBillingStartAtMs = 0
    this.gateBillingElapsedMs = 0
  }

  private clearGarageCarportAckWatch(): void {
    if (this.garageCarportAckWatchTimerId >= 0) {
      clearTimeout(this.garageCarportAckWatchTimerId)
      this.garageCarportAckWatchTimerId = -1
    }
    this.garageCarportAckPending = false
    this.garageCarportAckRetryDone = false
    this.garageCarportAckPendingLevel = 0
    this.garageCarportAckSentAtMs = 0
  }

  private armGarageCarportAckRetry(level: number): void {
    this.garageCarportAckPending = true
    this.garageCarportAckRetryDone = false
    this.garageCarportAckPendingLevel = level
    this.garageCarportAckSentAtMs = Date.now()

    if (this.garageCarportAckWatchTimerId >= 0) {
      clearTimeout(this.garageCarportAckWatchTimerId)
      this.garageCarportAckWatchTimerId = -1
    }

    this.garageCarportAckWatchTimerId = setTimeout((): void => {
      this.garageCarportAckWatchTimerId = -1
      if (!this.garageCarportAckPending || this.garageCarportAckRetryDone) return
      this.garageCarportAckRetryDone = true
      void this.retryGarageCarportAfterAckTimeout()
    }, 2000) as number
  }

  private async retryGarageCarportAfterAckTimeout(): Promise<void> {
    if (!this.garageCarportAckPending) return
    const s: Page1UiStore | undefined = this.store
    const level: number = this.garageCarportAckPendingLevel
    if (level < 2 || level > 4) {
      this.clearGarageCarportAckWatch()
      return
    }
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (s) {
      s.bumpTx()
      s.pushLog(`GARAGE_CARPORT_RETRY: 2s未收到0xBD/0x01，重发 carport(${level})`)
      s.setAction(`garage carport retry level=${level}`)
    }
    if (!this.canSendMotionCommand(`CARPORT_${level}`, 'GARAGE_RETRY')) {
      return
    }
    await this.proto.carport(level)
    this.garageCarportAckSentAtMs = Date.now()
  }

  private onPathAckReceived01(): void {
    if (!this.garageCarportAckPending) return
    const s: Page1UiStore | undefined = this.store
    const level: number = this.garageCarportAckPendingLevel
    const elapsedMs: number = this.garageCarportAckSentAtMs > 0 ? Math.max(0, Date.now() - this.garageCarportAckSentAtMs) : 0
    this.clearGarageCarportAckWatch()
    if (s) s.pushLog(`GARAGE_CARPORT_ACK: 收到0xBD/0x01 level=${level} elapsed=${elapsedMs}ms`)
  }

  private async onGateEnterAckCompleted(fromId: string, toId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const from: string = fromId.trim().toUpperCase()
    const to: string = toId.trim().toUpperCase()
    if (from !== 'B4' || to !== 'B2') return

    const nowMs: number = Date.now()
    this.gateBillingRunning = true
    this.gateBillingStartAtMs = nowMs
    this.gateBillingElapsedMs = 0
    s.pushLog('GATE_BILLING: 入闸完成(BD=02)，开始计时并发送 billing')

    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    s.bumpTx()
    await this.proto.billing()
  }

  private isGarageTerminalNode(nodeId: string): boolean {
    return this.isSmartParkingGoal(nodeId)
  }

  private smartParkingGoalId(): string {
    const s: Page1UiStore | undefined = this.store
    if (!s) return 'F1'
    return s.smartParkingGoalId()
  }

  private isSmartParkingGoal(goalId: string): boolean {
    const x: string = goalId.trim().toUpperCase()
    return x.length > 0 && x === this.smartParkingGoalId()
  }

  private async maybeHandleGarageDepartBeforeDrive(_nowMs: number): Promise<boolean> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return false
    if (s.pathNodes.length <= 1) return false

    const startId: string = s.pathNodes[0].trim().toUpperCase()
    if (!this.isGarageTerminalNode(startId)) return false
    if (s.pathIndex !== 0) return false

    const curId: string = s.currentSnapNodeId.trim().toUpperCase()
    if (curId.length > 0 && curId !== startId) return false

    if (this.garageDepartReady03) return false

    if (!this.garageDepartStopSent) {
      this.garageDepartStopSent = true
      s.setAction(`garage depart wait(BC/03) from ${startId}`)
      if (this.canRealSend()) {
        s.bumpTx()
        if (!this.canSendMotionCommand('LOWCARPORT', 'GARAGE_DEPART')) {
          return true
        }
        await this.proto.lowcarport()
        s.pushLog(`GARAGE_DEPART: lowcarport sent at ${startId}, wait BC/03`)
      } else {
        // 保持模拟可用，无需硬件反馈。
        this.garageDepartReady03 = true
        s.pushLog(`GARAGE_DEPART: DRY_RUN bypass at ${startId}`)
        return false
      }
    }
    return true
  }

  private onGarageDepartReadyAck(): void {
    const s: Page1UiStore | undefined = this.store
    this.garageDepartReady03 = true
    if (s) {
      s.pushLog('GARAGE_DEPART: recv BC/03, drive enabled')
      s.setAction('车库出库就绪')
    }
  }

  private beginGarageWaitParkDone04(level: number): void {
    const s: Page1UiStore | undefined = this.store
    this.garageWaitingParkDone04 = true
    this.garagePendingCarportLevel = 2
    if (s) {
      s.pushLog(`GARAGE_PARKING: wait BC/04 then carport(${this.garagePendingCarportLevel})`)
      s.setAction('车库停车等待 BC/04')
    }
  }

  private onGarageParkDone04(): void {
    const s: Page1UiStore | undefined = this.store
    if (this.garageFinalCarportSent) {
      if (s) s.pushLog('GARAGE_PARK_DONE: BC/04 ignored (already sent)')
      return
    }

    if (!this.garageWaitingParkDone04) {
      const smartGoalId: string = this.smartParkingGoalId()
      const curId: string = s ? s.currentSnapNodeId.trim().toUpperCase() : ''
      const destId: string = s ? s.destApplied.trim().toUpperCase() : ''
      const atSmartGoal: boolean = curId === smartGoalId || destId === smartGoalId
      if (!atSmartGoal) {
        if (s) s.pushLog('GARAGE_PARK_DONE: BC/04 ignored (not waiting)')
        return
      }
      if (s) s.pushLog(`GARAGE_PARK_DONE: BC/04 fallback trigger at ${smartGoalId}`)
    } else {
      this.garageWaitingParkDone04 = false
    }

    const level: number = this.garagePendingCarportLevel > 0 ? this.garagePendingCarportLevel : 2
    this.garagePendingCarportLevel = 0
    this.garageFinalCarportSent = true
    void this.sendGarageCarportAfterParkDone(level)
  }

  private async sendGarageCarportAfterParkDone(level: number): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    const targetLevel: number = 2
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (s) {
      s.pushLog(`GARAGE_PARK_DONE: BC/04 -> carport(${targetLevel})`)
      s.setAction(`garage carport level=${targetLevel}`)
      s.bumpTx()
    }
    if (!this.canSendMotionCommand(`CARPORT_${targetLevel}`, 'GARAGE_PARK_DONE')) {
      return
    }
    await this.proto.carport(targetLevel)
    if (this.canRealSend()) this.armGarageCarportAckRetry(targetLevel)
  }

  private async maybeHandleGarageFinalArrive(toId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = toId.trim().toUpperCase()
    if (!this.isGarageTerminalNode(id)) return
    // 车库流程现在由到达前超声波 + BC/04 握手驱动。
    s.pushLog(`GARAGE_ARRIVE: ${id} waiting BC/04 to carport`)
  }

  private findPendingRouteObstacleOnEdge(edgeId: string, nowMs: number): RouteObstaclePoint | undefined {
    return findPendingRouteObstacleOnEdge(this as object, edgeId, nowMs)
  }

  private maybeStartAheadVisionReplan(fromId: string, toId: string, nowMs: number): boolean {
    return maybeStartAheadVisionReplan(this as object, fromId, toId, nowMs)
  }

  private maybeHandleAheadVisionReplan(nowMs: number): boolean {
    return maybeHandleAheadVisionReplan(this as object, nowMs)
  }

  private resolveStartNodeId(): string {
    return resolveStartNodeId(this as object)
  }

  private isParkingInnerRowNode(id: string): boolean {
    return isParkingInnerRowNode(id)
  }

  private isInsideGateInnerSideNode(id: string): boolean {
    return isInsideGateInnerSideNode(id)
  }

  private gateForcedWaypoint(startId: string, goalId: string): string {
    return gateForcedWaypoint(this as object, startId, goalId)
  }

  private buildPathViaWaypoint(
    start: string,
    via: string,
    goal: string,
    blocked: Array<string>,
    blockedEdges: Array<string>
  ): AStarPlanResult {
    return buildPathViaWaypoint(this as object, start, via, goal, blocked, blockedEdges)
  }

  planPath(dest: string): void {
    planPathOp(this as object, dest)
  }

  private syncLogicalHeadingWithCurrentState(): void {
    syncLogicalHeadingWithCurrentState(this as object)
  }

  private segmentHeadingDeg(fromId: string, toId: string): number {
    return segmentHeadingDeg(this as object, fromId, toId)
  }

  private normToCardinal(v: number): number {
    return normToCardinal(this as object, v)
  }

  private actionForHeadingTransition(curDeg: number, desiredDeg: number): Page1Action | undefined {
    return actionForHeadingTransition(this as object, curDeg, desiredDeg)
  }

  private predictActionForPair(curHeadingDeg: number, fromId: string, toId: string): Page1Action {
    return predictActionForPair(this as object, curHeadingDeg, fromId, toId)
  }

  private predictedHeadingAfterAction(curHeadingDeg: number, action: Page1Action, fromId: string, toId: string): number {
    return predictedHeadingAfterAction(this as object, curHeadingDeg, action, fromId, toId)
  }

  private peekNextActionAfterCurrentStep(): Page1Action | undefined {
    return peekNextActionAfterCurrentStep(this as object)
  }

  private clearEmergencyAlarmTimer(): void {
    if (this.emergencyAlarmTimerId >= 0) {
      clearTimeout(this.emergencyAlarmTimerId)
      this.emergencyAlarmTimerId = -1
    }
  }

  private setMotionCommandBlock(reason: string, holdMs: number): void {
    const nowMs: number = Date.now()
    const safeHoldMs: number = Math.max(0, Math.round(holdMs))
    const untilMs: number = nowMs + safeHoldMs
    if (untilMs > this.motionCommandBlockUntilMs) {
      this.motionCommandBlockUntilMs = untilMs
    }
    this.motionCommandBlockReason = reason
  }

  private clearMotionCommandBlock(): void {
    this.motionCommandBlockUntilMs = 0
    this.motionCommandBlockReason = ''
    this.motionCommandBlockLastLogAtMs = 0
  }

  isMotionCommandBlocked(nowMs: number = Date.now()): boolean {
    return nowMs < this.motionCommandBlockUntilMs
  }

  canSendMotionCommand(commandKey: string, sourceTag: string): boolean {
    const nowMs: number = Date.now()
    if (!this.isMotionCommandBlocked(nowMs)) return true

    const s: Page1UiStore | undefined = this.store
    if (s && nowMs - this.motionCommandBlockLastLogAtMs >= 500) {
      this.motionCommandBlockLastLogAtMs = nowMs
      const remainMs: number = Math.max(0, this.motionCommandBlockUntilMs - nowMs)
      s.pushLog(
        `MOTION_BLOCKED: ${sourceTag}:${commandKey} skipped, remain=${remainMs}ms reason=${this.motionCommandBlockReason}`
      )
    }
    return false
  }

  private armAlarmEnable(delayMs: number, reason: string): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (s.alarmEnabled) return
    if (this.emergencyAlarmTimerId >= 0) return
    const safeDelayMs: number = Math.max(0, Math.round(delayMs))
    this.emergencyAlarmTimerId = setTimeout((): void => {
      this.emergencyAlarmTimerId = -1
      if (s.alarmEnabled) return
      this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
      s.alarmEnabled = true
      s.bumpTx()
      void this.proto.setAlarm(true)
      s.pushLog(`EMERGENCY_ALARM: ON reason=${reason}`)
    }, safeDelayMs) as number
  }

  private hasShigongBarrierFromLatestRecog(): boolean {
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.subtype !== RecognitionSubtype.BARRIER || r.boxes.length <= 0) return false
    for (let i: number = 0; i < r.boxes.length; i++) {
      const box: BBoxNorm = r.boxes[i]
      if (box.score < 0.18) continue
      const key: string = normalizeBarrierLabelKey(box.label)
      if (isShigongBarrierLabelKey(key)) return true
    }
    return false
  }

  maybeHandleBarrierEmergencyStop(nowMs: number): boolean {
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.subtype !== RecognitionSubtype.BARRIER) return false
    if (!this.hasShigongBarrierFromLatestRecog()) return false
    if (this.barrierEmergencyBusy) return true
    if (r.taskId.length > 0 && r.taskId === this.lastBarrierEmergencyTaskId) return false
    if (r.tsMs > 0 && r.tsMs <= this.lastBarrierEmergencyTsMs) return false

    this.barrierEmergencyBusy = true
    this.lastBarrierEmergencyTaskId = r.taskId
    this.lastBarrierEmergencyTsMs = Math.max(this.lastBarrierEmergencyTsMs, r.tsMs)

    void this.emergencyStopAndHold('BARRIER', 5000, 0).finally((): void => {
      this.barrierEmergencyBusy = false
    })
    return true
  }

  async emergencyStopAndHold(reason: string = 'MANUAL_SCRAM', holdMs: number = 5000, alarmDelayMs: number = 1000): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    this.cancelMapPoseAnimation()
    this.cancelParkingSequence()
    this.gateDepartInProgress = false
    this.resetGateDepartDedupState()
    this.resetAutoActionDedupState()
    this.resetPathAckState()
    this.stopActiveMotion()
    this.actionScheduler.reset()
    this.setMotionCommandBlock(reason, holdMs)

    s.autoFollowEnabled = false
    s.lastAutoFollowAtMs = Date.now()

    await this.sendDriveActionDirect(Page1Action.STOP)
    this.armAlarmEnable(alarmDelayMs, reason)

    s.setAction('紧急停止')
    s.pushLog(`EMERGENCY STOP: reason=${reason}, hold=${holdMs}ms, alarmDelay=${alarmDelayMs}ms`)
  }

  private canSendNextCommand(nowMs: number): boolean {
    return canSendNextCommand(this as object, nowMs)
  }

  schedulerSnapshot(nowMs: number = Date.now()): SchedulerSnapshot {
    const snap: SchedulerSnapshot = this.actionScheduler.snapshot(nowMs, this.motionRunning())
    this.lastSchedulerSnapshot = snap
    return snap
  }

  motionSnapshot(nowMs: number = Date.now()): MotionStateSnapshot {
    const snap: MotionStateSnapshot = this.motionPlayer.snapshot(nowMs)
    this.lastMotionSnapshot = snap
    return snap
  }

  setMotionPhaseTuning(tuning?: MotionPhaseTuning): void {
    this.motionPlayer.setPhaseTuning(tuning)
  }

  motionLastCompleteAtMs(): number {
    return this.lastMotionCompleteAtMs
  }

  private async sendAutoActionWithTiming(
    action: Page1Action,
    fromId: string,
    toId: string,
    nextAction?: Page1Action,
    customTiming?: MotionTimingProfile,
    advancePathOnFinish?: boolean,
    useReverseSpeed?: boolean,
    customLogTag?: string
  ): Promise<boolean> {
    return await sendAutoActionWithTiming(
      this as object,
      action,
      fromId,
      toId,
      nextAction,
      customTiming,
      advancePathOnFinish,
      useReverseSpeed,
      customLogTag
    )
  }

  private async followPathOnce(nowMs: number, force: boolean): Promise<void> {
    await followPathOnce(this as object, nowMs, force)
  }

  private async maybeRunParkingBeforeFinalEdgeArrival(arrivedId: string): Promise<boolean> {
    return await runParkingBeforeFinalEdgeArrival(this as object, arrivedId)
  }

  private edgeSideOfNode(id: string): EdgeSide {
    const s: Page1UiStore | undefined = this.store
    if (!s) return EdgeSide.NONE
    return Page1CoordinatorGridUtils.edgeSideOfNode(s.gridNodes, id)
  }

  private isReverseParkingGoal(goalId: string): boolean {
    return Page1CoordinatorGridUtils.isReverseParkingGoal(goalId)
  }

  private fallbackParkingGoalOnObstacle(goalId: string): string {
    const x: string = goalId.trim().toUpperCase()
    if (x === 'B1') return 'F1'
    if (x === 'F1') return 'B1'
    return 'F1'
  }

  private async maybeRunNormalFinalParkingAfterArrival(fromId: string, toId: string): Promise<boolean> {
    return false
  }

  private isLivePathPair(curId: string, nextId: string): boolean {
    const s: Page1UiStore | undefined = this.store
    if (!s) return false
    if (s.pathNodes.length <= 1) return false
    if (s.pathIndex < 0 || s.pathIndex >= s.pathNodes.length - 1) return false
    const liveCur: string = s.pathNodes[s.pathIndex].trim().toUpperCase()
    const liveNext: string = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
    return liveCur === curId && liveNext === nextId
  }

  private async maybeHandleGateDepartOnArrival(arrivedId: string): Promise<boolean> {
    return await runHandleGateDepartOnArrival(this as object, arrivedId)
  }

  private async updateMotionTimeline(nowMs: number): Promise<void> {
    await this.motionPlayer.update(nowMs, this.motionHooks())
    this.lastMotionSnapshot = this.motionPlayer.snapshot(nowMs)
    this.lastSchedulerSnapshot = this.actionScheduler.snapshot(nowMs, this.motionRunning())
  }

  private norm360(v: number): number {
    return Page1CoordinatorGridUtils.norm360(v)
  }

  private headingErrorDeg(curDeg: number, desiredDeg: number): number {
    return Page1CoordinatorGridUtils.headingErrorDeg(curDeg, desiredDeg)
  }

  private findNode(id: string): NormPoint | undefined {
    const s: Page1UiStore | undefined = this.store
    if (!s) return undefined
    return Page1CoordinatorGridUtils.findNode(s.gridNodes, id)
  }

  private startSimulator(): void {
    startSimulatorLoop(this as object)
  }

  private stopSimulator(): void {
    stopSimulatorLoop(this as object)
  }

  private simAmbientFrontCm(): number {
    return simAmbientFrontCm(this as object)
  }

  private simAmbientBackCm(): number {
    return simAmbientBackCm(this as object)
  }

  private simAmbientIrCm(): number {
    return simAmbientIrCm(this as object)
  }

  private simAmbientLux(): number {
    return simAmbientLux(this as object)
  }

  private async sleep(ms: number): Promise<void> {
    await sleepMs(ms)
  }

  private async simulateOnce(): Promise<void> {
    await simulateOnceLoop(this as object)
  }

  private decodePackedNodeId(v: number): string {
    return this.byteToHex(v)
  }

  async startManualRoute(dest: string): Promise<void> {
    const s = this.store
    if (!s) return

    const goal: string = dest.trim().toUpperCase()
    if (goal.length === 0) return

    s.destDraft = goal
    s.applyDest()

    if (!this.canRealSend()) {
      this.planPath(goal)
      return
    }

    this.planPath(goal)
  }

  async speakText(text: string): Promise<boolean> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return false

    const content: string = text.trim()
    if (content.length <= 0) return false

    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    s.setAction('站台播报')
    s.bumpTx()

    if (!this.canRealSend()) {
      s.pushLog('VOICE: 当前非REAL_SEND，跳过自动播报')
      return false
    }

    await this.proto.yuying(content)
    s.pushLog(`VOICE: 自动播报发送(${content.length}字)`)
    return true
  }
}

export const page1Coordinator: Page1Coordinator = new Page1Coordinator()
