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
import { videoStore } from '../../../state/VideoStore'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'

function shouldEnableTrafficBySegment(fromId: string, toId: string): boolean {
  const from: string = fromId.trim().toUpperCase()
  const to: string = toId.trim().toUpperCase()
  return (from === 'B4' && to === 'B6') || (from === 'D6' && to === 'F6')
}

function syncRecognitionBySegment(fromId: string, toId: string): void {
  const trafficEnabled: boolean = shouldEnableTrafficBySegment(fromId, toId)
  videoStore.setRecognitionEnabled(true)
  if (trafficEnabled) {
    videoStore.setPage2TrafficEnabled(true)
  } else {
    videoStore.setPage2Yolov26BarrierEnabled(true)
  }
}

function syncRecognitionByPathCursor(ctx: any): void {
  const s = ctx.store
  if (!s) return
  if (s.pathNodes.length <= 1) {
    videoStore.setRecognitionEnabled(true)
    videoStore.setPage2Yolov26BarrierEnabled(true)
    return
  }
  const idx: number = s.pathIndex
  if (idx < 0 || idx >= s.pathNodes.length - 1) {
    videoStore.setRecognitionEnabled(true)
    videoStore.setPage2Yolov26BarrierEnabled(true)
    return
  }
  const fromId: string = s.pathNodes[idx]
  const toId: string = s.pathNodes[idx + 1]
  syncRecognitionBySegment(fromId, toId)
}

export function motionHooks(ctx: any): any {
  return {
    findNode: (id: string): any => ctx.findNode(id),
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

export function schedulerDeps(ctx: any): any {
  return {
    sendDriveActionDirect: async (a: Page1Action): Promise<boolean> => {
      return await ctx.sendDriveActionDirect(a)
    },
    motionPlayer: ctx.motionPlayer,
    timingRegistry: ctx.timingRegistry,
    motionHooks: motionHooks(ctx)
  }
}

export async function maybeHandleMotionArrive(ctx: any, toId: string): Promise<void> {
  const s = ctx.store
  if (!s) return
  s.currentSnapNodeId = toId
  syncRecognitionByPathCursor(ctx)
  s.stepNextNode()
  syncRecognitionByPathCursor(ctx)
  ctx.uploadTrajectoryNode(toId)

  const fromId: string = ctx.motionPlayer.currentFromId()
  s.pushLog(`ARRIVE: ${toId} via MOTION | pathIndex=${s.pathIndex}`)

  const handledGateDepart: boolean = await ctx.maybeHandleGateDepartOnArrival(toId)
  if (handledGateDepart) return
  const handledEdgeParking: boolean = await ctx.maybeRunParkingBeforeFinalEdgeArrival(toId)
  if (handledEdgeParking) return
  const handledNormalParking: boolean = await ctx.maybeRunNormalFinalParkingAfterArrival(fromId, toId)
  if (handledNormalParking) return

  if (s.pathNodes.length > 0 && s.pathIndex >= s.pathNodes.length - 1) {
    await ctx.maybeHandleGarageFinalArrive(toId)
    if (!ctx.canSendNextCommand(Date.now())) return
    await ctx.sendDriveActionDirect(Page1Action.STOP)
    s.setAction('到达终点，停止')
    replayArchiveService.closeActive('到达终点')
    return
  }

  // 收到上一段 BD=02 并完成到点后，立即尝试下发下一步指令。
  await ctx.followPathOnce(Date.now(), true)
}

export function planPath(ctx: any, dest: string): void {
  const s = ctx.store
  if (!s) return
  const oldPath: Array<string> = s.pathNodes.slice()
  videoStore.setRecognitionEnabled(true)
  videoStore.setPage2Yolov26BarrierEnabled(true)
  ctx.resetGarageFlowState()

  ctx.clearAheadVisionReplanState()
  ctx.cancelParkingSequence()
  ctx.stopActiveMotion()
  ctx.resetGateDepartDedupState()
  ctx.resetRouteVoiceFlags()
  ctx.resetPathAckState()

  const goal: string = dest.trim().toUpperCase()
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

  const blocked: Array<string> = s.blockedNodes
  const blockedEdges: Array<string> = s.blockedEdges
  const gateVia: string = ctx.gateForcedWaypoint(start, goal)
  if (gateVia.length > 0) {
    const gateRes: any = ctx.buildPathViaWaypoint(start, gateVia, goal, blocked, blockedEdges)
    if (!gateRes.ok) {
      s.setPath([], 'A*闸口失败')
      s.pushLog(`A*: GATE FAIL reason=${gateRes.reason} start=${start} via=${gateVia} goal=${goal}`)
      return
    }
    s.setPath(gateRes.path, 'A*GATE')
    replayArchiveService.onPathReplanned(oldPath, gateRes.path, 'A*GATE')
    s.currentSnapNodeId = start
    syncRecognitionByPathCursor(ctx)
    ctx.uploadTrajectoryNode(start)
    s.lastAutoFollowAtMs = 0
    ctx.syncLogicalHeadingWithCurrentState()
    s.pushLog(`A*: GATE ${start} -> ${goal} via=${gateVia} | len=${gateRes.path.length} blockedN=${blocked.length} blockedE=${blockedEdges.length}`)
    if (s.pathIndex >= s.pathNodes.length - 1) {
      void ctx.sendDriveActionDirect(Page1Action.STOP)
      s.setAction('到达终点，停止')
    }
    return
  }

  const segPath: Array<string> | undefined = ctx.tryBuildSegmentAwarePath(goal, blocked, blockedEdges)
  if (segPath && segPath.length > 0) {
    s.setPath(segPath, 'A*SEG')
    replayArchiveService.onPathReplanned(oldPath, segPath, 'A*SEG')
    const near: string = ctx.nearestNodeIdByPose()
    s.currentSnapNodeId = GridIdCodec.isValidId(near) ? near : segPath[0]
    syncRecognitionByPathCursor(ctx)
    ctx.uploadTrajectoryNode(s.currentSnapNodeId)
    s.lastAutoFollowAtMs = 0
    ctx.syncLogicalHeadingWithCurrentState()
    s.pushLog(`A*: SEG -> ${goal} | len=${segPath.length} blockedN=${blocked.length} blockedE=${blockedEdges.length}`)
    if (s.pathIndex >= s.pathNodes.length - 1) {
      void ctx.sendDriveActionDirect(Page1Action.STOP)
      s.setAction('到达终点，停止')
    }
    return
  }

  const res: any = PathPlannerAStar.plan(start, goal, blocked, blockedEdges)
  if (!res.ok) {
    s.setPath([], 'A*失败')
    s.pushLog(`A*: FAIL reason=${res.reason} start=${start} goal=${goal} blockedN=[${blocked.join(',')}] blockedE=[${blockedEdges.join(',')}]`)
    return
  }

  s.setPath(res.path, 'A*')
  replayArchiveService.onPathReplanned(oldPath, res.path, 'A*')
  s.currentSnapNodeId = start
  syncRecognitionByPathCursor(ctx)
  ctx.uploadTrajectoryNode(start)
  s.lastAutoFollowAtMs = 0
  ctx.syncLogicalHeadingWithCurrentState()
  s.pushLog(`A*: ${start} -> ${goal} | len=${res.path.length} blockedN=${blocked.length} blockedE=${blockedEdges.length}`)
  if (s.pathIndex >= s.pathNodes.length - 1) {
    void ctx.sendDriveActionDirect(Page1Action.STOP)
    s.setAction('到达终点，停止')
  }
}
