/**
 * 代码指南：
 * 文件：pages/page1/app/Page1UiStore.ets
 * 用途：Page1 UI/业务状态容器（路径、位姿、遥测、日志、阻塞节点/边）。
 * 何时修改：为 page1 添加新状态字段、计算标志或状态变更 API 时。
 * 相关文件：app/Page1Coordinator.ets 和 pages/page1/components/ 下的组件。
 */
// entry/src/main/ets/pages/page1/app/Page1UiStore.ets

import { CarTelemetry } from '../types/Page1Types'
import { GridNode, SandboxGridModel } from '../types/SandboxGridTypes'
import { Pose2D, PoseSource } from '../types/PoseTypes'
import { PathPlannerAStar, RouteEdgeCodec, RouteSegment } from './PathPlannerAStar'
import { CAR_DEVICE_IP, CAR_TCP_PORT } from '../../../config/DeviceNetworkConfig'
import hilog from '@ohos.hilog'

const BIZLOG_DOMAIN = 0xFF03
const BIZLOG_TAG = 'bizlog'
const METRIC_LOG_DOMAIN = 0xFF09
const METRIC_LOG_TAG = 'metric'

export enum RiskLevel {
  SAFE = 0,
  WARN = 1,
  DANGER = 2
}

export enum CarConnState {
  IDLE = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  RECONNECTING = 3,
  FAILED = 4
}

export interface XYPos {
  x: number
  y: number
}

export interface RouteObstaclePoint {
  id: string
  xNorm: number
  yNorm: number
  edgeId: string
  t: number
  createdAtMs: number
  triggered: boolean
  hitAtMs: number
}

export interface MapTrafficLightPoint {
  id: string
  edgeId: string
  xNorm: number
  yNorm: number
  directionDeg: number
}

export interface MapGatePoint {
  id: string
  edgeId: string
  xNorm: number
  yNorm: number
}

export interface MapSpecialRoadPoint {
  id: string
  edgeId: string
  xNorm: number
  yNorm: number
}

export interface MapGaragePoint {
  id: string
  nodeId: string
  xNorm: number
  yNorm: number
}

export interface MapWarehousePoint {
  id: string
  nodeId: string
  xNorm: number
  yNorm: number
}

// 为与协调器交通闸门流程兼容而保留；地图侧编辑 UI 已移除。

interface RouteSegProjection {
  edgeId: string
  pxNorm: number
  pyNorm: number
  t: number
  d2: number
}

@Observed
export class Page1UiStore {
  // ===== 地图 =====
  // 地图尺寸与车点显示：
  // - mapW/mapH 由布局回调写入，错误会导致点击坐标换算异常
  // - carDotSize 仅影响显示大小，不影响规划与控制
  mapW: number = 0
  mapH: number = 0
  carX: number = 0.210
  carY: number = 0.902
  carDotSize: number = 26
  homePlaceConfigured: boolean = false
  companyPlaceConfigured: boolean = false
  homePlaceNodeId: string = ''
  companyPlaceNodeId: string = ''

  // ===== 黑线路网节点（行号 1/2/4/6/7）=====
  gridNodes: Array<GridNode> = SandboxGridModel.buildDefaultNodes()
  gridSnapEnabled: boolean = true
  // 吸附阈值（归一化坐标）：
  // - 调大：更容易吸附到节点，适合粗点选
  // - 调小：更难吸附，适合精细自由放置
  gridSnapThresholdNorm: number = 0.055
  // 边缘节点额外吸附增益：
  // - 调大：更容易点中边缘车位
  // - 调小：边缘点选更接近普通节点
  edgeSnapBoostNorm: number = 0.010
  currentSnapNodeId: string = ''

  // ===== B2：障碍 =====
  blockedNodes: Array<string> = []
  blockedEdges: Array<string> = []
  routeObstaclePoints: Array<RouteObstaclePoint> = []
  obstacleEditEnabled: boolean = false
  trafficLightEditEnabled: boolean = false
  gateEditEnabled: boolean = false
  specialRoadEditEnabled: boolean = false
  garageEditEnabled: boolean = false
  warehouseEditEnabled: boolean = false
  targetPickEnabled: boolean = false
  // 地图点选目标后，等待“再次点击目标按钮”确认发送
  mapTargetPendingSend: boolean = false
  // 路段拾取阈值：
  // - 调大：点击更容易命中路段
  // - 调小：误触少，但更难点中
  edgePickThresholdNorm: number = 0.030
  // 点障碍新增/删除/触发阈值：
  // - 调大：更敏感，更容易新增/删除/触发
  // - 调小：更严格，误触少但可能漏触发
  obstaclePointPickThresholdNorm: number = 0.030
  obstaclePointRemoveThresholdNorm: number = 0.020
  obstaclePointTriggerThresholdNorm: number = 0.022
  // 设障时节点吸附半径（比普通吸附更大）
  obstacleNodePickThresholdNorm: number = 0.075
  trafficLightNodePickThresholdNorm: number = 0.075
  trafficLights: Array<MapTrafficLightPoint> = []
  gatePoints: Array<MapGatePoint> = []
  specialRoadPoints: Array<MapSpecialRoadPoint> = []
  garagePoints: Array<MapGaragePoint> = []
  warehousePoints: Array<MapWarehousePoint> = []

  /**
   * 障碍编辑模式开关：
   * - 开启后，地图点击优先用于“加/删障碍”；
   * - 关闭后，恢复正常自动跟随相关行为。
   */
  toggleObstacleEdit(): void {
    this.obstacleEditEnabled = !this.obstacleEditEnabled
    if (this.obstacleEditEnabled) {
      this.trafficLightEditEnabled = false
      this.gateEditEnabled = false
      this.specialRoadEditEnabled = false
      this.garageEditEnabled = false
      this.warehouseEditEnabled = false
      this.targetPickEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`障碍编辑：${this.obstacleEditEnabled ? 'ON' : 'OFF'}`)
  }

  toggleTrafficLightEdit(): void {
    this.trafficLightEditEnabled = !this.trafficLightEditEnabled
    if (this.trafficLightEditEnabled) {
      this.obstacleEditEnabled = false
      this.gateEditEnabled = false
      this.specialRoadEditEnabled = false
      this.garageEditEnabled = false
      this.warehouseEditEnabled = false
      this.targetPickEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`红绿灯设置：${this.trafficLightEditEnabled ? 'ON' : 'OFF'}`)
  }

  toggleGateEdit(): void {
    this.gateEditEnabled = !this.gateEditEnabled
    if (this.gateEditEnabled) {
      this.obstacleEditEnabled = false
      this.trafficLightEditEnabled = false
      this.specialRoadEditEnabled = false
      this.garageEditEnabled = false
      this.warehouseEditEnabled = false
      this.targetPickEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`道闸设置：${this.gateEditEnabled ? 'ON' : 'OFF'}`)
  }

  toggleSpecialRoadEdit(): void {
    this.specialRoadEditEnabled = !this.specialRoadEditEnabled
    if (this.specialRoadEditEnabled) {
      this.obstacleEditEnabled = false
      this.trafficLightEditEnabled = false
      this.gateEditEnabled = false
      this.garageEditEnabled = false
      this.warehouseEditEnabled = false
      this.targetPickEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`特殊路段设置：${this.specialRoadEditEnabled ? 'ON' : 'OFF'}`)
  }

