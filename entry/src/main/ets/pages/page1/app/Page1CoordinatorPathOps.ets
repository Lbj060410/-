/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorPathOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorPathOps.ets
 * 用途： 封装路径跟踪、动作预测与路径段推进逻辑。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'
import { GridIdCodec, PathPlannerAStar } from './PathPlannerAStar'

export function resolveStartNodeId(ctx: any): string {
  const s = ctx.store
  if (!s) return 'D4'
  const snap = s.currentSnapNodeId.trim().toUpperCase()
  if (snap.length > 0 && GridIdCodec.isValidId(snap)) return snap
  const near = ctx.nearestNodeIdByPose()
  if (near.length > 0 && GridIdCodec.isValidId(near)) return near
  return 'D4'
}

export function isParkingInnerRowNode(id: string): boolean {
  const p = GridIdCodec.parse(id)
  if (!p) return false
  return p.row === 0
}

export function isInsideGateInnerSideNode(id: string): boolean {
  const p = GridIdCodec.parse(id)
  if (!p) return false
  return p.row <= 1
}

export function gateForcedWaypoint(ctx: any, startId: string, goalId: string): string {
  const startInner = isParkingInnerRowNode(startId)
  const goalInner = isParkingInnerRowNode(goalId)
  if (startInner && !goalInner) return 'B2'
  if (!startInner && goalInner) {
    if (isInsideGateInnerSideNode(startId)) return ''
    return 'B4'
  }
  return ''
}

export function buildPathViaWaypoint(
  ctx: any,
  start: string,
  via: string,
  goal: string,
  blocked: Array<string>,
  blockedEdges: Array<string>
): any {
  if (start === goal) return { ok: true, reason: 'same', path: [start] }
  if (!GridIdCodec.isValidId(start)) return { ok: false, reason: `bad start=${start}`, path: [] }
  if (!GridIdCodec.isValidId(goal)) return { ok: false, reason: `bad goal=${goal}`, path: [] }
  if (!GridIdCodec.isValidId(via)) return { ok: false, reason: `bad via=${via}`, path: [] }
  if (start === via || via === goal) return PathPlannerAStar.plan(start, goal, blocked, blockedEdges)

  const leg1 = PathPlannerAStar.plan(start, via, blocked, blockedEdges)
  if (!leg1.ok) return { ok: false, reason: `leg1 fail via=${via} reason=${leg1.reason}`, path: [] }

  const leg2 = PathPlannerAStar.plan(via, goal, blocked, blockedEdges)
  if (!leg2.ok) return { ok: false, reason: `leg2 fail via=${via} reason=${leg2.reason}`, path: [] }

  const out: Array<string> = []
  for (let i = 0; i < leg1.path.length; i++) out.push(leg1.path[i])
  for (let i = 0; i < leg2.path.length; i++) {
    const id = leg2.path[i]
    if (out.length > 0 && out[out.length - 1] === id) continue
    out.push(id)
  }
  return { ok: true, reason: 'ok', path: out }
}

export function syncLogicalHeadingWithCurrentState(ctx: any): void {
  const s = ctx.store
  if (!s) return
  ctx.logicalHeadingDeg = normToCardinal(ctx, s.pose.headingDeg)
  ctx.logicalHeadingInited = true
}

export function segmentHeadingDeg(ctx: any, fromId: string, toId: string): number {
  const from = GridIdCodec.parse(fromId)
  const to = GridIdCodec.parse(toId)
  if (!from || !to) return 0

  const dx = to.col - from.col
  const dy = to.row - from.row

  if (dx === 1 && dy === 0) return 0
  if (dx === 0 && dy === 1) return 90
  if (dx === -1 && dy === 0) return 180
  if (dx === 0 && dy === -1) return 270
  return 0
}

export function normToCardinal(ctx: any, v: number): number {
  const x = ctx.norm360(v)
  const idx = Math.round(x / 90) % 4
  return idx * 90
}

export function actionForHeadingTransition(ctx: any, curDeg: number, desiredDeg: number): Page1Action | undefined {
  const c = normToCardinal(ctx, curDeg)
  const d = normToCardinal(ctx, desiredDeg)
  const err = ctx.headingErrorDeg(c, d)

  if (err === 0) return undefined
  if (Math.abs(err) === 180) return Page1Action.UTURN
  if (err > 0) return Page1Action.RIGHT
  return Page1Action.LEFT
}

export function predictActionForPair(ctx: any, curHeadingDeg: number, fromId: string, toId: string): Page1Action {
  const desired = segmentHeadingDeg(ctx, fromId, toId)
  const turn = actionForHeadingTransition(ctx, curHeadingDeg, desired)
  if (turn !== undefined) return turn
  return Page1Action.GO
}

export function predictedHeadingAfterAction(
  ctx: any,
  curHeadingDeg: number,
  action: Page1Action,
  fromId: string,
  toId: string
): number {
  if (ctx.isTurnAction(action) || action === Page1Action.GO || action === Page1Action.BACK) {
    return segmentHeadingDeg(ctx, fromId, toId)
  }
  return curHeadingDeg
}

export function peekNextActionAfterCurrentStep(ctx: any): Page1Action | undefined {
  const s = ctx.store
  if (!s) return undefined

  const curIndex = s.pathIndex
  if (curIndex + 2 >= s.pathNodes.length) return undefined

  const fromId = s.pathNodes[curIndex]
  const toId = s.pathNodes[curIndex + 1]
  const nextId = s.pathNodes[curIndex + 2]

  const first = predictActionForPair(ctx, ctx.logicalHeadingDeg, fromId, toId)
  const headingAfterFirst = predictedHeadingAfterAction(ctx, ctx.logicalHeadingDeg, first, fromId, toId)
  return predictActionForPair(ctx, headingAfterFirst, toId, nextId)
}

