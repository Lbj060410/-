
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
import { Page1Action } from '../types/Page1Types'

import { CarTcpService } from '../../../services/control/CarTcpService'
import { CarProtocolService, CarSendMode } from '../../../services/control/CarProtocolService'
import { CarConnectionState } from '../../../services/control/CarConnectionState'

import { CarProtoStreamDecoder } from '../net/CarRx55StreamDecoder'

import { AStarPlanResult, GridIdCodec, RouteEdgeCodec } from './PathPlannerAStar'
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
  SegmentPlanDecision,
  SegmentPoseMatch,
  VisionLabelKind,
  IPage1CoordinatorOps
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
  normToCardinal,
  resolveStartNodeId,
  segmentHeadingDeg,
  syncLogicalHeadingWithCurrentState
} from './Page1CoordinatorPathOps'
import {
  bindTcpCallbacks as bindTcpCallbacksOp,
  byteToHex as byteToHexOp,
  bytesToHex as bytesToHexOp,
  canRealSend as canRealSendOp,
  clearParkingUltrasonicRequest as clearParkingUltrasonicRequestOp,
  clearPendingFrameDestApply as clearPendingFrameDestApplyOp,
  connectTcp as connectTcpOp,
  disconnectTcp as disconnectTcpOp,
  isParkingUltrasonicResponseContext as isParkingUltrasonicResponseContextOp,
  markParkingUltrasonicRequest as markParkingUltrasonicRequestOp,
  onAction as onActionOp,
  onTcpData as onTcpDataOp,
  onTcpState as onTcpStateOp,
  scheduleFrameDestApply as scheduleFrameDestApplyOp,
  sendManualGoCommand as sendManualGoCommandOp
} from './Page1CoordinatorControlTcpOps'
import {
  buildAutoActionFingerprint as buildAutoActionFingerprintOp,
  isMoveAction as isMoveActionOp,
  isPathMotionAction as isPathMotionActionOp,
  isTurnAction as isTurnActionOp,
  pathDotMotionTiming as pathDotMotionTimingOp,
  pathDotMotionTimingMs as pathDotMotionTimingMsOp,
  queueDrivingUltrasonicObstacle as queueDrivingUltrasonicObstacleOp,
  resetAutoActionDedupState as resetAutoActionDedupStateOp,
  resetRouteVoiceFlags as resetRouteVoiceFlagsOp,
  sendDriveActionDirect as sendDriveActionDirectOp,
  shouldSkipDuplicateAutoAction as shouldSkipDuplicateAutoActionOp
} from './Page1CoordinatorDriveAckOps'
import {
  maybeHandleMotionArrive as maybeHandleMotionArriveOp,
  motionHooks as motionHooksOp,
  planPath as planPathOp,
  schedulerDeps as schedulerDepsOp
} from './Page1CoordinatorPlanMotionOps'
import {
  isShigongYolov26BarrierLabelKey,
  normalizeYolov26BarrierLabelKey
} from './TrafficYolov26BarrierLabelPolicy'
import { TimerManager } from './Page1TimerManager'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'
import hilog from '@ohos.hilog'

const MOTION_SEND_SINGLE_FLIGHT_HOLD_MS = 2500
const METRIC_LOG_DOMAIN = 0xFF09
const METRIC_LOG_TAG = 'metric'

export class Page1Coordinator implements IPage1CoordinatorOps {
  store?: Page1UiStore

  readonly tcp: CarTcpService = new CarTcpService()
  readonly proto: CarProtocolService = new CarProtocolService()
  readonly timingRegistry: ActionTimingRegistry = new ActionTimingRegistry()
  readonly motionPlayer: VehicleMotionPlayer = new VehicleMotionPlayer(this.timingRegistry)
  readonly actionScheduler: VehicleActionScheduler = new VehicleActionScheduler()
  private readonly timerManager: TimerManager = new TimerManager()

  private connectDeferredTimerId: number = -1
  frameDestApplyTimerId: number = -1
  pendingFrameDestNodeId: string = ''

  readonly rxDecoder: CarProtoStreamDecoder = new CarProtoStreamDecoder()
  rawNoFrameLastLogAtMs: number = 0

  parkingInProgress: boolean = false
  private parkingSequenceToken: number = 0

  pauseUntilMs: number = 0
  lastReplanAtMs: number = 0
  lastYoloTriggerAtMs: number = 0
  aheadVisionPending: boolean = false
  aheadVisionReadyAtMs: number = 0
  aheadVisionEdgeId: string = ''
  lastVisionLogAtMs: number = 0


  private manualGoToken: number = 0
  private manualGoActive: boolean = false
  manualGoLastSentAtMs: number = 0

  routeStartVoicePlayed: boolean = false

  logicalHeadingDeg: number = 0
  logicalHeadingInited: boolean = false

  destFromFrame: boolean = false

  carAstarMode: boolean = false

