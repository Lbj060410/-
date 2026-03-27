/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorMapObstacleOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorMapObstacleOps.ets
 * 用途： 处理地图障碍标注、避障重规划与路线阻塞判定。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'
import { PathPlannerAStar, GridIdCodec, RouteEdgeCodec } from './PathPlannerAStar'
import { P1C, VisionLabelKind } from './Page1CoordinatorDefs'
import { commStore } from '../../../state/CommStore'
import { recogStore } from '../../../state/RecogStore'

export function clamp01Value(v: number): number {
  if (v < 0) return 0
  if (v > 1) return 1
  return v
}

export function turnDeltaDegValue(action: Page1Action): number {
  if (action === Page1Action.LEFT) return -90
  if (action === Page1Action.RIGHT) return 90
  if (action === Page1Action.LEFT_HALF) return -45
  if (action === Page1Action.RIGHT_HALF) return 45
  if (action === Page1Action.UTURN) return 180
  return 0
}

export function syncCurrentSnapNodeByPose(ctx: any, xNorm: number, yNorm: number): void {
  const s = ctx.store
  if (!s) return
  if (s.gridNodes.length <= 0) return
  let bestId = ''
  let bestD2 = 0
  for (let i = 0; i < s.gridNodes.length; i++) {
    const n = s.gridNodes[i]
    const dx = n.xNorm - xNorm
    const dy = n.yNorm - yNorm
    const d2 = dx * dx + dy * dy
    if (bestId.length <= 0 || d2 < bestD2) {
      bestId = n.id
      bestD2 = d2
    }
  }
  const snapThresholdNorm = 0.035
  if (bestId.length > 0 && bestD2 <= snapThresholdNorm * snapThresholdNorm) {
    s.currentSnapNodeId = bestId
    return
  }
  s.currentSnapNodeId = ''
}

export async function animateMapPoseTransition(
  ctx: any,
  fromXNorm: number,
  fromYNorm: number,
  toXNorm: number,
  toYNorm: number,
  fromHeadingDeg: number,
  toHeadingDeg: number,
  speed: number,
  durationMs: number,
  token: number
): Promise<void> {
  const safeDurationMs = Math.max(P1C.MAP_PREVIEW_TICK_MS, durationMs)
  const steps = Math.max(1, Math.round(safeDurationMs / P1C.MAP_PREVIEW_TICK_MS))
  const headingDelta = ctx.headingErrorDeg(fromHeadingDeg, toHeadingDeg)
  for (let i = 1; i <= steps; i++) {
    if (!ctx.isMapPoseAnimationActive(token)) return
    const t = i / steps
    const xNorm = clamp01Value(fromXNorm + (toXNorm - fromXNorm) * t)
    const yNorm = clamp01Value(fromYNorm + (toYNorm - fromYNorm) * t)
    const headingDeg = ctx.norm360(fromHeadingDeg + headingDelta * t)
    const liveSpeed = i >= steps ? 0 : speed
    const s = ctx.store
    if (s && !s.poseFollowEnabled) {
      s.carX = xNorm
      s.carY = yNorm
    }
    ctx.updatePoseAndTelemetryForDisplay(xNorm, yNorm, headingDeg, liveSpeed)
    if (i < steps) await ctx.sleep(P1C.MAP_PREVIEW_TICK_MS)
  }
}

export function previewManualActionOnMap(ctx: any, action: Page1Action): void {
  if (
    action !== Page1Action.GO &&
    action !== Page1Action.BACK &&
    action !== Page1Action.LEFT &&
    action !== Page1Action.RIGHT &&
    action !== Page1Action.LEFT_HALF &&
    action !== Page1Action.RIGHT_HALF &&
    action !== Page1Action.UTURN
  ) {
    return
  }
  if (ctx.motionRunning()) return
  void previewManualActionOnMapAsync(ctx, action)
}