  toggleGarageEdit(): void {
    this.garageEditEnabled = !this.garageEditEnabled
    if (this.garageEditEnabled) {
      this.obstacleEditEnabled = false
      this.trafficLightEditEnabled = false
      this.gateEditEnabled = false
      this.specialRoadEditEnabled = false
      this.warehouseEditEnabled = false
      this.targetPickEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`车库设置：${this.garageEditEnabled ? 'ON' : 'OFF'}`)
  }

  toggleWarehouseEdit(): void {
    this.warehouseEditEnabled = !this.warehouseEditEnabled
    if (this.warehouseEditEnabled) {
      this.obstacleEditEnabled = false
      this.trafficLightEditEnabled = false
      this.gateEditEnabled = false
      this.specialRoadEditEnabled = false
      this.garageEditEnabled = false
      this.targetPickEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`仓库设置：${this.warehouseEditEnabled ? 'ON' : 'OFF'}`)
  }

  toggleTargetPick(): void {
    this.targetPickEnabled = !this.targetPickEnabled
    if (this.targetPickEnabled) {
      this.obstacleEditEnabled = false
      this.trafficLightEditEnabled = false
      this.gateEditEnabled = false
      this.specialRoadEditEnabled = false
      this.garageEditEnabled = false
      this.warehouseEditEnabled = false
      this.mapTargetPendingSend = false
    }
    this.pushLog(`目标点选：${this.targetPickEnabled ? 'ON' : 'OFF'}`)
  }

  clearTrafficLightPoints(): void {
    if (this.trafficLights.length <= 0) return
    this.trafficLights = []
    this.pushLog('红绿灯清空')
  }

  upsertTrafficLightPoint(edgeId: string, directionDeg: number): boolean {
    const edge: string = edgeId.trim().toUpperCase()
    const pos: XYPos | undefined = this.edgeMidPosById(edge)
    if (!pos) return false

    const next: Array<MapTrafficLightPoint> = []
    let updated: boolean = false
    for (let i: number = 0; i < this.trafficLights.length; i++) {
      const one: MapTrafficLightPoint = this.trafficLights[i]
      if (one.edgeId === edge) {
        next.push({
          id: edge,
          edgeId: edge,
          xNorm: pos.x,
          yNorm: pos.y,
          directionDeg: directionDeg
        })
        updated = true
      } else {
        next.push(one)
      }
    }

    if (!updated) {
      if (this.trafficLights.length >= 2) {
        this.pushLog('红绿灯设置失败：最多2个')
        return false
      }
      next.push({
        id: edge,
        edgeId: edge,
        xNorm: pos.x,
        yNorm: pos.y,
        directionDeg: directionDeg
      })
    }

    this.trafficLights = next
    this.pushLog(`红绿灯设置：edge=${edge} dir=${Math.round(directionDeg)}`)
    return true
  }

  clearGatePoints(): void {
    if (this.gatePoints.length <= 0) return
    this.gatePoints = []
    this.pushLog('道闸清空')
  }

  upsertGatePoint(edgeId: string): boolean {
    const edge: string = edgeId.trim().toUpperCase()
    const pos: XYPos | undefined = this.edgeMidPosById(edge)
    if (!pos) return false
    // 道闸仅允许一个：新设置直接覆盖旧设置
    this.gatePoints = [{ id: edge, edgeId: edge, xNorm: pos.x, yNorm: pos.y }]
    this.pushLog(`道闸设置：edge=${edge}`)
    return true
  }

  clearSpecialRoadPoints(): void {
    if (this.specialRoadPoints.length <= 0) return
    this.specialRoadPoints = []
    this.pushLog('特殊路段清空')
  }

  upsertSpecialRoadPoint(edgeId: string): boolean {
    const edge: string = edgeId.trim().toUpperCase()
    const pos: XYPos | undefined = this.edgeMidPosById(edge)
    if (!pos) return false
    // 和道闸一致：仅允许一个
    this.specialRoadPoints = [{ id: edge, edgeId: edge, xNorm: pos.x, yNorm: pos.y }]
    this.pushLog(`特殊路段设置：edge=${edge}`)
    return true
  }

  clearGaragePoints(): void {
    if (this.garagePoints.length <= 0) return
    this.garagePoints = []
    this.pushLog('车库清空')
  }

  upsertGaragePoint(nodeId: string): boolean {
    const id: string = nodeId.trim().toUpperCase()
    const n: GridNode | undefined = this.findGridNodeById(id)
    if (!n) return false
    // 全图最多一个车库：新设置直接覆盖旧设置
    this.garagePoints = [{ id: id, nodeId: id, xNorm: n.xNorm, yNorm: n.yNorm }]
    this.pushLog(`车库设置：node=${id}`)
    return true
  }

  clearWarehousePoints(): void {
    if (this.warehousePoints.length <= 0) return
    this.warehousePoints = []
    this.pushLog('仓库清空')
  }

  upsertWarehousePoint(nodeId: string): boolean {
    const id: string = nodeId.trim().toUpperCase()
    const n: GridNode | undefined = this.findGridNodeById(id)
    if (!n) return false

    let existed: boolean = false
    const next: Array<MapWarehousePoint> = []
    for (let i: number = 0; i < this.warehousePoints.length; i++) {
      const one: MapWarehousePoint = this.warehousePoints[i]
      if (one.nodeId === id) {
        next.push({ id: id, nodeId: id, xNorm: n.xNorm, yNorm: n.yNorm })
        existed = true
      } else {
        next.push(one)
      }
    }

    if (!existed) {
      if (this.warehousePoints.length >= 7) {
        this.pushLog('仓库设置失败：最多7个')
        return false
      }
      next.push({ id: id, nodeId: id, xNorm: n.xNorm, yNorm: n.yNorm })
    }

    this.warehousePoints = next
    this.pushLog(`仓库设置：node=${id} (${this.warehousePoints.length}/7)`)
    return true
  }

  // ===== B3：自动避障注入 =====
  autoAvoidEnabled: boolean = true
  // 自动避障冷却：
  // - 调大：更稳，减少反复加障碍
  // - 调小：更灵敏，但可能频繁改路径
  autoAvoidCooldownMs: number = 1200
  lastAutoAvoidAtMs: number = 0

  // 自动避障触发条件：开关开启 + 非编辑态 + 冷却时间到
  canAutoAvoid(nowMs: number): boolean {
    if (!this.autoAvoidEnabled) return false
    if (this.obstacleEditEnabled) return false
    if (nowMs - this.lastAutoAvoidAtMs < this.autoAvoidCooldownMs) return false
    return true
  }

  markAutoAvoidTriggered(nowMs: number): void {
    this.lastAutoAvoidAtMs = nowMs
  }

  addBlockedIfAbsent(id: string, reason: string): boolean {
    if (id.length === 0) return false
    if (this.isBlocked(id)) return false
    if (this.currentSnapNodeId === id) return false

    const next: Array<string> = []
    for (let i: number = 0; i < this.blockedNodes.length; i++) next.push(this.blockedNodes[i])
    next.push(id)
    this.blockedNodes = next
    this.pushLog(`自动障碍 + ${id} (${reason})`)
    return true
  }

  addBlockedEdgeIfAbsent(edgeId: string, reason: string): boolean {
    const x: string = edgeId.trim().toUpperCase()
    const parsed: RouteSegment | undefined = RouteEdgeCodec.parse(x)
    if (!parsed) return false
    if (this.isBlockedEdgeById(x)) return false

    const next: Array<string> = []
    for (let i: number = 0; i < this.blockedEdges.length; i++) next.push(this.blockedEdges[i])
    next.push(x)
    this.blockedEdges = next
    this.pushLog(`自动路段障碍 + ${x} (${reason})`)
    return true
  }

