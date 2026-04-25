/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorTrafficGateOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorTrafficGateOps.ets
 * 用途： 处理道闸/交通灯策略判定与通行控制决策。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { recogStore } from '../../../state/RecogStore'
import { videoStore } from '../../../state/VideoStore'
import { Page1Action } from '../types/Page1Types'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { trafficSignalArbiter } from '../../../services/control/TrafficSignalArbiter'
import { RecognitionResultViewHelper } from '../../../services/recognition/RecognitionResultViewHelper'
import { RecognitionSubtype } from '../../../services/recognition/RecognitionTask'
import { RecognitionResult } from '../../../services/recognition/RecognitionResult'

type TrafficSignal = 'RED' | 'GREEN' | 'YELLOW' | 'UNKNOWN'

const TRAFFIC_GATE_LOG_COOLDOWN_MS: number = 1200
const EDGE_B4_B6: string = 'B4->B6'
const TRAFFIC_GATE_RETRY_TIMER: string = 'traffic_gate_retry'
const TRAFFIC_GATE_RETRY_INTERVAL_MS: number = 800
const TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS: number = 5000
const TRAFFIC_GATE_GREEN_CONFIRM_COUNT: number = 2
const TRAFFIC_GATE_PASS_BYPASS_MS: number = 2200
const TRAFFIC_SIGNAL_RESEND_WINDOW_MS: number = 15000
const TRAFFIC_GATE_GO_SEND_GAP_MS: number = 120

function logShibie(text: string): void {
  console.info(`[shibie] ${text}`)
}

function isActiveGateEdge(fromId: string, toId: string): boolean {
  return fromId === 'B4' && toId === 'B6'
}

function edgeKey(fromId: string, toId: string): string {
  if (fromId === 'B4' && toId === 'B6') return EDGE_B4_B6
  return ''
}

function headingGateEdgeBySnap(ctx: any): string {
  const s = ctx.store
  if (!s) return ''
  const snapId: string = s.currentSnapNodeId.trim().toUpperCase()
  if (snapId.length <= 0) return ''

  let headingDeg: number = Number(s.pose.headingDeg) || 0
  if (!Number.isFinite(headingDeg)) headingDeg = 0
  const headingCardinal: number = ctx.normToCardinal(headingDeg)

  // B4 -> B6 : southbound on B column
  if (snapId === 'B4' && headingCardinal === 90) return EDGE_B4_B6
  return ''
}

function activeGateEdge(ctx: any, fromManual: boolean): string {
  const s = ctx.store
  if (!s) return ''
  if (s.pathNodes.length > 1 && s.pathIndex >= 0 && s.pathIndex < s.pathNodes.length - 1) {
    const fromId: string = s.pathNodes[s.pathIndex].trim().toUpperCase()
    const toId: string = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
    if (isActiveGateEdge(fromId, toId)) {
      return edgeKey(fromId, toId)
    }
    // 自动主链：保持原规则，避免非门禁段误触发。
    if (!fromManual) {
      return ''
    }
    // 手动前进/0x01：即使存在路径，也允许用“点位+朝向”兜底触发门禁。
    return headingGateEdgeBySnap(ctx)
  }
  return headingGateEdgeBySnap(ctx)
}

function normalizeTrafficSignal(raw: string): TrafficSignal {
  const x: string = raw.trim().toLowerCase()
  if (x.length <= 0 || x === '-') return 'UNKNOWN'
  if (x.indexOf('red') >= 0 || x.indexOf('stop') >= 0 || x.indexOf('hong') >= 0 || x.indexOf('红') >= 0 || x === 'r') return 'RED'
  if (x.indexOf('green') >= 0 || x.indexOf('go') >= 0 || x.indexOf('lv') >= 0 || x.indexOf('lu') >= 0 || x.indexOf('绿') >= 0 || x === 'g') return 'GREEN'
  if (x.indexOf('yellow') >= 0 || x.indexOf('amber') >= 0 || x.indexOf('huang') >= 0 || x.indexOf('黄') >= 0 || x === 'y') return 'YELLOW'
  return 'UNKNOWN'
}