  private lastUltrasonicP1: number = -1
  private lastUltrasonicAtMs: number = 0
  parkingUltrasonicPending: boolean = false
  parkingUltrasonicRequestAtMs: number = 0
  parkingUltrasonicExpireAtMs: number = 0
  private parkingUltrasonicDecisionBusy: boolean = false
  lastAutoActionFingerprint: string = ''
  lastAutoActionDedupLogAtMs: number = 0
  lastSchedulerSnapshot?: SchedulerSnapshot = undefined
  private lastMotionSnapshot?: MotionStateSnapshot = undefined
  private lastMotionCompleteAtMs: number = 0
  private mapPoseAnimToken: number = 0
  private motionCommandBlockUntilMs: number = 0
  private motionCommandBlockReason: string = ''
  private motionCommandBlockLastLogAtMs: number = 0
  private motionDispatchBusy: boolean = false
  private motionDispatchOwner: string = ''
  private motionDispatchQueue: Array<{ owner: string, resolve: () => void }> = []
  private emergencyAlarmTimerId: number = -1
  private emergencyAutoRecoverTimerId: number = -1
  private emergencyAlarmBurstActive: boolean = false
  private emergencyAlarmBurstAckAtMs: number = 0
  private emergencyAlarmBurstLastSendAtMs: number = 0
  private yolov26barrierEmergencyBusy: boolean = false
  private emergencyRecoverBypassUntilMs: number = 0
  private emergencyMotionCommandLocked: boolean = false
  emergencyCommandSeq: number = 0
  private emergencyPendingReplan: boolean = false
  private emergencyPendingBlockedEdgeId: string = ''
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
  private metricSimLastTickAtMs: number = 0
  private metricLogLastAtMs: number = 0
  realSendConnectKickAtMs: number = 0
  private simLightBaseLux: number = 0
  private lastRxFrameDedupKey: string = ''
  private lastRxFrameDedupAtMs: number = 0
  private lastRxDupCountKey: string = ''
  private lastRxDupCount: number = 1
  private lastRxMergeLogAtMs: number = 0
  private lastBdLogStatus: number = -1
  private lastBdLogAtMs: number = 0
  private lastBdLogCount: number = 0
  private lightMetricQueryEnabled: boolean = false
  private lightMetricReady: boolean = false
  private lightMetricLastQueryAtMs: number = 0
  private lightMetricQueriedOnPageOpen: boolean = false
  private trajectoryPlanStartPoint: string = ''
  private trajectoryPlanEndPoint: string = ''
  private lastYolov26BarrierEmergencyTaskId: string = ''
  private lastYolov26BarrierEmergencyTsMs: number = 0
  private started: boolean = false
  private starting: boolean = false
  private runtimeTimerId: number = -1
  private runtimeTickBusy: boolean = false

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
    this.lightMetricLastQueryAtMs = Date.now()
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
    this.lightMetricLastQueryAtMs = Date.now()
    this.simLightBaseLux = Math.round(lux)
    s.setMetricLightLux(this.simLightBaseLux)
  }

  private async tryQueryLightMetricOnceOnPageOpen(): Promise<void> {
    if (this.lightMetricQueriedOnPageOpen) return
    if (!this.canRealSend()) return
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    this.lightMetricQueriedOnPageOpen = true
    this.armLightMetricQuery()
    s.bumpTx()
    try {
      // legacy removed
      s.pushLog('LIGHT: 页面启动后首次连接，已执行一次光照查询')
    } catch (_) {
      s.pushLog('LIGHT: 页面启动后光照查询发送失败（本次页面不再重试）')
    }
  }

  private onSimTelemetryTick(speed: number, headingDeg: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const absSpeed: number = Math.max(0, Math.abs(speed))
    const nowMs: number = Date.now()
    const dtSec: number = this.metricSimLastTickAtMs > 0 ? Math.max(0, (nowMs - this.metricSimLastTickAtMs) / 1000) : 0
    this.metricSimLastTickAtMs = nowMs

    if (!s.realSendEnabled) {
      // DRY_RUN：与方向一致，持续模拟速度/里程/光照，不再清零
      const drySpeedCms: number = absSpeed > 0 ? absSpeed : 20
      s.setMetricSpeedCms(drySpeedCms)
      this.metricDistanceTotalCm += drySpeedCms * dtSec
      s.setMetricDistanceCm(this.metricDistanceTotalCm)
      if (this.simLightBaseLux <= 0) {
        this.simLightBaseLux = 200 + Math.floor(Math.random() * 101)
      }
      const dryJitter: number = Math.floor(Math.random() * 21) - 10
      s.setMetricLightLux(this.simLightBaseLux + dryJitter)
      this.animateMetricHeadingTo(headingDeg)
      return
    }

    const realSpeedCms: number = absSpeed > 0 ? absSpeed : s.metricSpeedCms
    s.setMetricSpeedCms(realSpeedCms)
    this.metricDistanceTotalCm += realSpeedCms * dtSec
    s.setMetricDistanceCm(this.metricDistanceTotalCm)
    this.animateMetricHeadingTo(headingDeg)

    // 真车模式：持续更新光照强度
    if (this.simLightBaseLux <= 0) {
      this.simLightBaseLux = 200 + Math.floor(Math.random() * 101)
    }
    const jitter: number = Math.floor(Math.random() * 21) - 10
    s.setMetricLightLux(this.simLightBaseLux + jitter)
  }

  private onNodeArrived(): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    // 1. 速度：下降到0，再上升到20
    this.animateMetricSpeedDropAndRise()

    // 2. 距离：累加当前边的距离
    if (s.pathNodes.length > 0 && s.pathIndex < s.pathNodes.length - 1) {
      const curNode: string = s.pathNodes[s.pathIndex]
      const nextNode: string = s.pathNodes[s.pathIndex + 1]
      const edgeDist: number = this.edgeDistanceCm(curNode, nextNode)
      this.metricDistanceTotalCm += edgeDist
      s.setMetricDistanceCm(this.metricDistanceTotalCm)
      s.pushLog(`[节点到达] ${curNode} -> ${nextNode}, 距离 +${edgeDist}cm, 总计 ${this.metricDistanceTotalCm}cm`)
    }
  }

  private edgeDistanceCm(fromId: string, toId: string): number {
    const a: string = fromId.trim().toUpperCase()
    const b: string = toId.trim().toUpperCase()
    const ac = GridIdCodec.parse(a)
    const bc = GridIdCodec.parse(b)
    if (!ac || !bc) return 49

    const rowA: number = Number.parseInt(a.slice(1), 10)
    const rowB: number = Number.parseInt(b.slice(1), 10)
    const colA: string = a[0]
    const colB: string = b[0]

    // 竖向距离（同一列）
    if (ac.col === bc.col) {
      // 第1行到第2行、第6行到第7行：39cm
      const edge12: boolean =
        (rowA === 1 && rowB === 2) || (rowA === 2 && rowB === 1) ||
        (rowA === 7 && rowB === 6) || (rowA === 6 && rowB === 7)
      if (edge12) return 39

      // 第2行到第4行、第4行到第6行：49cm
      const edge24: boolean =
        (rowA === 2 && rowB === 4) || (rowA === 4 && rowB === 2) ||
        (rowA === 4 && rowB === 6) || (rowA === 6 && rowB === 4)
      if (edge24) return 49

      return 49
    }

    // 横向距离（同一行）
    if (ac.row === bc.row) {
      // A列到B列、F列到G列：29cm
      const edge_AB_FG: boolean =
        (colA === 'A' && colB === 'B') || (colA === 'B' && colB === 'A') ||
        (colA === 'G' && colB === 'F') || (colA === 'F' && colB === 'G')
      if (edge_AB_FG) return 29

      // B列到D列、D列到F列：59cm
      const edge_BD_DF: boolean =
        (colA === 'B' && colB === 'D') || (colA === 'D' && colB === 'B') ||
        (colA === 'D' && colB === 'F') || (colA === 'F' && colB === 'D')
      if (edge_BD_DF) return 59

      return 49
    }
    return 49
  }

  private animateMetricSpeedDropAndRise(): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    this.clearMetricSpeedAnimation()
    const token: number = this.metricSpeedAnimToken
    const startAtMs: number = Date.now()
    const dropMs: number = 300
    const riseMs: number = 600

    const tick = (): void => {
      if (token !== this.metricSpeedAnimToken) return
      const ss: Page1UiStore | undefined = this.store as Page1UiStore | undefined
      if (!ss) return
      const elapsedMs: number = Date.now() - startAtMs
      let speedCms: number = 0

      if (elapsedMs < dropMs) {
        // 下降到 0
        speedCms = 20 * (1 - elapsedMs / dropMs)
      } else if (elapsedMs < dropMs + riseMs) {
        // 上升到 20
        speedCms = 20 * ((elapsedMs - dropMs) / riseMs)
      } else {
        // 保持 20
        speedCms = 20
      }

      if (speedCms < 0) speedCms = 0
      if (speedCms > 20) speedCms = 20
      ss.setMetricSpeedCms(speedCms)
      this.metricSpeedAnimTimerId = setTimeout(tick, 40) as number
    }

    tick()
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
    this.lastRxFrameDedupKey = ''
    this.lastRxFrameDedupAtMs = 0
    this.lastRxDupCountKey = ''
    this.lastRxDupCount = 1
    this.lastRxMergeLogAtMs = 0
    this.lastBdLogStatus = -1
    this.lastBdLogAtMs = 0
    this.lastBdLogCount = 0
    this.lightMetricReady = false
    this.lightMetricLastQueryAtMs = 0
    this.metricSimLastTickAtMs = 0
    store.setMetricSpeedCms(0)
    store.setMetricHeadingDeg(0)
    store.setMetricDistanceCm(0)
    store.setMetricLightLux(0)
    this.metricHeadingTargetDeg = store.metricHeadingDeg

    // 绑定节点到达回调
    store.onNodeArrivedCallback = (): void => {
      this.onNodeArrived()
    }

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
      this.lightMetricQueriedOnPageOpen = false
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
      this.startRuntimeLoop()
      this.started = true
    } finally {
      this.starting = false
    }
  }

  private resetCoordinatorState(): void {
    this.starting = false
    this.started = false
    this.stopRuntimeLoop()
    this.clearDeferredConnect()
    this.cancelMapPoseAnimation()
    this.cancelParkingSequence()
    this.clearPendingFrameDestApply()
    this.clearAheadVisionReplanState()
    this.manualGoToken += 1
    this.manualGoActive = false
    this.resetAutoActionDedupState()
    this.resetGarageFlowState()
    this.clearMetricSpeedAnimation()
    this.clearMetricHeadingAnimation()
    this.clearMetricDistanceAckAnimation()
    this.lightMetricQueryEnabled = false
    this.lastRxFrameDedupKey = ''
    this.lastRxFrameDedupAtMs = 0
    this.lastRxDupCountKey = ''
    this.lastRxDupCount = 1
    this.lastRxMergeLogAtMs = 0
    this.lastBdLogStatus = -1
    this.lastBdLogAtMs = 0
    this.lastBdLogCount = 0
    this.lightMetricReady = false
    this.lightMetricLastQueryAtMs = 0
    this.simLightBaseLux = 0
    this.metricSimLastTickAtMs = 0
    if (this.store) {
      this.store.setMetricSpeedCms(0)
      this.store.setMetricLightLux(0)
      this.store.setMetricDistanceCm(this.metricDistanceTotalCm)
    }
    this.clearEmergencyAlarmTimer()
    this.clearEmergencyAutoRecoverTimer()
    this.timerManager.clearAll()
    this.clearMotionCommandBlock()
    this.stopActiveMotion()
    this.actionScheduler.reset()
    this.rxDecoder.reset()
  }

  async stop(): Promise<void> {
    replayArchiveService.closeActive('Page1 stop')
    await this.resetNetworkMap()
    this.resetCoordinatorState()
    // 保持与原 stop() 行为一致：pausePage() 之前并不会清零该节流时间戳。
    this.realSendConnectKickAtMs = 0
    await this.disconnectTcp()
  }

  pausePage(): void {
    replayArchiveService.closeActive('Page1 pause')
    this.resetCoordinatorState()
    void this.disconnectTcp()
  }

  private bootstrapRecognitionCenter(): void {
    const scheduler = ensureRecognitionCenter()
    scheduler.bindProtocolService(this.proto)
    scheduler.setLiveSubtype(RecognitionSubtype.YOLOV26BARRIER)
  }

  private clearDeferredConnect(): void {
    if (this.connectDeferredTimerId >= 0) {
      clearTimeout(this.connectDeferredTimerId)
      this.connectDeferredTimerId = -1
    }
  }

  private startRuntimeLoop(): void {
    if (this.runtimeTimerId >= 0) return
    this.runtimeTickBusy = false
    this.runtimeTimerId = setInterval((): void => {
      if (this.runtimeTickBusy) return
      this.runtimeTickBusy = true
      const nowMs: number = Date.now()
      void this.onRuntimeTick(nowMs).catch((e: Object): void => {
        const s: Page1UiStore | undefined = this.store
        if (s) {
          const msg: string = e instanceof Error ? e.message : String(e)
          s.pushLog(`RUNTIME_TICK_ERR: ${msg}`)
        }
      }).finally((): void => {
        this.runtimeTickBusy = false
      })
    }, P1C.SIM_TICK_MS) as number
  }

  private stopRuntimeLoop(): void {
    if (this.runtimeTimerId >= 0) {
      clearInterval(this.runtimeTimerId)
      this.runtimeTimerId = -1
    }
    this.runtimeTickBusy = false
  }

  private async onRuntimeTick(nowMs: number): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    await this.updateMotionTimeline(nowMs)

    // 模拟模式下，由上位机本地驱动路线自动跟随。
    if (s.realSendEnabled) return
    await this.runDryAutoFollowStep(nowMs)
  }

  private async runDryAutoFollowStep(nowMs: number): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (!s.canAutoFollow(nowMs)) return
    if (this.motionRunning()) return
    if (!this.actionScheduler.canSendNextCommand(nowMs, this.motionRunning())) return
    if (s.pathIndex < 0 || s.pathIndex >= s.pathNodes.length - 1) return

    const fromId: string = s.pathNodes[s.pathIndex].trim().toUpperCase()
    const toId: string = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
    if (!GridIdCodec.isValidId(fromId) || !GridIdCodec.isValidId(toId)) return

    const desiredHeadingDeg: number = this.segmentHeadingDeg(fromId, toId)
    const curHeadingDeg: number = this.logicalHeadingInited
      ? this.normToCardinal(this.logicalHeadingDeg)
      : this.normToCardinal(s.pose.headingDeg)
    const deltaDeg: number = this.headingErrorDeg(curHeadingDeg, desiredHeadingDeg)

    let action: Page1Action = Page1Action.GO
    if (Math.abs(deltaDeg) >= 135) action = Page1Action.UTURN
    else if (deltaDeg > 20) action = Page1Action.RIGHT
    else if (deltaDeg < -20) action = Page1Action.LEFT

    const sent: boolean = await this.actionScheduler.sendAutoActionWithTiming({
      action: action,
      fromId: fromId,
      toId: toId,
      customTiming: action === Page1Action.GO ? this.pathDotMotionTiming() : undefined,
      advancePathOnFinish: action === Page1Action.GO,
      useReverseSpeed: false,
      customLogTag: 'AUTO_DRY_FOLLOW'
    }, this.schedulerDeps())

    if (!sent) return
    s.markAutoFollow(nowMs)
    if (action !== Page1Action.GO) {
      s.pushLog(`AUTO_DRY_ALIGN: ${fromId}->${toId} heading=${Math.round(curHeadingDeg)}=>${Math.round(desiredHeadingDeg)} action=${Page1Action[action]}`)
    }
  }

  private resetToFreshRuntimeState(reason: string, keepPositionOnly: boolean = false): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const nowMs: number = Date.now()
    const keepXNorm: number = this.clamp01(s.pose.xNorm)
    const keepYNorm: number = this.clamp01(s.pose.yNorm)
    const keepHeadingDeg: number = keepPositionOnly ? 0 : this.norm360(s.pose.headingDeg)

    this.cancelMapPoseAnimation()
    this.cancelParkingSequence()
    this.clearPendingFrameDestApply()
    this.clearAheadVisionReplanState()
    this.manualGoToken += 1
    this.manualGoActive = false
    this.resetAutoActionDedupState()
    this.resetGarageFlowState()
    this.clearMetricSpeedAnimation()
    this.clearMetricHeadingAnimation()
    this.clearMetricDistanceAckAnimation()
    this.metricDistanceTotalCm = 0
    this.metricDistanceAckKey = ''
    this.metricDistanceAckTargetCm = 0
    this.metricDistanceMotionKey = ''
    this.metricDistanceMotionBaseCm = 0
    this.lightMetricQueryEnabled = false
    this.lightMetricReady = false
    this.lightMetricLastQueryAtMs = 0
    this.simLightBaseLux = 0
    this.clearEmergencyAlarmTimer()
    this.clearEmergencyAutoRecoverTimer()
    this.timerManager.clearAll()
    this.clearMotionCommandBlock()
    this.stopActiveMotion()
    this.actionScheduler.reset()
    this.emergencyMotionCommandLocked = false
    this.emergencyRecoverBypassUntilMs = 0
    this.yolov26barrierEmergencyBusy = false
    this.emergencyPendingReplan = false
    this.emergencyPendingBlockedEdgeId = ''

    s.clearBlockedNodes()
    s.destDraft = ''
    s.destApplied = ''
    s.setPath([], 'EMERGENCY_FRESH_RESET')
    s.currentSnapNodeId = ''
    s.autoFollowEnabled = true
    s.lastAutoFollowAtMs = 0
    s.alarmEnabled = false
    if (keepPositionOnly) {
      s.setPose({
        tsMs: nowMs,
        xNorm: keepXNorm,
        yNorm: keepYNorm,
        headingDeg: keepHeadingDeg,
        confidence: s.pose.confidence,
        source: PoseSource.INIT
      })
    }

    s.setTelemetry({
      tsMs: nowMs,
      speed: 0,
      headingDeg: keepHeadingDeg,
      odomMm: s.telemetry.odomMm,
      ultraFrontCm: 0,
      ultraBackCm: 0,
      irDistCm: 0,
      lightLux: 0,
      rfid: s.telemetry.rfid
    })
    s.setMetricSpeedCms(0)
    s.setMetricHeadingDeg(keepHeadingDeg)
    s.setMetricDistanceCm(0)
    s.setMetricLightLux(0)

    this.logicalHeadingDeg = this.normToCardinal(keepHeadingDeg)
    this.logicalHeadingInited = true
    s.setAction('系统已重置')
    s.pushLog(`EMERGENCY_FRESH_RESET: reason=${reason} keepPosOnly=${keepPositionOnly ? 1 : 0}`)
  }

  private bindTcpCallbacks(): void {
    bindTcpCallbacksOp(this)
  }

  private onTcpState(state: CarConnectionState, text: string): void {
    onTcpStateOp(this, state, text)
  }

  private onTcpData(data: Uint8Array): void {
    onTcpDataOp(this, data)
  }

  private clearPendingFrameDestApply(): void {
    clearPendingFrameDestApplyOp(this)
  }

  private scheduleFrameDestApply(destNodeId: string): void {
    scheduleFrameDestApplyOp(this, destNodeId)
  }

  private byteToHex(v: number): string {
    return byteToHexOp(v)
  }

  private bytesToHex(data: Uint8Array): string {
    return bytesToHexOp(data)
  }

  private markParkingUltrasonicRequest(nowMs: number): void {
    markParkingUltrasonicRequestOp(this, nowMs)
  }

  private clearParkingUltrasonicRequest(): void {
    clearParkingUltrasonicRequestOp(this)
  }

  private isParkingUltrasonicResponseContext(nowMs: number): boolean {
    return isParkingUltrasonicResponseContextOp(this, nowMs)
  }

   async connectTcp(ip: string, port: number): Promise<void> {
    await connectTcpOp(this, ip, port)
  }

  private async disconnectTcp(): Promise<void> {
    await disconnectTcpOp(this)
  }

   canRealSend(): boolean {
    return canRealSendOp(this)
  }

  private async sendManualGoCommand(actionText: string): Promise<void> {
    await sendManualGoCommandOp(this, actionText, this.emergencyCommandSeq)
  }

  async onAction(a: Page1Action): Promise<void> {
    await onActionOp(this, a)
  }

  async sendCustomControl0A(code: number): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const safeCode: number = Math.max(0, Math.min(0xFF, Math.trunc(code)))
    const hexCode: string = `0x${safeCode.toString(16).toUpperCase().padStart(2, '0')}`
    const motionKeyByCode: Record<number, string> = {
      0x01: 'GO',
      0x02: 'BACK',
      0x03: 'LEFT',
      0x04: 'RIGHT',
      0x05: 'LEFT_HALF',
      0x06: 'RIGHT_HALF',
      0x0E: 'UTURN'
    }
    const motionKey: string | undefined = motionKeyByCode[safeCode]
    if (motionKey && typeof this.acquireMotionDispatch === 'function') {
      await this.acquireMotionDispatch(`CUSTOM_0A:${motionKey}`)
    }
    try {
    if (motionKey && !this.canSendMotionCommand(motionKey, 'CUSTOM_0A')) {
      s.pushLog(`自定义控制拦截：${hexCode}，发送锁未释放`)
      return
    }
    // 门控已下线：不再拦截前进行为。
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    s.bumpTx()
    s.setAction(`自定义0x0A=${hexCode}`)
    s.pushLog(`自定义控制发送：${hexCode}`)
    // legacy removed
    if (safeCode === 0x01) this.previewManualActionOnMap(Page1Action.GO)
    else if (safeCode === 0x02) this.previewManualActionOnMap(Page1Action.BACK)
    else if (safeCode === 0x03) this.previewManualActionOnMap(Page1Action.LEFT)
    else if (safeCode === 0x04) this.previewManualActionOnMap(Page1Action.RIGHT)
    else if (safeCode === 0x05) this.previewManualActionOnMap(Page1Action.LEFT_HALF)
    else if (safeCode === 0x06) this.previewManualActionOnMap(Page1Action.RIGHT_HALF)
    else if (safeCode === 0x0E) this.previewManualActionOnMap(Page1Action.UTURN)
    } finally {
      if (motionKey && typeof this.leaveMotionDispatch === 'function') {
        this.leaveMotionDispatch(`CUSTOM_0A:${motionKey}`)
      }
    }
  }

  async sendCustomGroupCommand(group: number, subCode: number, ext?: Uint8Array): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const g: number = group & 0xFF
    const sub: number = subCode & 0xFF
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    const modeText: string = this.canRealSend() ? 'CCF5' : 'DRY_RUN'
    let seq: number = 0
    if (this.canRealSend()) {
      s.bumpTx()
      if (g === 0x0A) seq = await this.proto.Send0A(sub, ext, false, true)
      else if (g === 0x0B) seq = await this.proto.Send0B(sub, ext, false, true)
      else if (g === 0x0C) seq = await this.proto.Send0C(sub, ext, true, true)
      else {
        s.pushLog(`自定义发送失败：不支持组 0x${g.toString(16).toUpperCase().padStart(2, '0')}`)
        return
      }
      s.pushLog(`自定义发送(${modeText})：group=0x${g.toString(16).toUpperCase().padStart(2, '0')} sub=0x${sub.toString(16).toUpperCase().padStart(2, '0')} extLen=${ext ? ext.length : 0} seq=${seq}`)
    } else {
      s.pushLog(`自定义发送(${modeText})：group=0x${g.toString(16).toUpperCase().padStart(2, '0')} sub=0x${sub.toString(16).toUpperCase().padStart(2, '0')} extLen=${ext ? ext.length : 0}`)
    }
  }

  async sendCurrentNodeByMapClick(nodeId: string, dir: string | number = 'N'): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.sendCurrentNode(id, dir)
      s.pushLog(`当前位置上报(CCF5)：node=${id} dir=${String(dir)} seq=${seq}`)
    } else {
      s.pushLog(`当前位置上报(DRY_RUN)：node=${id} dir=${String(dir)}`)
    }
  }

  async sendObstacleEdgeByMapClick(fromNodeId: string, toNodeId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const a: string = (fromNodeId || '').trim().toUpperCase()
    const b: string = (toNodeId || '').trim().toUpperCase()
    if (a.length !== 2 || b.length !== 2) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setObstacleEdge(a, b, true)
      s.pushLog(`障碍上报(CCF5): edge=${a}|${b} seq=${seq}`)
    } else {
      s.pushLog(`障碍上报(DRY_RUN): edge=${a}|${b}`)
    }
  }

  async sendObstaclePointByMapClick(nodeId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.sendObstaclePoint(id)
      s.pushLog(`障碍上报(CCF5): node=${id} seq=${seq}`)
    } else {
      s.pushLog(`障碍上报(DRY_RUN): node=${id}`)
    }
  }

  async resetNetworkMap(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    s.clearMapSetupState()
    s.setAction('地图配置已清空')
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    try {
      if (this.canRealSend()) {
        s.bumpTx()
        const seq: number = await this.proto.resetNetworkMap()
        s.pushLog(`清图(CCF5): seq=${seq}`)
      } else {
        s.pushLog('清图(DRY_RUN)')
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e)
      s.pushLog(`清图发送失败: ${msg}`)
    }
  }

  async sendTrafficLightByMapEdge(edgeId: string, dir: string | number): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const seg = RouteEdgeCodec.parse((edgeId || '').trim().toUpperCase())
    if (!seg) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setTrafficLightNode(seg.a, seg.b, dir, true)
      s.pushLog(`红绿灯上报(CCF5): edge=${seg.a}|${seg.b} dir=${String(dir)} seq=${seq}`)
    } else {
      s.pushLog(`红绿灯上报(DRY_RUN): edge=${seg.a}|${seg.b} dir=${String(dir)}`)
    }
  }

  async clearTrafficLightsByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    s.clearTrafficLightPoints()
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.clearTrafficLightNode()
      s.pushLog(`清除红绿灯(CCF5): seq=${seq}`)
    } else {
      s.pushLog('清除红绿灯(DRY_RUN)')
    }
  }

  async sendBarrierByMapEdge(edgeId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const seg = RouteEdgeCodec.parse((edgeId || '').trim().toUpperCase())
    if (!seg) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setBarrierPosition(seg.a, seg.b, true)
      s.pushLog(`道闸上报(CCF5): edge=${seg.a}|${seg.b} seq=${seq}`)
    } else {
      s.pushLog(`道闸上报(DRY_RUN): edge=${seg.a}|${seg.b}`)
    }
  }

  async clearBarrierByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    s.clearGatePoints()
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.clearBarrier()
      s.pushLog(`清除道闸(CCF5): seq=${seq}`)
    } else {
      s.pushLog('清除道闸(DRY_RUN)')
    }
  }

  async sendSpecialSegmentByMapEdge(edgeId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const seg = RouteEdgeCodec.parse((edgeId || '').trim().toUpperCase())
    if (!seg) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setSpecialSegment(seg.a, seg.b, true)
      s.pushLog(`特殊路段上报(CCF5): edge=${seg.a}|${seg.b} seq=${seq}`)
    } else {
      s.pushLog(`特殊路段上报(DRY_RUN): edge=${seg.a}|${seg.b}`)
    }
  }

  async clearSpecialSegmentByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    s.clearSpecialRoadPoints()
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.clearSpecialSegment()
      s.pushLog(`清除特殊路段(CCF5): seq=${seq}`)
    } else {
      s.pushLog('清除特殊路段(DRY_RUN)')
    }
  }

  async setGarageByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const nodeId: string = (s.currentSnapNodeId || '').trim().toUpperCase()
    if (nodeId.length !== 2) {
      s.pushLog('设置车库失败：当前点位无效')
      return
    }
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setGaragePosition(nodeId)
      s.pushLog(`设置车库(CCF5): node=${nodeId} seq=${seq}`)
    } else {
      s.pushLog(`设置车库(DRY_RUN): node=${nodeId}`)
    }
  }

  async setGarageByMapNode(nodeId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setGaragePosition(id)
      s.pushLog(`设置车库(CCF5): node=${id} seq=${seq}`)
    } else {
      s.pushLog(`设置车库(DRY_RUN): node=${id}`)
    }
  }

  async clearGarageByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    s.clearGaragePoints()
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.clearGarageNode()
      s.pushLog(`清除车库(CCF5): seq=${seq}`)
    } else {
      s.pushLog('清除车库(DRY_RUN)')
    }
  }

  async setWarehouseByMapNode(nodeId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.setWarehouseNode(id)
      s.pushLog(`设置仓库(CCF5): node=${id} seq=${seq}`)
    } else {
      s.pushLog(`设置仓库(DRY_RUN): node=${id}`)
    }
  }

  async clearWarehouseByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    s.clearWarehousePoints()
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.clearWarehouseNode()
      s.pushLog(`清除仓库(CCF5): seq=${seq}`)
    } else {
      s.pushLog('清除仓库(DRY_RUN)')
    }
  }

  async stopTaskByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.stopTask()
      s.pushLog(`停止任务(CCF5): seq=${seq}`)
    } else {
      s.pushLog('停止任务(DRY_RUN)')
    }
  }

  async resumeTaskByUi(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (this.canRealSend()) {
      s.bumpTx()
      const seq: number = await this.proto.resumeTask()
      s.pushLog(`继续任务(CCF5): seq=${seq}`)
    } else {
      s.pushLog('继续任务(DRY_RUN)')
    }
  }

   async sendDriveActionDirect(a: Page1Action): Promise<boolean> {
    return await sendDriveActionDirectOp(this, a)
  }

  private buildAutoActionFingerprint(action: Page1Action): string {
    return buildAutoActionFingerprintOp(this, action)
  }

  private shouldSkipDuplicateAutoAction(action: Page1Action, actionText: string): boolean {
    return shouldSkipDuplicateAutoActionOp(this, action, actionText)
  }

   isTurnAction(a: Page1Action | undefined): boolean {
    return isTurnActionOp(a)
  }

  private isMoveAction(a: Page1Action | undefined): boolean {
    return isMoveActionOp(a)
  }

   resetRouteVoiceFlags(): void {
    resetRouteVoiceFlagsOp(this)
  }

  private resetAutoActionDedupState(): void {
    resetAutoActionDedupStateOp(this)
  }

  private isPathMotionAction(action: Page1Action): boolean {
    return isPathMotionActionOp(action)
  }

   pathDotMotionTimingMs(suggestedMs?: number): number {
    return pathDotMotionTimingMsOp(suggestedMs)
  }

  private pathDotMotionTiming(suggestedMs?: number): MotionTimingProfile {
    return pathDotMotionTimingOp(suggestedMs)
  }

  private queueDrivingUltrasonicObstacle(nowMs: number): void {
    queueDrivingUltrasonicObstacleOp(this, nowMs)
  }

   async maybePlayRouteStartVoice(): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (this.routeStartVoicePlayed) return

    this.routeStartVoicePlayed = true
    s.pushLog('VOICE: 出发前播报最优路径')
    if (!this.canRealSend()) return

    // await this.proto.voicefour()
    s.pushLog('VOICE: 已注释出发语音发送')
  }

   stopActiveMotion(): void {
    this.motionPlayer.reset()
  }

   motionRunning(): boolean {
    return this.motionPlayer.running()
  }

  private motionHooks(): VehicleMotionHooks {
    return motionHooksOp(this)
  }

   schedulerDeps(): VehicleActionSchedulerDeps {
    return schedulerDepsOp(this)
  }

   async maybeHandleMotionArrive(toId: string): Promise<void> {
    await maybeHandleMotionArriveOp(this, toId)
  }

  uploadTrajectoryNode(nodeId: string): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const id: string = nodeId.trim().toUpperCase()
    if (id.length <= 0) return
    const point: string = id
    const startPoint: string = this.trajectoryPlanStartPoint.length > 0 ? this.trajectoryPlanStartPoint : '-'
    const endPoint: string = this.trajectoryPlanEndPoint.length > 0 ? this.trajectoryPlanEndPoint : '-'
    const lineByResult = (ok: boolean): string =>
      `WEB_CONNECT: ${ok ? 'SUCCESS' : 'FAILED'} id=${id} point=${point} start=${startPoint} end=${endPoint}`
    const intervalMs: number = 0
    void saveCarTrajectoryByNode(id, intervalMs, {
      startPoint: this.trajectoryPlanStartPoint,
      endPoint: this.trajectoryPlanEndPoint
    })
      .then((ok: boolean): void => {
        s.pushLog(lineByResult(ok))
      })
      .catch((err: Object): void => {
        const message: string = (err as Error).message
        s.pushLog(`${lineByResult(false)} err=${message}`)
      })
  }

  setTrajectoryPlanEndpoints(startPoint: string, endPoint: string): void {
    this.trajectoryPlanStartPoint = startPoint.trim().toUpperCase()
    this.trajectoryPlanEndPoint = endPoint.trim().toUpperCase()
  }

  updatePoseAndTelemetryForDisplay(xNorm: number, yNorm: number, headingDeg: number, speed: number): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    const nowMs: number = Date.now()
    const prevX: number = s.pose.xNorm
    const prevY: number = s.pose.yNorm
    const dtSec: number = this.metricSimLastTickAtMs > 0 ? Math.max(0, (nowMs - this.metricSimLastTickAtMs) / 1000) : 0
    this.metricSimLastTickAtMs = nowMs

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

    // 与方向同链路实时刷新其余三个卡片指标
    const deltaNorm: number = this.normDistance(prevX, prevY, xNorm, yNorm)
    let speedCms: number = Math.max(0, Math.abs(speed))
    if (speedCms <= 0.01 && deltaNorm > 0) {
      // 某些阶段 speed 传 0，但位置仍在平滑移动，用位移估算速度
      const distByNormCm: number = deltaNorm * 250
      speedCms = dtSec > 0 ? distByNormCm / dtSec : distByNormCm
    }

    s.setMetricSpeedCms(speedCms)

    let distanceIncCm: number = 0
    if (dtSec > 0 && speedCms > 0.01) {
      distanceIncCm = speedCms * dtSec
    } else if (deltaNorm > 0) {
      distanceIncCm = deltaNorm * 250
    }
    if (distanceIncCm > 0) {
      this.metricDistanceTotalCm += distanceIncCm
      s.setMetricDistanceCm(this.metricDistanceTotalCm)
    }

    if (this.simLightBaseLux <= 0) {
      this.simLightBaseLux = 200 + Math.floor(Math.random() * 101)
    }
    const lightJitter: number = Math.floor(Math.random() * 21) - 10
    s.setMetricLightLux(this.simLightBaseLux + lightJitter)

    this.animateMetricHeadingTo(headingDeg)

    const nowLogMs: number = Date.now()
    if (nowLogMs - this.metricLogLastAtMs >= 250) {
      this.metricLogLastAtMs = nowLogMs
      hilog.info(
        METRIC_LOG_DOMAIN,
        METRIC_LOG_TAG,
        '[core] speedIn=%{public}s speedMetric=%{public}s heading=%{public}s dist=%{public}s light=%{public}s realSend=%{public}s pose=(%{public}s,%{public}s)',
        speed.toFixed(2),
        s.metricSpeedCms.toFixed(2),
        String(Math.round(s.metricHeadingDeg)),
        String(s.metricDistanceCm),
        String(s.metricLightLux),
        String(s.realSendEnabled),
        xNorm.toFixed(3),
        yNorm.toFixed(3)
      )
    }
  }

   updateHeadingOnlyAtCurrentPose(headingDeg: number): void {
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

  private normDistance(ax: number, ay: number, bx: number, by: number): number {
    const dx: number = bx - ax
    const dy: number = by - ay
    return Math.sqrt(dx * dx + dy * dy)
  }

  private cancelMapPoseAnimation(): void {
    this.mapPoseAnimToken += 1
  }

   beginMapPoseAnimation(): number {
    this.mapPoseAnimToken += 1
    return this.mapPoseAnimToken
  }

   isMapPoseAnimationActive(token: number): boolean {
    return token === this.mapPoseAnimToken
  }

  private turnDeltaDeg(action: Page1Action): number {
    return turnDeltaDegValue(action)
  }

  private syncCurrentSnapNodeByPose(xNorm: number, yNorm: number): void {
    syncCurrentSnapNodeByPose(this, xNorm, yNorm)
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
      this,
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

   previewManualActionOnMap(action: Page1Action): void {
    previewManualActionOnMap(this, action)
  }

  private playMapReverseParkingAnimation(arrivedId: string, goalId: string, headingDeg: number): void {
    playMapReverseParkingAnimation(this, arrivedId, goalId, headingDeg)
  }

   cancelParkingSequence(): void {
    this.parkingSequenceToken += 1
    this.parkingInProgress = false
    this.parkingUltrasonicDecisionBusy = false
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
    maybeLogVisionTaskOrTraffic(this, nowMs)
  }


  private yoloSuggestBlockedNodeId(nowMs: number): string {
    return yoloSuggestBlockedNodeId(this, nowMs)
  }

  private maybeTriggerRoutePointObstacle(): boolean {
    return maybeTriggerRoutePointObstacle(this)
  }

   frontRouteEdgeIdForDriving(): string {
    return frontRouteEdgeIdForDriving(this)
  }

  private markRouteObstaclePointOnEdge(edgeId: string, nowMs: number): void {
    markRouteObstaclePointOnEdge(this, edgeId, nowMs)
  }

  private promoteBlockedEdgePairsToBlockedNodes(): Array<string> {
    return promoteBlockedEdgePairsToBlockedNodes(this)
  }

   maybeHandleDrivingUltrasonicObstacle(nowMs: number, edgeOverride: string = ''): void {
    maybeHandleDrivingUltrasonicObstacle(this, nowMs, edgeOverride)
  }

   maybeReplanOnObstacle(): void {
    maybeReplanOnObstacle(this)
  }

  private isNextNodeBlocked(): boolean {
    return isNextNodeBlocked(this)
  }

   nearestNodeIdByPose(): string {
    return nearestNodeIdByPose(this)
  }

  private findNearestRouteSegmentByPose(): SegmentPoseMatch | undefined {
    return findNearestRouteSegmentByPose(this)
  }

   headingDegFromTo(ax: number, ay: number, bx: number, by: number): number {
    const rad: number = Math.atan2(by - ay, bx - ax)
    const deg: number = rad * 180.0 / Math.PI
    return this.norm360(deg)
  }

   segMidMinTValue(s: Page1UiStore): number {
    const raw: number = s.segMidMinT
    if (!Number.isFinite(raw)) return 0.12
    if (raw < 0.0) return 0.0
    if (raw > 0.49) return 0.49
    return raw
  }

   segMidMaxTValue(s: Page1UiStore): number {
    const minT: number = this.segMidMinTValue(s)
    const raw: number = s.segMidMaxT
    let v: number = Number.isFinite(raw) ? raw : 0.88
    if (v < minT + 0.02) v = minT + 0.02
    if (v > 1.0) v = 1.0
    return v
  }

   segHeadingPenaltyWeightValue(s: Page1UiStore): number {
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
    return chooseSegmentEndpointForGoal(this, seg, goal, blocked, blockedEdges)
  }

  private tryBuildSegmentAwarePath(goal: string, blocked: Array<string>, blockedEdges: Array<string>): Array<string> | undefined {
    return tryBuildSegmentAwarePath(this, goal, blocked, blockedEdges)
  }

   clearAheadVisionReplanState(): void {
    this.aheadVisionPending = false
    this.aheadVisionReadyAtMs = 0
    this.aheadVisionEdgeId = ''
  }

   resetGarageFlowState(): void {
    this.parkingUltrasonicDecisionBusy = false
  }

  private onPathAckReceived01(): void {
    if (this.emergencyAlarmBurstActive) {
      this.emergencyAlarmBurstAckAtMs = Date.now()
    }
  }


  private findPendingRouteObstacleOnEdge(edgeId: string, nowMs: number): RouteObstaclePoint | undefined {
    return findPendingRouteObstacleOnEdge(this, edgeId, nowMs)
  }

   maybeStartAheadVisionReplan(fromId: string, toId: string, nowMs: number): boolean {
    return maybeStartAheadVisionReplan(this, fromId, toId, nowMs)
  }

   maybeHandleAheadVisionReplan(nowMs: number): boolean {
    return maybeHandleAheadVisionReplan(this, nowMs)
  }

   resolveStartNodeId(): string {
    return resolveStartNodeId(this)
  }

   isReverseParkingGoal(id: string): boolean {
    const p = GridIdCodec.parse(id)
    if (!p) return false
    return p.row === 0
  }

  planPath(dest: string): void {
    planPathOp(this, dest)
  }

   syncLogicalHeadingWithCurrentState(): void {
    syncLogicalHeadingWithCurrentState(this)
  }

   segmentHeadingDeg(fromId: string, toId: string): number {
    return segmentHeadingDeg(this, fromId, toId)
  }

   normToCardinal(v: number): number {
    return normToCardinal(this, v)
  }

  private clearEmergencyAlarmTimer(): void {
    if (this.emergencyAlarmTimerId >= 0) {
      clearTimeout(this.emergencyAlarmTimerId)
      this.emergencyAlarmTimerId = -1
    }
  }

  private clearEmergencyAutoRecoverTimer(): void {
    if (this.emergencyAutoRecoverTimerId >= 0) {
      clearTimeout(this.emergencyAutoRecoverTimerId)
      this.emergencyAutoRecoverTimerId = -1
    }
  }

  private armEmergencyAutoRecover(reason: string, holdMs: number): void {
    this.clearEmergencyAutoRecoverTimer()
    const safeHoldMs: number = Math.max(0, Math.round(holdMs))
    this.emergencyAutoRecoverTimerId = setTimeout((): void => {
      this.emergencyAutoRecoverTimerId = -1
      void this.recoverFromEmergency(1000)
      const s: Page1UiStore | undefined = this.store
      if (s) {
        s.pushLog(`EMERGENCY AUTO_RECOVER: reason=${reason}, delay=${safeHoldMs}ms`)
      }
    }, safeHoldMs) as number
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
    const s: Page1UiStore | undefined = this.store
    if (this.emergencyMotionCommandLocked) {
      if (s && nowMs - this.motionCommandBlockLastLogAtMs >= 500) {
        this.motionCommandBlockLastLogAtMs = nowMs
        s.pushLog(`MOTION_LOCKED: ${sourceTag}:${commandKey} blocked after emergency stop`)
      }
      return false
    }

    // ACK 超时重发属于可靠性兜底链路，不受 single-flight 发送锁限制。
    if (sourceTag === 'PATH_ACK_RETRY') {
      return true
    }

    if (!this.isMotionCommandBlocked(nowMs)) {
      // 全局 single-flight：任何入口放行后短时间内拒绝并发第二次发送。
      this.setMotionCommandBlock(`SEND_LOCK:${sourceTag}:${commandKey}`, MOTION_SEND_SINGLE_FLIGHT_HOLD_MS)
      return true
    }

    if (s && nowMs - this.motionCommandBlockLastLogAtMs >= 500) {
      this.motionCommandBlockLastLogAtMs = nowMs
      const remainMs: number = Math.max(0, this.motionCommandBlockUntilMs - nowMs)
      s.pushLog(
        `MOTION_BLOCKED: ${sourceTag}:${commandKey} skipped, remain=${remainMs}ms reason=${this.motionCommandBlockReason}`
      )
    }
    return false
  }

  async acquireMotionDispatch(owner: string): Promise<void> {
    const safeOwner: string = owner.trim().length > 0 ? owner.trim() : 'UNKNOWN'
    if (!this.motionDispatchBusy) {
      this.motionDispatchBusy = true
      this.motionDispatchOwner = safeOwner
      return
    }
    const s: Page1UiStore | undefined = this.store
    if (s) s.pushLog(`MOTION_DISPATCH_QUEUE: enqueue owner=${safeOwner}, active=${this.motionDispatchOwner}`)
    await new Promise<void>((resolve) => {
      this.motionDispatchQueue.push({ owner: safeOwner, resolve: resolve })
    })
  }

  leaveMotionDispatch(owner: string): void {
    void owner
    if (this.motionDispatchQueue.length > 0) {
      const next = this.motionDispatchQueue.shift()
      if (next) {
        this.motionDispatchBusy = true
        this.motionDispatchOwner = next.owner
        next.resolve()
        return
      }
    }
    this.motionDispatchBusy = false
    this.motionDispatchOwner = ''
  }

  private async sendEmergencyAlarmBurst(reason: string, repeatCount: number = 3, intervalMs: number = 10): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const safeCount: number = Math.max(1, Math.round(repeatCount))
    const safeIntervalMs: number = Math.max(10, Math.round(intervalMs))
    this.emergencyAlarmBurstActive = true
    this.emergencyAlarmBurstAckAtMs = 0
    this.emergencyAlarmBurstLastSendAtMs = 0
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    try {
      for (let i: number = 0; i < safeCount; i++) {
        this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
        s.alarmEnabled = true
        s.bumpTx()
        this.emergencyAlarmBurstLastSendAtMs = Date.now()
        try {
          // legacy removed
        } catch (_) {}
        s.pushLog(`EMERGENCY_ALARM: ON#${i + 1}/${safeCount} reason=${reason}`)
        if (this.emergencyAlarmBurstAckAtMs >= this.emergencyAlarmBurstLastSendAtMs) {
          s.pushLog('EMERGENCY_ALARM: 收到新协议ACK，停止后续报警重发')
          break
        }
        if (i + 1 < safeCount && safeIntervalMs > 0) {
          await this.sleep(safeIntervalMs)
          if (this.emergencyAlarmBurstAckAtMs >= this.emergencyAlarmBurstLastSendAtMs) {
            s.pushLog('EMERGENCY_ALARM: 收到新协议ACK，停止后续报警重发')
            return
          }
        }
      }
    } finally {
      this.emergencyAlarmBurstActive = false
    }
  }

  private hasShigongYolov26BarrierFromLatestRecog(): boolean {
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.subtype !== RecognitionSubtype.YOLOV26BARRIER || r.boxes.length <= 0) return false
    for (let i: number = 0; i < r.boxes.length; i++) {
      const box: BBoxNorm = r.boxes[i]
      // Emergency stop only trusts high-confidence obstacle detections.
      if (box.score < 0.65) continue
      const key: string = normalizeYolov26BarrierLabelKey(box.label)
      if (isShigongYolov26BarrierLabelKey(key)) return true
    }
    return false
  }

  private applyPendingEmergencyReplan(): void {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    if (!this.emergencyPendingReplan) return
    if (s.destApplied.length <= 0) {
      this.emergencyPendingReplan = false
      this.emergencyPendingBlockedEdgeId = ''
      return
    }
    const blockedEdgeId: string = this.emergencyPendingBlockedEdgeId
    if (blockedEdgeId.length > 0) {
      s.addBlockedEdgeIfAbsent(blockedEdgeId, 'EMERGENCY_YOLOV26BARRIER')
      const mergedNodes: Array<string> = this.promoteBlockedEdgePairsToBlockedNodes()
      if (mergedNodes.length > 0) {
        s.pushLog(`EMERGENCY_REPLAN: edge->node ${mergedNodes.join(',')}`)
      }
    }
    const nearId: string = this.nearestNodeIdByPose()
    if (GridIdCodec.isValidId(nearId)) {
      s.currentSnapNodeId = nearId
      s.pushLog(`EMERGENCY_REPLAN: snap=${nearId}`)
    }
    this.emergencyPendingReplan = false
    this.emergencyPendingBlockedEdgeId = ''
    this.planPath(s.destApplied)
  }

  maybeHandleYolov26BarrierEmergencyStop(nowMs: number): boolean {
    if (nowMs < this.emergencyRecoverBypassUntilMs) return false
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.subtype !== RecognitionSubtype.YOLOV26BARRIER) return false
    if (!this.hasShigongYolov26BarrierFromLatestRecog()) return false
    if (this.yolov26barrierEmergencyBusy) return true
    if (r.taskId.length > 0 && r.taskId === this.lastYolov26BarrierEmergencyTaskId) return false
    if (r.tsMs > 0 && r.tsMs <= this.lastYolov26BarrierEmergencyTsMs) return false

    this.yolov26barrierEmergencyBusy = true
    this.lastYolov26BarrierEmergencyTaskId = r.taskId
    this.lastYolov26BarrierEmergencyTsMs = Math.max(this.lastYolov26BarrierEmergencyTsMs, r.tsMs)
    this.emergencyPendingBlockedEdgeId = this.frontRouteEdgeIdForDriving()
    this.emergencyPendingReplan = true

    void this.emergencyStopAndHold('YOLOV26BARRIER', 1000).finally((): void => {
      this.yolov26barrierEmergencyBusy = false
    })
    return true
  }

  async emergencyStopAndHold(reason: string = 'MANUAL_SCRAM', holdMs: number = 1000): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return
    const safeHoldMs: number = Math.max(0, Math.round(holdMs))

    this.cancelMapPoseAnimation()
    this.cancelParkingSequence()
    this.resetGarageFlowState()
    this.resetAutoActionDedupState()
    this.stopActiveMotion()
    this.actionScheduler.reset()
    this.setMotionCommandBlock(reason, safeHoldMs)
    this.emergencyMotionCommandLocked = true
    this.emergencyCommandSeq += 1

    s.lastAutoFollowAtMs = Date.now()

    await this.sendDriveActionDirect(Page1Action.STOP)
    await this.sendEmergencyAlarmBurst(reason, 3, 10)
    const keepPosOnly: boolean = reason === 'YOLOV26BARRIER'
    this.resetToFreshRuntimeState(reason, keepPosOnly)

    s.pushLog(`EMERGENCY STOP: reason=${reason}, hold=${safeHoldMs}ms`)
  }

  async recoverFromEmergency(graceMs: number = 1000): Promise<void> {
    const s: Page1UiStore | undefined = this.store
    if (!s) return

    this.clearEmergencyAlarmTimer()
    this.clearEmergencyAutoRecoverTimer()
    this.clearMotionCommandBlock()
    this.yolov26barrierEmergencyBusy = false
    this.emergencyRecoverBypassUntilMs = Date.now() + Math.max(1000, Math.round(graceMs))
    this.emergencyMotionCommandLocked = false

    s.alarmEnabled = false
    s.autoFollowEnabled = true
    if (s.pathNodes.length > 1 && s.pathIndex < s.pathNodes.length - 1) {
      // Allow route-follow loop to send next segment immediately after emergency recovery.
      s.lastAutoFollowAtMs = 0
    }
    this.applyPendingEmergencyReplan()
    this.proto.setMode(this.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)

    s.setAction('紧急状态已恢复')
    s.pushLog(`EMERGENCY RECOVER: bypass=${Math.max(1000, Math.round(graceMs))}ms`)
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

  private edgeSideOfNode(id: string): EdgeSide {
    const s: Page1UiStore | undefined = this.store
    if (!s) return EdgeSide.NONE
    return Page1CoordinatorGridUtils.edgeSideOfNode(s.gridNodes, id)
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


  private async updateMotionTimeline(nowMs: number): Promise<void> {
    await this.motionPlayer.update(nowMs, this.motionHooks())
    this.lastMotionSnapshot = this.motionPlayer.snapshot(nowMs)
    this.lastSchedulerSnapshot = this.actionScheduler.snapshot(nowMs, this.motionRunning())
  }

   norm360(v: number): number {
    return Page1CoordinatorGridUtils.norm360(v)
  }

   headingErrorDeg(curDeg: number, desiredDeg: number): number {
    return Page1CoordinatorGridUtils.headingErrorDeg(curDeg, desiredDeg)
  }

   findNode(id: string): NormPoint | undefined {
    const s: Page1UiStore | undefined = this.store
    if (!s) return undefined
    return Page1CoordinatorGridUtils.findNode(s.gridNodes, id)
  }

  private simAmbientFrontCm(): number {
    return 0
  }

  private simAmbientBackCm(): number {
    return 0
  }

  private simAmbientIrCm(): number {
    return 0
  }

  private simAmbientLux(): number {
    return 0
  }

   async sleep(ms: number): Promise<void> {
    const waitMs: number = Math.max(0, Math.trunc(ms))
    await new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => resolve(), waitMs)
    })
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
    if (!s.autoFollowEnabled) {
      s.autoFollowEnabled = true
      s.pushLog('AUTO_FOLLOW: 目标点发送时自动开启')
    }

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

    // legacy removed
    s.pushLog(`VOICE: 自动播报发送(${content.length}字)`)
    return true
  }
}

export const page1Coordinator: Page1Coordinator = new Page1Coordinator()









