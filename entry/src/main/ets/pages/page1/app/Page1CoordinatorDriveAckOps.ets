import { Page1Action } from '../types/Page1Types'
import { P1C, IPage1CoordinatorOps } from './Page1CoordinatorDefs'
import { MotionTimingProfile } from './ActionTimingRegistry'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'
import { Page1UiStore } from './Page1UiStore'

interface PendingAckMotion {
  action: Page1Action
  fromId: string
  toId: string
  nextAction?: Page1Action
  motionMs: number
  advancePathOnFinish: boolean
  useReverseSpeed: boolean
  customLogTag: string
}

function kickTcpConnectForRealSendIfNeeded(ctx: IPage1CoordinatorOps, s: Page1UiStore): void {
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

function isStaleByEmergencySeq(ctx: IPage1CoordinatorOps, seq: number): boolean {
  return (Number(ctx.emergencyCommandSeq) || 0) !== seq
}

export async function sendDriveActionDirect(ctx: IPage1CoordinatorOps, a: Page1Action): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (typeof ctx.acquireMotionDispatch === 'function') await ctx.acquireMotionDispatch(`AUTO:${Page1Action[a]}`)
  try {
    const commandSeq: number = Number(ctx.emergencyCommandSeq) || 0
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false

    const blockedMotion: boolean =
      a === Page1Action.GO || a === Page1Action.BACK || a === Page1Action.LEFT ||
      a === Page1Action.RIGHT || a === Page1Action.LEFT_HALF || a === Page1Action.RIGHT_HALF || a === Page1Action.UTURN
    const needMotionGate: boolean = blockedMotion && ctx.canRealSend()
    if (needMotionGate && typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand(Page1Action[a], 'AUTO_SIM')) return false

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

export function buildAutoActionFingerprint(ctx: IPage1CoordinatorOps, action: Page1Action): string {
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

export function shouldSkipDuplicateAutoAction(ctx: IPage1CoordinatorOps, action: Page1Action, actionText: string): boolean {
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

export function resetRouteVoiceFlags(ctx: IPage1CoordinatorOps): void { ctx.routeStartVoicePlayed = false }
export function resetAutoActionDedupState(ctx: IPage1CoordinatorOps): void { ctx.lastAutoActionFingerprint = ''; ctx.lastAutoActionDedupLogAtMs = 0 }

export function isPathMotionAction(action: Page1Action): boolean {
  return action === Page1Action.GO || action === Page1Action.BACK || action === Page1Action.LEFT || action === Page1Action.RIGHT || action === Page1Action.LEFT_HALF || action === Page1Action.RIGHT_HALF || action === Page1Action.UTURN
}

export function pathDotMotionTimingMs(suggestedMs?: number): number {
  const base: number = suggestedMs !== undefined ? suggestedMs : P1C.PATH_DOT_MOTION_MS
  return Math.max(120, Math.round(base))
}

export function pathDotMotionTiming(suggestedMs?: number): MotionTimingProfile {
  const ms: number = pathDotMotionTimingMs(suggestedMs)
  return { preMs: 0, activeMs: ms, postMs: 0, sendGapMs: ms }
}

export function startMotionNow(ctx: IPage1CoordinatorOps, req: PendingAckMotion): void {
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

export function queueDrivingUltrasonicObstacle(ctx: IPage1CoordinatorOps, nowMs: number): void {
  const s = ctx.store
  if (!s) return
  const edgeId: string = ctx.frontRouteEdgeIdForDriving()
  if (edgeId.length <= 0) return
  s.pushLog(`ULTRASONIC_P1_01: 立即停止并重规划 edge=${edgeId}`)
  ctx.maybeHandleDrivingUltrasonicObstacle(nowMs, edgeId)
}



