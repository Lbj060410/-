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
import { RouteEdgeCodec, GridIdCodec } from './PathPlannerAStar'
import hilog from '@ohos.hilog'

const PAGE1_SIM_LOG_DOMAIN = 0xFF03
const PAGE1_SIM_LOG_TAG = 'page1sim'

function clearParkingUltrasonicDecisionContext(ctx: any): void {
  ctx.parkingAwaitingUltrasonicDecision = false
  ctx.parkingAwaitingArrivedId = ''
  ctx.parkingAwaitingGoalId = ''
  ctx.parkingAwaitingRequestedAtMs = 0
  ctx.parkingUltrasonicDecisionBusy = false
  if (typeof ctx.clearParkingUltrasonicRequest === 'function') {
    ctx.clearParkingUltrasonicRequest()
  }
}

export function handleParkingSlotOccupied(ctx: any, arrivedId: string, goalId: string, sourceTag: string = ''): void {
  const s = ctx.store
  if (!s) return
  const fromId: string = arrivedId.trim().toUpperCase()
  const targetGoalId: string = goalId.trim().toUpperCase()
  if (!GridIdCodec.isValidId(fromId) || !GridIdCodec.isValidId(targetGoalId)) {
    s.pushLog(`停车位占用：上下文非法 from=${fromId} goal=${targetGoalId}`)
    clearParkingUltrasonicDecisionContext(ctx)
    return
  }

  if (ctx.isSmartParkingGoal(targetGoalId)) {
    ctx.garageWaitingParkDone04 = false
    ctx.garagePendingCarportLevel = 0
  }

  const blockedEdgeId: string = RouteEdgeCodec.normalize(fromId, targetGoalId)
  if (s.addBlockedEdgeIfAbsent(blockedEdgeId, 'PARK_SLOT_OBSTACLE')) {
    s.pushLog(`停车位障碍：封禁边 ${blockedEdgeId}`)
  }

  const fallbackGoalId: string = ctx.fallbackParkingGoalOnObstacle(targetGoalId).trim().toUpperCase()
  if (!GridIdCodec.isValidId(fallbackGoalId)) {
    s.pushLog(`停车位占用：备选车位非法 fallback=${fallbackGoalId} source=${sourceTag}`)
    clearParkingUltrasonicDecisionContext(ctx)
    return
  }

  s.destDraft = fallbackGoalId
  s.applyDest()
  s.pushLog(`停车位占用：${targetGoalId} 收到 0x01，重规划至 ${fallbackGoalId} source=${sourceTag}`)
  clearParkingUltrasonicDecisionContext(ctx)
  ctx.planPath(fallbackGoalId)
}

