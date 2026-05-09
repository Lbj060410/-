import { Page1Action } from '../types/Page1Types'
import { P1C, PendingAckMotion } from './Page1CoordinatorDefs'
import { MotionTimingProfile } from './ActionTimingRegistry'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'

function kickTcpConnectForRealSendIfNeeded(ctx: any, s: any): void {
  if (!s || !s.realSendEnabled) return
  const connState: number = Number(s.connState)
  if (connState === 1 || connState === 2 || connState === 3) return
  const nowMs: number = Date.now()
  const lastKickAtMs: number = Number(ctx.realSendConnectKickAtMs) || 0
  if (nowMs - lastKickAtMs < 2000) return
  ctx.realSendConnectKickAtMs = nowMs
  if (typeof s.pushLog === 'function') s.pushLog(`REAL_SEND: 链路未连接，自动重连 ${s.connIp}:${s.connPort}`)
  if (typeof ctx.connectTcp === 'function') void ctx.connectTcp(s.connIp, s.connPort)
}

function isStaleByEmergencySeq(ctx: any, seq: number): boolean {
  return (Number(ctx.emergencyCommandSeq) || 0) !== seq
}

export async function sendDriveActionDirect(ctx: any, a: Page1Action): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (typeof ctx.acquireMotionDispatch === 'function') await ctx.acquireMotionDispatch(`AUTO:${Page1Action[a]}`)
  try {
    const commandSeq: number = Number(ctx.emergencyCommandSeq) || 0
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false

    const blockedMotion: boolean =
      a === Page1Action.GO || a === Page1Action.BACK || a === Page1Action.LEFT ||
      a === Page1Action.RIGHT || a === Page1Action.LEFT_HALF || a === Page1Action.RIGHT_HALF || a === Page1Action.UTURN
    if (blockedMotion && typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand(Page1Action[a], 'AUTO_SIM')) return false

    let actionText: string = ''
    if (a === Page1Action.GO) actionText = '前进'
    else if (a === Page1Action.BACK) actionText = '后退'
    else if (a === Page1Action.LEFT) actionText = '左转'
    else if (a === Page1Action.RIGHT) actionText = '右转'
    else if (a === Page1Action.LEFT_HALF) actionText = '左半转'
    else if (a === Page1Action.RIGHT_HALF) actionText = '右半转'
    else if (a === Page1Action.UTURN) actionText = '掉头'
    else if (a === Page1Action.STOP) actionText = '停止'

    // 门控已下线：不再拦截自动前进。

    if (!ctx.canRealSend()) kickTcpConnectForRealSendIfNeeded(ctx, s)

    s.bumpTx()
    s.setAction(`自动动作=${actionText} | SIM`)
    replayArchiveService.onAction(actionText, ctx.canRealSend() ? 'AUTO_REAL_DISABLED' : 'AUTO_DRY')
    return true
  } finally {
    if (typeof ctx.leaveMotionDispatch === 'function') ctx.leaveMotionDispatch(`AUTO:${Page1Action[a]}`)
  }
}

export function buildAutoActionFingerprint(ctx: any, action: Page1Action): string {
  const s = ctx.store
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
  const motionFrom: string = ctx.motionPlayer.currentFromId().trim().toUpperCase()
  const motionTo: string = ctx.motionPlayer.currentToId().trim().toUpperCase()
  return `${action}|plan=${s.lastPlannedAtMs}|idx=${idx}/${len}|cur=${curId}|edge=${fromId}->${toId}|motion=${motionFrom}->${motionTo}`
}

export function shouldSkipDuplicateAutoAction(ctx: any, action: Page1Action, actionText: string): boolean {
  const s = ctx.store
  const fp: string = buildAutoActionFingerprint(ctx, action)
  if (fp !== ctx.lastAutoActionFingerprint) {
    ctx.lastAutoActionFingerprint = fp
    return false
  }
  if (s) {
    const nowMs: number = Date.now()
    s.setAction(`自动动作=${actionText} | 去重跳过`)
    if (nowMs - ctx.lastAutoActionDedupLogAtMs >= P1C.AUTO_SEND_DEDUP_LOG_COOLDOWN_MS) {
      ctx.lastAutoActionDedupLogAtMs = nowMs
      s.pushLog(`AUTO_SEND_DEDUP: ${actionText}（同一上下文仅发送一次）`)
    }
  }
  return true
}

export function isTurnAction(a: Page1Action | undefined): boolean {
  return a === Page1Action.LEFT || a === Page1Action.RIGHT || a === Page1Action.UTURN
}

export function isMoveAction(a: Page1Action | undefined): boolean {
  return a === Page1Action.GO || a === Page1Action.BACK
}