function latestFreshTrafficResult(nowMs: number): RecognitionResult | undefined {
  let best: RecognitionResult | undefined = undefined
  const tasks = recogStore.recogTasks
  for (let i: number = 0; i < tasks.length; i++) {
    const one = tasks[i].result
    if (!one || !one.ok) continue
    if (one.subtype !== RecognitionSubtype.TRAFFIC_LIGHT) continue
    if (nowMs - one.tsMs > TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS) continue
    if (!best || one.tsMs > best.tsMs) best = one
  }
  if (!best && recogStore.lastRecog && recogStore.lastRecog.ok && recogStore.lastRecog.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
    const one = recogStore.lastRecog
    if (nowMs - one.tsMs <= TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS) best = one
  }
  if (!best && recogStore.lastSnapshotRecog && recogStore.lastSnapshotRecog.ok &&
    recogStore.lastSnapshotRecog.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
    const one = recogStore.lastSnapshotRecog
    if (nowMs - one.tsMs <= TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS) best = one
  }
  return best
}

function latestTrafficResultAnyAge(): RecognitionResult | undefined {
  let best: RecognitionResult | undefined = undefined
  const tasks = recogStore.recogTasks
  for (let i: number = 0; i < tasks.length; i++) {
    const one = tasks[i].result
    if (!one || !one.ok) continue
    if (one.subtype !== RecognitionSubtype.TRAFFIC_LIGHT) continue
    if (!best || one.tsMs > best.tsMs) best = one
  }
  if (!best && recogStore.lastRecog && recogStore.lastRecog.ok && recogStore.lastRecog.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
    best = recogStore.lastRecog
  }
  if (!best && recogStore.lastSnapshotRecog && recogStore.lastSnapshotRecog.ok &&
    recogStore.lastSnapshotRecog.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
    best = recogStore.lastSnapshotRecog
  }
  return best
}

function readTrafficSignal(ctx: any, nowMs: number): TrafficSignal {
  const r: RecognitionResult | undefined = latestFreshTrafficResult(nowMs)
  if (!r) {
    ctx.trafficGateGreenStreak = 0
    const latest: RecognitionResult | undefined = latestTrafficResultAnyAge()
    if (!latest) {
      logShibie(`traffic-signal none any-result fresh<=${TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS}ms`)
    } else {
      const ageMs: number = Math.max(0, nowMs - latest.tsMs)
      logShibie(
        `traffic-signal stale source=${latest.source} task=${latest.taskId} age=${ageMs}ms fresh<=${TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS}ms`
      )
    }
    return 'UNKNOWN'
  }
  const signal: TrafficSignal = normalizeTrafficSignal(RecognitionResultViewHelper.bestTextForSubtype(r, RecognitionSubtype.TRAFFIC_LIGHT))
  const signalKey: string = (r.taskId && r.taskId.length > 0) ? r.taskId : String(r.tsMs)
  const prevSignalKey: string = String(ctx.trafficGateLastSignalKey || '')
  const prevSignal: string = String(ctx.trafficGateLastSignal || '')
  if (signalKey !== prevSignalKey) {
    if (signal === 'GREEN' && prevSignal === 'GREEN') {
      ctx.trafficGateGreenStreak = Number(ctx.trafficGateGreenStreak || 0) + 1
    } else if (signal === 'GREEN') {
      ctx.trafficGateGreenStreak = 1
    } else {
      ctx.trafficGateGreenStreak = 0
    }
    ctx.trafficGateLastSignalKey = signalKey
    ctx.trafficGateLastSignal = signal
  } else if (signal !== 'GREEN') {
    ctx.trafficGateGreenStreak = 0
    ctx.trafficGateLastSignal = signal
  }
  if (signal === 'GREEN' && Number(ctx.trafficGateGreenStreak || 0) >= TRAFFIC_GATE_GREEN_CONFIRM_COUNT) {
    logShibie(`traffic-signal pass key=${signalKey} ts=${r.tsMs} signal=GREEN streak=${ctx.trafficGateGreenStreak}`)
    return 'GREEN'
  }
  logShibie(
    `traffic-signal hold key=${signalKey} ts=${r.tsMs} signal=${signal} streak=${Number(ctx.trafficGateGreenStreak || 0)}/${TRAFFIC_GATE_GREEN_CONFIRM_COUNT}`
  )
  return signal === 'GREEN' ? 'YELLOW' : signal
}

