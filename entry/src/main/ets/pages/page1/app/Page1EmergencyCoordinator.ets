import { Page1UiStore } from './Page1UiStore'
import { Page1Action } from '../types/Page1Types'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { RecognitionResult, BBoxNorm } from '../../../services/recognition/RecognitionResult'
import { RecognitionSubtype } from '../../../services/recognition/RecognitionTask'
import { recogStore } from '../../../state/RecogStore'
import { GridIdCodec } from './PathPlannerAStar'
import {
  isShigongYolov26BarrierLabelKey,
  normalizeYolov26BarrierLabelKey
} from './TrafficYolov26BarrierLabelPolicy'

export class Page1EmergencyCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  clearEmergencyAlarmTimer(): void {
    if (this.ctx.emergencyAlarmTimerId >= 0) {
      clearTimeout(this.ctx.emergencyAlarmTimerId)
      this.ctx.emergencyAlarmTimerId = -1
    }
  }

  clearEmergencyAutoRecoverTimer(): void {
    if (this.ctx.emergencyAutoRecoverTimerId >= 0) {
      clearTimeout(this.ctx.emergencyAutoRecoverTimerId)
      this.ctx.emergencyAutoRecoverTimerId = -1
    }
  }

  armEmergencyAutoRecover(reason: string, holdMs: number): void {
    this.clearEmergencyAutoRecoverTimer()
    const safeHoldMs: number = Math.max(0, Math.round(holdMs))
    this.ctx.emergencyAutoRecoverTimerId = setTimeout((): void => {
      this.ctx.emergencyAutoRecoverTimerId = -1
      void this.recoverFromEmergency(1000)
      const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
      if (s) s.pushLog(`EMERGENCY AUTO_RECOVER: reason=${reason}, delay=${safeHoldMs}ms`)
    }, safeHoldMs) as number
  }

  setMotionCommandBlock(reason: string, holdMs: number): void {
    const nowMs: number = Date.now()
    const safeHoldMs: number = Math.max(0, Math.round(holdMs))
    const untilMs: number = nowMs + safeHoldMs
    if (untilMs > this.ctx.motionCommandBlockUntilMs) {
      this.ctx.motionCommandBlockUntilMs = untilMs
    }
    this.ctx.motionCommandBlockReason = reason
  }

  clearMotionCommandBlock(): void {
    this.ctx.motionCommandBlockUntilMs = 0
    this.ctx.motionCommandBlockReason = ''
    this.ctx.motionCommandBlockLastLogAtMs = 0
  }

  isMotionCommandBlocked(nowMs: number): boolean {
    return nowMs < this.ctx.motionCommandBlockUntilMs
  }

  canSendMotionCommand(commandKey: string, sourceTag: string): boolean {
    const nowMs: number = Date.now()
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (this.ctx.emergencyMotionCommandLocked) {
      if (s && nowMs - this.ctx.motionCommandBlockLastLogAtMs >= 500) {
        this.ctx.motionCommandBlockLastLogAtMs = nowMs
        s.pushLog(`MOTION_LOCKED: ${sourceTag}:${commandKey} blocked after emergency stop`)
      }
      return false
    }
    if (!this.isMotionCommandBlocked(nowMs)) return true
    if (s && nowMs - this.ctx.motionCommandBlockLastLogAtMs >= 500) {
      this.ctx.motionCommandBlockLastLogAtMs = nowMs
      const remainMs: number = Math.max(0, this.ctx.motionCommandBlockUntilMs - nowMs)
      s.pushLog(`MOTION_BLOCKED: ${sourceTag}:${commandKey} skipped, remain=${remainMs}ms reason=${this.ctx.motionCommandBlockReason}`)
    }
    return false
  }

  async sendEmergencyAlarmBurst(reason: string, repeatCount: number = 3, intervalMs: number = 10): Promise<void> {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    const safeCount: number = Math.max(1, Math.round(repeatCount))
    const safeIntervalMs: number = Math.max(0, Math.round(intervalMs))
    this.ctx.emergencyAlarmBurstActive = true
    this.ctx.emergencyAlarmBurstAckAtMs = 0
    this.ctx.emergencyAlarmBurstLastSendAtMs = 0
    this.ctx.proto.setMode(this.ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    try {
      for (let i: number = 0; i < safeCount; i++) {
        this.ctx.proto.setMode(this.ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
        s.alarmEnabled = true
        s.bumpTx()
        this.ctx.emergencyAlarmBurstLastSendAtMs = Date.now()
        try {
          await this.ctx.proto.setAlarm(true)
        } catch (_) {}
        s.pushLog(`EMERGENCY_ALARM: ON#${i + 1}/${safeCount} reason=${reason}`)
        if (this.ctx.emergencyAlarmBurstAckAtMs >= this.ctx.emergencyAlarmBurstLastSendAtMs) {
          s.pushLog('EMERGENCY_ALARM: received 0xBD/01, stop retries')
          break
        }
        if (i + 1 < safeCount && safeIntervalMs > 0) {
          const deadlineMs: number = Date.now() + safeIntervalMs
          while (Date.now() < deadlineMs) {
            if (this.ctx.emergencyAlarmBurstAckAtMs >= this.ctx.emergencyAlarmBurstLastSendAtMs) {
              s.pushLog('EMERGENCY_ALARM: received 0xBD/01, stop retries')
              return
            }
            await this.ctx.sleep(2)
          }
        }
      }
    } finally {
      this.ctx.emergencyAlarmBurstActive = false
    }
  }

  hasShigongYolov26BarrierFromLatestRecog(): boolean {
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.subtype !== RecognitionSubtype.YOLOV26BARRIER || r.boxes.length <= 0) return false
    for (let i: number = 0; i < r.boxes.length; i++) {
      const box: BBoxNorm = r.boxes[i]
      if (box.score < 0.18) continue
      const key: string = normalizeYolov26BarrierLabelKey(box.label)
      if (isShigongYolov26BarrierLabelKey(key)) return true
    }
    return false
  }

  applyPendingEmergencyReplan(): void {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    if (!this.ctx.emergencyPendingReplan) return
    if (s.destApplied.length <= 0) {
      this.ctx.emergencyPendingReplan = false
      this.ctx.emergencyPendingBlockedEdgeId = ''
      return
    }
    const blockedEdgeId: string = this.ctx.emergencyPendingBlockedEdgeId
    if (blockedEdgeId.length > 0) {
      s.addBlockedEdgeIfAbsent(blockedEdgeId, 'EMERGENCY_YOLOV26BARRIER')
      const mergedNodes: Array<string> = this.ctx.promoteBlockedEdgePairsToBlockedNodes()
      if (mergedNodes.length > 0) s.pushLog(`EMERGENCY_REPLAN: edge->node ${mergedNodes.join(',')}`)
    }
    const nearId: string = this.ctx.nearestNodeIdByPose()
    if (GridIdCodec.isValidId(nearId)) {
      s.currentSnapNodeId = nearId
      s.pushLog(`EMERGENCY_REPLAN: snap=${nearId}`)
    }
    this.ctx.emergencyPendingReplan = false
    this.ctx.emergencyPendingBlockedEdgeId = ''
    this.ctx.planPath(s.destApplied)
  }

  maybeHandleYolov26BarrierEmergencyStop(nowMs: number): boolean {
    if (nowMs < this.ctx.emergencyRecoverBypassUntilMs) return false
    const r: RecognitionResult | undefined = recogStore.lastRecog
    if (!r || !r.ok || r.subtype !== RecognitionSubtype.YOLOV26BARRIER) return false
    if (!this.hasShigongYolov26BarrierFromLatestRecog()) return false
    if (this.ctx.yolov26barrierEmergencyBusy) return true
    if (r.taskId.length > 0 && r.taskId === this.ctx.lastYolov26BarrierEmergencyTaskId) return false
    if (r.tsMs > 0 && r.tsMs <= this.ctx.lastYolov26BarrierEmergencyTsMs) return false

    this.ctx.yolov26barrierEmergencyBusy = true
    this.ctx.lastYolov26BarrierEmergencyTaskId = r.taskId
    this.ctx.lastYolov26BarrierEmergencyTsMs = Math.max(this.ctx.lastYolov26BarrierEmergencyTsMs, r.tsMs)
    this.ctx.emergencyPendingBlockedEdgeId = this.ctx.frontRouteEdgeIdForDriving()
    this.ctx.emergencyPendingReplan = true

    void this.emergencyStopAndHold('YOLOV26BARRIER', 1000).finally((): void => {
      this.ctx.yolov26barrierEmergencyBusy = false
    })
    return true
  }

  async emergencyStopAndHold(reason: string, holdMs: number): Promise<void> {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    const safeHoldMs: number = Math.max(0, Math.round(holdMs))

    this.ctx.cancelMapPoseAnimation()
    this.ctx.cancelParkingSequence()
    this.ctx.resetGarageFlowState()
    this.ctx.gateDepartInProgress = false
    this.ctx.resetGateDepartDedupState()
    this.ctx.resetAutoActionDedupState()
    this.ctx.resetPathAckState()
    this.ctx.stopActiveMotion()
    this.ctx.actionScheduler.reset()
    this.setMotionCommandBlock(reason, safeHoldMs)
    this.ctx.emergencyMotionCommandLocked = true
    this.ctx.emergencyCommandSeq += 1

    s.lastAutoFollowAtMs = Date.now()
    await this.ctx.driveAckCoordinator.sendDriveActionDirect(Page1Action.STOP)
    await this.sendEmergencyAlarmBurst(reason, 3, 10)
    const keepPosOnly: boolean = reason === 'YOLOV26BARRIER'
    this.ctx.resetToFreshRuntimeState(reason, keepPosOnly)
    s.pushLog(`EMERGENCY STOP: reason=${reason}, hold=${safeHoldMs}ms`)
  }

  async recoverFromEmergency(graceMs: number): Promise<void> {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    const bypassMs: number = Math.max(1000, Math.round(graceMs))

    this.clearEmergencyAlarmTimer()
    this.clearEmergencyAutoRecoverTimer()
    this.clearMotionCommandBlock()
    this.ctx.yolov26barrierEmergencyBusy = false
    this.ctx.emergencyRecoverBypassUntilMs = Date.now() + bypassMs
    this.ctx.emergencyMotionCommandLocked = false

    s.alarmEnabled = false
    s.autoFollowEnabled = true
    if (s.pathNodes.length > 1 && s.pathIndex < s.pathNodes.length - 1) {
      s.lastAutoFollowAtMs = 0
    }
    this.applyPendingEmergencyReplan()
    this.ctx.proto.setMode(this.ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)

    s.setAction('紧急状态已恢复')
    s.pushLog(`EMERGENCY RECOVER: bypass=${bypassMs}ms`)
  }
}
