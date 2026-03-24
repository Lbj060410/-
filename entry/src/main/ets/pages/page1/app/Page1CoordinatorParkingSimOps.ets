/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorParkingSimOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorParkingSimOps.ets
 * 用途： 处理停车流程模拟、仿真传感数据与停车阶段控制。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { P1C } from './Page1CoordinatorDefs'
import { RouteEdgeCodec } from './PathPlannerAStar'

async function alignToParkingGoal(ctx: any, arrivedId: string, goalId: string): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (!ctx.logicalHeadingInited) ctx.syncLogicalHeadingWithCurrentState()
  const parkingHeadingDeg = ctx.segmentHeadingDeg(arrivedId, goalId)
  const alignTurnAction = ctx.actionForHeadingTransition(ctx.logicalHeadingDeg, parkingHeadingDeg)
  if (alignTurnAction === undefined) return true

  s.pushLog(`停车对准：${arrivedId} -> ${goalId}`)
  const sentAlign: boolean = await ctx.sendDriveActionDirect(alignTurnAction)
  if (!sentAlign) {
    s.pushLog('停车对准：发送失败')
    return false
  }
  if (ctx.canRealSend()) {
    const ackOk: boolean = await ctx.waitForCurrentPathAckComplete(P1C.PATH_ACK_TIMEOUT_MS, 'PARK_ALIGN')
    if (!ackOk) {
      s.pushLog('停车对准：未收到 BD=02 完成回执')
      return false
    }
  }

  ctx.logicalHeadingDeg = parkingHeadingDeg
  ctx.logicalHeadingInited = true
  ctx.updateHeadingOnlyAtCurrentPose(parkingHeadingDeg)
  return true
}

async function runGateExitSettleBeforeDepart(ctx: any, curId: string, nextId: string): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (curId !== 'B2' || nextId !== 'B4') return true
  if (!ctx.gateBillingRunning) return true

  s.pushLog('GATE_SETTLE: 出闸前执行 leftHalf -> SrttleAccounts -> rightHalf')

  const sentLeftHalf: boolean = await ctx.sendDriveActionDirect(Page1Action.LEFT_HALF)
  if (!sentLeftHalf) {
    s.pushLog('GATE_SETTLE: leftHalf 发送失败，取消本次出闸')
    return false
  }
  if (ctx.canRealSend()) {
    const ackLeftOk: boolean = await ctx.waitForCurrentPathAckComplete(P1C.PATH_ACK_TIMEOUT_MS, 'GATE_SETTLE_LEFT_HALF')
    if (!ackLeftOk) {
      s.pushLog('GATE_SETTLE: leftHalf 等待BD=02超时，取消本次出闸')
      return false
    }
  }

  ctx.proto.setMode(ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
  s.bumpTx()
  await ctx.proto.SrttleAccounts()
  if (ctx.canRealSend()) {
    ctx.markPathCommandSent('道闸结算')
    const ackSettleOk: boolean = await ctx.waitForCurrentPathAckComplete(P1C.PATH_ACK_TIMEOUT_MS, 'GATE_SETTLE_ACCOUNTS')
    if (!ackSettleOk) {
      s.pushLog('GATE_SETTLE: SrttleAccounts 等待BD=02超时，取消本次出闸')
      return false
    }
  }

  const sentRightHalf: boolean = await ctx.sendDriveActionDirect(Page1Action.RIGHT_HALF)
  if (!sentRightHalf) {
    s.pushLog('GATE_SETTLE: rightHalf 发送失败，取消本次出闸')
    return false
  }
  if (ctx.canRealSend()) {
    const ackRightOk: boolean = await ctx.waitForCurrentPathAckComplete(P1C.PATH_ACK_TIMEOUT_MS, 'GATE_SETTLE_RIGHT_HALF')
    if (!ackRightOk) {
      s.pushLog('GATE_SETTLE: rightHalf 等待BD=02超时，取消本次出闸')
      return false
    }
  }

  const elapsedMs: number = Math.max(0, Date.now() - (ctx.gateBillingStartAtMs > 0 ? ctx.gateBillingStartAtMs : Date.now()))
  ctx.gateBillingElapsedMs = elapsedMs
  ctx.gateBillingRunning = false
  ctx.gateBillingStartAtMs = 0
  s.pushLog(`GATE_SETTLE: 完成，本地计时 ${elapsedMs}ms`)
  return true
}