export async function previewManualActionOnMapAsync(ctx: any, action: Page1Action): Promise<void> {
  const s = ctx.store
  if (!s) return
  const startXNorm = clamp01Value(s.pose.xNorm)
  const startYNorm = clamp01Value(s.pose.yNorm)
  const startHeadingDeg = ctx.norm360(s.pose.headingDeg)
  if (action === Page1Action.GO || action === Page1Action.BACK) {
    const headingDeg = ctx.normToCardinal(startHeadingDeg)
    let dirX = 0
    let dirY = 0
    if (headingDeg === 0) dirX = 1
    else if (headingDeg === 90) dirY = 1
    else if (headingDeg === 180) dirX = -1
    else dirY = -1
    const sign = action === Page1Action.BACK ? -1 : 1
    const toXNorm = clamp01Value(startXNorm + dirX * P1C.MANUAL_MAP_STEP_NORM * sign)
    const toYNorm = clamp01Value(startYNorm + dirY * P1C.MANUAL_MAP_STEP_NORM * sign)
    const speed = action === Page1Action.BACK ? -20 : 20
    const token = ctx.beginMapPoseAnimation()
    await animateMapPoseTransition(
      ctx,
      startXNorm,
      startYNorm,
      toXNorm,
      toYNorm,
      headingDeg,
      headingDeg,
      speed,
      P1C.MANUAL_MAP_MOVE_MS,
      token
    )
    if (!ctx.isMapPoseAnimationActive(token)) return
    ctx.logicalHeadingDeg = headingDeg
    ctx.logicalHeadingInited = true
    syncCurrentSnapNodeByPose(ctx, toXNorm, toYNorm)
    return
  }
  const deltaDeg = turnDeltaDegValue(action)
  if (deltaDeg === 0) return
  const toHeadingDeg = ctx.norm360(startHeadingDeg + deltaDeg)
  const token = ctx.beginMapPoseAnimation()
  await animateMapPoseTransition(
    ctx,
    startXNorm,
    startYNorm,
    startXNorm,
    startYNorm,
    startHeadingDeg,
    toHeadingDeg,
    0,
    P1C.MANUAL_MAP_TURN_MS,
    token
  )
  if (!ctx.isMapPoseAnimationActive(token)) return
  ctx.logicalHeadingDeg = ctx.normToCardinal(toHeadingDeg)
  ctx.logicalHeadingInited = true
  syncCurrentSnapNodeByPose(ctx, startXNorm, startYNorm)
}

export function playMapReverseParkingAnimation(ctx: any, arrivedId: string, goalId: string, headingDeg: number): void {
  void playMapReverseParkingAnimationAsync(ctx, arrivedId, goalId, headingDeg)
}

export async function playMapReverseParkingAnimationAsync(
  ctx: any,
  arrivedId: string,
  goalId: string,
  headingDeg: number
): Promise<void> {
  await ctx.sleep(P1C.SIM_TICK_MS)
  const s = ctx.store
  if (!s) return
  const goalNode = ctx.findNode(goalId)
  if (!goalNode) return
  const arrivedNode = ctx.findNode(arrivedId)
  const startXNorm = arrivedNode ? arrivedNode.xNorm : clamp01Value(s.pose.xNorm)
  const startYNorm = arrivedNode ? arrivedNode.yNorm : clamp01Value(s.pose.yNorm)
  const forwardHeadingDeg = ctx.normToCardinal(headingDeg)
  const reverseHeadingDeg = ctx.normToCardinal(forwardHeadingDeg + 180)
  const token = ctx.beginMapPoseAnimation()
  s.pushLog(`PARK_MAP_ANIM: ${arrivedId}->${goalId} 掉头后倒车入库`)
  await animateMapPoseTransition(
    ctx,
    startXNorm,
    startYNorm,
    startXNorm,
    startYNorm,
    forwardHeadingDeg,
    reverseHeadingDeg,
    0,
    P1C.MANUAL_MAP_TURN_MS,
    token
  )
  if (!ctx.isMapPoseAnimationActive(token)) return
  await animateMapPoseTransition(
    ctx,
    startXNorm,
    startYNorm,
    goalNode.xNorm,
    goalNode.yNorm,
    reverseHeadingDeg,
    reverseHeadingDeg,
    -20,
    P1C.PARK_HANDOFF_REVERSE_MAP_MS,
    token
  )
  if (!ctx.isMapPoseAnimationActive(token)) return
  s.currentSnapNodeId = goalId.trim().toUpperCase()
  ctx.logicalHeadingDeg = reverseHeadingDeg
  ctx.logicalHeadingInited = true
}

