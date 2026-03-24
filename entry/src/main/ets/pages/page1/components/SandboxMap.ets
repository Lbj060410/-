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

@Component
export struct SandboxMap {
  @State private store: Page1UiStore = page1Store
  fullHeightMap: boolean = false

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

      // 地图底图 + 网格点位 + 小车/朝向/当前节点覆盖层
      Stack() {
        Stack() {
          Image($rawfile('sandbox_map.png'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)

          this.buildGridOverlay()
          this.buildBlockedNodeMarkers()
          this.buildRouteObstaclePointMarkers()
          this.buildBlockedEdgeMarkers()
          this.buildDestinationMarker()
          this.buildCarDot()
          this.buildCarHeadingArrow()
          this.buildCurrentNodeBadge()
        }
        .width('100%')
        .height('100%')
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.offsetX, y: this.offsetY })
      }
      .width('100%')
      .height(this.fullHeightMap ? '100%' : 420)
      .borderRadius(Page1Theme.RADIUS_XL)
      .clip(true)
      .backgroundColor('#DDE6F5')
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
    ForEach(this.store.gridNodes, (n: GridNode): void => {
      if (!this.isCurrentNode(n.id)) {
        Column() {}
        .width(this.gridDotSize())
        .height(this.gridDotSize())
        .borderRadius(this.gridDotSize() / 2)
        .backgroundColor(this.nodeDotBg(n.id))
        .position(this.store.gridNodeDotPos(n, this.gridDotSize()))
        .zIndex(2)

        Text(n.id)
          .fontSize(10)
          .fontColor(this.nodeLabelColor(n.id))
          .fontWeight(this.nodeLabelWeight(n.id))
          .position(this.store.gridNodeLabelPos(n))
          .zIndex(2)
      }
    }, (n: GridNode): string => n.id)
  }

  @Builder
  private buildRouteObstaclePointMarkers(): void {
    ForEach(this.store.routeObstaclePoints, (p: RouteObstaclePoint): void => {
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
    ForEach(this.store.blockedEdges, (edgeId: string): void => {
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
    ForEach(this.store.gridNodes, (n: GridNode): void => {
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
    .backgroundColor('#FF3B30')
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

  private safeScale(): number {
    if (this.zoomScale <= 0.001) {
      return 0.001
    }
    return this.zoomScale
  }

  private gridDotSize(): number {
    return 10
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
    if (this.isBlockedNode(id)) return '#00000025'
    if (this.isPathCurrent(id)) {
      return '#1677FF'
    }
    if (this.isPathNext(id)) {
      return '#FF9500'
    }
    if (this.isPathVisited(id)) {
      return '#00000040'
    }
    if (this.isPathFuture(id)) {
      return '#1677FF40'
    }
    if (this.isCurrentNode(id)) {
      return '#1677FF'
    }
    return '#00000025'
  }

  private nodeLabelColor(id: string): string {
    if (this.isBlockedNode(id)) return '#00000070'
    if (this.isPathCurrent(id)) {
      return '#1677FF'
    }
    if (this.isPathNext(id)) {
      return '#FF9500'
    }
    if (this.isPathVisited(id)) {
      return '#00000070'
    }
    if (this.isPathFuture(id)) {
      return '#1677FF'
    }
    if (this.isCurrentNode(id)) {
      return '#1677FF'
    }
    return '#00000070'
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