export async function runParkingBeforeFinalEdgeArrival(ctx: any, arrivedId: string): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (s.pathNodes.length < 2) return false
  const preFinalIndex: number = s.pathNodes.length - 2
  if (s.pathIndex !== preFinalIndex) return false

  const goalId: string = s.pathNodes[s.pathNodes.length - 1]
  const isGarageGoal: boolean = ctx.isSmartParkingGoal(goalId)
  if (!isGarageGoal && !ctx.isReverseParkingGoal(goalId)) return false
  if (!isGarageGoal) {
    const side = ctx.edgeSideOfNode(goalId)
    if (side === 0) return false
  }

  const token = ctx.tryStartParkingSequence()
  if (token === null) return false
  s.pushLog(`停车前检查：arrived=${arrivedId} goal=${goalId}`)
  try {
    if (!ctx.isParkingSequenceActive(token)) return true

    const aligned: boolean = await alignToParkingGoal(ctx, arrivedId, goalId)
    if (!aligned) return true
    const parkingHeadingDeg: number = ctx.segmentHeadingDeg(arrivedId, goalId)
    const ultrasonicRequestAtMs: number = Date.now()
    ctx.lastUltrasonicP1 = -1
    ctx.lastUltrasonicAtMs = 0
    ctx.clearParkingUltrasonicRequest()
    if (ctx.canRealSend()) {
      s.bumpTx()
      ctx.markParkingUltrasonicRequest(ultrasonicRequestAtMs)
      await ctx.proto.ultrasonic()
    }

    const upperGoalId: string = goalId.trim().toUpperCase()
    if (isGarageGoal) {
      const level: number = 2
      s.pushLog(`停车前检查：${upperGoalId} 已发送超声波，交由小车自主入库，等待 BC/04 后 carport(${level})`)
      ctx.beginGarageWaitParkDone04(level)
      s.setPath([], 'GARAGE_WAIT_04')
    } else {
      s.pushLog(`停车前检查：${upperGoalId} 已发送超声波，交由小车自主入库`)
      s.setPath([], 'PARK_HANDOFF')
    }

    await ctx.sleep(P1C.ULTRASONIC_WAIT_MS)
    if (!ctx.isParkingSequenceActive(token)) return true

    const ultrasonicReady: boolean = ctx.lastUltrasonicAtMs >= ultrasonicRequestAtMs
    if (!ultrasonicReady) {
      ctx.playMapReverseParkingAnimation(arrivedId, goalId, parkingHeadingDeg)
      s.pushLog(`停车前检查：${upperGoalId} 超声波超时，按“不处理”保留当前状态`)
      return true
    }
    if (ctx.lastUltrasonicP1 !== 0x01) {
      ctx.playMapReverseParkingAnimation(arrivedId, goalId, parkingHeadingDeg)
      s.pushLog(`停车前检查：${upperGoalId} 超声波 p1=0x${ctx.byteToHex(ctx.lastUltrasonicP1)}，不处理`)
      return true
    }

    if (isGarageGoal) {
      ctx.garageWaitingParkDone04 = false
      ctx.garagePendingCarportLevel = 0
    }
    const blockedEdgeId: string = RouteEdgeCodec.normalize(arrivedId, goalId)
    if (s.addBlockedEdgeIfAbsent(blockedEdgeId, 'PARK_SLOT_OBSTACLE')) {
      s.pushLog(`停车位障碍：封禁边 ${blockedEdgeId}`)
    }
    const fallbackGoalId: string = ctx.fallbackParkingGoalOnObstacle(goalId)
    if (fallbackGoalId !== goalId) {
      s.destDraft = fallbackGoalId
      s.applyDest()
    }
    s.pushLog(`停车前检查：${upperGoalId} 收到 0x01，重规划至 ${fallbackGoalId}`)
    ctx.planPath(fallbackGoalId)
    return true
  } finally {
    ctx.clearParkingUltrasonicRequest()
    ctx.endParkingSequence(token)
  }
}
export async function runHandleGateDepartOnArrival(ctx: any, arrivedId: string): Promise<boolean> {
  const s = ctx.store
  if (!s) return false
  if (ctx.gateDepartInProgress) return true
  if (s.pathNodes.length <= 1) return false
  if (s.pathIndex < 0 || s.pathIndex >= s.pathNodes.length - 1) return false

  const curId = arrivedId.trim().toUpperCase()
  const nextId = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
  if (curId.length <= 0 || nextId.length <= 0) return false
  let flow = ''
  if (curId === 'B2' && nextId === 'B4') flow = '出库'
  else if (curId === 'B4' && nextId === 'B2') flow = '入库'
  else return false

  ctx.gateDepartInProgress = true
  try {
    if (!ctx.logicalHeadingInited) ctx.syncLogicalHeadingWithCurrentState()
    const gateHeadingDeg = ctx.segmentHeadingDeg(curId, nextId)
    const turnAction = ctx.actionForHeadingTransition(ctx.logicalHeadingDeg, gateHeadingDeg)
    if (turnAction !== undefined) {
      let turnText = '转向'
      if (turnAction === Page1Action.LEFT) turnText = '左转'
      else if (turnAction === Page1Action.RIGHT) turnText = '右转'
      else if (turnAction === Page1Action.UTURN) turnText = '掉头'
      s.setAction(`闸口对准=${turnText}`)
      s.pushLog(`GATE_ALIGN: ${curId}->${nextId} heading=${gateHeadingDeg} action=${turnText}`)
      const sentAlign = await ctx.sendDriveActionDirect(turnAction)
      if (!sentAlign) {
        s.pushLog(`GATE_ALIGN: ${curId}->${nextId} 对准发送失败`)
        return true
      }
      if (ctx.canRealSend()) {
        const ackOk = await ctx.waitForCurrentPathAckComplete(P1C.PATH_ACK_TIMEOUT_MS, 'GATE_ALIGN')
        if (!ackOk) {
          s.setAction('闸口对准超时')
          s.pushLog(`GATE_ALIGN: ${curId}->${nextId} 未收到BD=02，取消本次放行`)
          return true
        }
      }
      s.pushLog(`GATE_ALIGN: ${curId}->${nextId} 完成 heading=${gateHeadingDeg}`)
    } else {
      s.setAction('闸口对准=已就绪')
      s.pushLog(`GATE_ALIGN: ${curId}->${nextId} heading=${gateHeadingDeg} action=NONE`)
    }

    ctx.logicalHeadingDeg = gateHeadingDeg
    ctx.logicalHeadingInited = true
    ctx.updateHeadingOnlyAtCurrentPose(gateHeadingDeg)
    s.pushLog(`GATE_WAIT: ${P1C.GATE_DEPART_ALIGN_WAIT_MS}ms before depart`)
    await ctx.sleep(P1C.GATE_DEPART_ALIGN_WAIT_MS)
    if (!ctx.isLivePathPair(curId, nextId)) {
      s.pushLog(`GATE_DEPART_ABORT: 路径变化 ${curId}->${nextId}`)
      return true
    }

    const settleOk: boolean = await runGateExitSettleBeforeDepart(ctx, curId, nextId)
    if (!settleOk) return true

    const departKey = ctx.gateDepartSendKey(curId, nextId)
    const nowMs = Date.now()
    const lastByFlowAtMs = ctx.gateDepartLastSentAtByFlowKey.get(departKey) || 0
    const duplicateDepart =
      (departKey === ctx.gateDepartLastSentKey && nowMs - ctx.gateDepartLastSentAtMs < P1C.GATE_DEPART_DEDUP_MS) ||
      (lastByFlowAtMs > 0 && nowMs - lastByFlowAtMs < P1C.GATE_DEPART_DEDUP_MS)
    let departSent = false
    let sentInRealMode = false
    if (duplicateDepart) {
      s.setAction(`闸口放行=${flow} | 去重`)
      s.pushLog(`GATE_DEPART_DEDUP: ${curId}->${nextId} flow=${flow} key=${departKey}`)
    } else {
      sentInRealMode = ctx.canRealSend()
      ctx.proto.setMode(sentInRealMode ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
      s.bumpTx()
      if (sentInRealMode) {
        await ctx.proto.depart()
        ctx.markPathCommandSent('闸口放行')
        departSent = true
        s.setAction(`闸口放行=${flow}`)
        s.pushLog(`GATE_DEPART: ${curId}->${nextId} flow=${flow} sent`)
      } else {
        departSent = true
        const mode = s.realSendEnabled ? 'REAL_SEND(未连接)' : 'DRY_RUN'
        s.setAction(`闸口放行=${flow} | ${mode}`)
        s.pushLog(`GATE_DEPART: ${curId}->${nextId} flow=${flow} 演练模式`)
      }
      ctx.gateDepartLastSentKey = departKey
      ctx.gateDepartLastSentAtMs = nowMs
      ctx.gateDepartLastSentAtByFlowKey.set(departKey, nowMs)
    }

    if (departSent) {
      const nextActionAfterGate = ctx.peekNextActionAfterCurrentStep()
      const req = {
        action: Page1Action.GO,
        fromId: curId,
        toId: nextId,
        nextAction: nextActionAfterGate,
        motionMs: ctx.pathDotMotionTimingMs(),
        advancePathOnFinish: true,
        useReverseSpeed: false,
        customLogTag: 'SEGMENT_START_GATE'
      }
      if (sentInRealMode) {
        ctx.stageMotionWaitAckComplete(req)
        s.pushLog(`SEGMENT_START_GATE: ${curId} -> ${nextId} 等待BD=02 (${ctx.pathDotMotionTimingMs()}ms)`)
      } else {
        ctx.startMotionNow(req)
        s.pushLog(`SEGMENT_START_GATE: ${curId} -> ${nextId} DRY_RUN红点移动 (${ctx.pathDotMotionTimingMs()}ms)`)
      }
      s.markAutoFollow(Date.now())
    }
    return true
  } finally {
    ctx.gateDepartInProgress = false
  }
}

export function startSimulatorLoop(ctx: any): void {
  stopSimulatorLoop(ctx)
  ctx.simTick = 0
  ctx.simLoopBusy = false
  ctx.simTimerId = setInterval((): void => {
    simulateOnceLoop(ctx).catch((e: Error): void => {
      console.error('[Sim] simulateOnce error:', e.message)
    })
  }, P1C.SIM_TICK_MS) as number
}

export function stopSimulatorLoop(ctx: any): void {
  if (ctx.simTimerId !== -1) {
    clearInterval(ctx.simTimerId)
    ctx.simTimerId = -1
  }
  ctx.simLoopBusy = false
}

export function simAmbientFrontCm(ctx: any): number {
  return 80 + (ctx.simTick % 15)
}

export function simAmbientBackCm(ctx: any): number {
  return 70 + (ctx.simTick % 11)
}

export function simAmbientIrCm(ctx: any): number {
  return 20 + (ctx.simTick % 7)
}

export function simAmbientLux(ctx: any): number {
  return 300 + (ctx.simTick % 50)
}

export async function sleepMs(ms: number): Promise<void> {
  await new Promise<void>((resolve) => setTimeout(() => resolve(), ms))
}

export async function simulateOnceLoop(ctx: any): Promise<void> {
  if (ctx.simLoopBusy) return
  ctx.simLoopBusy = true
  try {
    const s = ctx.store
    if (!s) return
    const now = Date.now()
    await ctx.followPathOnce(now, false)
    ctx.simTick += 1
    await ctx.updateMotionTimeline(now)

    const liveMotionAction = ctx.motionPlayer.currentAction()
    const idleSpeed = ctx.motionRunning() && ctx.isMoveAction(liveMotionAction)
      ? (ctx.motionPlayer.usesReverseSpeed() || liveMotionAction === Page1Action.BACK ? -20 : 20)
      : 0

    s.setTelemetry({
      tsMs: now,
      speed: idleSpeed,
      headingDeg: s.pose.headingDeg,
      odomMm: s.telemetry.odomMm,
      ultraFrontCm: simAmbientFrontCm(ctx),
      ultraBackCm: simAmbientBackCm(ctx),
      irDistCm: simAmbientIrCm(ctx),
      lightLux: simAmbientLux(ctx),
      rfid: s.telemetry.rfid
    })
    s.updateRisk()
    if (ctx.maybeTriggerRoutePointObstacle()) return
    ctx.maybeReplanOnObstacle()
  } finally {
    ctx.simLoopBusy = false
  }
}