export function startsWithAny(s: string, prefixes: Array<string>): boolean {
  for (let i = 0; i < prefixes.length; i++) {
    if (s.startsWith(prefixes[i])) return true
  }
  return false
}

export function classifyLabel(label: string): VisionLabelKind {
  const x = label.trim().toLowerCase()
  if (x.length === 0) return VisionLabelKind.IGNORE
  if (startsWithAny(x, ['obstacle/', 'block/', 'barrier/'])) return VisionLabelKind.OBSTACLE
  if (x === 'person' || x === 'car' || x === 'truck' || x === 'bus' || x === 'cone' || x === 'barrel' || x === 'box' || x === 'obstacle') {
    return VisionLabelKind.OBSTACLE
  }
  if (x === 'traffic_light_red' || x === 'traffic_light_yellow' || x === 'traffic_light_green' || x === 'red' || x === 'yellow' || x === 'green' || x === 'stop_sign') {
    return VisionLabelKind.TRAFFIC
  }
  if (startsWithAny(x, ['qr/', 'plate/', 'color/', 'shape/', 'sign/', 'image/', 'task/'])) return VisionLabelKind.TASK
  return VisionLabelKind.TASK
}

export function maybeLogVisionTaskOrTraffic(ctx: any, nowMs: number): void {
  const s = ctx.store
  if (!s) return
  if (nowMs - ctx.lastVisionLogAtMs < P1C.VISION_LOG_COOLDOWN_MS) return
  const r = recogStore.lastRecog
  if (!r || r.boxes.length <= 0) return
  for (let i = 0; i < r.boxes.length; i++) {
    const b = r.boxes[i]
    const kind = classifyLabel(b.label)
    if (kind === VisionLabelKind.TASK) {
      ctx.lastVisionLogAtMs = nowMs
      s.pushLog(`VISION TASK: ${b.label} score=${b.score.toFixed(2)}`)
      return
    }
    if (kind === VisionLabelKind.TRAFFIC) {
      ctx.lastVisionLogAtMs = nowMs
      s.pushLog(`VISION TRAFFIC: ${b.label} score=${b.score.toFixed(2)}`)
      return
    }
  }
}

export function yoloSuggestBlockedNodeId(ctx: any, nowMs: number): string {
  if (nowMs - ctx.lastYoloTriggerAtMs < P1C.YOLO_COOLDOWN_MS) return ''
  const r = recogStore.lastRecog
  if (!r || r.boxes.length <= 0) return ''
  let hasObstacle = false
  for (let i = 0; i < r.boxes.length; i++) {
    if (classifyLabel(r.boxes[i].label) === VisionLabelKind.OBSTACLE) {
      hasObstacle = true
      break
    }
  }
  if (!hasObstacle) return ''
  const s = ctx.store
  if (!s) return ''
  if (s.pathNodes.length <= 1 || s.pathIndex >= s.pathNodes.length - 1) return ''
  const nextId = s.pathNodes[s.pathIndex + 1]
  if (!GridIdCodec.isValidId(nextId)) return ''
  if (s.currentSnapNodeId === nextId) return ''
  ctx.lastYoloTriggerAtMs = nowMs
  return nextId
}