function clearGateWaiting(ctx: any, restoreDefaultModel: boolean = false): void {
  ctx.trafficGateWaiting = false
  ctx.trafficGateEdgeKey = ''
  ctx.trafficGateResumeManual = false
  ctx.trafficGateAwaitGreenAck02 = false
  ctx.trafficGateGreenAckEdgeKey = ''
  ctx.trafficGateGreenAckResumeManual = false
  ctx.trafficGateGreenAckInFlight = false
  ctx.trafficGateGreenAckSeen01 = false
  ctx.trafficGateGreenStreak = 0
  ctx.trafficGateLastSignalKey = ''
  ctx.trafficGateLastSignal = 'UNKNOWN'
  ctx.trafficGateResumeModelAfterPass = false
  trafficSignalArbiter.endGateSession()
  if (ctx.timerManager && typeof ctx.timerManager.clear === 'function') {
    ctx.timerManager.clear(TRAFFIC_GATE_RETRY_TIMER)
  }
  if (restoreDefaultModel) {
    videoStore.setRecognitionEnabled(true)
    videoStore.setPage2Yolov26BarrierEnabled(true)
    logShibie('gate-restore-default-model yolov26barrier=ON')
  }
}

function hasRecentGreenAck(ctx: any, nowMs: number): boolean {
  const lastAckAtMs: number = Number(ctx.trafficGateLastGreenAckAtMs) || 0
  return lastAckAtMs > 0 && (nowMs - lastAckAtMs) <= TRAFFIC_SIGNAL_RESEND_WINDOW_MS
}

function shouldSendTrafficSignal(ctx: any, signal: 'RED' | 'GREEN', nowMs: number): boolean {
  const lastColor: string = String(ctx.trafficGateLastSentSignal || '')
  const lastAtMs: number = Number(ctx.trafficGateLastSentSignalAtMs) || 0
  if (lastColor !== signal) return true
  if (lastAtMs <= 0) return true
  if (nowMs - lastAtMs >= TRAFFIC_SIGNAL_RESEND_WINDOW_MS) return true
  return false
}

function canLogGate(ctx: any, nowMs: number): boolean {
  if (!ctx.trafficGateLastLogAtMs || nowMs - ctx.trafficGateLastLogAtMs >= TRAFFIC_GATE_LOG_COOLDOWN_MS) {
    ctx.trafficGateLastLogAtMs = nowMs
    return true
  }
  return false
}

function pushMergedGateLog(ctx: any, text: string): void {
  const s = ctx.store
  if (!s || typeof s.pushLog !== 'function') return
  const nowMs: number = Date.now()
  const prevKey: string = String(ctx.trafficGateMergeLogKey || '')
  const prevAtMs: number = Number(ctx.trafficGateMergeLogAtMs) || 0
  const nextCount: number = (prevKey === text && (nowMs - prevAtMs) <= 900)
    ? (Math.max(1, Number(ctx.trafficGateMergeLogCount) || 1) + 1)
    : 1
  ctx.trafficGateMergeLogKey = text
  ctx.trafficGateMergeLogAtMs = nowMs
  ctx.trafficGateMergeLogCount = nextCount
  if (nextCount === 1) {
    s.pushLog(text)
  } else if (nextCount <= 3) {
    s.pushLog(`${text} x${nextCount}`)
  }
}