  // ===== Step4：路径自动跟随（演示闭环）=====
  autoFollowEnabled: boolean = true
  // 智能停车位固定为 F7（不再提供切换开关）。
  smartParkingUseF7: boolean = true
  // 自动跟随节拍冷却：
  // - 调大：动作频率低，控制更稳但更慢
  // - 调小：动作频率高，响应更快但更容易叠命令
  autoFollowCooldownMs: number = 1500
  lastAutoFollowAtMs: number = 0

  // ===== SEG 规划参数（中途改目标更稳定）=====
  segPlannerEnabled: boolean = true
  // segMidMinT/segMidMaxT：判定“车是否在路段中部”区间
  // - 区间变大：更容易启用 SEG 规划
  // - 区间变小：更保守，更多回退普通 A*
  segMidMinT: number = 0.12
  segMidMaxT: number = 0.88
  // 朝向惩罚权重：
  // - 调大：更偏好与当前车头方向一致的端点
  // - 调小：更偏好纯距离最短
  segHeadingPenaltyWeight: number = 0.55

  // 自动跟随触发条件：有可执行路径 + 非编辑态 + 冷却时间到
  canAutoFollow(nowMs: number): boolean {
    if (!this.autoFollowEnabled) return false
    if (this.obstacleEditEnabled) return false
    if (this.pathNodes.length <= 1) return false
    if (this.pathIndex >= this.pathNodes.length - 1) return false
    if (nowMs - this.lastAutoFollowAtMs < this.autoFollowCooldownMs) return false
    return true
  }

  markAutoFollow(nowMs: number): void {
    this.lastAutoFollowAtMs = nowMs
  }

  smartParkingGoalId(): string {
    return 'F7'
  }

  toggleSmartParkingGoal(): void {
    // 兼容旧调用：策略固定 F7，不再切换。
    this.smartParkingUseF7 = true
    this.pushLog('智能车位：F7')
  }

  // ===== C0：Pose + 融合状态 =====
  poseFollowEnabled: boolean = true
  // poseInited：
  // - true 表示已由融合流程初始化过位姿
  // - false 时某些逻辑会走“按显示点/最近节点兜底”
  poseInited: boolean = false
  poseLastOdomMm: number = 0
  poseLastRfid: string = ''
  poseLastManualAtMs: number = 0

  pose: Pose2D = {
    tsMs: 0,
    xNorm: 0.210,
    yNorm: 0.902,
    headingDeg: 0,
    confidence: 0.70,
    source: PoseSource.INIT
  }

  setPose(p: Pose2D): void {
    const prevSource: PoseSource = this.pose.source
    this.pose = p
    if (this.poseFollowEnabled) {
      this.carX = this.clamp01(p.xNorm)
      this.carY = this.clamp01(p.yNorm)
    }

    // 接收到节点位置（RFID 校正）时触发指标动画
    if (p.source === PoseSource.RFID_CORRECT && this.onNodeArrivedCallback) {
      this.onNodeArrivedCallback()
    }
  }

  onNodeArrivedCallback: (() => void) | undefined = undefined

  setPlaceConfigured(homeNodeId: string, companyNodeId: string): void {
    const homeId: string = String(homeNodeId ?? '').trim().toUpperCase()
    const companyId: string = String(companyNodeId ?? '').trim().toUpperCase()
    this.homePlaceConfigured = this.isValidPlaceNodeId(homeId)
    this.companyPlaceConfigured = this.isValidPlaceNodeId(companyId)
    this.homePlaceNodeId = this.homePlaceConfigured ? homeId : ''
    this.companyPlaceNodeId = this.companyPlaceConfigured ? companyId : ''
  }

  private isValidPlaceNodeId(raw: string): boolean {
    const id: string = String(raw ?? '').trim().toUpperCase()
    if (id.length !== 2) return false
    const col: string = id.charAt(0)
    const row: string = id.charAt(1)
    return col >= 'A' && col <= 'G' && row >= '1' && row <= '7'
  }

  private normHeadingDeg(v: number): number {
    let x: number = v % 360
    if (x < 0) x += 360
    return x
  }

