/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorDriveAckOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorDriveAckOps.ets
 * 用途： 封装路径动作发送与 ACK 同步/重试逻辑，保证指令执行一致性。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'
import { P1C, PendingAckMotion } from './Page1CoordinatorDefs'
import { RouteEdgeCodec } from './PathPlannerAStar'
import { MotionTimingProfile } from './ActionTimingRegistry'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { maybeBlockGoByTrafficGate } from './Page1CoordinatorTrafficGateOps'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'

const PATH_ACK_RETRY_WAIT_MS: number =2000
const PATH_ACK_RETRY_MAX_SENDS: number = 3

function isStaleByEmergencySeq(ctx: any, seq: number): boolean {
  return (Number(ctx.emergencyCommandSeq) || 0) !== seq
}

function clearPathAckRetryTimer(ctx: any): void {
  if (ctx.pathAckRetryTimerId >= 0) {
    clearTimeout(ctx.pathAckRetryTimerId)
    ctx.pathAckRetryTimerId = -1
  }
}

function resolvePathAckCommandKey(actionText: string): string {
  if (actionText === '前进') return 'GO'
  if (actionText === '后退') return 'BACK'
  if (actionText === '左转') return 'LEFT'
  if (actionText === '右转') return 'RIGHT'
  if (actionText === '左半转') return 'LEFT_HALF'
  if (actionText === '右半转') return 'RIGHT_HALF'
  if (actionText === '掉头') return 'UTURN'
  if (actionText === '道闸结算') return 'SETTLE_ACCOUNTS'
  if (actionText === '闸口放行') return 'GATE_DEPART'
  return ''
}

async function sendPathAckCommandByKey(ctx: any, key: string, commandSeq: number): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (!ctx.canRealSend()) return false
  if (isStaleByEmergencySeq(ctx, commandSeq)) return false
  const isMotionKey: boolean =
    key === 'GO' ||
    key === 'BACK' ||
    key === 'LEFT' ||
    key === 'RIGHT' ||
    key === 'LEFT_HALF' ||
    key === 'RIGHT_HALF' ||
    key === 'UTURN' ||
    key === 'GATE_DEPART'
  if (isMotionKey && typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand(key, 'PATH_ACK_RETRY')) {
    return false
  }
  ctx.proto.setMode(CarSendMode.REAL_SEND)

  s.bumpTx()
  if (key === 'GO') {
    await ctx.proto.go()
    return true
  }
  if (key === 'BACK') {
    await ctx.proto.back()
    return true
  }
  if (key === 'LEFT') {
    await ctx.proto.left()
    return true
  }
  if (key === 'RIGHT') {
    await ctx.proto.right()
    return true
  }
  if (key === 'LEFT_HALF') {
    await ctx.proto.leftHalf()
    return true
  }
  if (key === 'RIGHT_HALF') {
    await ctx.proto.rightHalf()
    return true
  }
  if (key === 'UTURN') {
    await ctx.proto.uturn()
    return true
  }
  if (key === 'SETTLE_ACCOUNTS') {
    await ctx.proto.SrttleAccounts()
    return true
  }
  if (key === 'GATE_DEPART') {
    await ctx.proto.depart()
    return true
  }
  return false
}

function armPathAckRetryTimer(ctx: any): void {
  clearPathAckRetryTimer(ctx)
  if (!ctx.canRealSend()) return
  if (!ctx.pathAckAwaitingComplete) return
  const commandSeq: number = Number(ctx.pathAckCommandSeq) || 0
  if (isStaleByEmergencySeq(ctx, commandSeq)) return
  if (ctx.pathAckLastStatusCode === 0x01 || ctx.pathAckLastStatusCode === 0x02) return
  if (ctx.pathAckRetrySentCount >= PATH_ACK_RETRY_MAX_SENDS) return
  if (!ctx.pathAckCommandKey || ctx.pathAckCommandKey.length <= 0) return

  ctx.pathAckRetryTimerId = setTimeout((): void => {
    ctx.pathAckRetryTimerId = -1
    const latestSeq: number = Number(ctx.pathAckCommandSeq) || 0
    if (isStaleByEmergencySeq(ctx, latestSeq)) return
    void retryPathAckCommandIfNeeded(ctx)
  }, PATH_ACK_RETRY_WAIT_MS) as number
}

