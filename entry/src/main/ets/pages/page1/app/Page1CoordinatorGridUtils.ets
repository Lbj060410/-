/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorGridUtils.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorGridUtils.ets
 * 用途： 提供网格地图相关几何计算、节点定位与角度工具函数。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { GridNode } from '../types/SandboxGridTypes'
import { GridCoord, GridIdCodec } from './PathPlannerAStar'
import { EdgeSide, NormPoint } from './Page1CoordinatorDefs'

export class Page1CoordinatorGridUtils {
  static findNode(gridNodes: Array<GridNode>, id: string): NormPoint | undefined {
    for (let i: number = 0; i < gridNodes.length; i++) {
      const n: GridNode = gridNodes[i]
      if (n.id === id) return { xNorm: n.xNorm, yNorm: n.yNorm }
    }
    return undefined
  }

  static edgeSideOfNode(gridNodes: Array<GridNode>, id: string): EdgeSide {
    if (gridNodes.length <= 0) return EdgeSide.NONE

    const target: NormPoint | undefined = this.findNode(gridNodes, id)
    if (!target) return EdgeSide.NONE

    let minX: number = gridNodes[0].xNorm
    let maxX: number = gridNodes[0].xNorm
    let minY: number = gridNodes[0].yNorm
    let maxY: number = gridNodes[0].yNorm

    for (let i: number = 1; i < gridNodes.length; i++) {
      const n: GridNode = gridNodes[i]
      if (n.xNorm < minX) minX = n.xNorm
      if (n.xNorm > maxX) maxX = n.xNorm
      if (n.yNorm < minY) minY = n.yNorm
      if (n.yNorm > maxY) maxY = n.yNorm
    }

    const eps: number = 0.0005
    if (Math.abs(target.yNorm - minY) <= eps) return EdgeSide.TOP
    if (Math.abs(target.yNorm - maxY) <= eps) return EdgeSide.BOTTOM
    if (Math.abs(target.xNorm - minX) <= eps) return EdgeSide.LEFT
    if (Math.abs(target.xNorm - maxX) <= eps) return EdgeSide.RIGHT
    return EdgeSide.NONE
  }

  static isReverseParkingGoal(goalId: string): boolean {
    const x: string = goalId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(x)) return false
    const p: GridCoord | undefined = GridIdCodec.parse(x)
    if (!p) return false
    return p.row === 0 || p.row === 4 || p.col === 0 || p.col === 4
  }

  static fallbackParkingGoalOnObstacle(goalId: string): string {
    const x: string = goalId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(x)) return x
    if (x === 'B1') return 'F1'
    if (x === 'F1') return 'B1'
    return 'F1'
  }

  static norm360(v: number): number {
    let x: number = v % 360
    if (x < 0) x += 360
    return x
  }

  static headingErrorDeg(curDeg: number, desiredDeg: number): number {
    const c: number = this.norm360(curDeg)
    const d: number = this.norm360(desiredDeg)
    let e: number = d - c
    if (e > 180) e -= 360
    if (e < -180) e += 360
    return e
  }
}