function markGatePassed(ctx: any, edgeKey: string, nowMs: number): void {
  ctx.trafficGateBypassEdgeKey = edgeKey
  ctx.trafficGateBypassUntilMs = nowMs + TRAFFIC_GATE_PASS_BYPASS_MS
}

function isGateBypassActive(ctx: any, edgeKey: string, nowMs: number): boolean {
  const key: string = String(ctx.trafficGateBypassEdgeKey || '')
  const untilMs: number = Number(ctx.trafficGateBypassUntilMs || 0)
  return key === edgeKey && nowMs < untilMs
}

function hasPendingGreenAckForEdge(ctx: any, edgeKey: string): boolean {
  if (!ctx.trafficGateAwaitGreenAck02) return false
  return String(ctx.trafficGateGreenAckEdgeKey || '') === edgeKey
}

async function armGreenAckGate(ctx: any, edgeKey: string, fromManual: boolean): Promise<void> {
  const s = ctx.store
  if (!s) return
  if (ctx.trafficGateGreenAckInFlight) return
  if (hasPendingGreenAckForEdge(ctx, edgeKey)) return

  const nowMs: number = Date.now()
  if (!shouldSendTrafficSignal(ctx, 'GREEN', nowMs)) {
    pushMergedGateLog(ctx, `TRAFFIC_GATE GREEN_SKIP ${edgeKey}: same color within ${TRAFFIC_SIGNAL_RESEND_WINDOW_MS}ms`)
    return
  }

  ctx.trafficGateGreenAckInFlight = true
  try {
    ctx.proto.setMode(ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
    const rs = await trafficSignalArbiter.send(ctx.proto, 'G', 'GATE', 0)
    if (!rs.sent) {
      pushMergedGateLog(ctx, `TRAFFIC_GATE GREEN_ARB_SKIP ${edgeKey}: ${rs.reason}`)
      return
    }
    ctx.trafficGateLastSentSignal = 'GREEN'
    ctx.trafficGateLastSentSignalAtMs = nowMs
    ctx.trafficGateAwaitGreenAck02 = true
    ctx.trafficGateGreenAckEdgeKey = edgeKey
    ctx.trafficGateGreenAckResumeManual = fromManual
    ctx.trafficGateGreenAckSeen01 = false
    pushMergedGateLog(ctx, `TRAFFIC_GATE GREEN_SENT ${edgeKey}: wait BD=02 then GO`)
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e)
    s.pushLog(`TRAFFIC_GATE GREEN_SEND_FAIL ${edgeKey}: ${msg}`)
  } finally {
    ctx.trafficGateGreenAckInFlight = false
  }
}