export function maybeTriggerRoutePointObstacle(ctx: any): boolean {
  const s = ctx.store
  if (!s) return false
  if (ctx.trafficGateWaiting || ctx.aheadVisionPending || ctx.parkingInProgress) return false
  if (s.routeObstaclePoints.length <= 0) return false
  const now = Date.now()
  const th = s.obstaclePointTriggerThresholdNorm
  const th2 = th * th
  let hitId = ''
  for (let i = 0; i < s.routeObstaclePoints.length; i++) {
    const p = s.routeObstaclePoints[i]
    if (p.triggered) continue
    if (now - p.createdAtMs < 350) continue
    const dx = s.pose.xNorm - p.xNorm
    const dy = s.pose.yNorm - p.yNorm
    const d2 = dx * dx + dy * dy
    if (d2 <= th2) {
      hitId = p.id
      break
    }
  }
  if (hitId.length <= 0) return false
  const hit = s.markRouteObstacleTriggered(hitId, now)
  if (!hit) return false
  s.addBlockedEdgeIfAbsent(hit.edgeId, 'POINT_HIT')
  const mergedPointNodes = promoteBlockedEdgePairsToBlockedNodes(ctx)
  if (mergedPointNodes.length > 0) s.pushLog(`点障碍转点禁行：${mergedPointNodes.join(',')}`)
  s.pushLog(`点障碍命中：${hit.id} edge=${hit.edgeId} t=${hit.t.toFixed(2)}`)
  if (s.destApplied.length <= 0) return true
  ctx.stopActiveMotion()
  commStore.bumpReplan()
  commStore.bumpAvoid()
  ctx.lastReplanAtMs = now
  ctx.pauseUntilMs = now + P1C.PAUSE_REPLAN_MS
  void ctx.sendDriveActionDirect(Page1Action.STOP)
  s.pushLog(`REPLAN: POINT_HIT ${hit.edgeId} -> STOP&PLAN`)
  ctx.planPath(s.destApplied)
  return true
}

export function frontRouteEdgeIdForDriving(ctx: any): string {
  const s = ctx.store
  if (!s) return ''
  const liveAction = ctx.motionPlayer.currentAction()
  if (ctx.motionRunning() && liveAction === Page1Action.GO) {
    const fromId = ctx.motionPlayer.currentFromId().trim().toUpperCase()
    const toId = ctx.motionPlayer.currentToId().trim().toUpperCase()
    if (GridIdCodec.isValidId(fromId) && GridIdCodec.isValidId(toId)) return RouteEdgeCodec.normalize(fromId, toId)
  }
  if (s.pathNodes.length <= 1) return ''
  if (s.pathIndex < 0 || s.pathIndex >= s.pathNodes.length - 1) return ''
  const fromId = s.pathNodes[s.pathIndex].trim().toUpperCase()
  const toId = s.pathNodes[s.pathIndex + 1].trim().toUpperCase()
  if (!GridIdCodec.isValidId(fromId) || !GridIdCodec.isValidId(toId)) return ''
  return RouteEdgeCodec.normalize(fromId, toId)
}

export function markRouteObstaclePointOnEdge(ctx: any, edgeId: string, nowMs: number): void {
  const s = ctx.store
  if (!s) return
  const seg = RouteEdgeCodec.parse(edgeId)
  if (!seg) return
  const a = ctx.findNode(seg.a)
  const b = ctx.findNode(seg.b)
  if (!a || !b) return
  const t = 0.5
  const xNorm = a.xNorm + (b.xNorm - a.xNorm) * t
  const yNorm = a.yNorm + (b.yNorm - a.yNorm) * t
  const pointId = `auto_obs_${nowMs}_${edgeId}`
  for (let i = 0; i < s.routeObstaclePoints.length; i++) {
    const p = s.routeObstaclePoints[i]
    if (p.edgeId !== edgeId) continue
    if (Math.abs(p.t - t) <= 0.08) return
  }
  const next = []
  for (let i = 0; i < s.routeObstaclePoints.length; i++) next.push(s.routeObstaclePoints[i])
  next.push({
    id: pointId,
    xNorm: xNorm,
    yNorm: yNorm,
    edgeId: edgeId,
    t: t,
    createdAtMs: nowMs,
    triggered: false,
    hitAtMs: 0
  })
  s.routeObstaclePoints = next
  s.pushLog(`障碍点标注：edge=${edgeId} t=${t.toFixed(2)}`)
}

