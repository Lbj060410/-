import { Page1Action } from '../types/Page1Types'
import { GridIdCodec, PathPlannerAStar } from './PathPlannerAStar'
import { videoStore } from '../../../state/VideoStore'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'
import { VehicleMotionHooks } from './VehicleMotionPlayer'
import { VehicleActionSchedulerDeps } from './VehicleActionScheduler'

function shouldEnableTrafficBySegment(fromId: string, toId: string): boolean {
  const from: string = fromId.trim().toUpperCase()
  const to: string = toId.trim().toUpperCase()
  return (from === 'B4' && to === 'B6') || (from === 'D6' && to === 'F6')
}

function syncRecognitionBySegment(fromId: string, toId: string): void {
  const trafficEnabled: boolean = shouldEnableTrafficBySegment(fromId, toId)
  videoStore.setRecognitionEnabled(true)
  if (trafficEnabled) videoStore.setPage2TrafficEnabled(true)
  else videoStore.setPage2Yolov26BarrierEnabled(true)
}

export class Page1PlanMotionCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  private syncRecognitionByPathCursor(): void {
    const s = this.ctx.store
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
    syncRecognitionBySegment(s.pathNodes[idx], s.pathNodes[idx + 1])
  }

  motionHooks(): VehicleMotionHooks {
    return {
      findNode: (id: string): any => this.ctx.findNode(id),
      updatePoseAndTelemetryForDisplay: (xNorm: number, yNorm: number, headingDeg: number, speed: number): void => {
        this.ctx.updatePoseAndTelemetryForDisplay(xNorm, yNorm, headingDeg, speed)
      },
      updateHeadingOnlyAtCurrentPose: (headingDeg: number): void => {
        this.ctx.updateHeadingOnlyAtCurrentPose(headingDeg)
      },
      segmentHeadingDeg: (fromId: string, toId: string): number => this.ctx.pathCoordinator.segmentHeadingDeg(fromId, toId),
      getLogicalHeadingDeg: (): number => this.ctx.logicalHeadingDeg,
      setLogicalHeadingDeg: (headingDeg: number): void => {
        this.ctx.logicalHeadingDeg = headingDeg
        this.ctx.logicalHeadingInited = true
      },
      maybeHandleMotionArrive: async (toId: string): Promise<void> => {
        await this.maybeHandleMotionArrive(toId)
      },
      headingErrorDeg: (curDeg: number, desiredDeg: number): number => this.ctx.headingErrorDeg(curDeg, desiredDeg),
      norm360: (v: number): number => this.ctx.norm360(v)
    } as VehicleMotionHooks
  }

  schedulerDeps(): VehicleActionSchedulerDeps {
    return {
      sendDriveActionDirect: async (a: Page1Action): Promise<boolean> => {
        return await this.ctx.driveAckCoordinator.sendDriveActionDirect(a)
      },
      motionPlayer: this.ctx.motionPlayer,
      timingRegistry: this.ctx.timingRegistry,
      motionHooks: this.motionHooks()
    } as VehicleActionSchedulerDeps
  }

  async maybeHandleMotionArrive(toId: string): Promise<void> {
    const s = this.ctx.store
    if (!s) return
    s.currentSnapNodeId = toId
    this.syncRecognitionByPathCursor()
    s.stepNextNode()
    this.syncRecognitionByPathCursor()
    this.ctx.uploadTrajectoryNode(toId)

    const fromId: string = this.ctx.motionPlayer.currentFromId()
    s.pushLog(`ARRIVE: ${toId} via MOTION | pathIndex=${s.pathIndex}`)

    const handledGateDepart: boolean = await this.ctx.maybeHandleGateDepartOnArrival(toId)
    if (handledGateDepart) return
    const handledEdgeParking: boolean = await this.ctx.maybeRunParkingBeforeFinalEdgeArrival(toId)
    if (handledEdgeParking) return
    const handledNormalParking: boolean = await this.ctx.maybeRunNormalFinalParkingAfterArrival(fromId, toId)
    if (handledNormalParking) return

    if (s.pathNodes.length > 0 && s.pathIndex >= s.pathNodes.length - 1) {
      await this.ctx.maybeHandleGarageFinalArrive(toId)
      if (!this.ctx.pathCoordinator.canSendNextCommand(Date.now())) return
      await this.ctx.driveAckCoordinator.sendDriveActionDirect(Page1Action.STOP)
      s.setAction('到达终点，停止')
      replayArchiveService.closeActive('到达终点')
      return
    }
    await this.ctx.pathCoordinator.followPathOnce(Date.now(), true)
  }

  planPath(dest: string): void {
    const s = this.ctx.store
    if (!s) return
    const oldPath: Array<string> = s.pathNodes.slice()
    videoStore.setRecognitionEnabled(true)
    videoStore.setPage2Yolov26BarrierEnabled(true)
    this.ctx.resetGarageFlowState()

    this.ctx.clearAheadVisionReplanState()
    this.ctx.cancelParkingSequence()
    this.ctx.stopActiveMotion()
    this.ctx.resetGateDepartDedupState()
    this.ctx.resetRouteVoiceFlags()
    this.ctx.resetPathAckState()

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

    const start: string = this.ctx.pathCoordinator.resolveStartNodeId()
    if (!GridIdCodec.isValidId(start)) {
      s.setPath([], '起点非法')
      s.pushLog(`A*: 起点非法 start=${start}`)
      return
    }

    const blocked: Array<string> = s.blockedNodes
    const blockedEdges: Array<string> = s.blockedEdges
    const gateVia: string = this.ctx.pathCoordinator.gateForcedWaypoint(start, goal)
    if (gateVia.length > 0) {
      const gateRes: any = this.ctx.pathCoordinator.buildPathViaWaypoint(start, gateVia, goal, blocked, blockedEdges)
      if (!gateRes.ok) {
        s.setPath([], 'A*闸口失败')
        s.pushLog(`A*: GATE FAIL reason=${gateRes.reason} start=${start} via=${gateVia} goal=${goal}`)
        return
      }
      s.setPath(gateRes.path, 'A*GATE')
      replayArchiveService.onPathReplanned(oldPath, gateRes.path, 'A*GATE')
      s.currentSnapNodeId = start
      this.syncRecognitionByPathCursor()
      this.ctx.uploadTrajectoryNode(start)
      s.lastAutoFollowAtMs = 0
      this.ctx.pathCoordinator.syncLogicalHeadingWithCurrentState()
      s.pushLog(`A*: GATE ${start} -> ${goal} via=${gateVia} | len=${gateRes.path.length} blockedN=${blocked.length} blockedE=${blockedEdges.length}`)
      if (s.pathIndex >= s.pathNodes.length - 1) {
        void this.ctx.driveAckCoordinator.sendDriveActionDirect(Page1Action.STOP)
        s.setAction('到达终点，停止')
      }
      return
    }

    const segPath: Array<string> | undefined = this.ctx.tryBuildSegmentAwarePath(goal, blocked, blockedEdges)
    if (segPath && segPath.length > 0) {
      s.setPath(segPath, 'A*SEG')
      replayArchiveService.onPathReplanned(oldPath, segPath, 'A*SEG')
      const near: string = this.ctx.nearestNodeIdByPose()
      s.currentSnapNodeId = GridIdCodec.isValidId(near) ? near : segPath[0]
      this.syncRecognitionByPathCursor()
      this.ctx.uploadTrajectoryNode(s.currentSnapNodeId)
      s.lastAutoFollowAtMs = 0
      this.ctx.pathCoordinator.syncLogicalHeadingWithCurrentState()
      s.pushLog(`A*: SEG -> ${goal} | len=${segPath.length} blockedN=${blocked.length} blockedE=${blockedEdges.length}`)
      if (s.pathIndex >= s.pathNodes.length - 1) {
        void this.ctx.driveAckCoordinator.sendDriveActionDirect(Page1Action.STOP)
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
    this.syncRecognitionByPathCursor()
    this.ctx.uploadTrajectoryNode(start)
    s.lastAutoFollowAtMs = 0
    this.ctx.pathCoordinator.syncLogicalHeadingWithCurrentState()
    s.pushLog(`A*: ${start} -> ${goal} | len=${res.path.length} blockedN=${blocked.length} blockedE=${blockedEdges.length}`)
    if (s.pathIndex >= s.pathNodes.length - 1) {
      void this.ctx.driveAckCoordinator.sendDriveActionDirect(Page1Action.STOP)
      s.setAction('到达终点，停止')
    }
  }
}
