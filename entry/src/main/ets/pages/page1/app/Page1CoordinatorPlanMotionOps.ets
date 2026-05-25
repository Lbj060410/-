/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorPlanMotionOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorPlanMotionOps.ets
 * 用途： 封装规划与运动阶段联动逻辑，连接调度器与运动播放器。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'
import { GridIdCodec, PathPlannerAStar } from './PathPlannerAStar'
import { IPage1CoordinatorOps, P1C, SegmentPlanDecision, SegmentPoseMatch } from './Page1CoordinatorDefs'
import { videoStore } from '../../../state/VideoStore'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'
import { VehicleMotionHooks } from './VehicleMotionPlayer'
import { VehicleActionSchedulerDeps } from './VehicleActionScheduler'
import { animateMapPoseTransition } from './Page1CoordinatorMapObstacleOps'

function shouldEnableTrafficBySegment(fromId: string, toId: string): boolean {
  const from: string = fromId.trim().toUpperCase()
  const to: string = toId.trim().toUpperCase()
  return from === 'B4' && to === 'B6'
}

function shouldEnableTrafficByPoseAtB4(ctx: IPage1CoordinatorOps): boolean {
  const s = ctx.store
  if (!s) return false
  const curId: string = s.currentSnapNodeId.trim().toUpperCase()
  if (curId !== 'B4') return false
  if (typeof ctx.segmentHeadingDeg !== 'function') return false
  const desiredHeadingDeg: number = ctx.segmentHeadingDeg('B4', 'B6')
  const rawHeadingDeg: number = Number(ctx.logicalHeadingDeg) || 0
  const currentHeadingDeg: number = typeof ctx.normToCardinal === 'function'
    ? ctx.normToCardinal(rawHeadingDeg)
    : (Math.round(rawHeadingDeg / 90) % 4) * 90
  return currentHeadingDeg === desiredHeadingDeg
}

function syncRecognitionBySegment(fromId: string, toId: string): void {
  const trafficEnabled: boolean = shouldEnableTrafficBySegment(fromId, toId)
  if (trafficEnabled) {
    videoStore.setPage2TrafficEnabled(false)
  } else {
    videoStore.setPage2Yolov26BarrierEnabled(false)
  }
}

function syncRecognitionByPathCursor(ctx: IPage1CoordinatorOps): void {
  const s = ctx.store
  if (!s) return
  if (shouldEnableTrafficByPoseAtB4(ctx)) {
    videoStore.setRecognitionEnabled(false)
    videoStore.setPage2TrafficEnabled(false)
    return
  }
  if (s.pathNodes.length <= 1) {
    videoStore.setRecognitionEnabled(false)
    videoStore.setPage2Yolov26BarrierEnabled(false)
    return
  }
  const idx: number = s.pathIndex
  if (idx < 0 || idx >= s.pathNodes.length - 1) {
    videoStore.setRecognitionEnabled(false)
    videoStore.setPage2Yolov26BarrierEnabled(false)
    return
  }
  const fromId: string = s.pathNodes[idx]
  const toId: string = s.pathNodes[idx + 1]
  syncRecognitionBySegment(fromId, toId)
}

export function motionHooks(ctx: IPage1CoordinatorOps): VehicleMotionHooks {
  return {
    findNode: (id: string) => ctx.findNode(id),
    updatePoseAndTelemetryForDisplay: (xNorm: number, yNorm: number, headingDeg: number, speed: number): void => {
      ctx.updatePoseAndTelemetryForDisplay(xNorm, yNorm, headingDeg, speed)
    },
    updateHeadingOnlyAtCurrentPose: (headingDeg: number): void => {
      ctx.updateHeadingOnlyAtCurrentPose(headingDeg)
    },
    segmentHeadingDeg: (fromId: string, toId: string): number => ctx.segmentHeadingDeg(fromId, toId),
    getLogicalHeadingDeg: (): number => ctx.logicalHeadingDeg,
    setLogicalHeadingDeg: (headingDeg: number): void => {
      ctx.logicalHeadingDeg = headingDeg
      ctx.logicalHeadingInited = true
    },
    maybeHandleMotionArrive: async (toId: string): Promise<void> => {
      await ctx.maybeHandleMotionArrive(toId)
    },
    headingErrorDeg: (curDeg: number, desiredDeg: number): number => ctx.headingErrorDeg(curDeg, desiredDeg),
    norm360: (v: number): number => ctx.norm360(v)
  }
}