export function promoteBlockedEdgePairsToBlockedNodes(ctx: any): Array<string> {
  const s = ctx.store
  if (!s) return []
  if (s.blockedEdges.length < 2) return []
  const curSnapId = s.currentSnapNodeId.trim().toUpperCase()
  const candidateNodes = []
  for (let i = 0; i < s.blockedEdges.length; i++) {
    const parsed = RouteEdgeCodec.parse(s.blockedEdges[i])
    if (!parsed) continue
    if (candidateNodes.indexOf(parsed.a) < 0) candidateNodes.push(parsed.a)
    if (candidateNodes.indexOf(parsed.b) < 0) candidateNodes.push(parsed.b)
  }
  const removeEdges = []
  const promotedNodes = []
  for (let i = 0; i < candidateNodes.length; i++) {
    const nodeId = candidateNodes[i]
    if (nodeId === curSnapId) continue
    const touchingEdges = []
    for (let j = 0; j < s.blockedEdges.length; j++) {
      const edgeId = s.blockedEdges[j]
      const parsed = RouteEdgeCodec.parse(edgeId)
      if (!parsed) continue
      if (parsed.a === nodeId || parsed.b === nodeId) touchingEdges.push(edgeId)
    }
    // 永久分界线不计入升级判断，只统计动态阻塞边
    let dynamicTouchCount: number = 0
    for (let k = 0; k < touchingEdges.length; k++) {
      if (!s.isPermanentBlockedEdge(touchingEdges[k])) dynamicTouchCount++
    }
    if (dynamicTouchCount < 2) continue
    if (promotedNodes.indexOf(nodeId) < 0) promotedNodes.push(nodeId)
    s.addBlockedIfAbsent(nodeId, 'EDGE_PAIR')
    for (let j = 0; j < touchingEdges.length; j++) {
      const edgeId = touchingEdges[j]
      if (s.isPermanentBlockedEdge(edgeId)) continue  // 永久分界线不移除
      if (removeEdges.indexOf(edgeId) < 0) removeEdges.push(edgeId)
    }
    s.pushLog(`路段禁行转点禁行：${nodeId} edges=[${touchingEdges.join(',')}]`)
  }
  if (removeEdges.length > 0) {
    const nextEdges = []
    for (let i = 0; i < s.blockedEdges.length; i++) {
      const edgeId = s.blockedEdges[i]
      if (removeEdges.indexOf(edgeId) >= 0) continue
      nextEdges.push(edgeId)
    }
    s.blockedEdges = nextEdges
  }
  return promotedNodes
}

