/**
 * 代码指南：
 * 文件： pages/page1/components/SandboxMap.ets
 * 用途： 仅用于 Page1 页面的可视化组件（地图 / 状态 / 控件渲染）
 * 何时修改： 仅在需要修改视图样式、控件组件、纯展示类交互时编辑此文件
 * 相关文件： 页面状态数据来源于 app/Page1UiStore.ets，操作事件转发至 app/Page1Coordinator.ets
 */
// entry/src/main/ets/pages/page1/components/SandboxMap.ets

import { page1Store, Page1UiStore, XYPos, RouteObstaclePoint } from '../app/Page1UiStore'
import { GridNode } from '../types/SandboxGridTypes'
import { Page1Theme } from '../Page1Theme'
import { RouteEdgeCodec, PathPlannerAStar } from '../app/PathPlannerAStar'

type NodeBlockType = 'parking' | 'junction' | 'corridor'

interface NodeBlockRule {
  fullBlockThreshold: number
}

type MapDetailLevel = 'OVERVIEW' | 'ROUTE' | 'DETAIL'
interface MapRoadRect {
  id: string
  x: number
  y: number
  w: number
  h: number
}

interface MapBlockCellRect extends MapRoadRect {
  color: string
}

interface MapPathSegment {
  id: string
  fromId: string
  toId: string
  ax: number
  ay: number
  bx: number
  by: number
  index: number
}

interface MapTurnNode {
  id: string
  x: number
  y: number
  index: number
}

@Component
export struct SandboxMap {
  @State private store: Page1UiStore = page1Store
  fullHeightMap: boolean = false

  private readonly DEFAULT_ROUTE_ZOOM: number = 1.5
  @State private zoomScale: number = 1.5
  @State private pinchStartZoomScale: number = 1.5

  @State private offsetX: number = 0
  @State private offsetY: number = 0
  @State private panStartX: number = 0
  @State private panStartY: number = 0

  @State private cameraFollowEnabled: boolean = true
  private followTimerId: number = -1

  // 手动操作后的临时失权窗口
  @State private manualOverrideUntilMs: number = 0

  // 手动操作后允许自动跟随恢复的等待时间（毫秒）
  private readonly MANUAL_OVERRIDE_MS: number = 4800

  private readonly FOLLOW_TICK_MS: number = 120

  private markManualOverride(): void {
    const now: number = Date.now()
    this.manualOverrideUntilMs = now + this.MANUAL_OVERRIDE_MS
  }

  private shouldForceFollowNow(): boolean {
    // 程序在运行时，（AUTO_FOLLOW + speed!=0）强制跟随
    return this.store.autoFollowEnabled && Math.abs(this.store.telemetry.speed) > 0
  }

  aboutToAppear(): void {
    // 每次进入页面都回到 ROUTE 级缩放（1.2 <= zoom < 2.2）。
    this.zoomScale = this.DEFAULT_ROUTE_ZOOM
    this.pinchStartZoomScale = this.DEFAULT_ROUTE_ZOOM
    this.clampAll()
    this.syncCameraFollow()

    this.stopFollowTimer()
    this.followTimerId = setInterval((): void => {
      this.syncCameraFollow()
    }, this.FOLLOW_TICK_MS) as number
  }

  aboutToDisappear(): void {
    this.stopFollowTimer()
  }

  private stopFollowTimer(): void {
    if (this.followTimerId !== -1) {
      clearInterval(this.followTimerId)
      this.followTimerId = -1
    }
  }