export function schedulerDeps(ctx: IPage1CoordinatorOps): VehicleActionSchedulerDeps {
  return {
    sendDriveActionDirect: async (a: Page1Action): Promise<boolean> => {
      return await ctx.sendDriveActionDirect(a)
    },
    motionPlayer: ctx.motionPlayer,
    timingRegistry: ctx.timingRegistry,
    motionHooks: motionHooks(ctx)
  }
}

export async function maybeHandleMotionArrive(ctx: IPage1CoordinatorOps, toId: string): Promise<void> {
  const s = ctx.store
  if (!s) return
  s.currentSnapNodeId = toId
  syncRecognitionByPathCursor(ctx)
  s.stepNextNode()
  syncRecognitionByPathCursor(ctx)
  ctx.uploadTrajectoryNode(toId)

  s.pushLog(`ARRIVE: ${toId} via MOTION | pathIndex=${s.pathIndex}`)

  if (s.pathNodes.length > 0 && s.pathIndex >= s.pathNodes.length - 1) {
    await ctx.sendDriveActionDirect(Page1Action.STOP)
    s.setAction('到达终点，停止')
    replayArchiveService.closeActive('到达终点')
    return
  }
}

function transitionDurationMsBySegment(seg: SegmentPoseMatch, targetId: string): number {
  const remainRatio: number = targetId === seg.aId ? seg.t : (1 - seg.t)
  const clamped: number = Math.max(0.12, Math.min(1.0, remainRatio))
  return Math.max(P1C.MAP_PREVIEW_TICK_MS * 2, Math.round(P1C.PATH_DOT_MOTION_MS * clamped))
}

async function tryAnimateDryReplanToSegmentEndpoint(
  ctx: IPage1CoordinatorOps,
  goal: string,
  token: number
): Promise<void> {
  const s = ctx.store
  if (!s) return
  if (s.realSendEnabled) return
  if (!s.segPlannerEnabled) {
    s.pushLog('REPLAN_TRANSITION_SKIP: segPlanner disabled')
    return
  }

  const helperCtx = ctx as unknown as {
    findNearestRouteSegmentByPose?: () => SegmentPoseMatch | undefined
    chooseSegmentEndpointForGoal?: (
      seg: SegmentPoseMatch,
      goal: string,
      blocked: Array<string>,
      blockedEdges: Array<string>
    ) => SegmentPlanDecision | undefined
  }
  const findSeg = helperCtx.findNearestRouteSegmentByPose
  const chooseEndpoint = helperCtx.chooseSegmentEndpointForGoal
  if (typeof findSeg !== 'function' || typeof chooseEndpoint !== 'function') {
    s.pushLog('REPLAN_TRANSITION_SKIP: helper unavailable')
    return
  }

  const seg: SegmentPoseMatch | undefined = findSeg.call(helperCtx)
  if (!seg) {
    s.pushLog('REPLAN_TRANSITION_SKIP: no nearest segment')
    return
  }
  const minT: number = ctx.segMidMinTValue(s)
  const maxT: number = ctx.segMidMaxTValue(s)
  if (seg.t <= minT || seg.t >= maxT) {
    s.pushLog(`REPLAN_TRANSITION_SKIP: t=${seg.t.toFixed(2)} out of mid-range`)
    return
  }

  const decision: SegmentPlanDecision | undefined = chooseEndpoint.call(
    helperCtx,
    seg,
    goal,
    s.blockedNodes,
    s.blockedEdges
  )
  if (!decision) {
    s.pushLog('REPLAN_TRANSITION_SKIP: no endpoint decision')
    return
  }

  const target = ctx.findNode(decision.targetId)
  if (!target) {
    s.pushLog(`REPLAN_TRANSITION_SKIP: target missing ${decision.targetId}`)
    return
  }
  const state = ctx as unknown as { replanTransitionToken: number }
  if (state.replanTransitionToken !== token) return

  const currentHeadingDeg: number = ctx.norm360(s.pose.headingDeg)
  const retreatHeadingDeg: number = ctx.headingDegFromTo(seg.px, seg.py, target.xNorm, target.yNorm)
  const durationMs: number = transitionDurationMsBySegment(seg, decision.targetId)
  const mapToken: number = ctx.beginMapPoseAnimation()

  s.pushLog(`REPLAN_TRANSITION: ${decision.fromId}->${decision.targetId} t=${seg.t.toFixed(2)} retreat=${durationMs}ms`)
  await animateMapPoseTransition(
    ctx,
    seg.px,
    seg.py,
    target.xNorm,
    target.yNorm,
    currentHeadingDeg,
    retreatHeadingDeg,
    -20,
    durationMs,
    mapToken
  )
  if (state.replanTransitionToken !== token) return

  s.currentSnapNodeId = decision.targetId
  s.poseInited = true
  s.lastAutoFollowAtMs = Date.now()
  ctx.logicalHeadingDeg = ctx.normToCardinal(retreatHeadingDeg)
  ctx.logicalHeadingInited = true
  ctx.updatePoseAndTelemetryForDisplay(target.xNorm, target.yNorm, retreatHeadingDeg, 0)
}