export function canSendNextCommand(ctx: any, nowMs: number): boolean {
  const snap = ctx.actionScheduler.snapshot(nowMs, ctx.motionRunning())
  ctx.lastSchedulerSnapshot = snap
  return snap.canSend
}

export async function sendAutoActionWithTiming(
  ctx: any,
  action: Page1Action,
  fromId: string,
  toId: string,
  nextAction?: Page1Action,
  customTiming?: { activeMs: number },
  advancePathOnFinish?: boolean,
  useReverseSpeed?: boolean,
  customLogTag?: string
): Promise<boolean> {
  const sent = await ctx.sendDriveActionDirect(action)
  if (!sent) return false

  const req = {
    action: action,
    fromId: fromId,
    toId: toId,
    nextAction: nextAction,
    motionMs: ctx.pathDotMotionTimingMs(customTiming ? customTiming.activeMs : undefined),
    advancePathOnFinish: advancePathOnFinish === true,
    useReverseSpeed: useReverseSpeed === true,
    customLogTag: customLogTag ? customLogTag : ''
  }

  if (ctx.isPathMotionAction(action) && ctx.pathAckAwaitingComplete) {
    ctx.stageMotionWaitAckComplete(req)
  } else {
    ctx.startMotionNow(req)
  }

  return true
}

export async function followPathOnce(ctx: any, nowMs: number, force: boolean = false): Promise<void> {
  const s = ctx.store
  if (!s) return

  if (ctx.maybeHandleAheadVisionReplan(nowMs)) return
  if (nowMs < ctx.pauseUntilMs) return
  if (ctx.parkingInProgress) return
  if (ctx.gateDepartInProgress) return
  if (ctx.motionRunning()) return

  if (s.pathNodes.length > 0 && s.pathIndex >= s.pathNodes.length - 1) {
    if (!canSendNextCommand(ctx, nowMs)) return
    s.markAutoFollow(nowMs)
    await ctx.sendDriveActionDirect(Page1Action.STOP)
    s.setAction('到达终点，停止')
    return
  }

  if (!s.autoFollowEnabled && !force) return

  if (!force) {
    if (!s.canAutoFollow(nowMs)) return
  } else {
    if (s.obstacleEditEnabled) return
    if (s.pathNodes.length <= 1) return
    if (s.pathIndex >= s.pathNodes.length - 1) return
  }

  if (await ctx.maybeHandleGarageDepartBeforeDrive(nowMs)) {
    s.markAutoFollow(nowMs)
    return
  }

  if (!canSendNextCommand(ctx, nowMs)) return

  const idx = s.pathIndex
  const fromId = s.pathNodes[idx]
  const toId = s.pathNodes[idx + 1]

  if ((s.isBlocked(toId) || s.isBlockedEdge(fromId, toId)) && s.destApplied.length > 0) {
    ctx.maybeReplanOnObstacle()
    s.markAutoFollow(nowMs)
    return
  }

  if (!ctx.logicalHeadingInited) syncLogicalHeadingWithCurrentState(ctx)

  if (idx === 0 && !ctx.routeStartVoicePlayed) {
    await ctx.maybePlayRouteStartVoice()
    return
  }

  const desiredHeadingDeg = segmentHeadingDeg(ctx, fromId, toId)
  let turnAction = actionForHeadingTransition(ctx, ctx.logicalHeadingDeg, desiredHeadingDeg)
  if (turnAction === Page1Action.UTURN && idx === 0 && ctx.isReverseParkingGoal(fromId)) {
    // 停车位出发：避免在第一段边上原地掉头。
    turnAction = undefined
    s.pushLog(`PARK_DEPART: ${fromId}->${toId} 首段抑制掉头，改为直接前进`)
  }

  if (turnAction !== undefined) {
    const sentTurn = await sendAutoActionWithTiming(
      ctx,
      turnAction,
      fromId,
      toId,
      Page1Action.GO,
      undefined,
      false,
      false,
      'TURN_ONLY'
    )
    if (!sentTurn) return

    s.markAutoFollow(nowMs)

    let turnText = '转向'
    if (turnAction === Page1Action.LEFT) turnText = '左转'
    else if (turnAction === Page1Action.RIGHT) turnText = '右转'
    else if (turnAction === Page1Action.UTURN) turnText = '掉头'

    s.setAction(`自动转向=${turnText}`)
    s.pushLog(`TURN_ONLY: ${fromId} -> ${toId} | sent, wait BD=02 before dot turn`)
    return
  }

  if (ctx.maybeStartAheadVisionReplan(fromId, toId, nowMs)) {
    s.markAutoFollow(nowMs)
    return
  }

  const nextActionAfterGo = peekNextActionAfterCurrentStep(ctx)
  const sentGo = await sendAutoActionWithTiming(
    ctx,
    Page1Action.GO,
    fromId,
    toId,
    nextActionAfterGo,
    undefined,
    true,
    false,
    'SEGMENT_START'
  )
  if (!sentGo) return

  s.markAutoFollow(nowMs)
  s.pushLog(`SEGMENT_START: ${fromId} -> ${toId} | 已发送，等待BD=02后红点移动${ctx.pathDotMotionTimingMs()}ms`)
}

// 向后兼容的旧调用点别名。
export async function driveAutoStep(ctx: any, nowMs: number, force: boolean = false): Promise<void> {
  await followPathOnce(ctx, nowMs, force)
}