export function maybeHandleDrivingUltrasonicObstacle(ctx: any, nowMs: number, edgeOverride: string = ''): void {
  const s = ctx.store
  if (!s) return
  if (ctx.parkingInProgress) return
  if (s.destApplied.length <= 0 || s.pathNodes.length <= 1 || s.pathIndex >= s.pathNodes.length - 1) return
  const edgeId = edgeOverride.length > 0 ? edgeOverride : frontRouteEdgeIdForDriving(ctx)
  if (edgeId.length <= 0) return
  const addedEdge = s.addBlockedEdgeIfAbsent(edgeId, 'ULTRASONIC_P1_01')
  markRouteObstaclePointOnEdge(ctx, edgeId, nowMs)
  const mergedNodes = promoteBlockedEdgePairsToBlockedNodes(ctx)
  ctx.clearAheadVisionReplanState()
  ctx.stopActiveMotion()
  commStore.bumpReplan()
  commStore.bumpAvoid()
  ctx.lastReplanAtMs = nowMs
  ctx.pauseUntilMs = nowMs + P1C.PAUSE_REPLAN_MS
  void ctx.sendDriveActionDirect(Page1Action.STOP)
  if (mergedNodes.length > 0) {
    s.pushLog(`REPLAN: ULTRASONIC_P1_01 edge=${edgeId} node=[${mergedNodes.join(',')}] -> STOP&PLAN`)
  } else if (addedEdge) {
    s.pushLog(`REPLAN: ULTRASONIC_P1_01 ${edgeId} -> STOP&PLAN`)
  } else {
    s.pushLog(`REPLAN: ULTRASONIC_P1_01 ${edgeId} (already blocked) -> FORCE_STOP&PLAN`)
  }
  const nearId = ctx.nearestNodeIdByPose()
  if (GridIdCodec.isValidId(nearId)) {
    s.currentSnapNodeId = nearId
    s.pushLog(`REPLAN_SNAP: use nearest node ${nearId}`)
  }
  ctx.planPath(s.destApplied)
}

export function maybeReplanOnObstacle(ctx: any): void {
  const s = ctx.store
  if (!s) return
  if (ctx.trafficGateWaiting || ctx.aheadVisionPending || ctx.parkingInProgress) return
  const now = Date.now()
  if (typeof ctx.maybeHandleBarrierEmergencyStop === 'function' && ctx.maybeHandleBarrierEmergencyStop(now)) return
  if (s.destApplied.length === 0) return
  if (now < ctx.pauseUntilMs) return
  if (now - ctx.lastReplanAtMs < P1C.REPLAN_COOLDOWN_MS) return
  if (s.riskScore >= 95) commStore.bumpEStop()
  maybeLogVisionTaskOrTraffic(ctx, now)
  const riskHigh = s.riskScore >= 70
  const yoloBlockId = yoloSuggestBlockedNodeId(ctx, now)
  if (yoloBlockId.length > 0) s.addBlockedIfAbsent(yoloBlockId, 'YOLO')
  const blockedNext = isNextNodeBlocked(ctx)
  if (!blockedNext && !riskHigh && yoloBlockId.length === 0) return
  ctx.stopActiveMotion()
  commStore.bumpReplan()
  commStore.bumpAvoid()
  ctx.lastReplanAtMs = now
  ctx.pauseUntilMs = now + P1C.PAUSE_REPLAN_MS
  void ctx.sendDriveActionDirect(Page1Action.STOP)
  s.pushLog(`REPLAN: ${(blockedNext ? 'NEXT_BLOCKED' : (riskHigh ? 'RISK_HIGH' : 'YOLO_OBSTACLE'))} -> STOP&PLAN`)
  const nearId = nearestNodeIdByPose(ctx)
  if (GridIdCodec.isValidId(nearId)) {
    s.currentSnapNodeId = nearId
    s.pushLog(`REPLAN_SNAP: use nearest node ${nearId}`)
  }
  ctx.planPath(s.destApplied)
}

export function isNextNodeBlocked(ctx: any): boolean {
  const s = ctx.store
  if (!s) return false
  if (s.pathNodes.length <= 1 || s.pathIndex >= s.pathNodes.length - 1) return false
  const fromId = s.pathNodes[s.pathIndex]
  const nextId = s.pathNodes[s.pathIndex + 1]
  if (s.isBlocked(nextId)) return true
  return s.isBlockedEdge(fromId, nextId)
}