function applyPlannedPath(ctx: IPage1CoordinatorOps, goal: string): void {
  const s = ctx.store
  if (!s) return
  const oldPath: Array<string> = s.pathNodes.slice()
  videoStore.setRecognitionEnabled(false)
  videoStore.setPage2Yolov26BarrierEnabled(false)
  ctx.resetGarageFlowState()

  ctx.clearAheadVisionReplanState()
  ctx.cancelParkingSequence()
  ctx.stopActiveMotion()
  ctx.resetRouteVoiceFlags()

  if (goal.length === 0) {
    s.setPath([], '空目标')
    return
  }
  if (!GridIdCodec.isValidId(goal)) {
    s.setPath([], '非法目标')
    s.pushLog(`A*: 目标非法 dest=${goal}（期望黑线路网节点，如 A2 / D4 / G6）`)
    return
  }

  const start: string = ctx.resolveStartNodeId()
  if (!GridIdCodec.isValidId(start)) {
    s.setPath([], '起点非法')
    s.pushLog(`A*: 起点非法 start=${start}`)
    return
  }
  if (typeof ctx.setTrajectoryPlanEndpoints === 'function') {
    ctx.setTrajectoryPlanEndpoints(start, goal)
  }

  // 小车已内置 A*：上位机仍做一次本地 A*，仅用于地图路线可视化。
  const blocked: Array<string> = s.blockedNodes
  const blockedEdges: Array<string> = s.blockedEdges
  const helperCtx = ctx as unknown as {
    tryBuildSegmentAwarePath?: (goal: string, blocked: Array<string>, blockedEdges: Array<string>) => Array<string> | undefined
  }
  const segPath: Array<string> | undefined =
    !s.realSendEnabled && s.segPlannerEnabled && s.poseInited && typeof helperCtx.tryBuildSegmentAwarePath === 'function'
      ? helperCtx.tryBuildSegmentAwarePath.call(helperCtx, goal, blocked, blockedEdges)
      : undefined
  const visRes = segPath ? undefined : PathPlannerAStar.plan(start, goal, blocked, blockedEdges)
  const visualPath: Array<string> = segPath && segPath.length > 0
    ? segPath
    : (visRes && visRes.ok && visRes.path && visRes.path.length > 0)
      ? visRes.path
      : [start, goal]
  s.setPath(visualPath, 'CAR_ASTAR_VIS')
  ctx.carAstarMode = true
  replayArchiveService.onPathReplanned(oldPath, visualPath, 'CAR_ASTAR_VIS')
  s.currentSnapNodeId = start
  syncRecognitionByPathCursor(ctx)
  ctx.uploadTrajectoryNode(start)
  s.lastAutoFollowAtMs = 0
  ctx.syncLogicalHeadingWithCurrentState()
  s.pushLog(`CAR_ASTAR: visual path ready start=${start}, goal=${goal}, len=${visualPath.length}`)
  if (ctx.canRealSend && ctx.canRealSend() && ctx.proto && typeof ctx.proto.sendGoalNode === 'function') {
    void ctx.proto.sendGoalNode(goal, true)
    s.pushLog(`CAR_ASTAR: goal sent -> ${goal}`)
  } else {
    s.pushLog(`CAR_ASTAR: DRY_RUN goal=${goal}`)
  }
}

export function planPath(ctx: IPage1CoordinatorOps, dest: string): void {
  const goal: string = dest.trim().toUpperCase()
  const state = ctx as unknown as { replanTransitionBusy: boolean, replanTransitionToken: number }
  const s = ctx.store
  if (!s) return
  state.replanTransitionToken += 1
  const token: number = state.replanTransitionToken
  state.replanTransitionBusy = true
  if (!s.realSendEnabled) {
    ctx.stopActiveMotion()
    ctx.actionScheduler.reset()
  }

  void (async (): Promise<void> => {
    try {
      await tryAnimateDryReplanToSegmentEndpoint(ctx, goal, token)
      if (state.replanTransitionToken !== token) return
      applyPlannedPath(ctx, goal)
    } finally {
      if (state.replanTransitionToken === token) {
        state.replanTransitionBusy = false
      }
    }
  })()
}
