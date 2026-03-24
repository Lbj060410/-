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
import { RecognitionResultViewHelper } from '../../../services/recognition/RecognitionResultViewHelper'
import { RecognitionTaskSource } from '../../../services/recognition/RecognitionTask'

type TrafficSignal = 'RED' | 'GREEN' | 'YELLOW' | 'UNKNOWN'

const TRAFFIC_GATE_LOG_COOLDOWN_MS: number = 1200
const EDGE_B4_B6: string = 'B4->B6'
const EDGE_D6_F6: string = 'D6->F6'

function isActiveGateEdge(fromId: string, toId: string): boolean {
  return (fromId === 'B4' && toId === 'B6') ||
    (fromId === 'D6' && toId === 'F6')
}

function edgeKey(fromId: string, toId: string): string {
  if (fromId === 'B4' && toId === 'B6') return EDGE_B4_B6
  if (fromId === 'D6' && toId === 'F6') return EDGE_D6_F6
  return ''
}

function headingGateEdgeBySnap(ctx: any): string {
  const s = ctx.store
  if (!s) return ''
  const snapId: string = s.currentSnapNodeId.trim().toUpperCase()
  if (snapId.length <= 0) return ''

  let headingDeg: number = 0
  if (ctx.logicalHeadingInited) {
    headingDeg = ctx.logicalHeadingDeg
  } else {
    headingDeg = s.pose.headingDeg
  }
  const headingCardinal: number = ctx.normToCardinal(headingDeg)

  // B4 -> B6 : southbound on B column
  if (snapId === 'B4' && headingCardinal === 90) return EDGE_B4_B6
  // D6 -> F6 : eastbound on row 6
  if (snapId === 'D6' && headingCardinal === 0) return EDGE_D6_F6
  return ''
}

function activeGateEdge(ctx: any): string {
  const s = ctx.store
  if (!s) return ''
  if (s.pathNodes.length > 1 && s.pathIndex >= 0 && s.pathIndex < s.pathNodes.length - 1) {
    const fromId: string = s.pathNodes[s.pathIndex].trim().toUpperCase()
    const toId: string = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
    if (isActiveGateEdge(fromId, toId)) {
      return edgeKey(fromId, toId)
    }
  }
  return headingGateEdgeBySnap(ctx)
}

function normalizeTrafficSignal(raw: string): TrafficSignal {
  const x: string = raw.trim().toLowerCase()
  if (x.length <= 0 || x === '-') return 'UNKNOWN'
  if (x.indexOf('red') >= 0 || x.indexOf('stop') >= 0 || x.indexOf('hong') >= 0 || x === 'r') return 'RED'
  if (x.indexOf('green') >= 0 || x.indexOf('go') >= 0 || x.indexOf('lv') >= 0 || x.indexOf('lu') >= 0 || x === 'g') return 'GREEN'
  if (x.indexOf('yellow') >= 0 || x.indexOf('amber') >= 0 || x.indexOf('huang') >= 0 || x === 'y') return 'YELLOW'
  return 'UNKNOWN'
}

function liveTrafficSignal(): TrafficSignal {
  const text: string = RecognitionResultViewHelper.trafficLightTextForSources(
    recogStore,
    [RecognitionTaskSource.PAGE2_BUTTON]
  )
  return normalizeTrafficSignal(text)
}

function clearGateWaiting(ctx: any): void {
  ctx.trafficGateWaiting = false
  ctx.trafficGateEdgeKey = ''
}

function canLogGate(ctx: any, nowMs: number): boolean {
  if (!ctx.trafficGateLastLogAtMs || nowMs - ctx.trafficGateLastLogAtMs >= TRAFFIC_GATE_LOG_COOLDOWN_MS) {
    ctx.trafficGateLastLogAtMs = nowMs
    return true
  }
  return false
}

export function maybeBlockGoByTrafficGate(ctx: any, nowMs: number, fromManual: boolean): boolean {
  const s = ctx.store
  if (!s) return false
  const key: string = activeGateEdge(ctx)
  if (key.length <= 0) {
    clearGateWaiting(ctx)
    return false
  }

  const signal: TrafficSignal = liveTrafficSignal()
  if (signal === 'GREEN') {
    if (ctx.trafficGateWaiting && ctx.trafficGateEdgeKey === key && canLogGate(ctx, nowMs)) {
      s.pushLog(`TRAFFIC_GATE PASS ${key}: GREEN`)
    }
    clearGateWaiting(ctx)
    return false
  }

  ctx.trafficGateWaiting = true
  ctx.trafficGateEdgeKey = key
  if (canLogGate(ctx, nowMs)) {
    const modeText: string = fromManual ? 'MANUAL' : 'AUTO'
    s.pushLog(`TRAFFIC_GATE HOLD ${key}: signal=${signal} mode=${modeText}`)
  }
  s.setAction(`traffic gate waiting (${key})`)
  return true
}