  build() {
    Column({ space: 8 }) {
      if (!this.fullHeightMap) {
        Row({ space: 10 }) {
          Button(this.cameraBtnText())
            .layoutWeight(1)
            .height(40)
            .borderRadius(12)
            .backgroundColor(this.cameraBtnBg())
            .fontColor(this.cameraBtnFg())
            .fontSize(13)
            .onClick((): void => {
              // 手动切换镜头跟随后，视为一次人工接管，短时间内不自动抢回
              this.markManualOverride()

              this.cameraFollowEnabled = !this.cameraFollowEnabled
              this.store.pushLog(`镜头跟随：${this.cameraFollowEnabled ? 'ON' : 'OFF'}`)
              if (this.cameraFollowEnabled) {
                this.syncCameraFollow()
              }
            })

          Button(this.poseBtnText())
            .layoutWeight(1)
            .height(40)
            .borderRadius(12)
            .backgroundColor(this.poseBtnBg())
            .fontColor(this.poseBtnFg())
            .fontSize(13)
            .onClick((): void => {
              this.store.poseFollowEnabled = !this.store.poseFollowEnabled
              this.store.pushLog(`POSE跟随：${this.store.poseFollowEnabled ? 'ON' : 'OFF'}`)
              if (this.store.poseFollowEnabled) {
                this.store.poseInited = false
              }
            })

          Button(this.editBtnText())
            .layoutWeight(1)
            .height(40)
            .borderRadius(12)
            .backgroundColor(this.editBtnBg())
            .fontColor(this.editBtnFg())
            .fontSize(13)
            .onClick((): void => {
              this.store.toggleObstacleEdit()
            })
        }

        Button(`清空障碍(${this.store.blockedNodes.length + this.store.blockedEdges.length + this.store.routeObstaclePoints.length})`)
          .width('100%')
          .height(40)
          .borderRadius(12)
          .backgroundColor('#EDEFF2')
          .fontColor('#333333')
          .fontSize(13)
          .onClick((): void => {
            this.store.clearBlockedNodes()
          })
      }

      // 分层渲染：BaseLayer -> GridLayer -> RouteLayer -> ObstacleLayer -> VehicleLayer -> LabelLayer
      Stack() {
        Stack() {
          Image($rawfile('sandbox_map.png'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)

          if (!this.isOverviewLevel()) {
            this.buildGridOverlay()
            this.buildBlockedNodeMarkers()
            this.buildRouteObstaclePointMarkers()
            this.buildBlockedEdgeMarkers()
          }
          this.buildDestinationMarker()
          this.buildCarDot()
          this.buildCarHeadingArrow()
          if (this.isDetailLevel()) {
            this.buildCurrentNodeBadge()
          }
        }
        .width('100%')
        .height('100%')
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.offsetX, y: this.offsetY })
      }
      .width('100%')
      .height(this.fullHeightMap ? '100%' : 480)
      .borderRadius(Page1Theme.RADIUS_XL)
      .clip(true)
      .backgroundColor('#081624')
      .border({ width: 1, color: 'rgba(0,0,0,0.06)' })
      .shadow({ radius: 48, color: '#0000001F', offsetX: 0, offsetY: 12 })
      .onAreaChange((oldValue: Area, newValue: Area): void => {
        const w: number = this.lengthToNumber(newValue.width)
        const h: number = this.lengthToNumber(newValue.height)
        this.store.setMapSize(w, h)
        this.clampAll()
        this.syncCameraFollow()
      })
      .onClick((evt: ClickEvent): void => {
        const x: number = this.screenToMapX(evt.x)
        const y: number = this.screenToMapY(evt.y)

        if (this.store.obstacleEditEnabled) {
          if (this.store.toggleRouteObstaclePointByPixel(x, y)) {
            return
          }
          const id: string = this.store.nearestNodeIdByPixel(x, y)
          if (id.length > 0) {
            this.store.toggleBlockedNode(id)
          }
          return
        }

        if (this.store.targetPickEnabled) {
          const id: string = this.store.nearestNodeIdByPixel(x, y)
          if (id.length > 0) {
            this.store.destDraft = id
            this.store.mapTargetPendingSend = true
            this.store.pushLog(`目标点选：${id}，点击“目标”按钮确认发送`)
            this.store.targetPickEnabled = false
          }
          return
        }

        // 点选移动红点后立即跟随
        this.store.moveCarByClick(x, y)
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture()
            .onActionStart((): void => {
              // 用户开始拖动画面后，进入手动接管窗口，避免镜头立即抢回
              this.markManualOverride()
              this.panStartX = this.offsetX
              this.panStartY = this.offsetY
            })
            .onActionUpdate((e: GestureEvent): void => {
              const rawX: number = this.panStartX + e.offsetX
              const rawY: number = this.panStartY + e.offsetY
              this.offsetX = this.clampOffsetX(rawX)
              this.offsetY = this.clampOffsetY(rawY)
            }),

          PinchGesture()
            .onActionStart((): void => {
              // 用户开始双指缩放后，进入手动接管窗口，避免镜头立即抢回
              this.markManualOverride()
              this.pinchStartZoomScale = this.zoomScale
            })
            .onActionUpdate((e: GestureEvent): void => {
              const next: number = this.clampScale(this.pinchStartZoomScale * e.scale)
              this.zoomScale = next
              this.clampAll()
              this.syncCameraFollow()
            })
        )
      )
    }
    .width('100%')
    .height('100%')
    .margin({ top: this.fullHeightMap ? 0 : 12 })
  }

  private pathIndexOf(id: string): number {
    for (let i: number = 0; i < this.store.pathNodes.length; i++) {
      if (this.store.pathNodes[i] === id) {
        return i
      }
    }
    return -1
  }

  private isPathVisited(id: string): boolean {
    const idx: number = this.pathIndexOf(id)
    return idx >= 0 && idx < this.store.pathIndex
  }

  private isPathCurrent(id: string): boolean {
    const idx: number = this.pathIndexOf(id)
    return idx >= 0 && idx === this.store.pathIndex
  }

  private isPathNext(id: string): boolean {
    const idx: number = this.pathIndexOf(id)
    return idx >= 0 && idx === (this.store.pathIndex + 1)
  }

  private isPathFuture(id: string): boolean {
    const idx: number = this.pathIndexOf(id)
    return idx >= 0 && idx > (this.store.pathIndex + 1)
  }

  @Builder
  private buildGridOverlay(): void {
    ForEach(this.visibleGridNodesForRender(), (n: GridNode): void => {
      if (!this.isCurrentNode(n.id) && this.shouldShowGridNode(n.id)) {
        Column() {}
        .width(this.gridDotSize())
        .height(this.gridDotSize())
        .borderRadius(this.gridDotSize() / 2)
        .backgroundColor(this.nodeDotBg(n.id))
        .position(this.store.gridNodeDotPos(n, this.gridDotSize()))
        .zIndex(2)

        if (this.shouldShowNodeLabel(n.id)) {
          Text(n.id)
            .fontSize(this.nodeLabelFontSize())
            .fontColor(this.nodeLabelColor(n.id))
            .fontWeight(this.nodeLabelWeight(n.id))
            .position(this.store.gridNodeLabelPos(n))
            .zIndex(2)
        }
      }
    }, (n: GridNode): string => n.id)
  }

  @Builder
  private buildRouteObstaclePointMarkers(): void {
    ForEach(this.visibleRouteObstaclePointsForRender(), (p: RouteObstaclePoint): void => {
      if (!this.edgeMarkerSuppressedByNodeBlock(p.edgeId)) {
        Image($rawfile('icon/障碍物.png'))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
          .position(this.routeObstaclePointPos(p))
          .zIndex(4)
      }
    }, (p: RouteObstaclePoint): string => p.id)
  }

  private routeObstaclePointPos(p: RouteObstaclePoint): XYPos {
    const x: number = p.xNorm * this.store.mapW - 9
    const y: number = p.yNorm * this.store.mapH - 9
    return { x: x, y: y }
  }

  @Builder
  private buildBlockedEdgeMarkers(): void {
    ForEach(this.visibleBlockedEdgesForRender(), (edgeId: string): void => {
      if (this.edgeMarkerVisible(edgeId)) {
        Image($rawfile('icon/障碍物.png'))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
          .position(this.edgeMarkerPos(edgeId))
          .zIndex(3)
      }
    }, (edgeId: string): string => edgeId)
  }

  private edgeMarkerVisible(edgeId: string): boolean {
    if (this.edgeMarkerSuppressedByNodeBlock(edgeId)) return false
    return this.store.blockedEdgeMidPos(edgeId) !== undefined
  }

  private edgeMarkerPos(edgeId: string): XYPos {
    const p: XYPos | undefined = this.store.blockedEdgeMidPos(edgeId)
    if (!p) {
      return { x: -1000, y: -1000 }
    }
    return { x: p.x - 9, y: p.y - 9 }
  }

  @Builder
  private buildBlockedNodeMarkers(): void {
    ForEach(this.visibleBlockedNodesForRender(), (n: GridNode): void => {
      if (this.shouldShowBlockedNodeMarker(n.id)) {
        Image(this.blockedNodeMarkerResource(n.id))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .position(this.store.gridNodeDotPos(n, 20))
        .zIndex(6)
      }
    }, (n: GridNode): string => `blocked-node-${n.id}`)
  }

  private visibleGridNodesForRender(): Array<GridNode> {
    if (!this.isDetailLevel()) return this.store.gridNodes
    const out: Array<GridNode> = []
    for (let i: number = 0; i < this.store.gridNodes.length; i++) {
      const n: GridNode = this.store.gridNodes[i]
      if (this.isWorldPointVisible(n.xNorm * this.store.mapW, n.yNorm * this.store.mapH, 56)) out.push(n)
    }
    return out
  }

  private visibleRouteObstaclePointsForRender(): Array<RouteObstaclePoint> {
    const out: Array<RouteObstaclePoint> = []
    for (let i: number = 0; i < this.store.routeObstaclePoints.length; i++) {
      const p: RouteObstaclePoint = this.store.routeObstaclePoints[i]
      if (this.isRouteLevel() && (p.createdAtMs % 2 !== 0)) continue
      if (this.isDetailLevel() && !this.isWorldPointVisible(p.xNorm * this.store.mapW, p.yNorm * this.store.mapH, 48)) continue
      out.push(p)
    }
    return out
  }

  private visibleBlockedEdgesForRender(): Array<string> {
    const out: Array<string> = []
    for (let i: number = 0; i < this.store.blockedEdges.length; i++) {
      const edgeId: string = this.store.blockedEdges[i]
      if (this.isRouteLevel()) {
        const parsed = RouteEdgeCodec.parse(edgeId)
        if (!parsed) continue
        if ((parsed.a.charCodeAt(0) + parsed.b.charCodeAt(0)) % 2 !== 0) continue
      }
      out.push(edgeId)
    }
    return out
  }

  private visibleBlockedNodesForRender(): Array<GridNode> {
    const out: Array<GridNode> = []
    for (let i: number = 0; i < this.store.gridNodes.length; i++) {
      const n: GridNode = this.store.gridNodes[i]
      if (this.isDetailLevel() && !this.isWorldPointVisible(n.xNorm * this.store.mapW, n.yNorm * this.store.mapH, 48)) continue
      if (this.isRouteLevel() && ((n.id.charCodeAt(0) + n.id.charCodeAt(1)) % 2 !== 0)) continue
      out.push(n)
    }
    return out
  }

  @Builder
  private buildDestinationMarker(): void {
    if (this.hasDestinationMarker()) {
      Image($rawfile('icon/目的地.png'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .position(this.destinationMarkerPos())
        .zIndex(8)
    }
  }

  private hasDestinationMarker(): boolean {
    return this.destinationMarkerNode() !== undefined
  }

  private destinationMarkerPos(): XYPos {
    const node: GridNode | undefined = this.destinationMarkerNode()
    if (!node) return { x: -9999, y: -9999 }
    return this.store.gridNodeDotPos(node, 24)
  }

  private destinationMarkerNode(): GridNode | undefined {
    const targetId: string = this.displayTargetNodeId()
    if (targetId.length <= 0) return undefined
    return this.findGridNodeById(targetId)
  }

  private displayTargetNodeId(): string {
    const pending: string = this.store.destDraft.trim().toUpperCase()
    if (this.store.mapTargetPendingSend && pending.length > 0) return pending

    const applied: string = this.store.destApplied.trim().toUpperCase()
    if (applied.length > 0) return applied
    return ''
  }

  private findGridNodeById(id: string): GridNode | undefined {
    const x: string = id.trim().toUpperCase()
    if (x.length <= 0) return undefined
    for (let i: number = 0; i < this.store.gridNodes.length; i++) {
      const n: GridNode = this.store.gridNodes[i]
      if (n.id.toUpperCase() === x) return n
    }
    return undefined
  }

  @Builder
  private buildCarDot(): void {
    Column() {}
    .width(this.store.carDotSize)
    .height(this.store.carDotSize)
    .borderRadius(this.store.carDotSize / 2)
    .backgroundColor('#3381FF')
    .border({ width: 3, color: '#FFFFFF' })
    .position(this.store.carDotPos())
    .zIndex(10)
  }

  // 箭头相关
  @Builder
  private buildCarHeadingArrow(): void {
    Image($rawfile('icon/方向箭头.png'))
      .width(this.carArrowSize())
      .height(this.carArrowSize())
      .objectFit(ImageFit.Contain)
      .rotate({
        z: 1,
        angle: this.carArrowDisplayDeg(),
        centerX: '50%',
        centerY: '50%'
      })
      .position(this.carArrowPos())
      .zIndex(11)
  }

  private normHeadingDeg(v: number): number {
    let x: number = v % 360
    if (x < 0) {
      x += 360
    }
    return x
  }

  private carArrowSectorIndex(): number {
    const headingDeg: number = this.normHeadingDeg(this.store.pose.headingDeg)
    return Math.round(headingDeg / 45) % 8
  }

  private carArrowSize(): number {
    return 18
  }

  private carArrowPos(): XYPos {
    const dot: XYPos = this.store.carDotPos()
    const size: number = this.store.carDotSize
    const centerX: number = dot.x + size / 2
    const centerY: number = dot.y + size / 2
    const headingDeg: number = this.carArrowHeadingDeg()
    const rad: number = headingDeg * Math.PI / 180
    const radius: number = size / 2 + 10
    const arrowSize: number = this.carArrowSize()

    return {
      x: centerX + Math.cos(rad) * radius - arrowSize / 2,
      y: centerY + Math.sin(rad) * radius - arrowSize / 2
    }
  }

  private carArrowHeadingDeg(): number {
    // 边框优先规则：
    // - 红点贴左边框：箭头强制朝右
    // - 红点贴右边框：箭头强制朝左
    if (this.isCarNearLeftBorder()) return 0
    if (this.isCarNearRightBorder()) return 180
    return this.carArrowSectorIndex() * 45
  }

  private carArrowDisplayDeg(): number {
    // 假设方向箭头.png 的“0度”朝向为右（与旧版文本箭头一致）。
    // 若素材默认朝上，可改成：return this.carArrowHeadingDeg() + 90
    return this.carArrowHeadingDeg()
  }

  private isCarNearLeftBorder(): boolean {
    const dot: XYPos = this.store.carDotPos()
    const size: number = this.store.carDotSize
    const centerX: number = dot.x + size / 2
    const thresholdPx: number = Math.max(8, size * 0.7)
    return centerX <= thresholdPx
  }

  private isCarNearRightBorder(): boolean {
    const dot: XYPos = this.store.carDotPos()
    const size: number = this.store.carDotSize
    const mw: number = this.store.mapW
    if (mw <= 0) return false
    const centerX: number = dot.x + size / 2
    const thresholdPx: number = Math.max(8, size * 0.7)
    return centerX >= mw - thresholdPx
  }

  private edgeMarkerSuppressedByNodeBlock(edgeId: string): boolean {
    const parsed = RouteEdgeCodec.parse(edgeId)
    if (!parsed) return false
    return this.isNodeFullyBlocked(parsed.a) || this.isNodeFullyBlocked(parsed.b)
  }

  private isNodeFullyBlocked(nodeId: string): boolean {
    const x: string = nodeId.trim().toUpperCase()
    if (x.length <= 0) return false

    let blockedIncident: number = 0
    for (let i: number = 0; i < this.store.blockedEdges.length; i++) {
      const parsed = RouteEdgeCodec.parse(this.store.blockedEdges[i])
      if (!parsed) continue
      if (parsed.a === x || parsed.b === x) blockedIncident += 1
    }

    const rule: NodeBlockRule = this.nodeBlockRuleFor(x)
    return blockedIncident >= rule.fullBlockThreshold
  }

  private shouldShowBlockedNodeMarker(nodeId: string): boolean {
    const x: string = nodeId.trim().toUpperCase()
    if (x.length <= 0) return false
    return this.store.isBlocked(x) || this.isNodeFullyBlocked(x)
  }

  private blockedNodeMarkerResource(nodeId: string): any {
    if (this.isNodeFullyBlocked(nodeId) && !this.isParkingNode(nodeId)) {
      return $rawfile('icon/堵塞.png')
    }
    return $rawfile('icon/堵塞占用.png')
  }

  private nodeBlockTypeOf(nodeId: string): NodeBlockType {
    const x: string = nodeId.trim().toUpperCase()
    if (x.length <= 0) return 'corridor'

    // 停车位：顶行/底行停车节点统一按停车类型处理（堵塞图固定为占用图）。
    if (x === 'B1' || x === 'D1' || x === 'F1' || x === 'B7' || x === 'D7' || x === 'F7') {
      return 'parking'
    }

    const degree: number = this.nodeDegree(x)
    if (degree >= 3) return 'junction'
    return 'corridor'
  }

  private nodeBlockRuleFor(nodeId: string): NodeBlockRule {
    const t: NodeBlockType = this.nodeBlockTypeOf(nodeId)
    if (t === 'parking') {
      return {
        fullBlockThreshold: 999
      }
    }
    if (t === 'junction') {
      return {
        fullBlockThreshold: 3
      }
    }
    return {
      fullBlockThreshold: 2
    }
  }

  private isParkingNode(nodeId: string): boolean {
    return this.nodeBlockTypeOf(nodeId) === 'parking'
  }

  private nodeDegree(nodeId: string): number {
    const x: string = nodeId.trim().toUpperCase()
    if (x.length <= 0) return 0

    const edges = PathPlannerAStar.routeEdges()
    let degree: number = 0
    for (let i: number = 0; i < edges.length; i++) {
      const e = edges[i]
      if (e.a === x || e.b === x) degree += 1
    }
    return degree
  }

  @Builder
  private buildCurrentNodeBadge(): void {
    if (this.currentNodeBadgeId().length > 0) {
      Text(this.currentNodeBadgeId())
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111111')
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor('#FFFFFFEE')
        .border({ width: 1, color: '#00000022' })
        .borderRadius(8)
        .position(this.currentNodeBadgePos())
        .zIndex(12)
    }
  }

  @Builder
  private buildOverviewCurrentNodeMarker(): void {
    if (this.hasOverviewCurrentNodeMarker()) {
      Column() {}
        .width(14)
        .height(14)
        .borderRadius(7)
        .backgroundColor('#4089FF')
        .border({ width: 2, color: '#FFFFFF' })
        .position(this.overviewCurrentNodeMarkerPos())
        .zIndex(9)
    }
  }

  private hasOverviewCurrentNodeMarker(): boolean {
    return this.overviewCurrentNode() !== undefined
  }

  private overviewCurrentNode(): GridNode | undefined {
    const id: string = this.currentNodeBadgeId()
    if (id.length <= 0) return undefined
    return this.findGridNodeById(id)
  }

  private overviewCurrentNodeMarkerPos(): XYPos {
    const n: GridNode | undefined = this.overviewCurrentNode()
    if (!n) return { x: -9999, y: -9999 }
    return this.store.gridNodeDotPos(n, 14)
  }

  private currentNodeBadgeId(): string {
    return this.store.currentSnapNodeId.trim().toUpperCase()
  }

  private currentNodeBadgePos(): XYPos {
    const dot: XYPos = this.store.carDotPos()
    const size: number = this.store.carDotSize

    const bw: number = 34
    const bh: number = 18
    const centerX: number = dot.x + size / 2
    const centerY: number = dot.y + size / 2
    const oppositeDeg: number = (this.carArrowHeadingDeg() + 180) % 360
    const oppositeRad: number = oppositeDeg * Math.PI / 180
    const radius: number = size / 2 + 16

    let x: number = centerX + Math.cos(oppositeRad) * radius - bw / 2
    let y: number = centerY + Math.sin(oppositeRad) * radius - bh / 2

    const mw: number = this.store.mapW
    const mh: number = this.store.mapH

    if (x < 2) {
      x = 2
    }
    if (mw > 0 && x + bw > mw - 2) {
      x = mw - bw - 2
    }

    if (y < 2) y = 2
    if (mh > 0 && y + bh > mh - 2) {
      y = mh - bh - 2
    }

    return { x: x, y: y }
  }

  private syncCameraFollow(): void {
    if (!this.cameraFollowEnabled) {
      return
    }
    if (this.store.mapW <= 0 || this.store.mapH <= 0) {
      return
    }

    const now: number = Date.now()

    // 用户手动拖拽/缩放后的失权窗口内，不自动抢回镜头
    // 但当 AUTO_FOLLOW + speed!=0 时，仍然强制跟随
    if (!this.shouldForceFollowNow()) {
      if (now < this.manualOverrideUntilMs) {
        return
      }
    }

    const viewW: number = this.store.mapW
    const viewH: number = this.store.mapH
    const s: number = this.safeScale()

    const carPx: number = this.store.carX * viewW
    const carPy: number = this.store.carY * viewH

    const targetX: number = -((carPx - viewW / 2) * s)
    const targetY: number = -((carPy - viewH / 2) * s)

    this.offsetX = this.clampOffsetX(targetX)
    this.offsetY = this.clampOffsetY(targetY)
  }

  private clampAll(): void {
    this.offsetX = this.clampOffsetX(this.offsetX)
    this.offsetY = this.clampOffsetY(this.offsetY)
  }

  private clampScale(v: number): number {
    if (v < 1.0) {
      return 1.0
    }
    if (v > 4.0) {
      return 4.0
    }
    return v
  }

  private clampOffsetX(v: number): number {
    const viewW: number = this.store.mapW
    const viewH: number = this.store.mapH
    if (viewW <= 0 || viewH <= 0) {
      return 0
    }

    const s: number = this.safeScale()
    if (s <= 1.000) {
      return 0
    }

    const minX: number = (1 - s) * viewW / 2
    const maxX: number = (s - 1) * viewW / 2
    if (v < minX) {
      return minX
    }
    if (v > maxX) {
      return maxX
    }
    return v
  }

  private clampOffsetY(v: number): number {
    const viewW: number = this.store.mapW
    const viewH: number = this.store.mapH
    if (viewW <= 0 || viewH <= 0) {
      return 0
    }

    const s: number = this.safeScale()
    if (s <= 1.000) {
      return 0
    }

    const minY: number = (1 - s) * viewH / 2
    const maxY: number = (s - 1) * viewH / 2
    if (v < minY) {
      return minY
    }
    if (v > maxY) {
      return maxY
    }
    return v
  }

  private screenToMapX(x: number): number {
    const viewW: number = this.store.mapW
    const s: number = this.safeScale()
    return ((x - this.offsetX - viewW / 2) / s) + (viewW / 2)
  }

  private screenToMapY(y: number): number {
    const viewH: number = this.store.mapH
    const s: number = this.safeScale()
    return ((y - this.offsetY - viewH / 2) / s) + (viewH / 2)
  }

  private mapToScreenX(worldX: number): number {
    const viewW: number = this.store.mapW
    const s: number = this.safeScale()
    return ((worldX - viewW / 2) * s) + viewW / 2 + this.offsetX
  }

  private mapToScreenY(worldY: number): number {
    const viewH: number = this.store.mapH
    const s: number = this.safeScale()
    return ((worldY - viewH / 2) * s) + viewH / 2 + this.offsetY
  }

  private isWorldRectVisible(x: number, y: number, w: number, h: number, margin: number = 0): boolean {
    const sx0: number = this.mapToScreenX(x)
    const sy0: number = this.mapToScreenY(y)
    const sx1: number = this.mapToScreenX(x + w)
    const sy1: number = this.mapToScreenY(y + h)
    const left: number = Math.min(sx0, sx1)
    const right: number = Math.max(sx0, sx1)
    const top: number = Math.min(sy0, sy1)
    const bottom: number = Math.max(sy0, sy1)
    return !(right < -margin || left > this.store.mapW + margin || bottom < -margin || top > this.store.mapH + margin)
  }

  private isWorldPointVisible(x: number, y: number, margin: number = 0): boolean {
    const sx: number = this.mapToScreenX(x)
    const sy: number = this.mapToScreenY(y)
    return !(sx < -margin || sx > this.store.mapW + margin || sy < -margin || sy > this.store.mapH + margin)
  }

  @Builder
  private buildProceduralMapBase(): void {
    Stack() {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor(this.isOverviewLevel() ? '#061220' : '#081624')

      if (this.isOverviewLevel()) {
        // OVERVIEW 只保留暗底，不绘制网格。
      } else {
        if (this.isDetailLevel()) {
          this.buildRoadRects(this.detailGridRoadRects(this.greenBeltThickness() * 1.25), this.greenBeltColor())
          this.buildRoadRects(this.detailGridRoadRects(this.mainRoadThickness() * 1.05), this.mainRoadColor())
          this.buildRoadBlockCells()
        } else {
          this.buildRoadRects(this.roadRectsForThickness(this.greenBeltThickness()), this.greenBeltColor())
          this.buildRoadRects(this.roadRectsForThickness(this.mainRoadThickness()), this.mainRoadColor())
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildOverviewReferenceGridBase(): void {
    this.buildRoadRects(this.overviewExactLaneFillRects(), this.mainRoadColor(), false)
    this.buildRoadRects(this.overviewExactBlueRects(), this.mainRoadColor(), false)
    this.buildRoadRects(this.overviewExactGreenRectsNoCross(), this.greenBeltColor(), false)
  }

  @Builder
  private buildRoadRects(rects: Array<MapRoadRect>, color: string, rounded: boolean = true): void {
    ForEach(rects, (r: MapRoadRect): void => {
      Column() {}
        .width(r.w)
        .height(r.h)
        .borderRadius(rounded ? Math.min(r.w, r.h) / 2 : 0)
        .backgroundColor(color)
        .position({ x: r.x, y: r.y })
        .zIndex(1)
    }, (r: MapRoadRect): string => r.id)
  }

  private greenBeltColor(): string {
    return this.isDetailLevel() ? '#12324B' : '#163A56'
  }

  private mainRoadColor(): string {
    return this.isDetailLevel() ? '#0E2940' : '#113451'
  }

  private greenBeltThickness(): number {
    const base: number = Math.min(this.store.mapW, this.store.mapH)
    if (base <= 0) return 32
    const v: number = base * 0.072
    if (v < 26) return 26
    if (v > 42) return 42
    return v
  }

  private mainRoadThickness(): number {
    const base: number = Math.min(this.store.mapW, this.store.mapH)
    if (base <= 0) return 22
    const v: number = base * 0.048
    if (v < 16) return 16
    if (v > 28) return 28
    return v
  }

  private overviewGuideThickness(): number {
    const base: number = Math.min(this.store.mapW, this.store.mapH)
    if (base <= 0) return 3
    const v: number = base * 0.0046
    if (v < 2.5) return 2.5
    if (v > 4.5) return 4.5
    return v
  }

  private overviewGuideX(): Array<number> {
    const out: Array<number> = []
    // 严格按参考图：最小缩放仅三条纵线（对应 B / D / F）
    const raw: Array<number> = [0.188, 0.505, 0.813]
    for (let i: number = 0; i < raw.length; i++) {
      out.push(raw[i] * this.store.mapW)
    }
    return out
  }

  private overviewGuideY(): Array<number> {
    const out: Array<number> = []
    const raw: Array<number> = [0.094, 0.258, 0.507, 0.754, 0.917]
    for (let i: number = 0; i < raw.length; i++) {
      out.push(raw[i] * this.store.mapH)
    }
    return out
  }

  private overviewGuideVerticalRects(xs: Array<number>, ys: Array<number>, thickness: number): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    if (ys.length <= 0) return out
    const top: number = ys[0] - thickness / 2
    const bottom: number = ys[ys.length - 1] + thickness / 2
    const h: number = Math.max(0, bottom - top)
    for (let i: number = 0; i < xs.length; i++) {
      const x: number = xs[i] - thickness / 2
      out.push({ id: `ov-v-${i}`, x: x, y: top, w: thickness, h: h })
    }
    return out
  }

  private overviewGuideHorizontalRects(ys: Array<number>, thickness: number): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    const w: number = this.store.mapW
    for (let i: number = 0; i < ys.length; i++) {
      const y: number = ys[i] - thickness / 2
      out.push({ id: `ov-h-${i}`, x: 0, y: y, w: w, h: thickness })
    }
    return out
  }

  private overviewVerticalGuideRects(): Array<MapRoadRect> {
    const guideThickness: number = this.overviewGuideThickness()
    const guidesX: Array<number> = this.overviewGuideX()
    const guidesY: Array<number> = this.overviewGuideY()
    return this.overviewGuideVerticalRects(guidesX, guidesY, guideThickness)
  }

  private overviewHorizontalGuideRects(): Array<MapRoadRect> {
    const guideThickness: number = this.overviewGuideThickness()
    const guidesY: Array<number> = this.overviewGuideY()
    return this.overviewGuideHorizontalRects(guidesY, guideThickness)
  }

  private overviewRoadCellRects(): Array<MapRoadRect> {
    const guideThickness: number = this.overviewGuideThickness()
    const guidesX: Array<number> = this.overviewGuideX()
    const guidesY: Array<number> = this.overviewGuideY()
    return this.overviewCellRects(guidesX, guidesY, guideThickness, true)
  }

  private overviewLandCellRects(): Array<MapRoadRect> {
    const guideThickness: number = this.overviewGuideThickness()
    const guidesX: Array<number> = this.overviewGuideX()
    const guidesY: Array<number> = this.overviewGuideY()
    return this.overviewCellRects(guidesX, guidesY, guideThickness, false)
  }

  private overviewCellRects(xs: Array<number>, ys: Array<number>, guideThickness: number, road: boolean): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    if (xs.length < 1 || ys.length < 2) return out

    const pad: number = Math.max(2, guideThickness * 1.4)
    const colBounds: Array<number> = [0]
    for (let i: number = 0; i < xs.length; i++) colBounds.push(xs[i])
    colBounds.push(this.store.mapW)

    for (let r: number = 0; r < ys.length - 1; r++) {
      for (let c: number = 0; c < colBounds.length - 1; c++) {
        const isRoad: boolean = this.overviewRoadCellEnabled(r, c)
        if (isRoad !== road) continue

        const left: number = colBounds[c] + pad
        const top: number = ys[r] + pad
        const width: number = (colBounds[c + 1] - colBounds[c]) - pad * 2
        const height: number = (ys[r + 1] - ys[r]) - pad * 2
        if (width <= 0 || height <= 0) continue
        out.push({
          id: `ov-cell-${r}-${c}-${road ? 'road' : 'land'}`,
          x: left,
          y: top,
          w: width,
          h: height
        })
      }
    }
    return out
  }

  private overviewRoadCellEnabled(row: number, col: number): boolean {
    const mask: Array<Array<number>> = [
      [0, 0, 1, 0],
      [0, 1, 0, 1],
      [1, 0, 1, 0],
      [1, 1, 0, 1]
    ]
    if (row >= 0 && row < mask.length && col >= 0 && col < mask[row].length) {
      return mask[row][col] === 1
    }
    return (row + col) % 2 === 0
  }

  private refX(px: number): number {
    const canvas = this.overviewCanvasRect()
    return canvas.x + px / 1024.0 * canvas.size
  }

  private refY(py: number): number {
    const canvas = this.overviewCanvasRect()
    return canvas.y + py / 1024.0 * canvas.size
  }

  private overviewCanvasRect(): { x: number, y: number, size: number } {
    const w: number = this.store.mapW
    const h: number = this.store.mapH
    if (w <= 0 || h <= 0) {
      return { x: 0, y: 0, size: 0 }
    }
    const size: number = Math.min(w, h)
    const x: number = (w - size) / 2
    const y: number = (h - size) / 2
    return { x: x, y: y, size: size }
  }

  private overviewExactLaneFillRects(): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    const verticalLaneFills: Array<{ x: number, w: number, y: number, h: number }> = [
      { x: 195, w: 11, y: 81, h: 859 },
      { x: 510, w: 11, y: 81, h: 859 },
      { x: 826, w: 10, y: 81, h: 859 }
    ]
    for (let i: number = 0; i < verticalLaneFills.length; i++) {
      const v = verticalLaneFills[i]
      out.push({
        id: `ovx-lane-v-${i}`,
        x: this.refX(v.x),
        y: this.refY(v.y),
        w: this.refX(v.x + v.w) - this.refX(v.x),
        h: this.refY(v.y + v.h) - this.refY(v.y)
      })
    }

    const horizontalLaneFills: Array<{ y: number, h: number, x: number, w: number }> = [
      { y: 85, h: 11, x: 0, w: 1024 },
      { y: 251, h: 12, x: 0, w: 1024 },
      { y: 505, h: 11, x: 0, w: 1024 },
      { y: 757, h: 11, x: 0, w: 1024 },
      { y: 923, h: 13, x: 0, w: 1024 }
    ]
    for (let i: number = 0; i < horizontalLaneFills.length; i++) {
      const h = horizontalLaneFills[i]
      out.push({
        id: `ovx-lane-h-${i}`,
        x: this.refX(h.x),
        y: this.refY(h.y),
        w: this.refX(h.x + h.w) - this.refX(h.x),
        h: this.refY(h.y + h.h) - this.refY(h.y)
      })
    }
    return out
  }

  private overviewExactGreenRectsNoCross(): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    // 竖向绿线分段绘制，避开横向双线带，避免“绿线交叉”
    const verticals: Array<{ x: number, w: number }> = [
      { x: 190, w: 5 }, { x: 206, w: 5 },
      { x: 505, w: 5 }, { x: 521, w: 5 },
      { x: 822, w: 4 }, { x: 836, w: 5 }
    ]
    const vSegY: Array<{ y: number, h: number }> = [
      { y: 101, h: 146 }, { y: 267, h: 234 },
      { y: 521, h: 232 }, { y: 772, h: 147 }
    ]
    for (let i: number = 0; i < verticals.length; i++) {
      for (let j: number = 0; j < vSegY.length; j++) {
        const v = verticals[i]
        const s = vSegY[j]
        out.push({
          id: `ovx-v-${i}-${j}`,
          x: this.refX(v.x),
          y: this.refY(s.y),
          w: this.refX(v.x + v.w) - this.refX(v.x),
          h: this.refY(s.y + s.h) - this.refY(s.y)
        })
      }
    }

    // 横向绿线分段绘制，避开竖向双线带
    const horizontals: Array<{ y: number, h: number }> = [
      { y: 81, h: 4 }, { y: 96, h: 5 },
      { y: 247, h: 4 }, { y: 263, h: 4 },
      { y: 501, h: 4 }, { y: 516, h: 5 },
      { y: 753, h: 4 }, { y: 768, h: 4 },
      { y: 919, h: 4 }, { y: 936, h: 4 }
    ]
    const hSegX: Array<{ x: number, w: number }> = [
      { x: 0, w: 190 }, { x: 211, w: 294 },
      { x: 526, w: 296 }, { x: 841, w: 183 }
    ]
    for (let i: number = 0; i < horizontals.length; i++) {
      for (let j: number = 0; j < hSegX.length; j++) {
        const h = horizontals[i]
        const s = hSegX[j]
        out.push({
          id: `ovx-h-${i}-${j}`,
          x: this.refX(s.x),
          y: this.refY(h.y),
          w: this.refX(s.x + s.w) - this.refX(s.x),
          h: this.refY(h.y + h.h) - this.refY(h.y)
        })
      }
    }
    return out
  }

  private overviewExactBlueRects(): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    // 参考图4x4分块（列边界按双线间隔后区域）
    const cols: Array<{ x: number, w: number }> = [
      { x: 0, w: 190 },
      { x: 211, w: 294 },
      { x: 526, w: 296 },
      { x: 841, w: 183 }
    ]
    const rows: Array<{ y: number, h: number }> = [
      { y: 101, h: 146 },
      { y: 267, h: 234 },
      { y: 521, h: 232 },
      { y: 772, h: 147 }
    ]
    // 与参考图一致的蓝块分布
    const mask: Array<Array<number>> = [
      [0, 0, 1, 1],
      [0, 1, 0, 1],
      [1, 0, 1, 0],
      [1, 1, 0, 1]
    ]
    for (let r: number = 0; r < rows.length; r++) {
      for (let c: number = 0; c < cols.length; c++) {
        if (mask[r][c] !== 1) continue
        const cellX: number = cols[c].x
        const cellY: number = rows[r].y
        const cellW: number = cols[c].w
        const cellH: number = rows[r].h
        out.push({
          id: `ovx-cell-${r}-${c}`,
          x: this.refX(cellX),
          y: this.refY(cellY),
          w: this.refX(cellX + cellW) - this.refX(cellX),
          h: this.refY(cellY + cellH) - this.refY(cellY)
        })
      }
    }
    return out
  }

  private roadRectsForThickness(thickness: number): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    const edges = PathPlannerAStar.routeEdges()
    for (let i: number = 0; i < edges.length; i++) {
      const seg = edges[i]
      const a: GridNode | undefined = this.findGridNodeById(seg.a)
      const b: GridNode | undefined = this.findGridNodeById(seg.b)
      if (!a || !b) continue

      const ax: number = a.xNorm * this.store.mapW
      const ay: number = a.yNorm * this.store.mapH
      const bx: number = b.xNorm * this.store.mapW
      const by: number = b.yNorm * this.store.mapH
      const dx: number = Math.abs(bx - ax)
      const dy: number = Math.abs(by - ay)
      const key: string = RouteEdgeCodec.fromSegment(seg)

      if (dx >= dy) {
        const x: number = Math.min(ax, bx) - thickness / 2
        const y: number = (ay + by) / 2 - thickness / 2
        const w: number = dx + thickness
        const h: number = thickness
        out.push({ id: `${key}-h-${thickness}`, x: x, y: y, w: w, h: h })
      } else {
        const x: number = (ax + bx) / 2 - thickness / 2
        const y: number = Math.min(ay, by) - thickness / 2
        const w: number = thickness
        const h: number = dy + thickness
        out.push({ id: `${key}-v-${thickness}`, x: x, y: y, w: w, h: h })
      }
    }
    return out
  }

  private gridAxisX(): Array<number> {
    const out: Array<number> = []
    const seen: Map<string, boolean> = new Map<string, boolean>()
    for (let i: number = 0; i < this.store.gridNodes.length; i++) {
      const x: number = this.store.gridNodes[i].xNorm * this.store.mapW
      const key: string = `${Math.round(x)}`
      if (seen.get(key) === true) continue
      seen.set(key, true)
      out.push(x)
    }
    out.sort((a: number, b: number): number => a - b)
    return out
  }

  private gridAxisY(): Array<number> {
    const out: Array<number> = []
    const seen: Map<string, boolean> = new Map<string, boolean>()
    for (let i: number = 0; i < this.store.gridNodes.length; i++) {
      const y: number = this.store.gridNodes[i].yNorm * this.store.mapH
      const key: string = `${Math.round(y)}`
      if (seen.get(key) === true) continue
      seen.set(key, true)
      out.push(y)
    }
    out.sort((a: number, b: number): number => a - b)
    return out
  }

  private detailGridRoadRects(thickness: number): Array<MapRoadRect> {
    const out: Array<MapRoadRect> = []
    const xs: Array<number> = this.gridAxisX()
    const ys: Array<number> = this.gridAxisY()

    for (let i: number = 0; i < xs.length; i++) {
      out.push({
        id: `detail-v-${i}-${thickness}`,
        x: xs[i] - thickness / 2,
        y: 0,
        w: thickness,
        h: this.store.mapH
      })
    }
    for (let i: number = 0; i < ys.length; i++) {
      out.push({
        id: `detail-h-${i}-${thickness}`,
        x: 0,
        y: ys[i] - thickness / 2,
        w: this.store.mapW,
        h: thickness
      })
    }
    return out
  }

  private detailBlockCellRects(): Array<MapBlockCellRect> {
    const out: Array<MapBlockCellRect> = []
    if (!this.isDetailLevel()) return out
    const xs: Array<number> = this.gridAxisX()
    const ys: Array<number> = this.gridAxisY()
    const insetFactor: number = 0.20

    for (let r: number = 0; r + 1 < ys.length; r++) {
      for (let c: number = 0; c + 1 < xs.length; c++) {
        const cellW: number = xs[c + 1] - xs[c]
        const cellH: number = ys[r + 1] - ys[r]
        if (cellW <= 0 || cellH <= 0) continue
        const inset: number = Math.min(cellW, cellH) * insetFactor
        const x: number = xs[c] + inset
        const y: number = ys[r] + inset
        const w: number = cellW - inset * 2
        const h: number = cellH - inset * 2
        if (w <= 0 || h <= 0) continue
        if (!this.isWorldRectVisible(x, y, w, h, 42)) continue
        out.push({
          id: `detail-cell-${r}-${c}`,
          x: x,
          y: y,
          w: w,
          h: h,
          color: ((r + c) % 2 === 0) ? '#0A1F31' : '#0B2439'
        })
      }
    }
    return out
  }

  @Builder
  private buildRoadBlockCells(): void {
    ForEach(this.detailBlockCellRects(), (cell: MapBlockCellRect): void => {
        Column() {}
          .width(cell.w)
          .height(cell.h)
          .borderRadius(Math.min(cell.w, cell.h) * 0.18)
          .backgroundColor(cell.color)
          .border({ width: 1, color: '#1A496A55' })
          .position({ x: cell.x, y: cell.y })
          .zIndex(1)
    }, (cell: MapBlockCellRect): string => cell.id)
  }

  private safeScale(): number {
    if (this.zoomScale <= 0.001) {
      return 0.001
    }
    return this.zoomScale
  }

  private gridDotSize(): number {
    if (this.isDetailLevel()) return 12
    return 10
  }

  private detailLevel(): MapDetailLevel {
    if (this.zoomScale < 1.2) return 'OVERVIEW'
    if (this.zoomScale < 2.2) return 'ROUTE'
    return 'DETAIL'
  }

  private isOverviewLevel(): boolean {
    return this.detailLevel() === 'OVERVIEW'
  }

  private isRouteLevel(): boolean {
    return this.detailLevel() === 'ROUTE'
  }

  private isDetailLevel(): boolean {
    return this.detailLevel() === 'DETAIL'
  }

  private shouldShowGridNode(id: string): boolean {
    if (this.isDetailLevel()) return true
    if (this.isRouteLevel()) return true
    return false
  }

  private shouldShowNodeLabel(id: string): boolean {
    if (this.isDetailLevel()) return true
    if (this.isRouteLevel()) return this.isPathCurrent(id) || this.isPathNext(id) || this.isCurrentNode(id)
    return false
  }

  private nodeLabelFontSize(): number {
    if (this.isDetailLevel()) return 10
    return 9
  }

  private isCurrentNode(id: string): boolean {
    const cur: string = this.store.currentSnapNodeId.trim().toUpperCase()
    if (cur.length === 0) {
      return false
    }
    return cur === id.toUpperCase()
  }

  private isBlockedNode(id: string): boolean {
    return this.store.isBlocked(id)
  }

  private nodeDotBg(id: string): string {
    if (this.isBlockedNode(id)) return '#FF5C5C66'
    if (this.isPathCurrent(id)) {
      return '#27B8FF'
    }
    if (this.isPathNext(id)) {
      return '#FFD166'
    }
    if (this.isPathVisited(id)) {
      return '#245A7C'
    }
    if (this.isPathFuture(id)) {
      return '#1D7CBF66'
    }
    if (this.isCurrentNode(id)) {
      return '#27B8FF'
    }
    return '#28597A66'
  }

  private nodeLabelColor(id: string): string {
    if (this.isBlockedNode(id)) return '#FF9E9E'
    if (this.isPathCurrent(id)) {
      return '#73D7FF'
    }
    if (this.isPathNext(id)) {
      return '#FFD166'
    }
    if (this.isPathVisited(id)) {
      return '#86AEC8'
    }
    if (this.isPathFuture(id)) {
      return '#5FC7FF'
    }
    if (this.isCurrentNode(id)) {
      return '#73D7FF'
    }
    return '#86AEC8'
  }

  private nodeLabelWeight(id: string): FontWeight {
    if (this.isBlockedNode(id)) {
      return FontWeight.Bold
    }
    if (this.isPathCurrent(id) || this.isPathNext(id)) {
      return FontWeight.Bold
    }
    if (this.isCurrentNode(id)) {
      return FontWeight.Bold
    }
    return FontWeight.Normal
  }

  private editBtnText(): string {
    return this.store.obstacleEditEnabled ? '障碍编辑：开' : '障碍编辑：关'
  }

  private editBtnBg(): string {
    if (this.store.obstacleEditEnabled) {
      return '#FF9500'
    }
    return '#EDEFF2'
  }

  private editBtnFg(): string {
    if (this.store.obstacleEditEnabled) {
      return '#FFFFFF'
    }
    return '#333333'
  }

  private poseBtnText(): string {
    return this.store.poseFollowEnabled ? '姿态跟随：开' : '姿态跟随：关'
  }

  private poseBtnBg(): string {
    if (this.store.poseFollowEnabled) {
      return '#34C759'
    }
    return '#EDEFF2'
  }

  private poseBtnFg(): string {
    if (this.store.poseFollowEnabled) {
      return '#FFFFFF'
    }
    return '#333333'
  }

  private cameraBtnText(): string {
    return this.cameraFollowEnabled ? '镜头跟随：开' : '镜头跟随：关'
  }

  private cameraBtnBg(): string {
    if (this.cameraFollowEnabled) {
      return '#1677FF'
    }
    return '#EDEFF2'
  }

  private cameraBtnFg(): string {
    if (this.cameraFollowEnabled) {
      return '#FFFFFF'
    }
    return '#333333'
  }

  private lengthToNumber(v: Length): number {
    if (typeof v === 'number') {
      return v
    }
    if (typeof v === 'string') {
      const n: number = Number.parseFloat(v)
      return Number.isFinite(n) ? n : 0
    }
    return 0
  }
}
