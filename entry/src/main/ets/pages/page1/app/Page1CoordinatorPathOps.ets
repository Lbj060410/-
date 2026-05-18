/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorPathOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorPathOps.ets
 * 用途： 封装路径跟踪、动作预测与路径段推进逻辑。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1Action } from '../types/Page1Types'
import { GridIdCodec } from './PathPlannerAStar'
import { IPage1CoordinatorOps } from './Page1CoordinatorDefs'

export function resolveStartNodeId(ctx: IPage1CoordinatorOps): string {
  const s = ctx.store
  if (!s) return 'D4'
  const snap = s.currentSnapNodeId.trim().toUpperCase()
  if (snap.length > 0 && GridIdCodec.isValidId(snap)) return snap
  const near = ctx.nearestNodeIdByPose()
  if (near.length > 0 && GridIdCodec.isValidId(near)) return near
  return 'D4'
}

export function syncLogicalHeadingWithCurrentState(ctx: IPage1CoordinatorOps): void {
  const s = ctx.store
  if (!s) return
  ctx.logicalHeadingDeg = normToCardinal(ctx, s.pose.headingDeg)
  ctx.logicalHeadingInited = true
}

export function segmentHeadingDeg(ctx: IPage1CoordinatorOps, fromId: string, toId: string): number {
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

export function normToCardinal(ctx: IPage1CoordinatorOps, v: number): number {
  const x = ctx.norm360(v)
  const idx = Math.round(x / 90) % 4
  return idx * 90
}

export function canSendNextCommand(ctx: IPage1CoordinatorOps, nowMs: number): boolean {
  const snap = ctx.actionScheduler.snapshot(nowMs, ctx.motionRunning())
  ctx.lastSchedulerSnapshot = snap
  return snap.canSend
}
