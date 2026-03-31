import { Page1UiStore } from './Page1UiStore'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import hilog from '@ohos.hilog'
import {
  beginGarageWaitParkDone04 as beginGarageWaitParkDone04Op,
  isGarageTerminalNode as isGarageTerminalNodeOp,
  isSmartParkingGoal as isSmartParkingGoalOp,
  maybeHandleGarageDepartBeforeDrive as maybeHandleGarageDepartBeforeDriveOp,
  maybeHandleGarageFinalArrive as maybeHandleGarageFinalArriveOp,
  onGarageDepartReadyAck as onGarageDepartReadyAckOp,
  onGarageParkDone04 as onGarageParkDone04Op,
  onGateEnterAckCompleted as onGateEnterAckCompletedOp,
  sendGarageCarportAfterParkDone as sendGarageCarportAfterParkDoneOp,
  smartParkingGoalId as smartParkingGoalIdOp
} from './Page1CoordinatorGarageFlowOps'

const TEXTONE1_DOMAIN = 0xFF02
const TEXTONE1_TAG = 'textone1'

export class Page1GarageCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  resetGarageFlowState(): void {
    this.clearGarageDepartAckWatch()
    this.clearGarageCarportAckWatch()
    this.ctx.garageDepartStopSent = false
    this.ctx.garageDepartReady03 = false
    this.ctx.garageFinalCarportSent = false
    this.ctx.garageWaitingParkDone04 = false
    this.ctx.garagePendingCarportLevel = 0
    this.ctx.gateBillingRunning = false
    this.ctx.gateBillingStartAtMs = 0
    this.ctx.gateBillingElapsedMs = 0
    this.ctx.parkingAwaitingUltrasonicDecision = false
    this.ctx.parkingAwaitingArrivedId = ''
    this.ctx.parkingAwaitingGoalId = ''
    this.ctx.parkingAwaitingRequestedAtMs = 0
    this.ctx.parkingUltrasonicDecisionBusy = false
  }

  clearGarageDepartAckWatch(): void {
    if (this.ctx.garageDepartAckWatchTimerId >= 0) {
      clearTimeout(this.ctx.garageDepartAckWatchTimerId)
      this.ctx.garageDepartAckWatchTimerId = -1
    }
    this.ctx.garageDepartAckRetryCount = 0
  }

  armGarageDepartAckRetry(startId: string): void {
    if (this.ctx.garageDepartAckWatchTimerId >= 0) {
      clearTimeout(this.ctx.garageDepartAckWatchTimerId)
      this.ctx.garageDepartAckWatchTimerId = -1
    }
    this.ctx.garageDepartAckWatchTimerId = setTimeout((): void => {
      this.ctx.garageDepartAckWatchTimerId = -1
      void this.retryGarageDepartLowcarport(startId)
    }, 2000) as number
  }

  async retryGarageDepartLowcarport(startId: string): Promise<void> {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    if (this.ctx.garageDepartReady03) {
      this.clearGarageDepartAckWatch()
      return
    }
    if (!this.ctx.garageDepartStopSent) return
    if (!s.realSendEnabled || !this.ctx.canRealSend()) {
      this.armGarageDepartAckRetry(startId)
      return
    }
    if (this.ctx.garageDepartAckRetryCount >= 3) {
      const payloadText: string = 'textone1 GARAGE_DEPART retry_stop max=3 no_BC_03'
      hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
      s.pushLog(`GARAGE_DEPART: 0x19重发达上限(3)，仍未收到BC/03 start=${startId}`)
      return
    }
    if (!this.ctx.canSendMotionCommand('LOWCARPORT', 'GARAGE_DEPART_RETRY')) {
      this.armGarageDepartAckRetry(startId)
      return
    }

    this.ctx.garageDepartAckRetryCount += 1
    s.bumpTx()
    await this.ctx.proto.lowcarport()
    {
      const payloadText: string = `textone1 GARAGE_DEPART retry_send_0x19 count=${this.ctx.garageDepartAckRetryCount}`
      hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
    }
    s.pushLog(`GARAGE_DEPART: 2s未收到BC/03，重发0x19 count=${this.ctx.garageDepartAckRetryCount}`)
    this.armGarageDepartAckRetry(startId)
  }

  clearGarageCarportAckWatch(): void {
    if (this.ctx.garageCarportAckWatchTimerId >= 0) {
      clearTimeout(this.ctx.garageCarportAckWatchTimerId)
      this.ctx.garageCarportAckWatchTimerId = -1
    }
    this.ctx.garageCarportAckPending = false
    this.ctx.garageCarportAckRetryDone = false
    this.ctx.garageCarportAckPendingLevel = 0
    this.ctx.garageCarportAckSentAtMs = 0
  }

  armGarageCarportAckRetry(level: number): void {
    this.ctx.garageCarportAckPending = true
    this.ctx.garageCarportAckRetryDone = false
    this.ctx.garageCarportAckPendingLevel = level
    this.ctx.garageCarportAckSentAtMs = Date.now()

    if (this.ctx.garageCarportAckWatchTimerId >= 0) {
      clearTimeout(this.ctx.garageCarportAckWatchTimerId)
      this.ctx.garageCarportAckWatchTimerId = -1
    }

    this.ctx.garageCarportAckWatchTimerId = setTimeout((): void => {
      this.ctx.garageCarportAckWatchTimerId = -1
      if (!this.ctx.garageCarportAckPending || this.ctx.garageCarportAckRetryDone) return
      this.ctx.garageCarportAckRetryDone = true
      void this.retryGarageCarportAfterAckTimeout()
    }, 2000) as number
  }

  async retryGarageCarportAfterAckTimeout(): Promise<void> {
    if (!this.ctx.garageCarportAckPending) return
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    const level: number = this.ctx.garageCarportAckPendingLevel
    if (level < 2 || level > 4) {
      this.clearGarageCarportAckWatch()
      return
    }
    this.ctx.proto.setMode(this.ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    if (s) {
      s.bumpTx()
      s.pushLog(`GARAGE_CARPORT_RETRY: 2s未收到0xBD/0x01，重发carport(${level})`)
      s.setAction(`garage carport retry level=${level}`)
    }
    if (!this.ctx.canSendMotionCommand(`CARPORT_${level}`, 'GARAGE_RETRY')) {
      return
    }
    await this.ctx.proto.carport(level)
    this.ctx.garageCarportAckSentAtMs = Date.now()
  }

  onPathAckReceived01(): void {
    if (this.ctx.emergencyAlarmBurstActive) {
      this.ctx.emergencyAlarmBurstAckAtMs = Date.now()
    }
    if (!this.ctx.garageCarportAckPending) return
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    const level: number = this.ctx.garageCarportAckPendingLevel
    const elapsedMs: number = this.ctx.garageCarportAckSentAtMs > 0 ? Math.max(0, Date.now() - this.ctx.garageCarportAckSentAtMs) : 0
    this.clearGarageCarportAckWatch()
    if (s) s.pushLog(`GARAGE_CARPORT_ACK: 收到0xBD/0x01 level=${level} elapsed=${elapsedMs}ms`)
  }
  async onGateEnterAckCompleted(fromId: string, toId: string): Promise<void> { await onGateEnterAckCompletedOp(this.ctx, fromId, toId) }
  isGarageTerminalNode(nodeId: string): boolean { return isGarageTerminalNodeOp(this.ctx, nodeId) }
  smartParkingGoalId(): string { return smartParkingGoalIdOp(this.ctx) }
  isSmartParkingGoal(goalId: string): boolean { return isSmartParkingGoalOp(this.ctx, goalId) }
  async maybeHandleGarageDepartBeforeDrive(nowMs: number): Promise<boolean> { return await maybeHandleGarageDepartBeforeDriveOp(this.ctx, nowMs) }
  onGarageDepartReadyAck(): void { onGarageDepartReadyAckOp(this.ctx) }
  beginGarageWaitParkDone04(level: number): void { beginGarageWaitParkDone04Op(this.ctx, level) }
  onGarageParkDone04(): void { onGarageParkDone04Op(this.ctx) }
  async sendGarageCarportAfterParkDone(level: number): Promise<void> { await sendGarageCarportAfterParkDoneOp(this.ctx, level) }
  async maybeHandleGarageFinalArrive(toId: string): Promise<void> { await maybeHandleGarageFinalArriveOp(this.ctx, toId) }
}
