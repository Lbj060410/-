/**
 * 代码指南：
 * 文件： 
pages/page1/app/TrafficLightRouteMatcher.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/TrafficLightRouteMatcher.ets
 * 用途： 将交通灯识别结果与当前路径段进行匹配，用于通行决策。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * TrafficLightRouteMatcher
 * Pure functions to match map traffic lights with route segments.
 */
import { MapTrafficLightPoint } from './Page1UiStore'

export interface RouteMatcherNode {
  xNorm: number
  yNorm: number
}

export interface TrafficLightRouteMatchInput {
  trafficLights: Array<MapTrafficLightPoint>
  controlDistanceNorm: number
  fromId: string
  toId: string
  directionMaxErrDeg: number
  findNode(id: string): RouteMatcherNode | undefined
  segmentHeadingDeg(fromId: string, toId: string): number
  headingErrorDeg(curDeg: number, desiredDeg: number): number
}

function distance2PointToSegment(
  px: number,
  py: number,
  ax: number,
  ay: number,
  bx: number,
  by: number
): number {
  const vx: number = bx - ax
  const vy: number = by - ay
  const len2: number = vx * vx + vy * vy
  if (len2 <= 1e-8) {
    const dx0: number = px - ax
    const dy0: number = py - ay
    return dx0 * dx0 + dy0 * dy0
  }
  let t: number = ((px - ax) * vx + (py - ay) * vy) / len2
  if (t < 0) t = 0
  if (t > 1) t = 1
  const qx: number = ax + t * vx
  const qy: number = ay + t * vy
  const dx: number = px - qx
  const dy: number = py - qy
  return dx * dx + dy * dy
}

function directionMatchesSegment(input: TrafficLightRouteMatchInput, directionDeg: number): boolean {
  const segHeadingDeg: number = input.segmentHeadingDeg(input.fromId, input.toId)
  const errDeg: number = Math.abs(input.headingErrorDeg(segHeadingDeg, directionDeg))
  return errDeg <= input.directionMaxErrDeg
}

function nearSegment(point: MapTrafficLightPoint, fromNode: RouteMatcherNode, toNode: RouteMatcherNode, thNorm: number): boolean {
  const d2: number = distance2PointToSegment(
    point.xNorm,
    point.yNorm,
    fromNode.xNorm,
    fromNode.yNorm,
    toNode.xNorm,
    toNode.yNorm
  )
  return d2 <= thNorm * thNorm
}

export function matchActiveTrafficLightPointForSegment(input: TrafficLightRouteMatchInput): MapTrafficLightPoint | undefined {
  if (input.trafficLights.length <= 0) return undefined

  const fromNode: RouteMatcherNode | undefined = input.findNode(input.fromId)
  const toNode: RouteMatcherNode | undefined = input.findNode(input.toId)
  if (!fromNode || !toNode) return undefined

  let best: MapTrafficLightPoint | undefined = undefined
  let bestD2: number = 0
  const thNorm: number = input.controlDistanceNorm

  for (let i: number = 0; i < input.trafficLights.length; i++) {
    const p: MapTrafficLightPoint = input.trafficLights[i]
    if (!directionMatchesSegment(input, p.directionDeg)) continue
    if (!nearSegment(p, fromNode, toNode, thNorm)) continue

    const d2: number = distance2PointToSegment(
      p.xNorm,
      p.yNorm,
      fromNode.xNorm,
      fromNode.yNorm,
      toNode.xNorm,
      toNode.yNorm
    )
    if (!best || d2 < bestD2) {
      best = p
      bestD2 = d2
    }
  }
  return best
}

export function isTrafficLightControlledEdgeForSegment(input: TrafficLightRouteMatchInput): boolean {
  return matchActiveTrafficLightPointForSegment(input) !== undefined
}


