import { Page1Action } from '../types/Page1Types'
import { GridIdCodec, PathPlannerAStar } from './PathPlannerAStar'

export class Page1PathCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  resolveStartNodeId(): string {
    const s = this.ctx.store
    if (!s) return 'D4'
    const snap = s.currentSnapNodeId.trim().toUpperCase()
    if (snap.length > 0 && GridIdCodec.isValidId(snap)) return snap
    const near = this.ctx.nearestNodeIdByPose()
    if (near.length > 0 && GridIdCodec.isValidId(near)) return near
    return 'D4'
  }

  isParkingInnerRowNode(id: string): boolean {
    const p = GridIdCodec.parse(id)
    if (!p) return false
    return p.row === 0
  }

  isInsideGateInnerSideNode(id: string): boolean {
    const p = GridIdCodec.parse(id)
    if (!p) return false
    return p.row <= 1
  }

  private rowLabelByIndex(rowIndex: number): number {
    if (rowIndex === 0) return 1
    if (rowIndex === 1) return 2
    if (rowIndex === 2) return 4
    if (rowIndex === 3) return 6
    if (rowIndex === 4) return 7
    return -1
  }

  private isUpperZoneById(id: string): boolean {
    const p = GridIdCodec.parse(id)
    if (!p) return false
    const rowLabel: number = this.rowLabelByIndex(p.row)
    return rowLabel === 1 || rowLabel === 2
  }

  private isLowerZoneById(id: string): boolean {
    const p = GridIdCodec.parse(id)
    if (!p) return false
    const rowLabel: number = this.rowLabelByIndex(p.row)
    return rowLabel === 4 || rowLabel === 6 || rowLabel === 7
  }

  gateForcedWaypoint(startId: string, goalId: string): string {
    const startUpper: boolean = this.isUpperZoneById(startId)
    const goalUpper: boolean = this.isUpperZoneById(goalId)
    const startLower: boolean = this.isLowerZoneById(startId)
    const goalLower: boolean = this.isLowerZoneById(goalId)
    if (startUpper && goalLower) return 'B2'
    if (startLower && goalUpper) return 'B4'
    return ''
  }

  buildPathViaWaypoint(
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
    for (let i: number = 0; i < leg1.path.length; i++) out.push(leg1.path[i])
    for (let i: number = 0; i < leg2.path.length; i++) {
      const id = leg2.path[i]
      if (out.length > 0 && out[out.length - 1] === id) continue
      out.push(id)
    }
    return { ok: true, reason: 'ok', path: out }
  }

  syncLogicalHeadingWithCurrentState(): void {
    const s = this.ctx.store
    if (!s) return
    this.ctx.logicalHeadingDeg = this.normToCardinal(s.pose.headingDeg)
    this.ctx.logicalHeadingInited = true
  }

  segmentHeadingDeg(fromId: string, toId: string): number {
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

  normToCardinal(v: number): number {
    const x = this.ctx.norm360(v)
    const idx = Math.round(x / 90) % 4
    return idx * 90
  }

  actionForHeadingTransition(curDeg: number, desiredDeg: number): Page1Action | undefined {
    const c: number = this.normToCardinal(curDeg)
    const d: number = this.normToCardinal(desiredDeg)
    const err: number = this.ctx.headingErrorDeg(c, d)
    if (err === 0) return undefined
    if (Math.abs(err) === 180) return Page1Action.UTURN
    if (err > 0) return Page1Action.RIGHT
    return Page1Action.LEFT
  }

  predictActionForPair(curHeadingDeg: number, fromId: string, toId: string): Page1Action {
    const desired: number = this.segmentHeadingDeg(fromId, toId)
    const turn: Page1Action | undefined = this.actionForHeadingTransition(curHeadingDeg, desired)
    if (turn !== undefined) return turn
    return Page1Action.GO
  }

  predictedHeadingAfterAction(curHeadingDeg: number, action: Page1Action, fromId: string, toId: string): number {
    const isTurn: boolean =
      action === Page1Action.LEFT ||
      action === Page1Action.RIGHT ||
      action === Page1Action.UTURN
    if (isTurn || action === Page1Action.GO || action === Page1Action.BACK) {
      return this.segmentHeadingDeg(fromId, toId)
    }
    return curHeadingDeg
  }

  peekNextActionAfterCurrentStep(): Page1Action | undefined {
    const s = this.ctx.store
    if (!s) return undefined
    const curIndex: number = s.pathIndex
    if (curIndex + 2 >= s.pathNodes.length) return undefined
    const fromId: string = s.pathNodes[curIndex]
    const toId: string = s.pathNodes[curIndex + 1]
    const nextId: string = s.pathNodes[curIndex + 2]
    const first: Page1Action = this.predictActionForPair(this.ctx.logicalHeadingDeg, fromId, toId)
    const headingAfterFirst: number = this.predictedHeadingAfterAction(this.ctx.logicalHeadingDeg, first, fromId, toId)
    return this.predictActionForPair(headingAfterFirst, toId, nextId)
  }

  canSendNextCommand(nowMs: number): boolean {
    const snap = this.ctx.actionScheduler.snapshot(nowMs, this.ctx.motionRunning())
    this.ctx.lastSchedulerSnapshot = snap
    return snap.canSend
  }

  async sendAutoActionWithTiming(
    action: Page1Action,
    fromId: string,
    toId: string,
    nextAction?: Page1Action,
    customTiming?: { activeMs: number },
    advancePathOnFinish?: boolean,
    useReverseSpeed?: boolean,
    customLogTag?: string
  ): Promise<boolean> {
    const sent: boolean = await this.ctx.driveAckCoordinator.sendDriveActionDirect(action)
    if (!sent) return false
    const req = {
      action: action,
      fromId: fromId,
      toId: toId,
      nextAction: nextAction,
      motionMs: this.ctx.driveAckCoordinator.pathDotMotionTimingMs(customTiming ? customTiming.activeMs : undefined),
      advancePathOnFinish: advancePathOnFinish === true,
      useReverseSpeed: useReverseSpeed === true,
      customLogTag: customLogTag ? customLogTag : ''
    }
    if (this.ctx.driveAckCoordinator.isPathMotionAction(action) && this.ctx.pathAckAwaitingComplete) {
      this.ctx.driveAckCoordinator.stageMotionWaitAckComplete(req)
    } else {
      this.ctx.driveAckCoordinator.startMotionNow(req)
    }
    return true
  }

  async followPathOnce(nowMs: number, force: boolean = false): Promise<void> {
    const s = this.ctx.store
    if (!s) return
    if (force) s.pushLog(`AUTO_FIRST: follow enter idx=${s.pathIndex} len=${s.pathNodes.length}`)
    if (this.ctx.maybeHandleAheadVisionReplan(nowMs)) {
      if (force) s.pushLog('AUTO_FIRST: blocked by ahead-vision replan')
      return
    }
    if (nowMs < this.ctx.pauseUntilMs) {
      if (force) s.pushLog(`AUTO_FIRST: blocked by pause now=${nowMs} until=${this.ctx.pauseUntilMs}`)
      return
    }
    if (this.ctx.parkingInProgress) {
      if (force) s.pushLog('AUTO_FIRST: blocked by parkingInProgress')
      return
    }
    if (this.ctx.gateDepartInProgress) {
      if (force) s.pushLog('AUTO_FIRST: blocked by gateDepartInProgress')
      return
    }
    if (this.ctx.motionRunning()) {
      if (force) s.pushLog('AUTO_FIRST: blocked by motionRunning')
      return
    }
    if (s.pathNodes.length > 0 && s.pathIndex >= s.pathNodes.length - 1) {
      if (!this.canSendNextCommand(nowMs)) {
        if (force) s.pushLog('AUTO_FIRST: at-end STOP blocked by scheduler')
        return
      }
      s.markAutoFollow(nowMs)
      await this.ctx.driveAckCoordinator.sendDriveActionDirect(Page1Action.STOP)
      s.setAction('Arrived at destination, stop')
      return
    }
    if (!s.autoFollowEnabled && !force) return
    if (!force) {
      if (!s.canAutoFollow(nowMs)) return
    } else {
      if (s.obstacleEditEnabled) {
        s.pushLog('AUTO_FIRST: blocked by obstacleEditEnabled')
        return
      }
      if (s.pathNodes.length <= 1) {
        s.pushLog('AUTO_FIRST: blocked by pathNodes<=1')
        return
      }
      if (s.pathIndex >= s.pathNodes.length - 1) {
        s.pushLog(`AUTO_FIRST: blocked by idx end idx=${s.pathIndex} len=${s.pathNodes.length}`)
        return
      }
    }
    if (await this.ctx.maybeHandleGarageDepartBeforeDrive(nowMs)) {
      if (force) s.pushLog('AUTO_FIRST: consumed by garageDepart flow')
      s.markAutoFollow(nowMs)
      return
    }
    if (!this.canSendNextCommand(nowMs)) {
      if (force) s.pushLog('AUTO_FIRST: blocked by scheduler canSendNextCommand=false')
      return
    }
    const idx: number = s.pathIndex
    const fromId: string = s.pathNodes[idx]
    const toId: string = s.pathNodes[idx + 1]
    const gateEdge: boolean =
      (fromId.trim().toUpperCase() === 'B2' && toId.trim().toUpperCase() === 'B4') ||
      (fromId.trim().toUpperCase() === 'B4' && toId.trim().toUpperCase() === 'B2')
    if (gateEdge) {
      const handledGateDepartBeforeGo: boolean = await this.ctx.maybeHandleGateDepartOnArrival(fromId)
      if (force) s.pushLog(`AUTO_FIRST: gateEdge ${fromId}->${toId} handled=${handledGateDepartBeforeGo ? 1 : 0}`)
      if (!handledGateDepartBeforeGo) s.pushLog(`GATE_DEPART_GUARD: ${fromId}->${toId} blocked normal go`)
      s.markAutoFollow(nowMs)
      return
    }
    if ((s.isBlocked(toId) || s.isBlockedEdge(fromId, toId)) && s.destApplied.length > 0) {
      if (force) s.pushLog(`AUTO_FIRST: blocked by obstacle edge=${fromId}->${toId}, replan`)
      this.ctx.maybeReplanOnObstacle()
      s.markAutoFollow(nowMs)
      return
    }
    if (!this.ctx.logicalHeadingInited) this.syncLogicalHeadingWithCurrentState()
    if (idx === 0 && !this.ctx.routeStartVoicePlayed) {
      await this.ctx.maybePlayRouteStartVoice()
      if (!force) return
      s.pushLog('AUTO_FIRST: voice branch done, continue because force=1')
    }
    const desiredHeadingDeg: number = this.segmentHeadingDeg(fromId, toId)
    let turnAction: Page1Action | undefined = this.actionForHeadingTransition(this.ctx.logicalHeadingDeg, desiredHeadingDeg)
    if (force) {
      const turnName: string = turnAction !== undefined ? Page1Action[turnAction] : 'GO_DIRECT'
      s.pushLog(`AUTO_FIRST: heading cur=${this.ctx.logicalHeadingDeg} desired=${desiredHeadingDeg} turn=${turnName}`)
    }
    if (turnAction === Page1Action.UTURN && idx === 0 && this.ctx.isReverseParkingGoal(fromId)) {
      turnAction = undefined
      s.pushLog(`PARK_DEPART: ${fromId}->${toId} suppress UTURN on first segment`)
    }
    if (turnAction !== undefined) {
      if (force) s.pushLog(`AUTO_FIRST: first action TURN=${Page1Action[turnAction]}`)
      const sentTurn: boolean = await this.sendAutoActionWithTiming(
        turnAction, fromId, toId, Page1Action.GO, undefined, false, false, 'TURN_ONLY'
      )
      if (!sentTurn) {
        if (force) s.pushLog('AUTO_FIRST: TURN send failed')
        return
      }
      s.markAutoFollow(nowMs)
      let turnText: string = '杞悜'
      if (turnAction === Page1Action.LEFT) turnText = '宸﹁浆'
      else if (turnAction === Page1Action.RIGHT) turnText = '鍙宠浆'
      else if (turnAction === Page1Action.UTURN) turnText = '鎺夊ご'
      s.setAction(`鑷姩杞悜=${turnText}`)
      s.pushLog(`TURN_ONLY: ${fromId} -> ${toId} | sent, wait BD=02 before dot turn`)
      return
    }
    if (force) s.pushLog('AUTO_FIRST: before maybeStartAheadVisionReplan')
    let startedAheadVisionReplan: boolean = false
    try {
      startedAheadVisionReplan = this.ctx.maybeStartAheadVisionReplan(fromId, toId, nowMs)
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : `${e}`
      s.pushLog(`AUTO_FIRST: exception in maybeStartAheadVisionReplan: ${msg}`)
      return
    }
    if (startedAheadVisionReplan) {
      if (force) s.pushLog(`AUTO_FIRST: consumed by ahead-vision start replan edge=${fromId}->${toId}`)
      s.markAutoFollow(nowMs)
      return
    }
    if (force) s.pushLog('AUTO_FIRST: before peekNextActionAfterCurrentStep')
    let nextActionAfterGo: Page1Action | undefined = undefined
    try {
      nextActionAfterGo = this.peekNextActionAfterCurrentStep()
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : `${e}`
      s.pushLog(`AUTO_FIRST: exception in peekNextActionAfterCurrentStep: ${msg}`)
      return
    }
    if (force) s.pushLog(`AUTO_FIRST: peekNextActionAfterCurrentStep ok next=${nextActionAfterGo !== undefined ? Page1Action[nextActionAfterGo] : 'NONE'}`)
    let sentGo: boolean = false
    try {
      sentGo = await this.sendAutoActionWithTiming(
        Page1Action.GO, fromId, toId, nextActionAfterGo, undefined, true, false, 'SEGMENT_START'
      )
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : `${e}`
      s.pushLog(`AUTO_FIRST: exception while sending GO: ${msg}`)
      return
    }
    if (!sentGo) {
      if (force) s.pushLog(`AUTO_FIRST: GO send failed edge=${fromId}->${toId}`)
      return
    }
    if (force) s.pushLog(`AUTO_FIRST: GO send ok edge=${fromId}->${toId}`)
    s.markAutoFollow(nowMs)
    s.pushLog(`SEGMENT_START: ${fromId} -> ${toId} | sent, wait BD=02 then move dot ${this.ctx.driveAckCoordinator.pathDotMotionTimingMs()}ms`)
  }
}