  private verticalBounds(): { minY: number, maxY: number } {
    if (this.gridNodes.length <= 0) return { minY: 0, maxY: 1 }

    let minY: number = this.gridNodes[0].yNorm
    let maxY: number = this.gridNodes[0].yNorm
    for (let i: number = 1; i < this.gridNodes.length; i++) {
      const y: number = this.gridNodes[i].yNorm
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
    return { minY: minY, maxY: maxY }
  }

  private preferredHeadingForPlacement(yNorm: number, fallbackHeadingDeg: number): number {
    const bounds: { minY: number, maxY: number } = this.verticalBounds()
    const edgeBand: number = Math.max(this.gridSnapThresholdNorm + 0.02, 0.075)

    if (yNorm >= bounds.maxY - edgeBand) return 270
    if (yNorm <= bounds.minY + edgeBand) return 90
    return this.normHeadingDeg(fallbackHeadingDeg)
  }

  /**
   * 人工放置车辆位姿：
   * 这里会同步 pose 与 telemetry 的朝向，保证 UI 和控制逻辑使用同一朝向基准。
   */
  private applyManualPlacementPose(xNorm: number, yNorm: number, headingDeg: number): void {
    const now: number = Date.now()
    const nextHeadingDeg: number = this.normHeadingDeg(headingDeg)

    this.poseLastManualAtMs = now

    const p: Pose2D = {
      tsMs: now,
      xNorm: xNorm,
      yNorm: yNorm,
      headingDeg: nextHeadingDeg,
      confidence: this.pose.confidence,
      source: PoseSource.MANUAL
    }
    this.setPose(p)
    this.poseInited = false

    const nextTelemetry: CarTelemetry = {
      tsMs: now,
      speed: this.telemetry.speed,
      headingDeg: nextHeadingDeg,
      odomMm: this.telemetry.odomMm,
      ultraFrontCm: this.telemetry.ultraFrontCm,
      ultraBackCm: this.telemetry.ultraBackCm,
      irDistCm: this.telemetry.irDistCm,
      lightLux: this.telemetry.lightLux,
      rfid: this.telemetry.rfid
    }
    this.setTelemetry(nextTelemetry)
  }

  // ===== 基础 =====
  setMapSize(w: number, h: number): void {
    this.mapW = w
    this.mapH = h
  }

  setGridSnapEnabled(v: boolean): void {
    this.gridSnapEnabled = v
    this.pushLog(`网格吸附：${v ? 'ON' : 'OFF'}`)
    if (!v) this.currentSnapNodeId = ''
  }

  toggleGridSnap(): void {
    this.setGridSnapEnabled(!this.gridSnapEnabled)
  }

  private clamp01(v: number): number {
    if (v < 0) return 0
    if (v > 1) return 1
    return v
  }

  private normToCardinal(v: number): number {
    let x: number = v % 360
    if (x < 0) x += 360
    const idx: number = Math.round(x / 90) % 4
    return idx * 90
  }

  private dist2(ax: number, ay: number, bx: number, by: number): number {
    const dx: number = ax - bx
    const dy: number = ay - by
    return dx * dx + dy * dy
  }

  // 归一化坐标到最近节点（用于点选吸附与起点估计）
  private findNearestNodeByNorm(nx: number, ny: number): GridNode | undefined {
    if (this.gridNodes.length === 0) return undefined
    let best: GridNode | undefined = undefined
    let bestD2: number = 0

    for (let i: number = 0; i < this.gridNodes.length; i++) {
      const n: GridNode = this.gridNodes[i]
      const d2: number = this.dist2(nx, ny, n.xNorm, n.yNorm)
      if (!best) { best = n; bestD2 = d2; continue }
      if (d2 < bestD2) { best = n; bestD2 = d2 }
    }
    return best
  }

  private isEdgeNode(n: GridNode): boolean {
    if (this.gridNodes.length <= 0) return false

    let minX: number = this.gridNodes[0].xNorm
    let maxX: number = this.gridNodes[0].xNorm
    let minY: number = this.gridNodes[0].yNorm
    let maxY: number = this.gridNodes[0].yNorm
    for (let i: number = 1; i < this.gridNodes.length; i++) {
      const g: GridNode = this.gridNodes[i]
      if (g.xNorm < minX) minX = g.xNorm
      if (g.xNorm > maxX) maxX = g.xNorm
      if (g.yNorm < minY) minY = g.yNorm
      if (g.yNorm > maxY) maxY = g.yNorm
    }

    const eps: number = 0.0005
    if (Math.abs(n.xNorm - minX) <= eps) return true
    if (Math.abs(n.xNorm - maxX) <= eps) return true
    if (Math.abs(n.yNorm - minY) <= eps) return true
    if (Math.abs(n.yNorm - maxY) <= eps) return true
    return false
  }

  // 路网外框节点给予更大吸附半径，便于边缘停车点选
  private snapThresholdForNode(n: GridNode): number {
    let th: number = this.gridSnapThresholdNorm
    if (this.isEdgeNode(n)) th += this.edgeSnapBoostNorm
    if (th < 0.01) th = 0.01
    if (th > 0.20) th = 0.20
    return th
  }

  nearestNodeIdByPixel(x: number, y: number): string {
    if (this.mapW <= 0 || this.mapH <= 0) return ''
    const nx: number = this.clamp01(x / this.mapW)
    const ny: number = this.clamp01(y / this.mapH)
    const nearest: GridNode | undefined = this.findNearestNodeByNorm(nx, ny)
    if (!nearest) return ''
    return nearest.id
  }

  nearestNodeIdByPixelForObstacle(x: number, y: number): string {
    if (this.mapW <= 0 || this.mapH <= 0) return ''
    const nx: number = this.clamp01(x / this.mapW)
    const ny: number = this.clamp01(y / this.mapH)
    const nearest: GridNode | undefined = this.findNearestNodeByNorm(nx, ny)
    if (!nearest) return ''
    const d2: number = this.dist2(nx, ny, nearest.xNorm, nearest.yNorm)
    const th: number = this.obstacleNodePickThresholdNorm
    if (d2 > th * th) return ''
    return nearest.id
  }

  nearestNodeIdByPixelForTrafficLight(x: number, y: number): string {
    if (this.mapW <= 0 || this.mapH <= 0) return ''
    const nx: number = this.clamp01(x / this.mapW)
    const ny: number = this.clamp01(y / this.mapH)
    const nearest: GridNode | undefined = this.findNearestNodeByNorm(nx, ny)
    if (!nearest) return ''
    const d2: number = this.dist2(nx, ny, nearest.xNorm, nearest.yNorm)
    const th: number = this.trafficLightNodePickThresholdNorm
    if (d2 > th * th) return ''
    return nearest.id
  }

  edgeMidPosById(edgeId: string): XYPos | undefined {
    const p: RouteSegment | undefined = RouteEdgeCodec.parse(edgeId)
    if (!p) return undefined
    const a: GridNode | undefined = this.findGridNodeById(p.a)
    const b: GridNode | undefined = this.findGridNodeById(p.b)
    if (!a || !b) return undefined
    return {
      x: (a.xNorm + b.xNorm) * 0.5,
      y: (a.yNorm + b.yNorm) * 0.5
    }
  }

  isBlocked(id: string): boolean {
    for (let i: number = 0; i < this.blockedNodes.length; i++) {
      if (this.blockedNodes[i] === id) return true
    }
    return false
  }

  // 路段阻塞判定：无向边统一编码后查询
  isBlockedEdge(aId: string, bId: string): boolean {
    if (aId.length <= 0 || bId.length <= 0) return false
    const edgeId: string = RouteEdgeCodec.normalize(aId, bId)
    return this.isBlockedEdgeById(edgeId)
  }

  isBlockedEdgeById(edgeId: string): boolean {
    const x: string = edgeId.trim().toUpperCase()
    if (x.length <= 0) return false
    for (let i: number = 0; i < this.blockedEdges.length; i++) {
      if (this.blockedEdges[i] === x) return true
    }
    return false
  }

  /**
   * 手动切换“路段障碍”：
   * - 不能添加与当前位置直接相邻的障碍，避免把当前车锁死；
   * - 再次点击同一路段会移除障碍。
   */
  toggleBlockedEdge(edgeId: string): void {
    const x: string = edgeId.trim().toUpperCase()
    if (x.length <= 0) return

    const parsed: RouteSegment | undefined = RouteEdgeCodec.parse(x)
    if (!parsed) return
    const cur: string = this.currentSnapNodeId.trim().toUpperCase()
    if (cur === parsed.a || cur === parsed.b) {
      this.pushLog(`路段障碍拒绝：${x}（与当前位置相邻）`)
      return
    }

    const next: Array<string> = []
    let removed: boolean = false
    for (let i: number = 0; i < this.blockedEdges.length; i++) {
      const cur: string = this.blockedEdges[i]
      if (cur === x) { removed = true; continue }
      next.push(cur)
    }

    if (!removed) { next.push(x); this.pushLog(`路段障碍 + ${x}`) }
    else { this.pushLog(`路段障碍 - ${x}`) }

    this.blockedEdges = next
  }

  private nextRouteObstaclePointId(): string {
    const now: number = Date.now()
    const r: number = Math.floor(Math.random() * 1000)
    return `P${now}_${r}`
  }

  private nearestRouteObstaclePointIndexByNorm(nx: number, ny: number, thNorm: number): number {
    if (this.routeObstaclePoints.length <= 0) return -1
    const th2: number = thNorm * thNorm
    let bestIdx: number = -1
    let bestD2: number = 0

    for (let i: number = 0; i < this.routeObstaclePoints.length; i++) {
      const p: RouteObstaclePoint = this.routeObstaclePoints[i]
      const d2: number = this.dist2(nx, ny, p.xNorm, p.yNorm)
      if (d2 > th2) continue
      if (bestIdx < 0 || d2 < bestD2) {
        bestIdx = i
        bestD2 = d2
      }
    }
    return bestIdx
  }

  /**
   * 地图点击“点障碍”：
   * - 若点击到已有点障碍附近：删除；
   * - 否则投影到最近路段并创建点障碍。
   */
  toggleRouteObstaclePointByPixel(x: number, y: number): boolean {
    if (this.mapW <= 0 || this.mapH <= 0) return false
    const nx: number = this.clamp01(x / this.mapW)
    const ny: number = this.clamp01(y / this.mapH)

    const removeIdx: number =
      this.nearestRouteObstaclePointIndexByNorm(nx, ny, this.obstaclePointRemoveThresholdNorm)
    if (removeIdx >= 0) {
      const removed: RouteObstaclePoint = this.routeObstaclePoints[removeIdx]
      const nextRemoved: Array<RouteObstaclePoint> = []
      for (let i: number = 0; i < this.routeObstaclePoints.length; i++) {
        if (i === removeIdx) continue
        nextRemoved.push(this.routeObstaclePoints[i])
      }
      this.routeObstaclePoints = nextRemoved
      this.pushLog(`点障碍 - ${removed.id} edge=${removed.edgeId}`)
      return true
    }

    const proj: RouteSegProjection | undefined = this.projectToNearestRouteSegmentByNorm(nx, ny)
    if (!proj) return false
    const th2: number = this.obstaclePointPickThresholdNorm * this.obstaclePointPickThresholdNorm
    if (proj.d2 > th2) return false

    const now: number = Date.now()
    const point: RouteObstaclePoint = {
      id: this.nextRouteObstaclePointId(),
      xNorm: proj.pxNorm,
      yNorm: proj.pyNorm,
      edgeId: proj.edgeId,
      t: proj.t,
      createdAtMs: now,
      triggered: false,
      hitAtMs: 0
    }

    const next: Array<RouteObstaclePoint> = []
    for (let i: number = 0; i < this.routeObstaclePoints.length; i++) next.push(this.routeObstaclePoints[i])
    next.push(point)
    this.routeObstaclePoints = next
    this.pushLog(`点障碍 + ${point.id} edge=${point.edgeId} t=${point.t.toFixed(2)}`)
    return true
  }

  // 把某个点障碍标记为已触发（保留记录，不直接删除）
  markRouteObstacleTriggered(pointId: string, nowMs: number): RouteObstaclePoint | undefined {
    const target: string = pointId.trim()
    if (target.length <= 0) return undefined

    let hit: RouteObstaclePoint | undefined = undefined
    const next: Array<RouteObstaclePoint> = []
    for (let i: number = 0; i < this.routeObstaclePoints.length; i++) {
      const p: RouteObstaclePoint = this.routeObstaclePoints[i]
      if (p.id !== target) {
        next.push(p)
        continue
      }

      if (p.triggered) {
        next.push(p)
        hit = p
        continue
      }

      const t: RouteObstaclePoint = {
        id: p.id,
        xNorm: p.xNorm,
        yNorm: p.yNorm,
        edgeId: p.edgeId,
        t: p.t,
        createdAtMs: p.createdAtMs,
        triggered: true,
        hitAtMs: nowMs
      }
      next.push(t)
      hit = t
    }

    this.routeObstaclePoints = next
    return hit
  }

  private findGridNodeById(id: string): GridNode | undefined {
    const x: string = id.trim().toUpperCase()
    if (x.length <= 0) return undefined
    for (let i: number = 0; i < this.gridNodes.length; i++) {
      const n: GridNode = this.gridNodes[i]
      if (n.id.toUpperCase() === x) return n
    }
    return undefined
  }

  /**
   * 点到线段投影：
   * 返回投影点坐标、t(0..1) 与距离平方 d2，
   * 是“点击映射到路段”和“最近路段搜索”的几何基础。
   */
  private pointSegProjection(px: number, py: number, ax: number, ay: number, bx: number, by: number): RouteSegProjection {
    const vx: number = bx - ax
    const vy: number = by - ay
    const len2: number = vx * vx + vy * vy

    if (len2 <= 1e-8) {
      const d2a: number = this.dist2(px, py, ax, ay)
      return { edgeId: '', pxNorm: ax, pyNorm: ay, t: 0, d2: d2a }
    }

    let t: number = ((px - ax) * vx + (py - ay) * vy) / len2
    if (t < 0) t = 0
    if (t > 1) t = 1

    const qx: number = ax + t * vx
    const qy: number = ay + t * vy
    const d2: number = this.dist2(px, py, qx, qy)
    return { edgeId: '', pxNorm: qx, pyNorm: qy, t: t, d2: d2 }
  }

  // 在全路网边集中找“距离点击点最近的一条边”
  private projectToNearestRouteSegmentByNorm(nx: number, ny: number): RouteSegProjection | undefined {
    const edges: Array<RouteSegment> = PathPlannerAStar.routeEdges()
    let best: RouteSegProjection | undefined = undefined
    let bestD2: number = 0

    for (let i: number = 0; i < edges.length; i++) {
      const e: RouteSegment = edges[i]
      const a: GridNode | undefined = this.findGridNodeById(e.a)
      const b: GridNode | undefined = this.findGridNodeById(e.b)
      if (!a || !b) continue

      const p: RouteSegProjection = this.pointSegProjection(nx, ny, a.xNorm, a.yNorm, b.xNorm, b.yNorm)
      p.edgeId = RouteEdgeCodec.fromSegment(e)

      if (!best || p.d2 < bestD2) {
        best = p
        bestD2 = p.d2
      }
    }
    return best
  }

  nearestEdgeIdByPixel(x: number, y: number): string {
    if (this.mapW <= 0 || this.mapH <= 0) return ''
    const nx: number = this.clamp01(x / this.mapW)
    const ny: number = this.clamp01(y / this.mapH)
    const best: RouteSegProjection | undefined = this.projectToNearestRouteSegmentByNorm(nx, ny)
    if (!best) return ''
    const th: number = this.edgePickThresholdNorm
    if (best.d2 > th * th) return ''
    return best.edgeId
  }

  blockedEdgeMidPos(edgeId: string): XYPos | undefined {
    const p: RouteSegment | undefined = RouteEdgeCodec.parse(edgeId)
    if (!p) return undefined

    const a: GridNode | undefined = this.findGridNodeById(p.a)
    const b: GridNode | undefined = this.findGridNodeById(p.b)
    if (!a || !b) return undefined

    const mx: number = (a.xNorm + b.xNorm) * 0.5
    const my: number = (a.yNorm + b.yNorm) * 0.5
    return { x: mx * this.mapW, y: my * this.mapH }
  }


  toggleBlockedNode(id: string): void {
    if (id.length === 0) return
    if (this.currentSnapNodeId === id) {
      this.pushLog(`障碍设置拒绝：${id}（与当前位置冲突）`)
      return
    }

    const next: Array<string> = []
    let removed: boolean = false
    for (let i: number = 0; i < this.blockedNodes.length; i++) {
      const cur: string = this.blockedNodes[i]
      if (cur === id) { removed = true; continue }
      next.push(cur)
    }

    if (!removed) { next.push(id); this.pushLog(`障碍 + ${id}`) }
    else { this.pushLog(`障碍 - ${id}`) }

    this.blockedNodes = next
  }

  clearBlockedNodes(): void {
    const alreadyClear: boolean =
      this.blockedNodes.length === 0 &&
      this.routeObstaclePoints.length === 0 &&
      this.blockedEdges.length === 0
    if (alreadyClear) return
    this.blockedNodes = []
    this.blockedEdges = []
    this.routeObstaclePoints = []
    this.pushLog('障碍清空')
  }

  clearMapSetupState(): void {
    this.blockedNodes = []
    this.blockedEdges = []
    this.routeObstaclePoints = []
    this.trafficLights = []
    this.gatePoints = []
    this.specialRoadPoints = []
    this.garagePoints = []
    this.warehousePoints = []
    this.obstacleEditEnabled = false
    this.trafficLightEditEnabled = false
    this.gateEditEnabled = false
    this.specialRoadEditEnabled = false
    this.garageEditEnabled = false
    this.warehouseEditEnabled = false
    this.targetPickEnabled = false
    this.mapTargetPendingSend = false
    this.pushLog('清图：地图配置已清空（障碍/红绿灯/道闸/特殊路段/车库/仓库）')
  }

  /**
   * 地图点选移车逻辑：
   * 1) 开启吸附时，优先吸附到最近节点；
   * 2) 未命中吸附阈值则自由放置；
   * 3) 最终统一调用 applyManualPlacementPose 同步位姿。
   */
  moveCarByClick(x: number, y: number): void {
    if (this.mapW <= 0 || this.mapH <= 0) return

    const nx: number = this.clamp01(x / this.mapW)
    const ny: number = this.clamp01(y / this.mapH)

    if (this.gridSnapEnabled) {
      const nearest: GridNode | undefined = this.findNearestNodeByNorm(nx, ny)
      if (nearest) {
        const d2: number = this.dist2(nx, ny, nearest.xNorm, nearest.yNorm)
        const th: number = this.snapThresholdForNode(nearest)
        const th2: number = th * th
        if (d2 <= th2) {
          this.currentSnapNodeId = nearest.id
          this.pushLog(`地图点选：吸附到节点 ${nearest.id}`)

          const headingDeg: number = this.preferredHeadingForPlacement(nearest.yNorm, this.pose.headingDeg)
          this.slideCarToPose(nearest.xNorm, nearest.yNorm, headingDeg, this.carSlideDurationMs, (): void => {
            this.applyManualPlacementPose(nearest.xNorm, nearest.yNorm, headingDeg)
          })
          return
        }
      }
    }

    this.currentSnapNodeId = ''
    this.pushLog(`地图点选：自由移动 car=(${nx.toFixed(3)},${ny.toFixed(3)})`)

    const headingDeg: number = this.preferredHeadingForPlacement(ny, this.pose.headingDeg)
    this.slideCarToPose(nx, ny, headingDeg, this.carSlideDurationMs, (): void => {
      this.applyManualPlacementPose(nx, ny, headingDeg)
    })
  }

  carDotPos(): XYPos {
    const size: number = this.carDotSize
    return { x: (this.carX * this.mapW) - size / 2, y: (this.carY * this.mapH) - size / 2 }
  }

  gridNodeDotPos(n: GridNode, dotSize: number): XYPos {
    return { x: (n.xNorm * this.mapW) - dotSize / 2, y: (n.yNorm * this.mapH) - dotSize / 2 }
  }

  gridNodeLabelPos(n: GridNode): XYPos {
    return { x: (n.xNorm * this.mapW) + 8, y: (n.yNorm * this.mapH) - 10 }
  }

  // ===== 目的地 =====
  destDraft: string = ''
  // destDraft：输入框草稿；destApplied：实际参与规划的目标
  // 只有 applyDest() 后才会影响规划目标
  destApplied: string = ''

  // 目的地应用：把输入草稿固化为当前目标（不在此处规划）
  applyDest(): void {
    const v: string = this.destDraft.trim()
    this.destApplied = v
    this.setAction(v.length > 0 ? `目标已设：${v}` : '目标清空')
  }

  // ===== 真车模式开关 =====
  // realSendEnabled:
  // - true: 允许真实发包（仍需 TCP CONNECTED）
  // - false: 仅 DRY_RUN 记录日志不发车
  realSendEnabled: boolean = true
  alarmEnabled: boolean = false

  setRealSendEnabled(v: boolean): void {
    this.realSendEnabled = v
    this.pushLog(`真车模式：${v ? 'REAL_SEND' : 'DRY_RUN'}`)
  }

  toggleRealSend(): void {
    this.setRealSendEnabled(!this.realSendEnabled)
  }

  // ===== 态势信息 =====
  actionText: string = '状态：待机'

  setAction(text: string): void {
    this.actionText = text
    this.pushLog(`执行：${text}`)
  }

  riskLevel: RiskLevel = RiskLevel.SAFE
  riskText: string = 'SAFE'
  // riskScore:
  // - 越高越危险；>=70 触发高风险分支
  // - 评分来源见 updateRisk()
  riskScore: number = 0

  // 风险评分模型：根据前/后超声和红外距离计算 SAFE/WARN/DANGER
  updateRisk(): void {
    const f: number = this.telemetry.ultraFrontCm
    const b: number = this.telemetry.ultraBackCm
    const ir: number = this.telemetry.irDistCm

    let score: number = 0
    if (f > 0 && f < 25) score += 50
    if (b > 0 && b < 25) score += 30
    if (ir > 0 && ir < 15) score += 40
    if (score > 100) score = 100
    this.riskScore = score

    if (score >= 70) { this.riskLevel = RiskLevel.DANGER; this.riskText = 'DANGER' }
    else if (score >= 35) { this.riskLevel = RiskLevel.WARN; this.riskText = 'WARN' }
    else { this.riskLevel = RiskLevel.SAFE; this.riskText = 'SAFE' }
  }

  // ===== 路径队列 =====
  // pathNodes/pathIndex 语义：
  // - pathNodes[pathIndex] 是当前节点
  // - pathNodes[pathIndex + 1] 是下一跳目标
  pathNodes: Array<string> = []
  pathIndex: number = 0
  lastPlannedAtMs: number = 0

  /**
   * 写入新路径时重置 pathIndex：
   * pathNodes[pathIndex] 始终表示”当前节点”。
   */
  setPath(nodes: Array<string>, reason: string): void {
    this.pathNodes = nodes
    this.pathIndex = 0
    this.lastPlannedAtMs = Date.now()
    this.pushLog(`路径规划(${reason})：${this.pathNodes.join('→')}`)
  }

  stepNextNode(): void {
    if (this.pathNodes.length <= 0) return
    if (this.pathIndex < this.pathNodes.length - 1) this.pathIndex += 1
  }

  private startMoveToNextNode(): void {
    if (!this.autoMoveEnabled || this.pathIndex >= this.pathNodes.length) return

    const targetNode: string = this.pathNodes[this.pathIndex]
    const node: GridNode | undefined = this.findGridNodeById(targetNode)
    if (!node) return

    this.nextNodeTarget = targetNode
    this.carMoveState = 'MOVING'
    this.pushLog(`[自动移动] 开始移动到节点 ${targetNode}`)

    // 真车模式：2秒移动到下一节点；模拟模式：400ms
    const moveDurationMs: number = this.realSendEnabled ? 2000 : this.carSlideDurationMs

    // 滑动小车到目标节点
    this.slideCarToPose(node.xNorm, node.yNorm, this.pose.headingDeg, moveDurationMs, (): void => {
      this.carMoveState = 'WAITING'
      this.pushLog(`[自动移动] 已到达节点 ${targetNode}，等待位置确认`)
    })
  }

  onAutoMoveNodeReceived(receivedNodeId: string): void {
    if (!this.autoMoveEnabled) return
    if (this.carMoveState === 'IDLE') return

    this.lastReceivedNodeId = receivedNodeId

    // 情况1：收到的节点是当前目标节点
    if (receivedNodeId === this.nextNodeTarget) {
      this.pushLog(`[自动移动] 位置确认 ${receivedNodeId}，继续下一节点`)
      this.carMoveState = 'IDLE'
      this.stepNextNode()
      return
    }

    // 情况2：收到的节点不是当前目标，先滑动到接收的位置
    if (this.carMoveState === 'WAITING') {
      const node: GridNode | undefined = this.findGridNodeById(receivedNodeId)
      if (node) {
        this.pushLog(`[自动移动] 位置不匹配，滑动到 ${receivedNodeId}`)
        // 真车模式：2秒移动；模拟模式：400ms
        const moveDurationMs: number = this.realSendEnabled ? 2000 : this.carSlideDurationMs
        this.slideCarToPose(node.xNorm, node.yNorm, this.pose.headingDeg, moveDurationMs, (): void => {
          this.carMoveState = 'IDLE'
          this.stepNextNode()
        })
      }
    }
  }

  stopAutoMove(): void {
    this.autoMoveEnabled = false
    this.carMoveState = 'IDLE'
    this.nextNodeTarget = ''
    if (this.autoMoveDelayTimerId >= 0) {
      clearTimeout(this.autoMoveDelayTimerId)
      this.autoMoveDelayTimerId = -1
    }
    this.pushLog('[自动移动] 已停止')
  }

  clearPath(): void {
    this.stopAutoMove()
    this.pathNodes = []
    this.pathIndex = 0
    this.pushLog('[路径] 已清空')
  }

  // ===== 小车移动状态机 =====
  autoMoveEnabled: boolean = false
  carMoveState: 'IDLE' | 'MOVING' | 'WAITING' = 'IDLE'
  nextNodeTarget: string = ''
  lastReceivedNodeId: string = ''
  private autoMoveDelayTimerId: number = -1

  // ===== 通信状态 =====
  connState: CarConnState = CarConnState.IDLE
  connText: string = 'TCP:IDLE'
  connIp: string = CAR_DEVICE_IP
  connPort: number = CAR_TCP_PORT

  // 统计计数：
  // - txFrames/rxFrames 仅用于显示和诊断，不参与控制逻辑
  txFrames: number = 0
  rxFrames: number = 0
  reconnectCount: number = 0
  // heartbeatOk 表示最近一段时间是否有正常收包
  heartbeatOk: boolean = false

  setConnState(state: CarConnState, text: string): void {
    this.connState = state
    this.connText = text
    this.pushLog(`链路状态：${text}`)
  }

  bumpTx(): void { this.txFrames += 1 }
  bumpRx(): void { this.rxFrames += 1 }

  telemetry: CarTelemetry = {
    tsMs: 0,
    speed: 0,
    headingDeg: 0,
    odomMm: 0,
    ultraFrontCm: 0,
    ultraBackCm: 0,
    irDistCm: 0,
    lightLux: 0,
    rfid: ''
  }

  setTelemetry(t: CarTelemetry): void {
    this.telemetry = t
    this.updateDisplayMetricsFromTelemetry('telemetry', t)
    this.ensureMetricAnimatorRunning()
  }

  private carAnimTimerId: number = -1
  private carAnimFromX: number = 0
  private carAnimFromY: number = 0
  private carAnimToX: number = 0
  private carAnimToY: number = 0
  private carAnimStartTime: number = 0
  private carAnimFromHeading: number = 0
  private carAnimToHeading: number = 0
  private readonly carSlideDurationMs: number = 400
  private readonly carSlideFrameMs: number = 16

  private stopCarSlide(): void {
    if (this.carAnimTimerId >= 0) {
      clearInterval(this.carAnimTimerId)
      this.carAnimTimerId = -1
    }
  }

  private setVisualPoseState(xNorm: number, yNorm: number, headingDeg: number): void {
    const sx: number = this.clamp01(xNorm)
    const sy: number = this.clamp01(yNorm)
    const sh: number = this.normHeadingDeg(headingDeg)
    this.carX = sx
    this.carY = sy
    this.pose = {
      ...this.pose,
      tsMs: Date.now(),
      xNorm: sx,
      yNorm: sy,
      headingDeg: sh
    }
  }

  private slideCarToPose(
    toXNorm: number,
    toYNorm: number,
    toHeadingDeg: number,
    durationMs: number,
    onDone?: () => void
  ): void {
    const targetX: number = this.clamp01(toXNorm)
    const targetY: number = this.clamp01(toYNorm)
    const targetHeading: number = this.normHeadingDeg(toHeadingDeg)
    const fromX: number = this.carX
    const fromY: number = this.carY
    const fromHeading: number = this.normHeadingDeg(this.pose.headingDeg)

    this.stopCarSlide()

    this.carAnimFromX = fromX
    this.carAnimFromY = fromY
    this.carAnimToX = targetX
    this.carAnimToY = targetY
    this.carAnimFromHeading = fromHeading
    this.carAnimToHeading = targetHeading
    this.carAnimStartTime = Date.now()

    const safeDurationMs: number = Math.max(60, Math.round(durationMs))
    if (safeDurationMs <= 60) {
      this.setVisualPoseState(targetX, targetY, targetHeading)
      if (onDone) onDone()
      return
    }

    this.carAnimTimerId = setInterval((): void => {
      const elapsed: number = Date.now() - this.carAnimStartTime
      if (elapsed >= safeDurationMs) {
        this.setVisualPoseState(this.carAnimToX, this.carAnimToY, this.carAnimToHeading)
        this.stopCarSlide()
        if (onDone) onDone()
        return
      }

      const t: number = elapsed / safeDurationMs
      const easeT: number = this.easeInOutSine(t)
      const cx: number = this.carAnimFromX + (this.carAnimToX - this.carAnimFromX) * easeT
      const cy: number = this.carAnimFromY + (this.carAnimToY - this.carAnimFromY) * easeT
      const ch: number = this.lerpHeading(this.carAnimFromHeading, this.carAnimToHeading, easeT)
      this.setVisualPoseState(cx, cy, ch)
    }, this.carSlideFrameMs) as number
  }

  updateCurrentNodePose(nodeId: string, headingDeg: number): void {
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return
    const n: GridNode | undefined = this.findGridNodeById(id)
    if (!n) return
    this.currentSnapNodeId = id
    this.ensureMetricAnimatorRunning()
    this.setMetricHeadingDeg(headingDeg)
    if (this.metricTargetSpeedCms <= 0.01) {
      this.metricTargetSpeedCms = 12
    }
    hilog.info(
      METRIC_LOG_DOMAIN,
      METRIC_LOG_TAG,
      '[store] node=%{public}s heading=%{public}s speedTarget=%{public}s',
      id,
      String(Math.round(this.metricHeadingDeg)),
      this.metricTargetSpeedCms.toFixed(2)
    )
    this.slideCarToPose(n.xNorm, n.yNorm, headingDeg, this.carSlideDurationMs, (): void => {
      this.applyManualPlacementPose(n.xNorm, n.yNorm, headingDeg)
    })
  }

  private lerpHeading(from: number, to: number, t: number): number {
    let diff = to - from
    if (diff > 180) diff -= 360
    if (diff < -180) diff += 360
    return from + diff * t
  }

  private easeInOutSine(t: number): number {
    return -(Math.cos(Math.PI * t) - 1) / 2
  }

  // ===== 状态栏显示（与底层遥测解耦）=====
  metricSpeedCms: number = 0
  metricHeadingDeg: number = 0
  metricHeadingText: string = 'N'
  metricDistanceCm: number = 0
  metricLightLux: number = 0
  metricDebugLine: string = ''
  private metricStoreLastTsMs: number = 0
  private metricStoreLastXNorm: number = 0
  private metricStoreLastYNorm: number = 0
  private metricStoreLastOdomMm: number = 0
  private metricStoreLogLastAtMs: number = 0
  private metricAnimTimerId: number = -1
  private metricAnimLastTsMs: number = 0
  private metricLightWaveDeg: number = 0
  private metricLightNextShuffleAtMs: number = 0
  private metricTargetSpeedCms: number = 0
  private metricTargetDistanceCm: number = 0
  private metricTargetLightLux: number = this.randomLightBaseLux()
  private metricStoreLightBaseLux: number = this.metricTargetLightLux
  private readonly metricNormToCm: number = 250

  setMetricSpeedCms(v: number): void {
    const safe: number = Number.isFinite(v) ? v : 0
    const clamped: number = Math.max(0, Math.abs(safe))
    this.metricSpeedCms = Math.round(clamped * 10) / 10
  }

  setMetricHeadingDeg(v: number): void {
    this.metricHeadingDeg = this.normHeadingDeg(v)
    this.metricHeadingText = this.headingTextFromDeg(this.metricHeadingDeg)
  }

  setMetricDistanceCm(v: number): void {
    const safe: number = Number.isFinite(v) ? v : 0
    this.metricDistanceCm = Math.max(0, Math.round(safe))
  }

  setMetricLightLux(v: number): void {
    const safe: number = Number.isFinite(v) ? v : 0
    this.metricLightLux = Math.max(0, Math.round(safe))
  }

  private headingTextFromDeg(v: number): string {
    const idx: number = Math.round(this.normHeadingDeg(v) / 45) % 8
    if (idx === 0) return 'N'
    if (idx === 1) return 'NE'
    if (idx === 2) return 'E'
    if (idx === 3) return 'SE'
    if (idx === 4) return 'S'
    if (idx === 5) return 'SW'
    if (idx === 6) return 'W'
    return 'NW'
  }

  private normDistance(ax: number, ay: number, bx: number, by: number): number {
    const dx: number = ax - bx
    const dy: number = ay - by
    return Math.sqrt(dx * dx + dy * dy)
  }

  private randomLightBaseLux(): number {
    return 200 + Math.floor(Math.random() * 251)
  }

  private ensureMetricAnimatorRunning(): void {
    if (this.metricAnimTimerId >= 0) return
    this.metricAnimLastTsMs = Date.now()
    this.metricAnimTimerId = setInterval((): void => {
      this.tickMetricAnimator()
    }, 120) as number
  }

  private tickMetricAnimator(): void {
    const nowMs: number = Date.now()
    let dtSec: number = (nowMs - this.metricAnimLastTsMs) / 1000
    this.metricAnimLastTsMs = nowMs
    if (!Number.isFinite(dtSec) || dtSec <= 0) dtSec = 0.12
    if (dtSec > 0.5) dtSec = 0.5

    const speedGap: number = this.metricTargetSpeedCms - this.metricSpeedCms
    const speedStep: number = Math.abs(speedGap) * 0.35
    if (speedStep < 0.2) {
      this.setMetricSpeedCms(this.metricTargetSpeedCms)
    } else {
      const nextSpeed: number = this.metricSpeedCms + speedStep * (speedGap >= 0 ? 1 : -1)
      this.setMetricSpeedCms(nextSpeed)
    }

    if (this.metricDistanceCm < this.metricTargetDistanceCm) {
      const gapCm: number = this.metricTargetDistanceCm - this.metricDistanceCm
      const travelBySpeed: number = Math.max(0.35, this.metricSpeedCms * dtSec)
      const incCm: number = Math.min(gapCm, travelBySpeed)
      this.setMetricDistanceCm(this.metricDistanceCm + incCm)
    }

    if (nowMs >= this.metricLightNextShuffleAtMs) {
      this.metricStoreLightBaseLux = this.randomLightBaseLux()
      this.metricTargetLightLux = this.metricStoreLightBaseLux
      this.metricLightNextShuffleAtMs = nowMs + 1800 + Math.floor(Math.random() * 1200)
    }

    this.metricLightWaveDeg += dtSec * 120
    if (this.metricLightWaveDeg >= 360) this.metricLightWaveDeg -= 360
    const wave: number = Math.sin((this.metricLightWaveDeg * Math.PI) / 180) * 10
    const lightTarget: number = Math.max(200, Math.min(450, this.metricTargetLightLux + wave))
    const lightGap: number = lightTarget - this.metricLightLux
    this.setMetricLightLux(this.metricLightLux + lightGap * 0.3)

    if (nowMs - this.metricStoreLogLastAtMs >= 250) {
      this.metricStoreLogLastAtMs = nowMs
      hilog.info(
        METRIC_LOG_DOMAIN,
        METRIC_LOG_TAG,
        '[store] src=anim speed=%{public}s target=%{public}s dist=%{public}s targetDist=%{public}s light=%{public}s',
        this.metricSpeedCms.toFixed(2),
        this.metricTargetSpeedCms.toFixed(2),
        String(this.metricDistanceCm),
        String(Math.round(this.metricTargetDistanceCm)),
        String(this.metricLightLux)
      )
    }
  }

  private updateDisplayMetricsFromTelemetry(source: string, t: CarTelemetry): void {
    const nowMs: number = t.tsMs > 0 ? t.tsMs : Date.now()
    const curX: number = this.pose.xNorm
    const curY: number = this.pose.yNorm
    const curHeadingDeg: number = this.normHeadingDeg(t.headingDeg)

    let dtSec: number = 0
    if (this.metricStoreLastTsMs > 0 && nowMs > this.metricStoreLastTsMs) {
      dtSec = (nowMs - this.metricStoreLastTsMs) / 1000
    }

    let distFromPoseCm: number = 0
    if (this.metricStoreLastTsMs > 0) {
      const deltaNorm: number = this.normDistance(
        this.metricStoreLastXNorm,
        this.metricStoreLastYNorm,
        curX,
        curY
      )
      distFromPoseCm = deltaNorm * this.metricNormToCm
    }

    let distIncCm: number = 0
    if (t.odomMm > 0 && this.metricStoreLastOdomMm > 0 && t.odomMm >= this.metricStoreLastOdomMm) {
      distIncCm = (t.odomMm - this.metricStoreLastOdomMm) / 10
    }
    if (distIncCm <= 0 && distFromPoseCm > 0) {
      distIncCm = distFromPoseCm
    }
    if (distIncCm > 0.01) {
      this.metricTargetDistanceCm += distIncCm
    }

    let speedCms: number = Math.max(0, Math.abs(t.speed))
    if (speedCms <= 0.01 && distIncCm > 0.01) {
      if (dtSec > 0.05) speedCms = distIncCm / dtSec
      else speedCms = distIncCm * 5
    }
    if (speedCms > 55) speedCms = 55
    this.metricTargetSpeedCms = speedCms

    this.setMetricHeadingDeg(curHeadingDeg)

    this.metricStoreLastTsMs = nowMs
    this.metricStoreLastXNorm = curX
    this.metricStoreLastYNorm = curY
    if (t.odomMm > 0) this.metricStoreLastOdomMm = t.odomMm

    if (nowMs - this.metricStoreLogLastAtMs >= 250) {
      this.metricStoreLogLastAtMs = nowMs
      hilog.info(
        METRIC_LOG_DOMAIN,
        METRIC_LOG_TAG,
        '[store] src=%{public}s speedTarget=%{public}s heading=%{public}s distTarget=%{public}s lightBase=%{public}s odom=%{public}s',
        source,
        this.metricTargetSpeedCms.toFixed(2),
        String(Math.round(this.metricHeadingDeg)),
        String(Math.round(this.metricTargetDistanceCm)),
        String(this.metricTargetLightLux),
        String(t.odomMm)
      )
    }
  }

  batteryPct: number = 87
  logs: Array<string> = []

  // 统一日志入口：带毫秒时间戳，最多保留最近 60 条
  pushLog(line: string): void {
    const ts: number = Date.now()
    const item: string = `${ts} | ${line}`
    hilog.info(BIZLOG_DOMAIN, BIZLOG_TAG, 'page1: %{public}s', item)
    // 普通业务日志改为仅输出到 hilog，UI 面板不再保留。
    if (this.logs.length > 0) this.logs = []
  }
}

export const page1Store: Page1UiStore = new Page1UiStore()