export function maybeBlockGoByTrafficGate(ctx: any, nowMs: number, fromManual: boolean): boolean {
  const s = ctx.store
  if (!s) return false
  const key: string = activeGateEdge(ctx, fromManual)
  if (key.length <= 0) {
    logShibie(`gate-inactive mode=${fromManual ? 'MANUAL' : 'AUTO'}`)
    clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)
    return false
  }
  trafficSignalArbiter.beginGateSession(key)

  if (isGateBypassActive(ctx, key, nowMs)) {
    const leftMs: number = Math.max(0, Number(ctx.trafficGateBypassUntilMs || 0) - nowMs)
    logShibie(`gate-bypass edge=${key} left=${leftMs}ms`)
    return false
  }

  if (hasPendingGreenAckForEdge(ctx, key)) {
    s.setAction(`traffic gate waiting green-ack (${key})`)
    if (canLogGate(ctx, nowMs)) {
      pushMergedGateLog(ctx, `TRAFFIC_GATE HOLD ${key}: waiting GREEN_ACK_02`)
    }
    return true
  }

  // 仅在门控阶段临时切换到 traffic 模型，放行后由 clearGateWaiting 自动恢复默认模型。
  const trafficEnabledBeforeGate: boolean = !!videoStore.page2TrafficEnabled
  if (!videoStore.recognitionEnabled) {
    videoStore.setRecognitionEnabled(true)
  }
  if (!trafficEnabledBeforeGate) {
    videoStore.setPage2TrafficEnabled(true)
    ctx.trafficGateResumeModelAfterPass = true
    logShibie(`gate-auto-switch traffic=ON edge=${key}`)
  }

  const signal: TrafficSignal = readTrafficSignal(ctx, nowMs)
  if (signal === 'RED') {
    if (!ctx.trafficGateRedSendInFlight && shouldSendTrafficSignal(ctx, 'RED', nowMs)) {
      ctx.trafficGateRedSendInFlight = true
      void (async (): Promise<void> => {
        try {
          ctx.proto.setMode(ctx.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
          const rs = await trafficSignalArbiter.send(ctx.proto, 'R', 'GATE', 0)
          if (!rs.sent) {
            pushMergedGateLog(ctx, `TRAFFIC_GATE RED_ARB_SKIP ${key}: ${rs.reason}`)
            return
          }
          ctx.trafficGateLastSentSignal = 'RED'
          ctx.trafficGateLastSentSignalAtMs = nowMs
          pushMergedGateLog(ctx, `TRAFFIC_GATE RED_SENT ${key}: x2`)
        } catch (e) {
          const msg: string = e instanceof Error ? e.message : String(e)
          s.pushLog(`TRAFFIC_GATE RED_SEND_FAIL ${key}: ${msg}`)
        } finally {
          ctx.trafficGateRedSendInFlight = false
        }
      })()
    }
  }
  if (signal === 'GREEN') {
    if (!ctx.canRealSend()) {
      markGatePassed(ctx, key, nowMs)
      logShibie(`gate-pass-dry edge=${key} mode=${fromManual ? 'MANUAL' : 'AUTO'}`)
      clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)
      return false
    }
    ctx.trafficGateWaiting = true
    ctx.trafficGateEdgeKey = key
    ctx.trafficGateResumeManual = fromManual
    logShibie(`gate-green edge=${key} mode=${fromManual ? 'MANUAL' : 'AUTO'} wait-ack=02`)
    if (canLogGate(ctx, nowMs)) {
      pushMergedGateLog(ctx, `TRAFFIC_GATE GREEN ${key}: send green then wait BD=02`)
    }
    void armGreenAckGate(ctx, key, fromManual)
    s.setAction(`traffic gate waiting green-ack (${key})`)
    armTrafficGateRetryIfNeeded(ctx)
    return true
  }

  ctx.trafficGateWaiting = true
  ctx.trafficGateEdgeKey = key
  ctx.trafficGateResumeManual = fromManual
  if (ctx.trafficGateResumeModelAfterPass !== true) {
    ctx.trafficGateResumeModelAfterPass = false
  }
  logShibie(`gate-hold edge=${key} mode=${fromManual ? 'MANUAL' : 'AUTO'} signal=${signal}`)
  if (canLogGate(ctx, nowMs)) {
    const modeText: string = fromManual ? 'MANUAL' : 'AUTO'
    pushMergedGateLog(ctx, `TRAFFIC_GATE HOLD ${key}: signal=${signal} mode=${modeText}`)
  }
  s.setAction(`traffic gate waiting (${key})`)
  armTrafficGateRetryIfNeeded(ctx)
  return true
}