export function nearestNodeIdByPose(ctx: any): string {
  const s = ctx.store
  if (!s || s.gridNodes.length === 0) return ''
  const px = s.pose.xNorm
  const py = s.pose.yNorm
  let bestId = ''
  let bestD2 = 0
  for (let i = 0; i < s.gridNodes.length; i++) {
    const n = s.gridNodes[i]
    const dx = px - n.xNorm
    const dy = py - n.yNorm
    const d2 = dx * dx + dy * dy
    if (bestId.length === 0) {
      bestId = n.id
      bestD2 = d2
      continue
    }
    if (d2 < bestD2) {
      bestId = n.id
      bestD2 = d2
    }
  }
  return bestId
}

export function findNearestRouteSegmentByPose(ctx: any): any {
  const s = ctx.store
  if (!s) return undefined
  const px = s.pose.xNorm
  const py = s.pose.yNorm
  const edges = PathPlannerAStar.routeEdges()
  let best = undefined
  let bestD2 = 0
  for (let i = 0; i < edges.length; i++) {
    const e = edges[i]
    const a = ctx.findNode(e.a)
    const b = ctx.findNode(e.b)
    if (!a || !b) continue
    const vx = b.xNorm - a.xNorm
    const vy = b.yNorm - a.yNorm
    const len2 = vx * vx + vy * vy
    if (len2 <= 1e-8) continue
    let t = ((px - a.xNorm) * vx + (py - a.yNorm) * vy) / len2
    if (t < 0) t = 0
    if (t > 1) t = 1
    const qx = a.xNorm + t * vx
    const qy = a.yNorm + t * vy
    const dx = px - qx
    const dy = py - qy
    const d2 = dx * dx + dy * dy
    if (!best || d2 < bestD2) {
      bestD2 = d2
      best = {
        aId: e.a,
        bId: e.b,
        ax: a.xNorm,
        ay: a.yNorm,
        bx: b.xNorm,
        by: b.yNorm,
        px: px,
        py: py,
        t: t,
        d2: d2
      }
    }
  }
  return best
}

export function chooseSegmentEndpointForGoal(ctx: any, seg: any, goal: string, blocked: Array<string>, blockedEdges: Array<string>): any {
  const s = ctx.store
  if (!s) return undefined
  let best = undefined
  let bestScore = 0
  const targetA = seg.aId
  const targetB = seg.bId
  const targetIds = [targetA, targetB]
  for (let i = 0; i < targetIds.length; i++) {
    const targetId = targetIds[i]
    const fromId = targetId === targetA ? targetB : targetA
    if (s.isBlocked(targetId)) continue
    if (s.isBlockedEdge(fromId, targetId)) continue
    const tail = PathPlannerAStar.plan(targetId, goal, blocked, blockedEdges)
    if (!tail.ok) continue
    const distAlong = targetId === targetA ? seg.t : (1 - seg.t)
    const tx = targetId === targetA ? seg.ax : seg.bx
    const ty = targetId === targetA ? seg.ay : seg.by
    let desired = ctx.headingDegFromTo(seg.px, seg.py, tx, ty)
    if (distAlong < 0.04) desired = ctx.segmentHeadingDeg(fromId, targetId)
    const headingErr = Math.abs(ctx.headingErrorDeg(ctx.logicalHeadingDeg, desired))
    const headingPenaltyWeight = ctx.segHeadingPenaltyWeightValue(s)
    const headingPenalty = (headingErr / 180.0) * headingPenaltyWeight
    const pathCost = Math.max(0, tail.path.length - 1)
    const score = pathCost + distAlong + headingPenalty
    if (!best || score < bestScore) {
      bestScore = score
      best = { fromId: fromId, targetId: targetId, t: seg.t, score: score }
    }
  }
  return best
}