export async function onParkingUltrasonicResult(ctx: any, ultrasonicP1: number, recvAtMs: number): Promise<void> {
  const s = ctx.store
  if (!s) return
  if (!ctx.parkingAwaitingUltrasonicDecision) return
  if (ctx.parkingUltrasonicDecisionBusy) return
  if (recvAtMs <= 0) return
  ctx.parkingUltrasonicDecisionBusy = true
  const arrivedId: string = (ctx.parkingAwaitingArrivedId as string).trim().toUpperCase()
  const goalId: string = (ctx.parkingAwaitingGoalId as string).trim().toUpperCase()
  try {
    if (!GridIdCodec.isValidId(arrivedId) || !GridIdCodec.isValidId(goalId)) {
      s.pushLog(`停车超声波：忽略，等待上下文非法 from=${arrivedId} goal=${goalId}`)
      clearParkingUltrasonicDecisionContext(ctx)
      return
    }

    const requestAtMsRaw: number = Number(ctx.parkingAwaitingRequestedAtMs)
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
      handleParkingSlotOccupied(ctx, arrivedId, goalId, 'ULTRASONIC')
      return
    }

    // 停车接管逻辑：只依赖超声波结果，不再强制要求额外 BD=02 才允许倒车动画。
    // 若此时恰好还有 ACK 在收尾，最多等待一小段；超时也不中断停车动画。
    if (ctx.canRealSend() && ctx.pathAckAwaitingComplete) {
      const ackOk: boolean = await ctx.waitForCurrentPathAckComplete(P1C.LIGHT_QUERY_WAIT_TIMEOUT_MS, 'PARK_HANDOFF_WAIT_ACK02')
      if (!ackOk) {
        s.pushLog(`停车超声波：p1=0x${ctx.byteToHex(ultrasonicP1)}，ACK未完成但继续倒车入库动画`)
      }
    }

    const parkingHeadingDeg: number = ctx.segmentHeadingDeg(arrivedId, goalId)
    ctx.playMapReverseParkingAnimation(arrivedId, goalId, parkingHeadingDeg)
    s.pushLog(`停车超声波：p1=0x${ctx.byteToHex(ultrasonicP1)}，执行倒车入库动画`)
    clearParkingUltrasonicDecisionContext(ctx)
  } finally {
    ctx.parkingUltrasonicDecisionBusy = false
  }
}

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
  if (curId === 'B2' && nextId === 'B4') {
    s.pushLog('GATE_SETTLE: 已禁用 SrttleAccounts/billing，直接发送 depart')
  }
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
    const ultrasonicRequestAtMs: number = Date.now()
    ctx.lastUltrasonicP1 = -1
    ctx.lastUltrasonicAtMs = 0
    clearParkingUltrasonicDecisionContext(ctx)
    ctx.parkingAwaitingUltrasonicDecision = true
    ctx.parkingAwaitingArrivedId = arrivedId.trim().toUpperCase()
    ctx.parkingAwaitingGoalId = goalId.trim().toUpperCase()
    ctx.parkingAwaitingRequestedAtMs = ultrasonicRequestAtMs
    ctx.parkingUltrasonicDecisionBusy = false
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

    if (!ctx.canRealSend()) {
      const parkingHeadingDeg: number = ctx.segmentHeadingDeg(arrivedId, goalId)
      ctx.playMapReverseParkingAnimation(arrivedId, goalId, parkingHeadingDeg)
      s.pushLog(`停车前检查：${upperGoalId} DRY_RUN 直接执行倒车入库动画`)
      clearParkingUltrasonicDecisionContext(ctx)
      return true
    }

    await ctx.sleep(P1C.ULTRASONIC_WAIT_MS)
    if (!ctx.isParkingSequenceActive(token)) return true
    const ultrasonicReady: boolean = ctx.lastUltrasonicAtMs >= ultrasonicRequestAtMs
    if (!ultrasonicReady) {
      s.pushLog(`停车前检查：${upperGoalId} 等待超声波回包中，收到结果后再决定是否倒车入库`)
      return true
    }

    await onParkingUltrasonicResult(ctx, ctx.lastUltrasonicP1, ctx.lastUltrasonicAtMs)
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
      if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('GATE_DEPART', 'GARAGE_FLOW')) {
        s.setAction(`闸口放行=${flow} | 熔断中`)
        return true
      }
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
      const departAtMs: number = Date.now()
      if (curId === 'B2' && nextId === 'B4') {
        ctx.gateBillingRunning = true
        ctx.gateBillingStartAtMs = departAtMs
        ctx.gateBillingElapsedMs = 0
        s.pushLog(`GATE_BILLING: B2->B4 depart sent，开始内部计时 at=${departAtMs}`)
      } else if (curId === 'B4' && nextId === 'B2') {
        const elapsedMs: number = ctx.gateBillingStartAtMs > 0
          ? Math.max(0, departAtMs - ctx.gateBillingStartAtMs)
          : 0
        ctx.gateBillingElapsedMs = elapsedMs
        ctx.gateBillingRunning = false
        ctx.gateBillingStartAtMs = 0
        s.pushLog(`GATE_BILLING: B4->B2 depart sent，结束内部计时 elapsed=${elapsedMs}ms`)
      }
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
      const msg: string = e instanceof Error ? e.message : 'simulateOnce error'
      hilog.error(PAGE1_SIM_LOG_DOMAIN, PAGE1_SIM_LOG_TAG, '%{public}s', `[Sim] simulateOnce error: ${msg}`)
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
  const edge: { fromId: string, toId: string } | undefined = resolveDisplayEdge(ctx)
  if (!edge) return 57
  return edgeDistanceCm(edge.fromId, edge.toId)
}

export function simAmbientBackCm(ctx: any): number {
  return 70 + (ctx.simTick % 11)
}

export function simAmbientIrCm(ctx: any): number {
  return 20 + (ctx.simTick % 7)
}