function armTrafficGateRetryIfNeeded(ctx: any): void {
  if (!ctx.timerManager || typeof ctx.timerManager.get !== 'function' || typeof ctx.timerManager.set !== 'function') return
  if (ctx.timerManager.get(TRAFFIC_GATE_RETRY_TIMER) >= 0) return
  ctx.trafficGateRetryBusy = false

  const scheduleNext = (): void => {
    const nextId: number = setTimeout((): void => {
      void tickOnce().catch((e: unknown): void => {
        const msg: string = (e instanceof Error) ? e.message : String(e)
        logShibie(`gate-retry-unhandled msg=${msg}`)
      })
    }, TRAFFIC_GATE_RETRY_INTERVAL_MS) as number
    ctx.timerManager.set(TRAFFIC_GATE_RETRY_TIMER, nextId)
  }

  const tickOnce = async (): Promise<void> => {
    if (!ctx.trafficGateWaiting) {
      ctx.timerManager.clear(TRAFFIC_GATE_RETRY_TIMER)
      return
    }
    if (ctx.trafficGateRetryBusy) {
      scheduleNext()
      return
    }

    ctx.trafficGateRetryBusy = true
    try {
      const signal: TrafficSignal = readTrafficSignal(ctx, Date.now())
      if (signal !== 'GREEN') {
        logShibie(`gate-retry-wait edge=${String(ctx.trafficGateEdgeKey || '')} signal=${signal}`)
        scheduleNext()
        return
      }

      const resumeManual: boolean = !!ctx.trafficGateResumeManual
      const passedEdge: string = String(ctx.trafficGateEdgeKey || '')
      logShibie(`gate-retry-green edge=${passedEdge} mode=${resumeManual ? 'MANUAL' : 'AUTO'} wait-ack=02`)
      await armGreenAckGate(ctx, passedEdge, resumeManual)
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e)
      logShibie(`gate-retry-error edge=${String(ctx.trafficGateEdgeKey || '')} msg=${msg}`)
    } finally {
      ctx.trafficGateRetryBusy = false
      if (ctx.trafficGateWaiting) {
        scheduleNext()
      }
    }
  }

  scheduleNext()
}

export function onTrafficGateAckStatus(ctx: any, status: number): void {
  if (!ctx.trafficGateAwaitGreenAck02) return
  const st: number = status & 0xff

  if (st === 0x01) {
    ctx.trafficGateGreenAckSeen01 = true
    const s01 = ctx.store
    const edge01: string = String(ctx.trafficGateGreenAckEdgeKey || '')
    if (s01 && edge01.length > 0 && typeof s01.pushLog === 'function') {
      pushMergedGateLog(ctx, `TRAFFIC_GATE GREEN_ACK_01 ${edge01}: waiting BD=02`)
    }
    return
  }

  if (st !== 0x02) return
  // 现场设备存在 02 先到或仅到 02 的情况；GREEN 发送成功后收到 02 即视为 ACK 到位并放行。

  const edgeKey: string = String(ctx.trafficGateGreenAckEdgeKey || '')
  const resumeManual: boolean = !!ctx.trafficGateGreenAckResumeManual
  if (edgeKey.length <= 0) {
    clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)
    return
  }

  markGatePassed(ctx, edgeKey, Date.now())
  ctx.trafficGateLastGreenAckAtMs = Date.now()
  const s = ctx.store
  if (s && typeof s.pushLog === 'function') {
    pushMergedGateLog(ctx, `TRAFFIC_GATE GREEN_ACK_02 ${edgeKey}: allow GO`)
  }
  clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)

  if (resumeManual) {
    if (typeof ctx.onAction === 'function') {
      setTimeout((): void => {
        if (typeof ctx.onAction === 'function') {
          void ctx.onAction(Page1Action.GO)
        }
      }, TRAFFIC_GATE_GO_SEND_GAP_MS)
    }
    return
  }
  if (typeof ctx.followPathOnce === 'function') {
    setTimeout((): void => {
      if (typeof ctx.followPathOnce === 'function') {
        void ctx.followPathOnce(Date.now(), true)
      }
    }, TRAFFIC_GATE_GO_SEND_GAP_MS)
  }
}