export function resetRouteVoiceFlags(ctx: any): void { ctx.routeStartVoicePlayed = false }
export function resetAutoActionDedupState(ctx: any): void { ctx.lastAutoActionFingerprint = ''; ctx.lastAutoActionDedupLogAtMs = 0 }

export function resetPathAckState(ctx: any): void {
  ctx.pathAckFirstCommandSent = false
  ctx.pathAckAwaitingComplete = false
  ctx.pathAckBlocked = false
  ctx.pathAckLastSendAtMs = 0
  ctx.pathAckLastStatusCode = 0
  ctx.pathAckLastStatusAtMs = 0
  ctx.pathAckLastCommandText = ''
  ctx.pathAckLastWaitLogAtMs = 0
  ctx.pathAckRetrySentCount = 0
  ctx.pathAckCommandKey = ''
  ctx.pathAckCommandSeq = Number(ctx.emergencyCommandSeq) || 0
  ctx.pathAckCommandToken = 0
  ctx.pathAckSeen01Token = 0
  ctx.pathAckSeen02Token = 0
  ctx.pathAckSeen02AtMs = 0
  ctx.pathAckSeen02PromoteTimerId = -1
  ctx.pathAckRetryGraceToken = 0
  ctx.pathAckRetryGraceAtMs = 0
  ctx.pendingAckMotion = undefined
  ctx.suppressNextAckCompleteMotion = false
  ctx.suppressAckCompleteEdgeId = ''
  ctx.pendingDrivingUltrasonicObstacleEdgeId = ''
  ctx.pendingDrivingUltrasonicObstacleAtMs = 0
}

export function isPathMotionAction(action: Page1Action): boolean {
  return action === Page1Action.GO || action === Page1Action.BACK || action === Page1Action.LEFT || action === Page1Action.RIGHT || action === Page1Action.LEFT_HALF || action === Page1Action.RIGHT_HALF || action === Page1Action.UTURN
}

export function canSendPathCommandNow(_ctx: any, _nextActionText: string): boolean { return true }

export function markPathCommandSent(ctx: any, actionText: string): void {
  ctx.pathAckFirstCommandSent = true
  ctx.pathAckAwaitingComplete = false
  ctx.pathAckBlocked = false
  ctx.pathAckLastSendAtMs = Date.now()
  ctx.pathAckLastStatusCode = 0x02
  ctx.pathAckLastCommandText = actionText
}

export function onPathAckFrame(_ctx: any, _f: any): void {}

export function pathDotMotionTimingMs(suggestedMs?: number): number {
  const base: number = suggestedMs !== undefined ? suggestedMs : P1C.PATH_DOT_MOTION_MS
  return Math.max(120, Math.round(base))
}

export function pathDotMotionTiming(suggestedMs?: number): MotionTimingProfile {
  const ms: number = pathDotMotionTimingMs(suggestedMs)
  return { preMs: 0, activeMs: ms, postMs: 0, sendGapMs: ms }
}

export async function waitForCurrentPathAckComplete(_ctx: any, _maxWaitMs: number, _waitTag: string): Promise<boolean> {
  return true
}

export function stageMotionWaitAckComplete(ctx: any, req: PendingAckMotion): void {
  ctx.pendingAckMotion = req
  ctx.pendingAckMotionToken = Number(ctx.pathAckCommandToken) || 0
}

export function startMotionNow(ctx: any, req: PendingAckMotion): void {
  ctx.actionScheduler.beginMotionOnlyWithTiming({
    action: req.action,
    fromId: req.fromId,
    toId: req.toId,
    nextAction: req.nextAction,
    customTiming: pathDotMotionTiming(req.motionMs),
    advancePathOnFinish: req.advancePathOnFinish,
    useReverseSpeed: req.useReverseSpeed,
    customLogTag: req.customLogTag
  }, ctx.schedulerDeps())
}

export function startPendingAckMotionOnComplete(ctx: any): void {
  const req: PendingAckMotion | undefined = ctx.pendingAckMotion
  if (!req) return
  ctx.pendingAckMotion = undefined
  startMotionNow(ctx, req)
}

export function queueDrivingUltrasonicObstacle(ctx: any, nowMs: number): void {
  const s = ctx.store
  if (!s) return
  const edgeId: string = ctx.frontRouteEdgeIdForDriving()
  if (edgeId.length <= 0) return
  s.pushLog(`ULTRASONIC_P1_01: 立即停止并重规划 edge=${edgeId}`)
  ctx.maybeHandleDrivingUltrasonicObstacle(nowMs, edgeId)
}

export function flushDrivingUltrasonicObstacleAfterAck(_ctx: any): void {}
