/**
 * 代码指南：
 * 文件：pages/page1/app/FusionEngineC0.ets
 * 用途：Page1 位姿/遥测相关逻辑的融合/计算辅助器。
 * 何时修改：调整融合数学、滤波器或数据组合策略时。
 * 相关文件：app/Page1Coordinator.ets 和 pages/page1/types/ 下的类型。
 */
// entry/src/main/ets/pages/page1/app/FusionEngineC0.ets

import { Pose2D, PoseSource } from '../types/PoseTypes'
import { CarTelemetry } from '../types/Page1Types'
import { Page1UiStore } from './Page1UiStore'
import { GridNode } from '../types/SandboxGridTypes'

export class FusionEngineC0 {
  private static readonly MAP_MM: number = 50000
  private static readonly MAX_STEP_NORM: number = 0.010

  private static readonly CONF_DECAY_PER_TICK: number = 0.006
  private static readonly CONF_MIN: number = 0.10
  private static readonly CONF_RFID: number = 0.95

  // ✅ 手动点选后“保护窗口”：短时间不衰减置信度
  private static readonly MANUAL_GRACE_MS: number = 800

  static update(store: Page1UiStore, t: CarTelemetry): void {
    if (!store.poseFollowEnabled) return
    if (store.mapW <= 0 || store.mapH <= 0) return
    // 防止传感器异常值（NaN / Infinity）污染位姿计算并向下扩散
    if (!Number.isFinite(t.headingDeg) || !Number.isFinite(t.odomMm)) return

    const nowMs: number = t.tsMs
    const inManualGrace: boolean =
      (store.poseLastManualAtMs > 0) && (nowMs - store.poseLastManualAtMs <= FusionEngineC0.MANUAL_GRACE_MS)

    // 1) RFID 校正（只在变化时触发）
    const rfid: string = t.rfid.trim()
    if (rfid.length > 0 && rfid !== store.poseLastRfid) {
      const node: GridNode | undefined = FusionEngineC0.findNodeById(store.gridNodes, rfid)
      store.poseLastRfid = rfid

      if (node) {
        const p: Pose2D = {
          tsMs: t.tsMs,
          xNorm: node.xNorm,
          yNorm: node.yNorm,
          headingDeg: FusionEngineC0.normHeading(t.headingDeg),
          confidence: FusionEngineC0.CONF_RFID,
          source: PoseSource.RFID_CORRECT
        }
        store.setPose(p)
        store.poseLastOdomMm = t.odomMm
        store.poseInited = true
        store.pushLog(`融合校正：RFID=${rfid} conf=${p.confidence.toFixed(2)}`)
        return
      }

      store.pushLog(`融合提示：RFID=${rfid} 未匹配网格节点`)
    }

    // 2) 初始化（建立 odom 基准）
    const curOdom: number = t.odomMm
    if (store.poseInited === false) {
      const baseConf: number = (store.pose.confidence >= 0.70) ? store.pose.confidence : 0.70
      const initPose: Pose2D = {
        tsMs: t.tsMs,
        xNorm: store.carX,
        yNorm: store.carY,
        headingDeg: FusionEngineC0.normHeading(t.headingDeg),
        confidence: baseConf,
        source: PoseSource.INIT
      }
      store.setPose(initPose)
      store.poseLastOdomMm = curOdom
      store.poseInited = true
      store.pushLog('融合初始化：poseFollow=ON 后建立 odom 基准')
      return
    }

    // 3) dead-reckoning（里程增量 + 航向）
    const lastOdom: number = store.poseLastOdomMm
    let dMm: number = curOdom - lastOdom

    // ✅ dMm 异常过滤：一次跳太大就只更新基准不移动（避免乱跑）
    if (dMm > 600 || dMm < -600) {
      FusionEngineC0.updateHeadingOnly(store, t)
      store.poseLastOdomMm = curOdom
      return
    }
    if (dMm < 0 && t.speed >= 0) {
      FusionEngineC0.updateHeadingOnly(store, t)
      store.poseLastOdomMm = curOdom
      return
    }
    if (dMm === 0) {
      FusionEngineC0.updateHeadingOnly(store, t)
      store.poseLastOdomMm = curOdom
      return
    }

    const heading: number = FusionEngineC0.normHeading(t.headingDeg)
    const rad: number = FusionEngineC0.deg2rad(heading)

    let stepNorm: number = Math.abs(dMm) / FusionEngineC0.MAP_MM
    if (stepNorm > FusionEngineC0.MAX_STEP_NORM) stepNorm = FusionEngineC0.MAX_STEP_NORM

    const dir: number = dMm >= 0 ? 1 : -1

    const dx: number = dir * stepNorm * Math.cos(rad)
    const dy: number = dir * stepNorm * Math.sin(rad)

    const prev: Pose2D = store.pose
    const nextPose: Pose2D = {
      tsMs: t.tsMs,
      xNorm: FusionEngineC0.clamp01(prev.xNorm + dx),
      yNorm: FusionEngineC0.clamp01(prev.yNorm + dy),
      headingDeg: heading,
      confidence: inManualGrace ? prev.confidence : FusionEngineC0.decayConf(prev.confidence),
      source: PoseSource.DEAD_RECKONING
    }

    store.setPose(nextPose)
    store.poseLastOdomMm = curOdom
  }

  private static updateHeadingOnly(store: Page1UiStore, t: CarTelemetry): void {
    const heading: number = FusionEngineC0.normHeading(t.headingDeg)
    const prev: Pose2D = store.pose
    if (FusionEngineC0.normHeading(prev.headingDeg) === heading) return

    const nextPose: Pose2D = {
      tsMs: t.tsMs,
      xNorm: prev.xNorm,
      yNorm: prev.yNorm,
      headingDeg: heading,
      confidence: prev.confidence,
      source: prev.source
    }
    store.setPose(nextPose)
  }

  private static findNodeById(nodes: Array<GridNode>, id: string): GridNode | undefined {
    const target: string = id.toUpperCase()
    for (let i: number = 0; i < nodes.length; i++) {
      if (nodes[i].id.toUpperCase() === target) return nodes[i]
    }
    return undefined
  }

  private static deg2rad(d: number): number {
    return d * Math.PI / 180.0
  }

  private static normHeading(d: number): number {
    let x: number = d % 360
    if (x < 0) x += 360
    return x
  }

  private static clamp01(v: number): number {
    if (v < 0) return 0
    if (v > 1) return 1
    return v
  }

  private static decayConf(v: number): number {
    const next: number = v - FusionEngineC0.CONF_DECAY_PER_TICK
    if (next < FusionEngineC0.CONF_MIN) return FusionEngineC0.CONF_MIN
    return next
  }
}