export function tryBuildSegmentAwarePath(ctx: any, goal: string, blocked: Array<string>, blockedEdges: Array<string>): Array<string> | undefined {
  const s = ctx.store
  if (!s) return undefined
  if (!s.segPlannerEnabled || !s.poseInited) return undefined
  const seg = findNearestRouteSegmentByPose(ctx)
  if (!seg) return undefined
  const minT = ctx.segMidMinTValue(s)
  const maxT = ctx.segMidMaxTValue(s)
  if (seg.t <= minT || seg.t >= maxT) return undefined
  const decision = chooseSegmentEndpointForGoal(ctx, seg, goal, blocked, blockedEdges)
  if (!decision) return undefined
  const tail = PathPlannerAStar.plan(decision.targetId, goal, blocked, blockedEdges)
  if (!tail.ok) return undefined
  const path: Array<string> = []
  if (!s.isBlocked(decision.fromId) && decision.fromId !== decision.targetId) {
    path.push(decision.fromId)
  }
  for (let i = 0; i < tail.path.length; i++) {
    const id = tail.path[i]
    if (path.length <= 0 || path[path.length - 1] !== id) path.push(id)
  }
  if (path.length <= 0) return undefined
  s.pushLog(`A*: SEG mode=${decision.fromId}->${decision.targetId} t=${decision.t.toFixed(2)} score=${decision.score.toFixed(2)}`)
  return path
}

export function findPendingRouteObstacleOnEdge(ctx: any, edgeId: string, nowMs: number): any {
  const s = ctx.store
  if (!s) return undefined
  const x = edgeId.trim().toUpperCase()
  if (x.length <= 0) return undefined
  for (let i = 0; i < s.routeObstaclePoints.length; i++) {
    const p = s.routeObstaclePoints[i]
    if (p.triggered) continue
    if (nowMs - p.createdAtMs < 350) continue
    if (p.edgeId.trim().toUpperCase() !== x) continue
    return p
  }
  return undefined
}

export function maybeStartAheadVisionReplan(ctx: any, fromId: string, toId: string, nowMs: number): boolean {
  const s = ctx.store
  if (!s) return false
  if (ctx.aheadVisionPending) return true
  if (s.destApplied.length <= 0) return false
  const edgeId = RouteEdgeCodec.normalize(fromId, toId)
  const p = findPendingRouteObstacleOnEdge(ctx, edgeId, nowMs)
  if (!p) return false
  const hit = s.markRouteObstacleTriggered(p.id, nowMs)
  if (!hit) return false
  ctx.aheadVisionPending = true
  ctx.aheadVisionReadyAtMs = nowMs + P1C.AHEAD_VISION_REPLAN_MS
  ctx.aheadVisionEdgeId = edgeId
  s.setAction('前视发现障碍，等待重规划')
  s.pushLog(`VISION_AHEAD: edge=${edgeId} point=${hit.id} -> wait=${P1C.AHEAD_VISION_REPLAN_MS}ms`)
  return true
}

export function maybeHandleAheadVisionReplan(ctx: any, nowMs: number): boolean {
  if (!ctx.aheadVisionPending) return false
  if (ctx.trafficGateWaiting) return true
  const s = ctx.store
  if (!s) {
    ctx.clearAheadVisionReplanState()
    return true
  }
  if (nowMs < ctx.aheadVisionReadyAtMs) return true
  const edgeId = ctx.aheadVisionEdgeId
  const goal = s.destApplied
  ctx.clearAheadVisionReplanState()
  if (edgeId.length <= 0 || goal.length <= 0) return true
  s.addBlockedEdgeIfAbsent(edgeId, 'VISION_AHEAD')
  const mergedNodes = promoteBlockedEdgePairsToBlockedNodes(ctx)
  if (mergedNodes.length > 0) s.pushLog(`前视障碍转点禁行：${mergedNodes.join(',')}`)
  commStore.bumpReplan()
  commStore.bumpAvoid()
  ctx.lastReplanAtMs = nowMs
  ctx.pauseUntilMs = nowMs + P1C.PAUSE_REPLAN_MS
  void ctx.sendDriveActionDirect(Page1Action.STOP)
  s.pushLog(`REPLAN: VISION_AHEAD ${edgeId} -> STOP&PLAN`)
  ctx.planPath(goal)
  return true
}