async function retryPathAckCommandIfNeeded(ctx: any): Promise<void> {
  const s = ctx.store
  if (!s) return
  if (!ctx.canRealSend()) return
  if (!ctx.pathAckAwaitingComplete) return
  const commandSeq: number = Number(ctx.pathAckCommandSeq) || 0
  if (isStaleByEmergencySeq(ctx, commandSeq)) return
  if (ctx.pathAckLastStatusCode === 0x01 || ctx.pathAckLastStatusCode === 0x02) return
  if (ctx.pathAckRetrySentCount >= PATH_ACK_RETRY_MAX_SENDS) return
  const key: string = ctx.pathAckCommandKey || ''
  if (key.length <= 0) return

  const nextSendCount: number = ctx.pathAckRetrySentCount + 1
  const sentOk: boolean = await sendPathAckCommandByKey(ctx, key, commandSeq)
  if (!sentOk) {
    s.pushLog(`PATH_ACK_RETRY: 重发失败 key=${key}`)
    return
  }

  ctx.pathAckRetrySentCount = nextSendCount
  ctx.pathAckLastSendAtMs = Date.now()
  ctx.pathAckLastStatusCode = 0
  s.pushLog(`PATH_ACK_RETRY: 2000ms未收到0x01，重发第${nextSendCount}次/${PATH_ACK_RETRY_MAX_SENDS} cmd=${ctx.pathAckLastCommandText}`)
  armPathAckRetryTimer(ctx)
}

async function waitLightBaselineReadyForInitialGo(ctx: any, timeoutMs: number): Promise<boolean> {
  const s = ctx.store
  if (!s) return false

  const nowMs: number = Date.now()
  const lastQueryAtMs: number = Number(ctx.lightMetricLastQueryAtMs) || 0
  const shouldQueryNow: boolean =
    !ctx.lightMetricQueryEnabled ||
    (nowMs - lastQueryAtMs >= P1C.LIGHT_QUERY_MIN_INTERVAL_MS)
  let gateAtMs: number = lastQueryAtMs > 0 ? lastQueryAtMs : nowMs

  if (shouldQueryNow) {
    try {
      if (typeof ctx.armLightMetricQuery === 'function') {
        ctx.armLightMetricQuery()
      }
      gateAtMs = Date.now()
      ctx.lightMetricLastQueryAtMs = gateAtMs
      s.bumpTx()
      await ctx.proto.light()
      s.pushLog('LIGHT: 起步前已发送光照查询，等待BD=02后再发前进')
    } catch (_) {
      s.pushLog('LIGHT: 起步前光照查询发送失败，本轮前进取消')
      return false
    }
  } else {
    s.pushLog('LIGHT: 起步前等待最近一次光照查询的BD=02')
  }

  const waitMs: number = Math.max(300, timeoutMs)
  const deadlineMs: number = Date.now() + waitMs
  while (Date.now() <= deadlineMs) {
    const statusCode: number = Number(ctx.pathAckLastStatusCode) || 0
    const statusAtMs: number = Number(ctx.pathAckLastStatusAtMs) || 0
    if (statusCode === 0x02 && statusAtMs >= gateAtMs) return true
    await ctx.sleep(120)
  }
  s.pushLog(`LIGHT: 起步等待BD=02超时(${waitMs}ms)，本轮前进取消`)
  return false
}

