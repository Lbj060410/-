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
import { RecognitionResultViewHelper } from '../../../services/recognition/RecognitionResultViewHelper'
import { RecognitionSubtype, RecognitionTaskSource } from '../../../services/recognition/RecognitionTask'
import { RecognitionResult } from '../../../services/recognition/RecognitionResult'

type TrafficSignal = 'RED' | 'GREEN' | 'YELLOW' | 'UNKNOWN'

const TRAFFIC_GATE_LOG_COOLDOWN_MS: number = 1200
const EDGE_B4_B6: string = 'B4->B6'
const TRAFFIC_GATE_RETRY_TIMER: string = 'traffic_gate_retry'
const TRAFFIC_GATE_RETRY_INTERVAL_MS: number = 800
const TRAFFIC_SIGNAL_FRESH_MAX_AGE_MS: number = 5000
const TRAFFIC_GATE_GREEN_CONFIRM_COUNT: number = 2
const TRAFFIC_GATE_PASS_BYPASS_MS: number = 2200

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
  ctx.trafficGateGreenStreak = 0
  ctx.trafficGateLastSignalKey = ''
  ctx.trafficGateLastSignal = 'UNKNOWN'
  ctx.trafficGateResumeModelAfterPass = false
  if (ctx.timerManager && typeof ctx.timerManager.clear === 'function') {
    ctx.timerManager.clear(TRAFFIC_GATE_RETRY_TIMER)
  }
  if (restoreDefaultModel) {
    videoStore.setRecognitionEnabled(true)
    videoStore.setPage2Yolov26BarrierEnabled(true)
    logShibie('gate-restore-default-model yolov26barrier=ON')
  }
}

function canLogGate(ctx: any, nowMs: number): boolean {
  if (!ctx.trafficGateLastLogAtMs || nowMs - ctx.trafficGateLastLogAtMs >= TRAFFIC_GATE_LOG_COOLDOWN_MS) {
    ctx.trafficGateLastLogAtMs = nowMs
    return true
  }
  return false
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

export function maybeBlockGoByTrafficGate(ctx: any, nowMs: number, fromManual: boolean): boolean {
  const s = ctx.store
  if (!s) return false
  const key: string = activeGateEdge(ctx, fromManual)
  if (key.length <= 0) {
    logShibie(`gate-inactive mode=${fromManual ? 'MANUAL' : 'AUTO'}`)
    clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)
    return false
  }

  if (isGateBypassActive(ctx, key, nowMs)) {
    const leftMs: number = Math.max(0, Number(ctx.trafficGateBypassUntilMs || 0) - nowMs)
    logShibie(`gate-bypass edge=${key} left=${leftMs}ms`)
    return false
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
  if (signal === 'GREEN') {
    markGatePassed(ctx, key, nowMs)
    logShibie(`gate-pass edge=${key} mode=${fromManual ? 'MANUAL' : 'AUTO'}`)
    if (ctx.trafficGateWaiting && ctx.trafficGateEdgeKey === key && canLogGate(ctx, nowMs)) {
      s.pushLog(`TRAFFIC_GATE PASS ${key}: GREEN`)
    }
    clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)
    return false
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
    s.pushLog(`TRAFFIC_GATE HOLD ${key}: signal=${signal} mode=${modeText}`)
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
      markGatePassed(ctx, passedEdge, Date.now())
      logShibie(`gate-retry-pass edge=${String(ctx.trafficGateEdgeKey || '')} mode=${resumeManual ? 'MANUAL' : 'AUTO'}`)
      clearGateWaiting(ctx, !!ctx.trafficGateResumeModelAfterPass)

      if (resumeManual) {
        if (typeof ctx.onAction === 'function') {
          await ctx.onAction(Page1Action.GO)
        }
        return
      }
      if (typeof ctx.followPathOnce === 'function') {
        await ctx.followPathOnce(Date.now(), true)
      }
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