export function simAmbientLux(ctx: any): number {
  const baseLuxRaw: number = Number(ctx.simLightBaseLux)
  const baseLux: number = Number.isFinite(baseLuxRaw) ? Math.max(0, Math.round(baseLuxRaw)) : 0
  const delta: number = Math.floor(Math.random() * 41) - 20
  const v: number = baseLux + delta
  return v < 0 ? 0 : v
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

    const frontCm: number = simAmbientFrontCm(ctx)
    const lightQueryEnabled: boolean = !!ctx.lightMetricQueryEnabled
    const lightReady: boolean = !!ctx.lightMetricReady
    const lightLux: number = (lightQueryEnabled && lightReady) ? simAmbientLux(ctx) : 0
    s.setTelemetry({
      tsMs: now,
      speed: idleSpeed,
      headingDeg: s.pose.headingDeg,
      odomMm: s.telemetry.odomMm,
      ultraFrontCm: frontCm,
      ultraBackCm: simAmbientBackCm(ctx),
      irDistCm: simAmbientIrCm(ctx),
      lightLux: lightLux,
      rfid: s.telemetry.rfid
    })
    const realSendNow: boolean = !!(ctx.store && ctx.store.realSendEnabled)
    if (!realSendNow) {
      s.setMetricSpeedCms(0)
      s.setMetricHeadingDeg(0)
      s.setMetricDistanceCm(0)
      s.setMetricLightLux(0)
    }
    if (realSendNow) {
      s.setMetricHeadingDeg(s.telemetry.headingDeg)
      s.setMetricLightLux(lightQueryEnabled && lightReady ? Math.max(0, Math.round(s.telemetry.lightLux)) : 0)
    }
    const lastMetricLogAtMs: number = Number(ctx.metricDebugLastLogAtMs) || 0
    if (now - lastMetricLogAtMs >= 1000) {
      ctx.metricDebugLastLogAtMs = now
      const line: string =
        `METRIC_DBG rs=${realSendNow ? 1 : 0} conn=${s.connText} `
        + `m=[${s.metricSpeedCms},${Math.round(s.metricHeadingDeg)}/${s.metricHeadingText},${s.metricDistanceCm},${s.metricLightLux}] `
        + `t=[${s.telemetry.speed},${Math.round(s.telemetry.headingDeg)},${s.telemetry.ultraFrontCm},${s.telemetry.lightLux}]`
      s.metricDebugLine = line
      s.pushLog(line)
    }
    s.updateRisk()
    if (ctx.maybeTriggerRoutePointObstacle()) return
    ctx.maybeReplanOnObstacle()
  } finally {
    ctx.simLoopBusy = false
  }
}

function resolveDisplayEdge(ctx: any): { fromId: string, toId: string } | undefined {
  const req = ctx.pendingAckMotion
  if (req && typeof req.fromId === 'string' && typeof req.toId === 'string') {
    const a: string = req.fromId.trim().toUpperCase()
    const b: string = req.toId.trim().toUpperCase()
    if (GridIdCodec.isValidId(a) && GridIdCodec.isValidId(b)) return { fromId: a, toId: b }
  }

  const motionFrom: string = ctx.motionPlayer.currentFromId().trim().toUpperCase()
  const motionTo: string = ctx.motionPlayer.currentToId().trim().toUpperCase()
  if (GridIdCodec.isValidId(motionFrom) && GridIdCodec.isValidId(motionTo)) {
    return { fromId: motionFrom, toId: motionTo }
  }

  const s = ctx.store
  if (!s) return undefined
  const idx: number = s.pathIndex
  if (idx >= 0 && idx + 1 < s.pathNodes.length) {
    const fromId: string = s.pathNodes[idx].trim().toUpperCase()
    const toId: string = s.pathNodes[idx + 1].trim().toUpperCase()
    if (GridIdCodec.isValidId(fromId) && GridIdCodec.isValidId(toId)) return { fromId: fromId, toId: toId }
  }
  return undefined
}

function edgeDistanceCm(aId: string, bId: string): number {
  const a: string = aId.trim().toUpperCase()
  const b: string = bId.trim().toUpperCase()
  const ac = GridIdCodec.parse(a)
  const bc = GridIdCodec.parse(b)
  if (!ac || !bc) return 57

  const rowA: number = Number.parseInt(a.slice(1), 10)
  const rowB: number = Number.parseInt(b.slice(1), 10)
  const colA: string = a[0]
  const colB: string = b[0]

  if (ac.col === bc.col) {
    const topBottom: boolean =
      (rowA === 1 && rowB === 2) || (rowA === 2 && rowB === 1) ||
      (rowA === 7 && rowB === 6) || (rowA === 6 && rowB === 7)
    return topBottom ? 37 : 57
  }

  if (ac.row === bc.row) {
    const sideEdge: boolean =
      (colA === 'A' && colB === 'B') || (colA === 'B' && colB === 'A') ||
      (colA === 'G' && colB === 'F') || (colA === 'F' && colB === 'G')
    return sideEdge ? 47 : 71
  }

  return 57
}