export async function sendDriveActionDirect(ctx: any, a: Page1Action): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  const commandSeq: number = Number(ctx.emergencyCommandSeq) || 0

  const isBlockedMotionAction: boolean =
    a === Page1Action.GO ||
    a === Page1Action.BACK ||
    a === Page1Action.LEFT ||
    a === Page1Action.RIGHT ||
    a === Page1Action.LEFT_HALF ||
    a === Page1Action.RIGHT_HALF ||
    a === Page1Action.UTURN
  if (isBlockedMotionAction && typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand(Page1Action[a], 'AUTO')) {
    return false
  }

  ctx.proto.setMode(ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)

  if (a === Page1Action.GO) {
    const blockedByTrafficGate: boolean = maybeBlockGoByTrafficGate(ctx, Date.now(), false)
    if (blockedByTrafficGate) return false
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

  if (shouldSkipDuplicateAutoAction(ctx, a, actionText)) return false
  const isPathMotion: boolean = isPathMotionAction(a)

  if (!ctx.canRealSend()) {
    s.bumpTx()
    s.setAction(`自动动作=${actionText} | ${s.realSendEnabled ? 'REAL_SEND(但未连接)' : 'DRY_RUN'}`)
    replayArchiveService.onAction(actionText, 'AUTO_DRY')
    return true
  }

  if (isPathMotion && !canSendPathCommandNow(ctx, actionText)) return false

  const isInitialPathGo: boolean = a === Page1Action.GO && !ctx.pathAckFirstCommandSent
  if (isPathMotion) {
    if (isInitialPathGo) {
      const ready: boolean = await waitLightBaselineReadyForInitialGo(ctx, P1C.LIGHT_QUERY_WAIT_TIMEOUT_MS)
      if (!ready) return false
    }
    if (!ctx.lightMetricReady) {
      const nowMs: number = Date.now()
      const lastQueryAtMs: number = Number(ctx.lightMetricLastQueryAtMs) || 0
      const shouldQuery: boolean =
        !ctx.lightMetricQueryEnabled ||
        (nowMs - lastQueryAtMs >= P1C.LIGHT_QUERY_MIN_INTERVAL_MS)
      if (shouldQuery) {
        if (typeof ctx.armLightMetricQuery === 'function') {
          ctx.armLightMetricQuery()
        }
        ctx.lightMetricLastQueryAtMs = nowMs
        s.bumpTx()
        void ctx.proto.light()
          .then((): void => {
            s.pushLog('LIGHT: 出发前自动查询光照基准(异步)')
          })
          .catch((): void => {
            s.pushLog('LIGHT: 出发前自动查询失败，继续发送运动指令')
          })
      }
    }
  }

  s.bumpTx()
  s.setAction(`自动动作=${actionText}`)

  if (a === Page1Action.GO) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.go()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.BACK) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.back()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.LEFT) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.left()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.RIGHT) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.right()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.LEFT_HALF) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.leftHalf()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.RIGHT_HALF) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.rightHalf()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.UTURN) {
    if (isStaleByEmergencySeq(ctx, commandSeq)) return false
    await ctx.proto.uturn()
    if (isPathMotion) markPathCommandSent(ctx, actionText)
    replayArchiveService.onAction(actionText, 'AUTO')
    return true
  }
  if (a === Page1Action.STOP) {
    const s2 = ctx.store
    if (s2) s2.pushLog('AUTO_STOP: 已忽略 stopTask 下发（该指令无法停止行动任务）')
    return true
  }

  return false
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

  return `${action}|plan=${s.lastPlannedAtMs}|idx=${idx}/${len}|cur=${curId}|edge=${fromId}->${toId}|motion=${motionFrom}->${motionTo}|gd=${ctx.gateDepartInProgress ? 1 : 0}`
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

export function resetRouteVoiceFlags(ctx: any): void {
  ctx.routeStartVoicePlayed = false
}

export function resetAutoActionDedupState(ctx: any): void {
  ctx.lastAutoActionFingerprint = ''
  ctx.lastAutoActionDedupLogAtMs = 0
}

export function resetPathAckState(ctx: any): void {
  clearPathAckRetryTimer(ctx)
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
  ctx.pendingAckMotion = undefined
  ctx.suppressNextAckCompleteMotion = false
  ctx.suppressAckCompleteEdgeId = ''
  ctx.pendingDrivingUltrasonicObstacleEdgeId = ''
  ctx.pendingDrivingUltrasonicObstacleAtMs = 0
}

export function isPathMotionAction(action: Page1Action): boolean {
  return action === Page1Action.GO ||
    action === Page1Action.BACK ||
    action === Page1Action.LEFT ||
    action === Page1Action.RIGHT ||
    action === Page1Action.LEFT_HALF ||
    action === Page1Action.RIGHT_HALF ||
    action === Page1Action.UTURN
}

