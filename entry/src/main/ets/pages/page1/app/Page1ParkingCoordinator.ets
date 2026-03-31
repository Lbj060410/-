import { P1C } from './Page1CoordinatorDefs'
import { RouteEdgeCodec, GridIdCodec } from './PathPlannerAStar'

export class Page1ParkingCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  cancelParkingSequence(): void {
    this.ctx.parkingSequenceToken += 1
    this.ctx.parkingInProgress = false
    this.ctx.parkingAwaitingUltrasonicDecision = false
    this.ctx.parkingAwaitingArrivedId = ''
    this.ctx.parkingAwaitingGoalId = ''
    this.ctx.parkingAwaitingRequestedAtMs = 0
    this.ctx.parkingUltrasonicDecisionBusy = false
  }

  isParkingSequenceActive(token: number): boolean {
    return this.ctx.parkingInProgress && token === this.ctx.parkingSequenceToken
  }

  tryStartParkingSequence(): number | null {
    if (this.ctx.parkingInProgress) return null
    const token: number = this.ctx.parkingSequenceToken + 1
    this.ctx.parkingSequenceToken = token
    this.ctx.parkingInProgress = true
    return token
  }

  endParkingSequence(token: number): void {
    if (token === this.ctx.parkingSequenceToken) {
      this.ctx.parkingInProgress = false
    }
  }

  private clearParkingUltrasonicDecisionContext(): void {
    this.ctx.parkingAwaitingUltrasonicDecision = false
    this.ctx.parkingAwaitingArrivedId = ''
    this.ctx.parkingAwaitingGoalId = ''
    this.ctx.parkingAwaitingRequestedAtMs = 0
    this.ctx.parkingUltrasonicDecisionBusy = false
    if (typeof this.ctx.clearParkingUltrasonicRequest === 'function') {
      this.ctx.clearParkingUltrasonicRequest()
    }
  }

  private handleParkingSlotOccupied(arrivedId: string, goalId: string, sourceTag: string = ''): void {
    const s = this.ctx.store
    if (!s) return
    const fromId: string = arrivedId.trim().toUpperCase()
    const targetGoalId: string = goalId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(fromId) || !GridIdCodec.isValidId(targetGoalId)) {
      s.pushLog(`停车位占用：上下文非法 from=${fromId} goal=${targetGoalId}`)
      this.clearParkingUltrasonicDecisionContext()
      return
    }
    if (targetGoalId !== 'B1') {
      s.pushLog(`停车位占用：忽略 goal=${targetGoalId} source=${sourceTag}`)
      this.clearParkingUltrasonicDecisionContext()
      return
    }

    if (this.ctx.isSmartParkingGoal(targetGoalId)) {
      this.ctx.garageWaitingParkDone04 = false
      this.ctx.garagePendingCarportLevel = 0
    }

    const blockedEdgeId: string = RouteEdgeCodec.normalize(fromId, targetGoalId)
    if (s.addBlockedEdgeIfAbsent(blockedEdgeId, 'PARK_SLOT_OBSTACLE')) {
      s.pushLog(`停车位障碍：封禁边 ${blockedEdgeId}`)
    }

    const fallbackGoalId: string = this.ctx.fallbackParkingGoalOnObstacle(targetGoalId).trim().toUpperCase()
    if (!GridIdCodec.isValidId(fallbackGoalId)) {
      s.pushLog(`停车位占用：备选车位非法 fallback=${fallbackGoalId} source=${sourceTag}`)
      this.clearParkingUltrasonicDecisionContext()
      return
    }

    s.destDraft = fallbackGoalId
    s.applyDest()
    s.pushLog(`停车位占用：${targetGoalId} 收到 0x01，重规划至 ${fallbackGoalId} source=${sourceTag}`)
    this.clearParkingUltrasonicDecisionContext()
    this.ctx.planPath(fallbackGoalId)
  }

  async onParkingUltrasonicResult(ultrasonicP1: number, recvAtMs: number): Promise<void> {
    const s = this.ctx.store
    if (!s) return
    if (!this.ctx.parkingAwaitingUltrasonicDecision) return
    if (this.ctx.parkingUltrasonicDecisionBusy) return
    if (recvAtMs <= 0) return
    this.ctx.parkingUltrasonicDecisionBusy = true
    const arrivedId: string = (this.ctx.parkingAwaitingArrivedId as string).trim().toUpperCase()
    const goalId: string = (this.ctx.parkingAwaitingGoalId as string).trim().toUpperCase()
    try {
      if (!GridIdCodec.isValidId(arrivedId) || !GridIdCodec.isValidId(goalId)) {
        s.pushLog(`停车超声波：忽略，等待上下文非法 from=${arrivedId} goal=${goalId}`)
        this.clearParkingUltrasonicDecisionContext()
        return
      }
      const requestAtMsRaw: number = Number(this.ctx.parkingAwaitingRequestedAtMs)
      const requestAtMs: number = Number.isFinite(requestAtMsRaw) ? requestAtMsRaw : 0
      if (requestAtMs > 0) {
        if (recvAtMs < requestAtMs) {
          s.pushLog(`停车超声波：忽略过期回包 recv=${recvAtMs} < req=${requestAtMs}`)
          return
        }
        const expireAtMs: number = requestAtMs + P1C.ULTRASONIC_RESPONSE_CONTEXT_MS
        if (recvAtMs > expireAtMs) {
          s.pushLog(`停车超声波：忽略过期回包 recv=${recvAtMs} > expire=${expireAtMs}`)
          return
        }
      }

      if (ultrasonicP1 === 0x01) {
        this.handleParkingSlotOccupied(arrivedId, goalId, 'ULTRASONIC')
        return
      }

      if (this.ctx.canRealSend() && this.ctx.pathAckAwaitingComplete) {
        const ackOk: boolean = await this.ctx.driveAckCoordinator.waitForCurrentPathAckComplete(P1C.LIGHT_QUERY_WAIT_TIMEOUT_MS, 'PARK_HANDOFF_WAIT_ACK02')
        if (!ackOk) {
          s.pushLog(`停车超声波：p1=0x${this.ctx.byteToHex(ultrasonicP1)}，ACK未完成但继续倒车入库动画`)
        }
      }

      const parkingHeadingDeg: number = this.ctx.pathCoordinator.segmentHeadingDeg(arrivedId, goalId)
      this.ctx.playMapReverseParkingAnimation(arrivedId, goalId, parkingHeadingDeg)
      s.pushLog(`停车超声波：p1=0x${this.ctx.byteToHex(ultrasonicP1)}，执行倒车入库动画`)
      this.clearParkingUltrasonicDecisionContext()
    } finally {
      this.ctx.parkingUltrasonicDecisionBusy = false
    }
  }
}
