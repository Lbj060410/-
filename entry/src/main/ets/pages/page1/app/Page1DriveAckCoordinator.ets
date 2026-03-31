import { Page1Action } from '../types/Page1Types'
import { CarFrame55 } from '../net/CarRx55StreamDecoder'
import { MotionTimingProfile } from './ActionTimingRegistry'
import { P1C, PendingAckMotion } from './Page1CoordinatorDefs'
import { RouteEdgeCodec } from './PathPlannerAStar'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { maybeBlockGoByTrafficGate } from './Page1CoordinatorTrafficGateOps'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'

const PATH_ACK_RETRY_WAIT_MS: number = 2000
const PATH_ACK_RETRY_MAX_SENDS: number = 3

export class Page1DriveAckCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  private kickTcpConnectForRealSendIfNeeded(s: any): void {
    if (!s || !s.realSendEnabled) return
    const connState: number = Number(s.connState)
    if (connState === 1 || connState === 2 || connState === 3) return
    const nowMs: number = Date.now()
    const lastKickAtMs: number = Number(this.ctx.realSendConnectKickAtMs) || 0
    if (nowMs - lastKickAtMs < 2000) return
    this.ctx.realSendConnectKickAtMs = nowMs
    if (typeof s.pushLog === 'function') {
      s.pushLog(`REAL_SEND: 链路未连接，自动重连 ${s.connIp}:${s.connPort}`)
    }
    if (typeof this.ctx.connectTcp === 'function') {
      void this.ctx.connectTcp(s.connIp, s.connPort)
    }
  }

  private isStaleByEmergencySeq(seq: number): boolean {
    return (Number(this.ctx.emergencyCommandSeq) || 0) !== seq
  }

  private clearPathAckRetryTimer(): void {
    if (this.ctx.pathAckRetryTimerId >= 0) {
      clearTimeout(this.ctx.pathAckRetryTimerId)
      this.ctx.pathAckRetryTimerId = -1
    }
  }

  private resolvePathAckCommandKey(actionText: string): string {
    if (actionText === '前进') return 'GO'
    if (actionText === '后退') return 'BACK'
    if (actionText === '左转') return 'LEFT'
    if (actionText === '右转') return 'RIGHT'
    if (actionText === '左半转') return 'LEFT_HALF'
    if (actionText === '右半转') return 'RIGHT_HALF'
    if (actionText === '掉头') return 'UTURN'
    if (actionText === '闸口放行') return 'GATE_DEPART'
    return ''
  }

  private async sendPathAckCommandByKey(key: string, commandSeq: number): Promise<boolean> {
    const s = this.ctx.store
    if (!s) return false
    if (!this.ctx.canRealSend()) return false
    if (this.isStaleByEmergencySeq(commandSeq)) return false
    const isMotionKey: boolean =
      key === 'GO' || key === 'BACK' || key === 'LEFT' || key === 'RIGHT' ||
      key === 'LEFT_HALF' || key === 'RIGHT_HALF' || key === 'UTURN' || key === 'GATE_DEPART'
    if (isMotionKey && typeof this.ctx.canSendMotionCommand === 'function' && !this.ctx.canSendMotionCommand(key, 'PATH_ACK_RETRY')) {
      return false
    }
    this.ctx.proto.setMode(CarSendMode.REAL_SEND)
    s.bumpTx()
    if (key === 'GO') { await this.ctx.proto.go(); return true }
    if (key === 'BACK') { await this.ctx.proto.back(); return true }
    if (key === 'LEFT') { await this.ctx.proto.left(); return true }
    if (key === 'RIGHT') { await this.ctx.proto.right(); return true }
    if (key === 'LEFT_HALF') { await this.ctx.proto.leftHalf(); return true }
    if (key === 'RIGHT_HALF') { await this.ctx.proto.rightHalf(); return true }
    if (key === 'UTURN') { await this.ctx.proto.uturn(); return true }
    if (key === 'GATE_DEPART') { await this.ctx.proto.depart(); return true }
    return false
  }

  private armPathAckRetryTimer(): void {
    this.clearPathAckRetryTimer()
    if (!this.ctx.canRealSend()) return
    if (!this.ctx.pathAckAwaitingComplete) return
    const commandSeq: number = Number(this.ctx.pathAckCommandSeq) || 0
    if (this.isStaleByEmergencySeq(commandSeq)) return
    if (this.ctx.pathAckLastStatusCode === 0x01 || this.ctx.pathAckLastStatusCode === 0x02) return
    if (this.ctx.pathAckRetrySentCount >= PATH_ACK_RETRY_MAX_SENDS) return
    if (!this.ctx.pathAckCommandKey || this.ctx.pathAckCommandKey.length <= 0) return
    this.ctx.pathAckRetryTimerId = setTimeout((): void => {
      this.ctx.pathAckRetryTimerId = -1
      const latestSeq: number = Number(this.ctx.pathAckCommandSeq) || 0
      if (this.isStaleByEmergencySeq(latestSeq)) return
      void this.retryPathAckCommandIfNeeded()
    }, PATH_ACK_RETRY_WAIT_MS) as number
  }

  private async retryPathAckCommandIfNeeded(): Promise<void> {
    const s = this.ctx.store
    if (!s) return
    if (!this.ctx.canRealSend()) return
    if (!this.ctx.pathAckAwaitingComplete) return
    const commandSeq: number = Number(this.ctx.pathAckCommandSeq) || 0
    if (this.isStaleByEmergencySeq(commandSeq)) return
    if (this.ctx.pathAckLastStatusCode === 0x01 || this.ctx.pathAckLastStatusCode === 0x02) return
    if (this.ctx.pathAckRetrySentCount >= PATH_ACK_RETRY_MAX_SENDS) return
    const key: string = this.ctx.pathAckCommandKey || ''
    if (key.length <= 0) return
    const nextSendCount: number = this.ctx.pathAckRetrySentCount + 1
    const sentOk: boolean = await this.sendPathAckCommandByKey(key, commandSeq)
    if (!sentOk) {
      s.pushLog(`PATH_ACK_RETRY: 重发失败 key=${key}`)
      return
    }
    this.ctx.pathAckRetrySentCount = nextSendCount
    this.ctx.pathAckLastSendAtMs = Date.now()
    this.ctx.pathAckLastStatusCode = 0
    s.pushLog(`PATH_ACK_RETRY: 2000ms未收到0x01，重发第${nextSendCount}次/${PATH_ACK_RETRY_MAX_SENDS} cmd=${this.ctx.pathAckLastCommandText}`)
    this.armPathAckRetryTimer()
  }

  async sendDriveActionDirect(a: Page1Action): Promise<boolean> {
    const s = this.ctx.store
    if (!s) return false
    const commandSeq: number = Number(this.ctx.emergencyCommandSeq) || 0
    const isBlockedMotionAction: boolean =
      a === Page1Action.GO || a === Page1Action.BACK || a === Page1Action.LEFT ||
      a === Page1Action.RIGHT || a === Page1Action.LEFT_HALF || a === Page1Action.RIGHT_HALF || a === Page1Action.UTURN
    if (isBlockedMotionAction && typeof this.ctx.canSendMotionCommand === 'function' && !this.ctx.canSendMotionCommand(Page1Action[a], 'AUTO')) {
      s.pushLog(`AUTO_FIRST: send blocked by motion command gate action=${Page1Action[a]}`)
      return false
    }
    this.ctx.proto.setMode(this.ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (a === Page1Action.GO) {
      const blockedByTrafficGate: boolean = maybeBlockGoByTrafficGate(this.ctx, Date.now(), false)
      if (blockedByTrafficGate) {
        s.pushLog('AUTO_FIRST: GO blocked by traffic gate')
        return false
      }
    }
    let actionText: string = ''
    if (a === Page1Action.GO) actionText = '前进'
    else if (a === Page1Action.BACK) actionText = '后退'
    else if (a === Page1Action.LEFT) actionText = '左转'
    else if (a === Page1Action.RIGHT) actionText = '右转'
    else if (a === Page1Action.LEFT_HALF) actionText = '左半转'
    else if (a === Page1Action.RIGHT_HALF) actionText = '右半转'
    else if (a === Page1Action.UTURN) actionText = '掉头'
    else if (a === Page1Action.STOP) actionText = '停止'
    if (this.shouldSkipDuplicateAutoAction(a, actionText)) {
      s.pushLog(`AUTO_FIRST: send skipped by dedup action=${actionText}`)
      return false
    }
    const isPathMotion: boolean = this.isPathMotionAction(a)
    if (!this.ctx.canRealSend()) {
      this.kickTcpConnectForRealSendIfNeeded(s)
      s.bumpTx()
      s.setAction(`自动动作=${actionText} | ${s.realSendEnabled ? 'REAL_SEND(但未连接)' : 'DRY_RUN'}`)
      replayArchiveService.onAction(actionText, 'AUTO_DRY')
      return true
    }
    if (isPathMotion && !this.canSendPathCommandNow(actionText)) {
      s.pushLog(`AUTO_FIRST: send blocked by path-ack gate action=${actionText}`)
      return false
    }
    s.bumpTx()
    s.setAction(`自动动作=${actionText}`)
    if (a === Page1Action.GO) {
      if (this.isStaleByEmergencySeq(commandSeq)) {
        s.pushLog('AUTO_FIRST: GO blocked by stale emergency seq')
        return false
      }
      if (isPathMotion && typeof this.ctx.isNextNodeBlocked === 'function' && this.ctx.isNextNodeBlocked()) {
        s.pushLog('AUTO_FIRST: GO blocked by next node blocked check')
        return false
      }
      await this.ctx.proto.go()
      if (isPathMotion) this.markPathCommandSent(actionText)
      replayArchiveService.onAction(actionText, 'AUTO')
      return true
    }
    if (a === Page1Action.BACK) { if (this.isStaleByEmergencySeq(commandSeq)) return false; await this.ctx.proto.back(); if (isPathMotion) this.markPathCommandSent(actionText); replayArchiveService.onAction(actionText, 'AUTO'); return true }
    if (a === Page1Action.LEFT) { if (this.isStaleByEmergencySeq(commandSeq)) return false; await this.ctx.proto.left(); if (isPathMotion) this.markPathCommandSent(actionText); replayArchiveService.onAction(actionText, 'AUTO'); return true }
    if (a === Page1Action.RIGHT) { if (this.isStaleByEmergencySeq(commandSeq)) return false; await this.ctx.proto.right(); if (isPathMotion) this.markPathCommandSent(actionText); replayArchiveService.onAction(actionText, 'AUTO'); return true }
    if (a === Page1Action.LEFT_HALF) { if (this.isStaleByEmergencySeq(commandSeq)) return false; await this.ctx.proto.leftHalf(); if (isPathMotion) this.markPathCommandSent(actionText); replayArchiveService.onAction(actionText, 'AUTO'); return true }
    if (a === Page1Action.RIGHT_HALF) { if (this.isStaleByEmergencySeq(commandSeq)) return false; await this.ctx.proto.rightHalf(); if (isPathMotion) this.markPathCommandSent(actionText); replayArchiveService.onAction(actionText, 'AUTO'); return true }
    if (a === Page1Action.UTURN) { if (this.isStaleByEmergencySeq(commandSeq)) return false; await this.ctx.proto.uturn(); if (isPathMotion) this.markPathCommandSent(actionText); replayArchiveService.onAction(actionText, 'AUTO'); return true }
    if (a === Page1Action.STOP) {
      const s2 = this.ctx.store
      if (!this.ctx.canRealSend()) {
        if (s2) s2.pushLog('AUTO_STOP: DRY_RUN，跳过发送')
        return true
      }
      this.ctx.proto.setMode(CarSendMode.REAL_SEND)
      if (s2) s2.bumpTx()
      await this.ctx.proto.stopTask()
      if (s2) s2.pushLog('AUTO_STOP: 已发送停止指令给真车')
      return true
    }
    return false
  }

  buildAutoActionFingerprint(action: Page1Action): string {
    const s = this.ctx.store
    if (!s) return `${action}|NO_STORE`
    const idx: number = s.pathIndex
    const len: number = s.pathNodes.length
    let fromId: string = ''
    let toId: string = ''
    if (idx >= 0 && idx < len - 1) {
      fromId = s.pathNodes[idx].trim().toUpperCase()
      toId = s.pathNodes[idx + 1].trim().toUpperCase()
    }
    const curId: string = s.currentSnapNodeId.trim().toUpperCase()
    const motionFrom: string = this.ctx.motionPlayer.currentFromId().trim().toUpperCase()
    const motionTo: string = this.ctx.motionPlayer.currentToId().trim().toUpperCase()
    return `${action}|plan=${s.lastPlannedAtMs}|idx=${idx}/${len}|cur=${curId}|edge=${fromId}->${toId}|motion=${motionFrom}->${motionTo}|gd=${this.ctx.gateDepartInProgress ? 1 : 0}`
  }

  shouldSkipDuplicateAutoAction(action: Page1Action, actionText: string): boolean {
    const s = this.ctx.store
    const fp: string = this.buildAutoActionFingerprint(action)
    if (fp !== this.ctx.lastAutoActionFingerprint) {
      this.ctx.lastAutoActionFingerprint = fp
      return false
    }
    if (s) {
      const nowMs: number = Date.now()
      s.setAction(`自动动作=${actionText} | 去重跳过`)
      if (nowMs - this.ctx.lastAutoActionDedupLogAtMs >= P1C.AUTO_SEND_DEDUP_LOG_COOLDOWN_MS) {
        this.ctx.lastAutoActionDedupLogAtMs = nowMs
        s.pushLog(`AUTO_SEND_DEDUP: ${actionText}（同一上下文仅发送一次）`)
      }
    }
    return true
  }

  isTurnAction(a: Page1Action | undefined): boolean {
    return a === Page1Action.LEFT || a === Page1Action.RIGHT || a === Page1Action.UTURN
  }
  isMoveAction(a: Page1Action | undefined): boolean {
    return a === Page1Action.GO || a === Page1Action.BACK
  }
  resetRouteVoiceFlags(): void { this.ctx.routeStartVoicePlayed = false }
  resetAutoActionDedupState(): void { this.ctx.lastAutoActionFingerprint = ''; this.ctx.lastAutoActionDedupLogAtMs = 0 }
  resetPathAckState(): void {
    this.clearPathAckRetryTimer()
    this.ctx.pathAckFirstCommandSent = false
    this.ctx.pathAckAwaitingComplete = false
    this.ctx.pathAckBlocked = false
    this.ctx.pathAckLastSendAtMs = 0
    this.ctx.pathAckLastStatusCode = 0
    this.ctx.pathAckLastStatusAtMs = 0
    this.ctx.pathAckLastCommandText = ''
    this.ctx.pathAckLastWaitLogAtMs = 0
    this.ctx.pathAckRetrySentCount = 0
    this.ctx.pathAckCommandKey = ''
    this.ctx.pathAckCommandSeq = Number(this.ctx.emergencyCommandSeq) || 0
    this.ctx.pendingAckMotion = undefined
    this.ctx.suppressNextAckCompleteMotion = false
    this.ctx.suppressAckCompleteEdgeId = ''
    this.ctx.pendingDrivingUltrasonicObstacleEdgeId = ''
    this.ctx.pendingDrivingUltrasonicObstacleAtMs = 0
  }
  isPathMotionAction(action: Page1Action): boolean {
    return action === Page1Action.GO ||
      action === Page1Action.BACK ||
      action === Page1Action.LEFT ||
      action === Page1Action.RIGHT ||
      action === Page1Action.LEFT_HALF ||
      action === Page1Action.RIGHT_HALF ||
      action === Page1Action.UTURN
  }
  canSendPathCommandNow(nextActionText: string): boolean {
    const s = this.ctx.store
    if (!s) return false
    if (!this.ctx.pathAckFirstCommandSent) return true
    if (!this.ctx.pathAckAwaitingComplete) return true
    const nowMs: number = Date.now()
    const elapsedMs: number = nowMs - this.ctx.pathAckLastSendAtMs
    if (this.ctx.pathAckBlocked) {
      const logElapsed: number = nowMs - this.ctx.pathAckLastWaitLogAtMs
      if (logElapsed >= P1C.PATH_ACK_WAIT_LOG_COOLDOWN_MS) {
        this.ctx.pathAckLastWaitLogAtMs = nowMs
        s.pushLog(`PATH_ACK_BLOCKED: 等待上一条完成，下一条=${nextActionText}`)
      }
      return false
    }
    if (elapsedMs >= P1C.PATH_ACK_TIMEOUT_MS) {
      this.ctx.pathAckBlocked = true
      this.ctx.pathAckLastWaitLogAtMs = nowMs
      s.setAction(`路径指令等待超时：${this.ctx.pathAckLastCommandText}`)
      s.pushLog(`PATH_ACK_TIMEOUT: 未收到 cmd=0xBD 完成回执(02)，上一条=${this.ctx.pathAckLastCommandText}`)
      return false
    }
    const waitLogElapsed: number = nowMs - this.ctx.pathAckLastWaitLogAtMs
    if (waitLogElapsed >= P1C.PATH_ACK_WAIT_LOG_COOLDOWN_MS) {
      this.ctx.pathAckLastWaitLogAtMs = nowMs
      if (this.ctx.pathAckLastStatusCode === 0x01) s.pushLog(`PATH_ACK_WAIT: 已收到(01)，等待完成(02)，下一条=${nextActionText}`)
      else s.pushLog(`PATH_ACK_WAIT: 等待 cmd=0xBD 回执，下一条=${nextActionText}`)
    }
    return false
  }
  markPathCommandSent(actionText: string): void {
    const commandSeq: number = Number(this.ctx.emergencyCommandSeq) || 0
    this.ctx.pathAckFirstCommandSent = true
    this.ctx.pathAckAwaitingComplete = true
    this.ctx.pathAckBlocked = false
    this.ctx.pathAckLastSendAtMs = Date.now()
    this.ctx.pathAckLastStatusCode = 0
    this.ctx.pathAckLastCommandText = actionText
    this.ctx.pathAckRetrySentCount = 1
    this.ctx.pathAckCommandKey = this.resolvePathAckCommandKey(actionText)
    this.ctx.pathAckCommandSeq = commandSeq
    this.armPathAckRetryTimer()
  }
  onPathAckFrame(f: CarFrame55): void {
    const status: number = f.p1 & 0xff
    replayArchiveService.onAck(status)
    this.ctx.pathAckLastStatusAtMs = Date.now()
    if (typeof this.ctx.onPathAckStatusForDashboard === 'function') this.ctx.onPathAckStatusForDashboard(status)
    if (status === 0x01) {
      this.ctx.pathAckLastStatusCode = 0x01
      this.clearPathAckRetryTimer()
      try { this.ctx.onPathAckReceived01() } catch (_) {}
      return
    }
    if (status === 0x02) {
      this.clearPathAckRetryTimer()
      this.ctx.pathAckLastStatusCode = 0x02
      this.ctx.pathAckAwaitingComplete = false
      this.ctx.pathAckBlocked = false
      this.ctx.pathAckRetrySentCount = 0
      this.ctx.pathAckCommandKey = ''
      const reqOnAck: PendingAckMotion | undefined = this.ctx.pendingAckMotion
      if (reqOnAck && reqOnAck.action === Page1Action.GO) {
        const fromId: string = reqOnAck.fromId.trim().toUpperCase()
        const toId: string = reqOnAck.toId.trim().toUpperCase()
        if (fromId === 'B4' && toId === 'B2') {
          try { void this.ctx.onGateEnterAckCompleted(fromId, toId) } catch (_) {}
        }
      }
      if (this.ctx.suppressNextAckCompleteMotion) {
        const s = this.ctx.store
        const req: PendingAckMotion | undefined = this.ctx.pendingAckMotion
        let suppressed: boolean = false
        if (!req) suppressed = true
        else {
          const reqEdgeId: string = RouteEdgeCodec.normalize(req.fromId, req.toId)
          if (this.ctx.suppressAckCompleteEdgeId.length <= 0 || reqEdgeId === this.ctx.suppressAckCompleteEdgeId) suppressed = true
        }
        if (suppressed) {
          this.ctx.pendingAckMotion = undefined
          this.ctx.suppressNextAckCompleteMotion = false
          this.ctx.suppressAckCompleteEdgeId = ''
          if (s) s.pushLog('PATH_DOT_MOVE: 抑制本次 BD=02 红点前移（路段障碍重规划）')
          this.flushDrivingUltrasonicObstacleAfterAck()
          return
        }
      }
      const req2: PendingAckMotion | undefined = this.ctx.pendingAckMotion
      if (req2) {
        const s2 = this.ctx.store
        const toId2: string = req2.toId.trim().toUpperCase()
        const fromId2: string = req2.fromId.trim().toUpperCase()
        if (s2 && (s2.isBlocked(toId2) || s2.isBlockedEdge(fromId2, toId2))) {
          this.ctx.pendingAckMotion = undefined
          s2.pushLog(`PATH_ACK_BLOCK: BD=02后发现目标节点/边已被阻塞 ${fromId2}->${toId2}，跳过动画并重规划`)
          if (s2.destApplied.length > 0) {
            this.ctx.stopActiveMotion()
            void this.sendDriveActionDirect(Page1Action.STOP)
            this.ctx.planPath(s2.destApplied)
          }
          return
        }
      }
      this.startPendingAckMotionOnComplete()
    }
  }
  pathDotMotionTimingMs(suggestedMs?: number): number {
    const base: number = suggestedMs !== undefined ? suggestedMs : P1C.PATH_DOT_MOTION_MS
    return Math.max(120, Math.round(base))
  }
  pathDotMotionTiming(suggestedMs?: number): MotionTimingProfile {
    const ms: number = this.pathDotMotionTimingMs(suggestedMs)
    return { preMs: 0, activeMs: ms, postMs: 0, sendGapMs: ms }
  }
  async waitForCurrentPathAckComplete(maxWaitMs: number, waitTag: string): Promise<boolean> {
    const s = this.ctx.store
    const timeoutMs: number = Math.max(300, maxWaitMs)
    const deadlineMs: number = Date.now() + timeoutMs
    let lastLogAtMs: number = 0
    while (Date.now() <= deadlineMs) {
      if (!this.ctx.pathAckAwaitingComplete) return true
      const nowMs: number = Date.now()
      if (s && nowMs - lastLogAtMs >= P1C.PATH_ACK_WAIT_LOG_COOLDOWN_MS) {
        lastLogAtMs = nowMs
        if (this.ctx.pathAckLastStatusCode === 0x01) s.pushLog(`${waitTag}: 已收到(01)，等待完成(02)`)
        else s.pushLog(`${waitTag}: 等待 cmd=0xBD 回执`)
      }
      await this.ctx.sleep(120)
    }
    if (s) s.pushLog(`${waitTag}: 等待BD=02超时(${timeoutMs}ms)`)
    return !this.ctx.pathAckAwaitingComplete
  }
  stageMotionWaitAckComplete(req: PendingAckMotion): void {
    this.ctx.pendingAckMotion = req
  }
  startMotionNow(req: PendingAckMotion): void {
    this.ctx.actionScheduler.beginMotionOnlyWithTiming({
      action: req.action,
      fromId: req.fromId,
      toId: req.toId,
      nextAction: req.nextAction,
      customTiming: this.pathDotMotionTiming(req.motionMs),
      advancePathOnFinish: req.advancePathOnFinish,
      useReverseSpeed: req.useReverseSpeed,
      customLogTag: req.customLogTag
    }, this.ctx.schedulerDeps())
  }
  startPendingAckMotionOnComplete(): void {
    const req: PendingAckMotion | undefined = this.ctx.pendingAckMotion
    if (!req) return
    this.ctx.pendingAckMotion = undefined
    const s = this.ctx.store
    if (s) s.pushLog(`PATH_DOT_MOVE: 收到BD=02，开始移动 ${req.fromId} -> ${req.toId} (${this.pathDotMotionTimingMs(req.motionMs)}ms)`)
    this.startMotionNow(req)
  }
  queueDrivingUltrasonicObstacle(nowMs: number): void {
    const s = this.ctx.store
    if (!s) return
    if (this.ctx.parkingInProgress) return
    if (s.destApplied.length <= 0) return
    if (s.pathNodes.length <= 1) return
    if (s.pathIndex >= s.pathNodes.length - 1) return
    const req: PendingAckMotion | undefined = this.ctx.pendingAckMotion
    const awaitingGoComplete: boolean = this.ctx.pathAckAwaitingComplete && req !== undefined && req.action === Page1Action.GO
    if (!this.ctx.motionRunning() && !awaitingGoComplete) return
    const edgeId: string = this.ctx.frontRouteEdgeIdForDriving()
    if (edgeId.length <= 0) return
    this.ctx.suppressNextAckCompleteMotion = true
    this.ctx.suppressAckCompleteEdgeId = edgeId
    this.ctx.pendingDrivingUltrasonicObstacleEdgeId = ''
    this.ctx.pendingDrivingUltrasonicObstacleAtMs = 0
    s.pushLog(`ULTRASONIC_P1_01: 立即停止并重规划 edge=${edgeId}`)
    this.ctx.maybeHandleDrivingUltrasonicObstacle(nowMs, edgeId)
  }
  flushDrivingUltrasonicObstacleAfterAck(): void {
    const edgeId: string = this.ctx.pendingDrivingUltrasonicObstacleEdgeId
    const atMs: number = this.ctx.pendingDrivingUltrasonicObstacleAtMs > 0 ? this.ctx.pendingDrivingUltrasonicObstacleAtMs : Date.now()
    this.ctx.pendingDrivingUltrasonicObstacleEdgeId = ''
    this.ctx.pendingDrivingUltrasonicObstacleAtMs = 0
    if (edgeId.length <= 0) return
    this.ctx.maybeHandleDrivingUltrasonicObstacle(atMs, edgeId)
  }
  resetGateDepartDedupState(): void {
    this.ctx.gateDepartLastSentKey = ''
    this.ctx.gateDepartLastSentAtMs = 0
    this.ctx.gateDepartLastSentAtByFlowKey.clear()
  }
  gateDepartSendKey(curId: string, nextId: string): string {
    return `${curId}->${nextId}`
  }
}