export function canSendPathCommandNow(ctx: any, nextActionText: string): boolean {
  const s = ctx.store
  if (!s) return false
  if (!ctx.pathAckFirstCommandSent) return true
  if (!ctx.pathAckAwaitingComplete) return true

  const nowMs: number = Date.now()
  const elapsedMs: number = nowMs - ctx.pathAckLastSendAtMs

  if (ctx.pathAckBlocked) {
    const logElapsed: number = nowMs - ctx.pathAckLastWaitLogAtMs
    if (logElapsed >= P1C.PATH_ACK_WAIT_LOG_COOLDOWN_MS) {
      ctx.pathAckLastWaitLogAtMs = nowMs
      s.pushLog(`PATH_ACK_BLOCKED: 等待上一条完成，下一条=${nextActionText}`)
    }
    return false
  }

  if (elapsedMs >= P1C.PATH_ACK_TIMEOUT_MS) {
    ctx.pathAckBlocked = true
    ctx.pathAckLastWaitLogAtMs = nowMs
    s.setAction(`路径指令等待超时：${ctx.pathAckLastCommandText}`)
    s.pushLog(`PATH_ACK_TIMEOUT: 未收到 cmd=0xBD 完成回执(02)，上一条=${ctx.pathAckLastCommandText}`)
    return false
  }

  const waitLogElapsed: number = nowMs - ctx.pathAckLastWaitLogAtMs
  if (waitLogElapsed >= P1C.PATH_ACK_WAIT_LOG_COOLDOWN_MS) {
    ctx.pathAckLastWaitLogAtMs = nowMs
    if (ctx.pathAckLastStatusCode === 0x01) {
      s.pushLog(`PATH_ACK_WAIT: 已收到(01)，等待完成(02)，下一条=${nextActionText}`)
    } else {
      s.pushLog(`PATH_ACK_WAIT: 等待 cmd=0xBD 回执，下一条=${nextActionText}`)
    }
  }

  return false
}

export function markPathCommandSent(ctx: any, actionText: string): void {
  const commandSeq: number = Number(ctx.emergencyCommandSeq) || 0
  ctx.pathAckFirstCommandSent = true
  ctx.pathAckAwaitingComplete = true
  ctx.pathAckBlocked = false
  ctx.pathAckLastSendAtMs = Date.now()
  ctx.pathAckLastStatusCode = 0
  ctx.pathAckLastCommandText = actionText
  ctx.pathAckRetrySentCount = 1
  ctx.pathAckCommandKey = resolvePathAckCommandKey(actionText)
  ctx.pathAckCommandSeq = commandSeq
  armPathAckRetryTimer(ctx)
}

export function onPathAckFrame(ctx: any, f: any): void {
  const status: number = f.p1 & 0xff
  replayArchiveService.onAck(status)
  ctx.pathAckLastStatusAtMs = Date.now()
  if (typeof ctx.onPathAckStatusForDashboard === 'function') {
    ctx.onPathAckStatusForDashboard(status)
  }

  if (status === 0x01) {
    ctx.pathAckLastStatusCode = 0x01
    clearPathAckRetryTimer(ctx)
    try {
      ctx.onPathAckReceived01()
    } catch (_) {}
    return
  }

  if (status === 0x02) {
    clearPathAckRetryTimer(ctx)
    ctx.pathAckLastStatusCode = 0x02
    ctx.pathAckAwaitingComplete = false
    ctx.pathAckBlocked = false
    ctx.pathAckRetrySentCount = 0
    ctx.pathAckCommandKey = ''

    const reqOnAck: PendingAckMotion | undefined = ctx.pendingAckMotion
    if (reqOnAck && reqOnAck.action === Page1Action.GO) {
      const fromId: string = reqOnAck.fromId.trim().toUpperCase()
      const toId: string = reqOnAck.toId.trim().toUpperCase()
      if (fromId === 'B4' && toId === 'B2') {
        try {
          void ctx.onGateEnterAckCompleted(fromId, toId)
        } catch (_) {}
      }
    }

    if (ctx.suppressNextAckCompleteMotion) {
      const s = ctx.store
      const req: PendingAckMotion | undefined = ctx.pendingAckMotion
      let suppressed: boolean = false

      if (!req) {
        suppressed = true
      } else {
        const reqEdgeId: string = RouteEdgeCodec.normalize(req.fromId, req.toId)
        if (ctx.suppressAckCompleteEdgeId.length <= 0 || reqEdgeId === ctx.suppressAckCompleteEdgeId) {
          suppressed = true
        }
      }

      if (suppressed) {
        ctx.pendingAckMotion = undefined
        ctx.suppressNextAckCompleteMotion = false
        ctx.suppressAckCompleteEdgeId = ''
        if (s) s.pushLog('PATH_DOT_MOVE: 抑制本次 BD=02 红点前移（路段障碍重规划）')
        flushDrivingUltrasonicObstacleAfterAck(ctx)
        return
      }
    }

    startPendingAckMotionOnComplete(ctx)
  }
}

export function pathDotMotionTimingMs(suggestedMs?: number): number {
  const base: number = suggestedMs !== undefined ? suggestedMs : P1C.PATH_DOT_MOTION_MS
  return Math.max(120, Math.round(base))
}

export function pathDotMotionTiming(suggestedMs?: number): MotionTimingProfile {
  const ms: number = pathDotMotionTimingMs(suggestedMs)
  return { preMs: 0, activeMs: ms, postMs: 0, sendGapMs: ms }
}

export async function waitForCurrentPathAckComplete(ctx: any, maxWaitMs: number, waitTag: string): Promise<boolean> {
  const s = ctx.store
  const timeoutMs: number = Math.max(300, maxWaitMs)
  const deadlineMs: number = Date.now() + timeoutMs
  let lastLogAtMs: number = 0

  while (Date.now() <= deadlineMs) {
    if (!ctx.pathAckAwaitingComplete) return true

    const nowMs: number = Date.now()
    if (s && nowMs - lastLogAtMs >= P1C.PATH_ACK_WAIT_LOG_COOLDOWN_MS) {
      lastLogAtMs = nowMs
      if (ctx.pathAckLastStatusCode === 0x01) s.pushLog(`${waitTag}: 已收到(01)，等待完成(02)`)
      else s.pushLog(`${waitTag}: 等待 cmd=0xBD 回执`)
    }

    await ctx.sleep(120)
  }

  if (s) s.pushLog(`${waitTag}: 等待BD=02超时(${timeoutMs}ms)`)
  return !ctx.pathAckAwaitingComplete
}

export function stageMotionWaitAckComplete(ctx: any, req: PendingAckMotion): void {
  ctx.pendingAckMotion = req
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
  const s = ctx.store
  if (s) s.pushLog(`PATH_DOT_MOVE: 收到BD=02，开始移动 ${req.fromId} -> ${req.toId} (${pathDotMotionTimingMs(req.motionMs)}ms)`)

  startMotionNow(ctx, req)
}

export function queueDrivingUltrasonicObstacle(ctx: any, nowMs: number): void {
  const s = ctx.store
  if (!s) return
  if (ctx.parkingInProgress) return
  if (s.destApplied.length <= 0) return
  if (s.pathNodes.length <= 1) return
  if (s.pathIndex >= s.pathNodes.length - 1) return

  const req: PendingAckMotion | undefined = ctx.pendingAckMotion
  const awaitingGoComplete: boolean = ctx.pathAckAwaitingComplete && req !== undefined && req.action === Page1Action.GO
  if (!ctx.motionRunning() && !awaitingGoComplete) return

  const edgeId: string = ctx.frontRouteEdgeIdForDriving()
  if (edgeId.length <= 0) return

  ctx.suppressNextAckCompleteMotion = true
  ctx.suppressAckCompleteEdgeId = edgeId
  ctx.pendingDrivingUltrasonicObstacleEdgeId = edgeId
  ctx.pendingDrivingUltrasonicObstacleAtMs = nowMs
  s.pushLog(`ULTRASONIC_P1_01: 已挂起路段障碍 edge=${edgeId}，等待BD=02后重规划`)
}

export function flushDrivingUltrasonicObstacleAfterAck(ctx: any): void {
  const edgeId: string = ctx.pendingDrivingUltrasonicObstacleEdgeId
  const atMs: number = ctx.pendingDrivingUltrasonicObstacleAtMs > 0 ? ctx.pendingDrivingUltrasonicObstacleAtMs : Date.now()

  ctx.pendingDrivingUltrasonicObstacleEdgeId = ''
  ctx.pendingDrivingUltrasonicObstacleAtMs = 0

  if (edgeId.length <= 0) return
  ctx.maybeHandleDrivingUltrasonicObstacle(atMs, edgeId)
}

export function resetGateDepartDedupState(ctx: any): void {
  ctx.gateDepartLastSentKey = ''
  ctx.gateDepartLastSentAtMs = 0
  ctx.gateDepartLastSentAtByFlowKey.clear()
}

export function gateDepartSendKey(curId: string, nextId: string): string {
  return `${curId}->${nextId}`
}
