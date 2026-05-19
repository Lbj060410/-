/**
 * 代码指南：
 * 文件： pages/page1/components/SandboxMap.ets
 * 用途： 仅用于 Page1 页面的可视化组件（地图 / 状态 / 控件渲染）
 * 何时修改： 仅在需要修改视图样式、控件组件、纯展示类交互时编辑此文件
 * 相关文件： 页面状态数据来源于 app/Page1UiStore.ets，操作事件转发至 app/Page1Coordinator.ets
 */
// entry/src/main/ets/pages/page1/components/SandboxMap.ets

import { page1Store, Page1UiStore, XYPos, RouteObstaclePoint } from '../app/Page1UiStore'
import { page1Coordinator } from '../app/Page1Coordinator'
import { GridNode } from '../types/SandboxGridTypes'
import { Page1Theme } from '../Page1Theme'
import { RouteEdgeCodec, PathPlannerAStar } from '../app/PathPlannerAStar'
import hilog from '@ohos.hilog'

const BENGKUI_LOG_DOMAIN: number = 0xFF0B
const BENGKUI_LOG_TAG: string = 'bengkui'
const SHANTUI_LOG_DOMAIN: number = 0xFF0C
const SHANTUI_LOG_TAG: string = 'shantui'

type NodeBlockType = 'parking' | 'junction' | 'corridor'

interface RouteHighlightStyle {
  routeHighlight: {
    lineWidth: number
  }
  visual: {
    coreBorderColor: string
    flowColorA: string
    flowColorB: string
    flowBreathBase: number
    flowBreathAmp: number
    flowBreathSpeed: number
  }
}

const ROUTE_HIGHLIGHT_STYLE: RouteHighlightStyle = {
  routeHighlight: {
    lineWidth: 14
  },
  visual: {
    coreBorderColor: '#4a0087ff',
    flowColorA: '#ff00ff87',
    flowColorB: '#fff6719e',
    flowBreathBase: 0.75,
    flowBreathAmp: 0.25,
    flowBreathSpeed: 0.038
  }
}

interface NodeBlockRule {
  fullBlockThreshold: number
}

type MapDetailLevel = 'OVERVIEW' | 'ROUTE' | 'DETAIL'

interface RoutePolyPoint {
  x: number
  y: number
  s: number
}

@Component
export struct SandboxMap {
  @State private store: Page1UiStore = page1Store
  fullHeightMap: boolean = false
  private readonly routeHighlightStyle: RouteHighlightStyle = ROUTE_HIGHLIGHT_STYLE
  // 取消 Page1 分层式渲染显示：统一按单一细节层渲染。
  private readonly flatRenderModeEnabled: boolean = true

  private readonly DEFAULT_ROUTE_ZOOM: number = 1.5
  @State private zoomScale: number = 1.5
  @State private pinchStartZoomScale: number = 1.5

  @State private offsetX: number = 0
  @State private offsetY: number = 0
  @State private panStartX: number = 0
  @State private panStartY: number = 0

  @State private cameraFollowEnabled: boolean = true
  private followTimerId: number = -1
  private flowAnimTimerId: number = -1

  // 手动操作后的临时失权窗口
  @State private manualOverrideUntilMs: number = 0
  @State private routeAnimTick: number = 0
  private lastTishixianDebugSig: string = ''
  @State private directionPickerVisible: boolean = false
  @State private directionPickerCenterX: number = 0
  @State private directionPickerCenterY: number = 0
  @State private directionPickerNodeId: string = ''
  @State private directionPickerEdgeId: string = ''
  @State private directionPickerSelected: string = 'N'
  @State private directionPickerCloseTimerId: number = -1
  @State private directionPickerMode: 'CAR' | 'TRAFFIC' = 'CAR'

  // 手动操作后允许自动跟随恢复的等待时间（毫秒）
  private readonly MANUAL_OVERRIDE_MS: number = 2800

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
    this.logBengkui('SandboxMap.aboutToAppear')
    this.clampAll()
    this.syncCameraFollow()

    this.stopFollowTimer()
    this.followTimerId = setInterval((): void => {
      this.syncCameraFollow()
    }, this.FOLLOW_TICK_MS) as number

    // 流光重绘独立 60fps 循环，避免被 120ms 的跟随节拍拖慢
    if (this.flowAnimTimerId !== -1) clearInterval(this.flowAnimTimerId)
    this.flowAnimTimerId = setInterval((): void => {
      this.routeAnimTick = (this.routeAnimTick + 1) % 1000000
      this.drawCompleteStreamingRoute()
    }, 16) as number
  }

  aboutToDisappear(): void {
    this.logBengkui('SandboxMap.aboutToDisappear')
    this.stopFollowTimer()
  }

  private stopFollowTimer(): void {
    if (this.followTimerId !== -1) {
      clearInterval(this.followTimerId)
      this.followTimerId = -1
    }
    if (this.flowAnimTimerId !== -1) {
      clearInterval(this.flowAnimTimerId)
      this.flowAnimTimerId = -1
    }
  }

  private logBengkui(msg: string): void {
    hilog.info(BENGKUI_LOG_DOMAIN, BENGKUI_LOG_TAG, '%{public}s', msg)
  }

  private logShantui(msg: string): void {
    hilog.info(SHANTUI_LOG_DOMAIN, SHANTUI_LOG_TAG, '%{public}s', msg)
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
          // 仅使用代码绘制地图（不再使用历史图片底图）。
          this.buildParkingLotGrid()
          // 图层2：路线（地图上方）
          this.buildPlannedRouteHighlight()

          // 图层3：点位/障碍/目的地标志（路线上方）
          if (!this.isOverviewLevel()) {
            this.buildGridOverlay()
            this.buildTrafficLightMarkers()
            this.buildGateMarkers()
            this.buildSpecialRoadMarkers()
            this.buildGarageMarkers()
            this.buildWarehouseMarkers()
            this.buildBlockedNodeMarkers()
            this.buildRouteObstaclePointMarkers()
            this.buildBlockedEdgeMarkers()
            this.buildPlaceBindingBubbles()
          }
          this.buildDestinationMarker()

          // 图层4：小车相关（最上层）
          this.buildCarDot()
          if (this.isDetailLevel()) {
            this.buildCurrentNodeBadge()
          }
        }
        .width('100%')
        .height('100%')
        .scale({ x: this.zoomScale, y: this.zoomScale })
        .translate({ x: this.offsetX, y: this.offsetY })
        if (this.directionPickerVisible) {
          this.buildDirectionPicker()
        }
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
          const nodeId: string = this.store.nearestNodeIdByPixelForObstacle(x, y)
          if (nodeId.length > 0) {
            const wasBlockedNode: boolean = this.store.isBlocked(nodeId)
            this.store.toggleBlockedNode(nodeId)
            const nowBlockedNode: boolean = this.store.isBlocked(nodeId)
            if (!wasBlockedNode && nowBlockedNode) {
              void page1Coordinator.sendObstaclePointByMapClick(nodeId)
            }
            return
          }

          const edgeId: string = this.store.nearestEdgeIdByPixel(x, y).trim().toUpperCase()
          if (edgeId.length > 0) {
            const wasBlocked: boolean = this.store.isBlockedEdgeById(edgeId)
            this.store.toggleBlockedEdge(edgeId)
            const nowBlocked: boolean = this.store.isBlockedEdgeById(edgeId)
            if (!wasBlocked && nowBlocked) {
              const seg = RouteEdgeCodec.parse(edgeId)
              if (seg) {
                void page1Coordinator.sendObstacleEdgeByMapClick(seg.a, seg.b)
              }
            }
            return
          }
          return
        }

        if (this.store.trafficLightEditEnabled) {
          const edgeId: string = this.store.nearestEdgeIdByPixel(x, y).trim().toUpperCase()
          if (edgeId.length > 0) {
            this.openDirectionPickerForTrafficLightEdge(edgeId)
          }
          return
        }

        if (this.store.gateEditEnabled) {
          const edgeId: string = this.store.nearestEdgeIdByPixel(x, y).trim().toUpperCase()
          if (edgeId.length > 0) {
            this.store.upsertGatePoint(edgeId)
            void page1Coordinator.sendBarrierByMapEdge(edgeId)
            this.store.gateEditEnabled = false
          }
          return
        }

        if (this.store.specialRoadEditEnabled) {
          const edgeId: string = this.store.nearestEdgeIdByPixel(x, y).trim().toUpperCase()
          if (edgeId.length > 0) {
            this.store.upsertSpecialRoadPoint(edgeId)
            void page1Coordinator.sendSpecialSegmentByMapEdge(edgeId)
            this.store.specialRoadEditEnabled = false
          }
          return
        }

        if (this.store.garageEditEnabled) {
          const id: string = this.store.nearestNodeIdByPixel(x, y)
          if (id.length > 0) {
            this.store.upsertGaragePoint(id)
            void page1Coordinator.setGarageByMapNode(id)
            this.store.garageEditEnabled = false
          }
          return
        }

        if (this.store.warehouseEditEnabled) {
          const id: string = this.store.nearestNodeIdByPixel(x, y)
          if (id.length > 0) {
            this.store.upsertWarehousePoint(id)
            void page1Coordinator.setWarehouseByMapNode(id)
            this.store.warehouseEditEnabled = false
          }
          return
        }

        if (this.store.targetPickEnabled) {
          const id: string = this.store.nearestNodeIdByPixel(x, y)
          if (id.length > 0) {
            this.store.destDraft = id
            this.store.mapTargetPendingSend = true
            this.debugTishixian('pick', `goal=${id} pending=1`)
            this.store.pushLog(`目标点选：${id}，点击“目标”按钮确认发送`)
            this.store.targetPickEnabled = false
          }
          return
        }

        // 点选移动红点后立即跟随
        this.store.moveCarByClick(x, y)
        const snapId: string = this.store.currentSnapNodeId.trim().toUpperCase()
        if (snapId.length === 2) {
          this.openDirectionPicker(snapId)
        }
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

  // --- 逻辑处理部分 ---

  private openDirectionPicker(nodeId: string): void {
    const n: GridNode | undefined = this.store.gridNodes.find((x: GridNode): boolean => x.id === nodeId)
    if (!n) return
    this.directionPickerNodeId = nodeId
    // 这里的 CenterX/Y 仅用于放置 Picker 的位置
    this.directionPickerCenterX = n.xNorm * this.store.mapW
    this.directionPickerCenterY = n.yNorm * this.store.mapH
    this.directionPickerSelected = 'N'
    this.directionPickerMode = 'CAR'
    this.directionPickerVisible = true
    this.logShantui(`open picker node=${nodeId} center=(${this.directionPickerCenterX.toFixed(1)},${this.directionPickerCenterY.toFixed(1)})`)
  }

  private openDirectionPickerForTrafficLightEdge(edgeId: string): void {
    const pos = this.store.edgeMidPosById(edgeId)
    if (!pos) return
    this.directionPickerNodeId = ''
    this.directionPickerEdgeId = edgeId
    this.directionPickerCenterX = pos.x * this.store.mapW
    this.directionPickerCenterY = pos.y * this.store.mapH
    this.directionPickerSelected = 'N'
    this.directionPickerMode = 'TRAFFIC'
    this.directionPickerVisible = true
    this.logShantui(`open traffic picker edge=${edgeId}`)
  }

  private closeDirectionPicker(): void {
    this.clearDirectionPickerCloseTimer()
    this.logShantui(`close picker node=${this.directionPickerNodeId} selected=${this.directionPickerSelected}`)
    this.directionPickerVisible = false
    this.directionPickerNodeId = ''
    this.directionPickerEdgeId = ''
  }

  private clearDirectionPickerCloseTimer(): void {
    if (this.directionPickerCloseTimerId !== -1) {
      clearTimeout(this.directionPickerCloseTimerId)
      this.directionPickerCloseTimerId = -1
    }
  }

  /**
   * 核心修复：基于组件内部坐标判定扇区
   * lx, ly 为相对于 Picker 左上角的像素坐标
   */
  private selectDirectionByLocalPoint(lx: number, ly: number): string {
    const center = this.directionPickerSize() / 2 // 66
    const dx = lx - center
    const dy = ly - center

    // 点击中心极小范围（死区）不触发，防止误触
    if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return this.directionPickerSelected

    // 对角分割逻辑 (X形判断)
    if (dy <= -Math.abs(dx)) return 'N' // 上方扇区
    if (dy >= Math.abs(dx)) return 'S'  // 下方扇区
    if (dx >= Math.abs(dy)) return 'E'  // 右侧扇区
    return 'W'                         // 左侧扇区
  }

  private headingDegFromDir(dir: string): number {
    const d: string = (dir || 'N').trim().toUpperCase()
    if (d === 'E') return 0
    if (d === 'S') return 90
    if (d === 'W') return 180
    return 270 // N
  }

  private syncLocalHeadingByDir(dir: string): void {
    const nextHeadingDeg: number = this.headingDegFromDir(dir)
    this.store.setPose({
      ...this.store.pose,
      tsMs: Date.now(),
      headingDeg: nextHeadingDeg
    })
  }

  private onDirectionSectorClick(localX: number, localY: number): void {
    // 1. 获取点击方向
    const dir: string = this.selectDirectionByLocalPoint(localX, localY)
    this.logShantui(`sector click local=(${localX.toFixed(1)},${localY.toFixed(1)}) dir=${dir}`)
    this.directionPickerSelected = dir

    // 2. 仅 CAR 模式同步小车朝向；TRAFFIC 模式只设置红绿灯方向，不改车头。
    if (this.directionPickerMode === 'CAR') {
      this.syncLocalHeadingByDir(dir)
      this.logShantui(`sync heading dir=${dir} headingDeg=${this.headingDegFromDir(dir)}`)
    }

    // 3. 延迟发送指令并关闭，增加用户确认感
    this.clearDirectionPickerCloseTimer()
    this.directionPickerCloseTimerId = setTimeout((): void => {
      const nodeId: string = this.directionPickerNodeId
      const edgeId: string = this.directionPickerEdgeId
      const finalDir: string = this.directionPickerSelected
      const mode: 'CAR' | 'TRAFFIC' = this.directionPickerMode
      this.logShantui(`picker commit node=${nodeId} dir=${finalDir}`)
      this.closeDirectionPicker()
      if (nodeId.length === 2) {
        if (mode === 'TRAFFIC') {
          const deg: number = this.headingDegFromDir(finalDir)
          if (edgeId.length > 0) {
            this.store.upsertTrafficLightPoint(edgeId, deg)
            void page1Coordinator.sendTrafficLightByMapEdge(edgeId, finalDir)
          }
          this.store.trafficLightEditEnabled = false
          return
        }
        this.logShantui(`sendCurrentNodeByMapClick node=${nodeId} dir=${finalDir}`)
        void page1Coordinator.sendCurrentNodeByMapClick(nodeId, finalDir)
      } else if (mode === 'TRAFFIC' && edgeId.length > 0) {
        const deg: number = this.headingDegFromDir(finalDir)
        this.store.upsertTrafficLightPoint(edgeId, deg)
        void page1Coordinator.sendTrafficLightByMapEdge(edgeId, finalDir)
        this.store.trafficLightEditEnabled = false
      }
    }, 200) as number
  }

  // --- UI 辅助部分 ---

  private directionPickerSize(): number { return 132 }
  private directionPickerPosX(): number { return this.directionPickerCenterX - this.directionPickerSize() / 2 }
  private directionPickerPosY(): number { return this.directionPickerCenterY - this.directionPickerSize() / 2 }

  /**
   * 获取高亮块的旋转角度
   */
  private getHighlightRotate(dir: string): number {
    if (dir === 'E') return 90
    if (dir === 'S') return 180
    if (dir === 'W') return 270
    return 0 // N
  }

  @Builder
  private buildDirectionPicker(): void {
    Stack() {
      // 1. 底盘：更通透的玻璃磨砂
      Column() {}
      .width(this.directionPickerSize())
      .height(this.directionPickerSize())
      .borderRadius(this.directionPickerSize() / 2)
      // 降低 alpha 到 0.15 (#26)，让背景地图更清晰地透过来
      .backgroundColor('#26FFFFFF')
      .backgroundBlurStyle(BlurStyle.Thin)
      .backdropBlur(50) // 增加模糊半径，提升高级感
      .shadow({ radius: 30, color: '#00000033', offsetX: 0, offsetY: 8 })

      // 2. 选中扇区：高度突出
      Column() {}
      .width(this.directionPickerSize())
      .height(this.directionPickerSize())
      .borderRadius(this.directionPickerSize() / 2)
      .sweepGradient({
        center: [this.directionPickerSize() / 2, this.directionPickerSize() / 2],
        start: 0,
        end: 90,
        // 使用更亮的渐变，从 0.6 降低到 0.2，产生边缘羽化的发光效果
        colors: [['#99FFFFFF', 0], ['#33FFFFFF', 1]]
      })
      .clip(true)
      // 旋转修正，让 90 度扇区完美对齐 N/E/S/W
      .rotate({ z: 1, angle: this.getHighlightRotate(this.directionPickerSelected) - 135 })
      .animation({ duration: 200, curve: Curve.FastOutSlowIn })
      // 扇区自带一层发光阴影，使其在视觉上“浮起来”
      .shadow({ radius: 20, color: '#40FFFFFF', offsetX: 0, offsetY: 0 })

      // 3. 装饰线：极细透明黑，仅作刻度参考
      Column().width(0.8).height(this.directionPickerSize() - 20).backgroundColor('#0D000000').rotate({ z: 1, angle: 45 })
      Column().width(0.8).height(this.directionPickerSize() - 20).backgroundColor('#0D000000').rotate({ z: 1, angle: -45 })

      // 4. 方向文字：对比度优化
      this.buildDirectionText('N', { x: '50%', y: 14 }, '50%', 0)
      this.buildDirectionText('E', { x: this.directionPickerSize() - 26, y: '50%' }, 0, '50%')
      this.buildDirectionText('S', { x: '50%', y: this.directionPickerSize() - 38 }, '50%', 0)
      this.buildDirectionText('W', { x: 14, y: '50%' }, 0, '50%')
    }
    .width(this.directionPickerSize())
    .height(this.directionPickerSize())
    // 增加一个微小的入场/切换动画
    .scale({ x: this.directionPickerVisible ? 1 : 0.8, y: this.directionPickerVisible ? 1 : 0.8 })
    .opacity(this.directionPickerVisible ? 1 : 0)
    .animation({ duration: 150 })
    .position({ x: this.directionPickerPosX(), y: this.directionPickerPosY() })
    .zIndex(99)
    .onClick((evt: ClickEvent) => {
      this.onDirectionSectorClick(evt.x, evt.y)
    })
  }

  @Builder
  private buildDirectionText(label: string, pos: Position, anchorX: string | number, anchorY: string | number) {
    Text(label)
      .fontSize(22) // 略微放大文字
      .fontWeight(FontWeight.Bolder)
        // 选中时使用亮蓝色（高对比度），未选中时使用深灰
      .fontColor(this.directionPickerSelected === label ? '#0052FF' : '#555555')
      .position(pos)
      .markAnchor({ x: anchorX, y: anchorY })
  }

  @Builder
  private buildTrafficLightMarkers(): void {
    ForEach(this.store.trafficLights, (p: any): void => {
      Image($rawfile('icon/红绿灯.png'))
        .width(this.mapPlacedMarkerSize())
        .height(this.mapPlacedMarkerSize())
        .objectFit(ImageFit.Contain)
        .position({ x: p.xNorm * this.store.mapW - this.mapPlacedMarkerSize() / 2, y: p.yNorm * this.store.mapH - this.mapPlacedMarkerSize() / 2 })
        .zIndex(6)
    }, (p: any): string => `traffic-${p.id}`)
  }

  @Builder
  private buildGateMarkers(): void {
    ForEach(this.store.gatePoints, (p: any): void => {
      Image($rawfile('icon/道闸.png'))
        .width(this.mapPlacedMarkerSize())
        .height(this.mapPlacedMarkerSize())
        .objectFit(ImageFit.Contain)
        .position({ x: p.xNorm * this.store.mapW - this.mapPlacedMarkerSize() / 2, y: p.yNorm * this.store.mapH - this.mapPlacedMarkerSize() / 2 })
        .zIndex(6)
    }, (p: any): string => `gate-${p.id}`)
  }

  @Builder
  private buildSpecialRoadMarkers(): void {
    ForEach(this.store.specialRoadPoints, (p: any): void => {
      Image($rawfile('icon/农作物.png'))
        .width(this.mapPlacedMarkerSize())
        .height(this.mapPlacedMarkerSize())
        .objectFit(ImageFit.Contain)
        .position({ x: p.xNorm * this.store.mapW - this.mapPlacedMarkerSize() / 2, y: p.yNorm * this.store.mapH - this.mapPlacedMarkerSize() / 2 })
        .zIndex(6)
    }, (p: any): string => `special-${p.id}`)
  }

  @Builder
  private buildGarageMarkers(): void {
    ForEach(this.store.garagePoints, (p: any): void => {
      Image($rawfile('icon/车库.png'))
        .width(this.mapPlacedMarkerSize())
        .height(this.mapPlacedMarkerSize())
        .objectFit(ImageFit.Contain)
        .position({ x: p.xNorm * this.store.mapW - this.mapPlacedMarkerSize() / 2, y: p.yNorm * this.store.mapH - this.mapPlacedMarkerSize() / 2 })
        .zIndex(6)
    }, (p: any): string => `garage-${p.id}`)
  }

  @Builder
  private buildWarehouseMarkers(): void {
    ForEach(this.store.warehousePoints, (p: any): void => {
      Image($rawfile('icon/仓储.png'))
        .width(this.mapPlacedMarkerSize())
        .height(this.mapPlacedMarkerSize())
        .objectFit(ImageFit.Contain)
        .position({ x: p.xNorm * this.store.mapW - this.mapPlacedMarkerSize() / 2, y: p.yNorm * this.store.mapH - this.mapPlacedMarkerSize() / 2 })
        .zIndex(6)
    }, (p: any): string => `warehouse-${p.id}`)
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
        Image($rawfile('icon/道路阻塞.png'))
          .width(this.blockedMarkerSize())
          .height(this.blockedMarkerSize())
          .objectFit(ImageFit.Contain)
          .position(this.routeObstaclePointPos(p))
          .zIndex(4)
      }
    }, (p: RouteObstaclePoint): string => p.id)
  }

  private routeObstaclePointPos(p: RouteObstaclePoint): XYPos {
    const x: number = p.xNorm * this.store.mapW - this.blockedMarkerSize() / 2
    const y: number = p.yNorm * this.store.mapH - this.blockedMarkerSize() / 2
    return { x: x, y: y }
  }

  @Builder
  private buildBlockedEdgeMarkers(): void {
    ForEach(this.visibleBlockedEdgesForRender(), (edgeId: string): void => {
      if (this.edgeMarkerVisible(edgeId)) {
        Image($rawfile('icon/道路阻塞.png'))
          .width(this.blockedMarkerSize())
          .height(this.blockedMarkerSize())
          .objectFit(ImageFit.Contain)
          .position(this.edgeMarkerPos(edgeId))
          .zIndex(3)
      }
    }, (edgeId: string): string => edgeId)
  }

  @Builder
  private buildPlaceBindingBubbles(): void {
    this.buildPlaceBubble('home', this.store.homePlaceNodeId, '物流中心')
    this.buildPlaceBubble('company', this.store.companyPlaceNodeId, '快递点')
  }

  @Builder
  private buildPlaceBubble(kind: 'home' | 'company', nodeId: string, text: string): void {
    if (this.shouldShowPlaceBubble(nodeId)) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 气泡主体
        Column() {
          Text(text)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        }
        .width(120)
        .backgroundColor(this.placeBubbleBg(kind))
        .borderRadius(12)
        .border({ width: 2, color: 'rgba(255,255,255,0.4)' })
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 4 })

        // 指向箭头（三角形）
        Polygon({ width: 20, height: 16 })
          .points([[10, 16], [0, 0], [20, 0]])
          .fill(this.placeBubbleBg(kind))
          .stroke(Color.Transparent)
          .position({ x: 50, y: 100 })
      }
      .width(120)
      .height(120)
      .position(this.placeBubblePosById(nodeId))
      .zIndex(9)
    }
  }

  private shouldShowPlaceBubble(nodeId: string): boolean {
    const node: GridNode | undefined = this.findGridNodeById(nodeId)
    if (!node) return false
    if (this.isDetailLevel() && !this.isWorldPointVisible(node.xNorm * this.store.mapW, node.yNorm * this.store.mapH, 64)) return false
    return true
  }

  private placeBubbleBg(kind: 'home' | 'company'): string {
    if (kind === 'home') return 'rgba(16, 185, 129, 0.94)'
    return 'rgba(59, 130, 246, 0.94)'
  }

  private placeBubblePosById(nodeId: string): XYPos {
    const node: GridNode | undefined = this.findGridNodeById(nodeId)
    if (!node) return { x: -9999, y: -9999 }
    return this.placeBubblePos(node)
  }

  private placeBubblePos(node: GridNode): XYPos {
    const centerX: number = node.xNorm * this.store.mapW
    const centerY: number = node.yNorm * this.store.mapH
    const bubbleWidth: number = 120
    const bubbleHeight: number = 120
    return {
      x: centerX - bubbleWidth / 2,
      y: centerY - bubbleHeight - 12
    }
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
    return { x: p.x - this.blockedMarkerSize() / 2, y: p.y - this.blockedMarkerSize() / 2 }
  }

  @Builder
  private buildBlockedNodeMarkers(): void {
    ForEach(this.visibleBlockedNodesForRender(), (n: GridNode): void => {
      if (this.shouldShowBlockedNodeMarker(n.id)) {
        Image(this.blockedNodeMarkerResource(n.id))
          .width(this.blockedMarkerSize())
          .height(this.blockedMarkerSize())
          .objectFit(ImageFit.Contain)
          .position(this.store.gridNodeDotPos(n, this.blockedMarkerSize()))
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
    if (this.shouldShowDestinationVisual()) {
      Column() {}
        .width(this.destinationOuterRingSize())
        .height(this.destinationOuterRingSize())
        .borderRadius(this.destinationOuterRingSize() / 2)
        .border({ width: 2.4, color: '#7CD7FF' })
        .backgroundColor('#0F58B2FF')
        .position(this.destinationOuterRingPos())
        .scale({ x: this.destinationOuterRingScale(), y: this.destinationOuterRingScale() })
        .opacity(this.destinationOuterRingOpacity())
        .shadow({ radius: 12, color: '#2A7BE7FF', offsetX: 0, offsetY: 0 })
        .zIndex(7)

      Column() {}
        .width(this.destinationInnerRingSize())
        .height(this.destinationInnerRingSize())
        .borderRadius(this.destinationInnerRingSize() / 2)
        .border({ width: 2.0, color: '#9CE6FF' })
        .backgroundColor('#1646A8FF')
        .position(this.destinationInnerRingPos())
        .scale({ x: this.destinationInnerRingScale(), y: this.destinationInnerRingScale() })
        .opacity(this.destinationInnerRingOpacity())
        .shadow({ radius: 10, color: '#307BDFFF', offsetX: 0, offsetY: 0 })
        .zIndex(8)

      Image($rawfile('icon/目的地.png'))
        .width(this.destinationMarkerSize())
        .height(this.destinationMarkerSize())
        .objectFit(ImageFit.Contain)
        .position(this.destinationMarkerAnimatedPos())
        .zIndex(9)
    }
  }

  private hasDestinationMarker(): boolean {
    return this.destinationMarkerNode() !== undefined
  }

  private shouldShowDestinationVisual(): boolean {
    const targetId: string = this.displayTargetNodeId()
    if (targetId.length <= 0) return false
    const applied: string = this.store.destApplied.trim().toUpperCase()
    if (targetId !== applied) return true
    return !this.hasArrivedAppliedDestination()
  }

  private hasArrivedAppliedDestination(): boolean {
    const applied: string = this.store.destApplied.trim().toUpperCase()
    if (applied.length <= 0) return false
    const current: string = this.store.currentSnapNodeId.trim().toUpperCase()
    if (current !== applied) return false
    if (this.store.pathNodes.length <= 0) return true
    const lastId: string = this.store.pathNodes[this.store.pathNodes.length - 1].trim().toUpperCase()
    if (lastId !== applied) return false
    return this.store.pathIndex >= (this.store.pathNodes.length - 1)
  }

  private destinationBreathPhase(): number {
    return (Math.sin(this.routeAnimTick * 0.09) + 1) / 2
  }

  private destinationRingFloatOffsetY(): number {
    return (0.5 - this.destinationBreathPhase()) * 4
  }

  private destinationIconFloatOffsetY(): number {
    return (0.5 - this.destinationBreathPhase()) * 8
  }

  private destinationOuterRingSize(): number {
    return this.destinationMarkerSize() + 30
  }

  private destinationInnerRingSize(): number {
    return this.destinationMarkerSize() + 14
  }

  private destinationOuterRingScale(): number {
    return 0.96 + 0.14 * this.destinationBreathPhase()
  }

  private destinationInnerRingScale(): number {
    return 0.98 + 0.10 * this.destinationBreathPhase()
  }

  private destinationOuterRingOpacity(): number {
    return 0.24 + 0.28 * this.destinationBreathPhase()
  }

  private destinationInnerRingOpacity(): number {
    return 0.32 + 0.34 * this.destinationBreathPhase()
  }

  private destinationNodeCenter(): XYPos {
    const node: GridNode | undefined = this.destinationMarkerNode()
    if (!node) return { x: -9999, y: -9999 }
    return { x: node.xNorm * this.store.mapW, y: node.yNorm * this.store.mapH }
  }

  private destinationOuterRingPos(): XYPos {
    const center: XYPos = this.destinationNodeCenter()
    const size: number = this.destinationOuterRingSize()
    return { x: center.x - size / 2, y: center.y - size / 2 + this.destinationRingFloatOffsetY() }
  }

  private destinationInnerRingPos(): XYPos {
    const center: XYPos = this.destinationNodeCenter()
    const size: number = this.destinationInnerRingSize()
    return { x: center.x - size / 2, y: center.y - size / 2 + this.destinationRingFloatOffsetY() }
  }

  private destinationMarkerAnimatedPos(): XYPos {
    const p: XYPos = this.destinationMarkerPos()
    return { x: p.x, y: p.y + this.destinationIconFloatOffsetY() }
  }

  private destinationMarkerPos(): XYPos {
    const node: GridNode | undefined = this.destinationMarkerNode()
    if (!node) return { x: -9999, y: -9999 }
    const size: number = this.destinationMarkerSize()
    const center: XYPos = this.store.gridNodeDotPos(node, size)
    // 让图片底端对齐点位：在居中位置基础上向上偏移半个高度
    return { x: center.x, y: center.y - size / 2 }
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
    if (pending.length > 0 && pending !== applied) return pending

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
    Image($rawfile('icon/小车.png'))
      .width(this.carIconSize())
      .height(this.carIconSize())
      .objectFit(ImageFit.Contain)
      .rotate({
        z: 1,
        angle: this.normHeadingDeg(this.store.pose.headingDeg) + 90,
        centerX: '50%',
        centerY: '50%'
      })
      .position(this.carIconPos())
      .zIndex(10)
  }

  private normHeadingDeg(v: number): number {
    let x: number = v % 360
    if (x < 0) {
      x += 360
    }
    return x
  }

  private carIconSize(): number {
    const min: number = Math.max(44, this.store.carDotSize + 22)
    if (min > 80) return 80
    return min
  }

  private carIconPos(): XYPos {
    const dot: XYPos = this.store.carDotPos()
    const dotSize: number = this.store.carDotSize
    const iconSize: number = this.carIconSize()
    const centerX: number = dot.x + dotSize / 2
    const centerY: number = dot.y + dotSize / 2
    return {
      x: centerX - iconSize / 2,
      y: centerY - iconSize / 2
    }
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
    return $rawfile('icon/道路阻塞.png')
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
    const oppositeDeg: number = (this.normHeadingDeg(this.store.pose.headingDeg) + 180) % 360
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

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings)

  @Builder
  private buildPlannedRouteHighlight(): void {
    // 🎨【Canvas 完整流光渲染】一次性绘制整条路线的连贯流光
    Canvas(this.canvasContext)
      .width('100%')
      .height('100%')
      .onReady((): void => {
        this.drawCompleteStreamingRoute()
      })
  }

  private drawCompleteStreamingRoute(): void {
    const ctx = this.canvasContext
    ctx.clearRect(0, 0, this.store.mapW, this.store.mapH)
    const nodes = this.activeHighlightNodes()
    if (nodes.length >= 2) {
      const pts: Array<RoutePolyPoint> = this.buildRoutePolyline(nodes)
      if (pts.length >= 2) {
        const thickness = this.routeHighlightThickness(this.routeHighlightStyle)

        // 1. 整条路径的底色轨道（科技蓝、低透明度）
        this.strokePolyline(ctx, pts, this.routeHighlightStyle.visual.coreBorderColor, thickness, 0.3)

        // 2. 流光跑马灯效果（虚线 + dashOffset 动画）
        this.drawDashedFlowLine(ctx, pts, thickness)
      }
    }
    this.drawPlacedMarkerFlowBorders(ctx)
  }

  private drawDashedFlowLine(ctx: CanvasRenderingContext2D, pts: Array<RoutePolyPoint>, thickness: number): void {
    const total: number = pts[pts.length - 1].s
    if (total <= 0) return

    const sweepLen: number = Math.max(50, total * 0.18)
    const speed: number = 5.0
    const streamerCount: number = 3
    const cycle: number = total + sweepLen

    const heads: Array<number> = []
    const baseHead: number = (this.routeAnimTick * speed) % cycle
    for (let k: number = 0; k < streamerCount; k++) {
      heads.push((baseHead + (cycle * k) / streamerCount) % cycle)
    }

    const step: number = 4
    const lineW: number = Math.max(2, thickness * 0.32)
    ctx.lineCap = 'butt'
    ctx.lineJoin = 'round'
    ctx.lineWidth = lineW
    const breathAlpha: number = this.routeFlowBreathAlpha()

    let prev: RoutePolyPoint = this.pointAtArcLength(pts, 0)
    for (let s: number = step; s <= total; s += step) {
      const cur: RoutePolyPoint = this.pointAtArcLength(pts, s)
      const mid: number = s - step / 2

      let bestAlpha: number = 0
      let bestHeadFactor: number = 0
      for (let k: number = 0; k < heads.length; k++) {
        const dist: number = heads[k] - mid
        if (dist < 0) continue
        if (dist > sweepLen) continue
        const f: number = 1 - dist / sweepLen
        const a: number = Math.pow(f, 2.0)
        if (a > bestAlpha) {
          bestAlpha = a
          bestHeadFactor = f
        }
      }
      if (bestAlpha <= 0.01) {
        prev = cur
        continue
      }

      // 关键修正：按“尾部蓝 -> 头部青”给每段流光上色，形成可见渐变尾迹。
      ctx.strokeStyle = this.routeFlowGradientColor(bestHeadFactor)
      ctx.globalAlpha = bestAlpha * breathAlpha
      ctx.beginPath()
      ctx.moveTo(prev.x, prev.y)
      ctx.lineTo(cur.x, cur.y)
      ctx.stroke()

      prev = cur
    }
    ctx.globalAlpha = 1
  }

  private routeFlowBreathPhase(): number {
    const base: number = this.routeAnimTick * this.routeHighlightStyle.visual.flowBreathSpeed
    return (Math.sin(base) + 1) / 2
  }

  private routeFlowBreathAlpha(): number {
    const b: number = this.routeHighlightStyle.visual.flowBreathBase
    const a: number = this.routeHighlightStyle.visual.flowBreathAmp
    const out: number = b + a * this.routeFlowBreathPhase()
    if (out < 0.08) return 0.08
    if (out > 1) return 1
    return out
  }

  private routeFlowBreathColor(): string {
    return this.mixHexColor(this.routeHighlightStyle.visual.flowColorA, this.routeHighlightStyle.visual.flowColorB, this.routeFlowBreathPhase())
  }

  private routeFlowGradientColor(headFactor: number): string {
    const h: number = headFactor < 0 ? 0 : (headFactor > 1 ? 1 : headFactor)
    const pulse: number = this.routeFlowBreathPhase()
    const t: number = h * 0.82 + pulse * 0.18
    // 尾部更蓝，头部更青亮
    return this.mixHexColor(this.routeHighlightStyle.visual.flowColorB, this.routeHighlightStyle.visual.flowColorA, t)
  }

  private mixHexColor(a: string, b: string, t: number): string {
    const aa = this.parseHexColor(a)
    const bb = this.parseHexColor(b)
    const p: number = t < 0 ? 0 : (t > 1 ? 1 : t)
    const r: number = Math.floor(aa.r + (bb.r - aa.r) * p)
    const g: number = Math.floor(aa.g + (bb.g - aa.g) * p)
    const bl: number = Math.floor(aa.b + (bb.b - aa.b) * p)
    return this.rgbToHex(r, g, bl)
  }

  private parseHexColor(hex: string): { r: number, g: number, b: number } {
    const raw: string = hex.trim().replace('#', '')
    if (raw.length === 6) {
      const r: number = Number.parseInt(raw.slice(0, 2), 16)
      const g: number = Number.parseInt(raw.slice(2, 4), 16)
      const b: number = Number.parseInt(raw.slice(4, 6), 16)
      return { r: r, g: g, b: b }
    }
    return { r: 0, g: 255, b: 204 }
  }

  private rgbToHex(r: number, g: number, b: number): string {
    const rr: string = this.byteToHex(r)
    const gg: string = this.byteToHex(g)
    const bb: string = this.byteToHex(b)
    return `#${rr}${gg}${bb}`
  }

  private byteToHex(v: number): string {
    const c: number = v < 0 ? 0 : (v > 255 ? 255 : v)
    const s: string = c.toString(16).toUpperCase()
    return s.length >= 2 ? s : `0${s}`
  }

  private pointAtArcLength(pts: Array<RoutePolyPoint>, s: number): RoutePolyPoint {
    if (s <= 0) return { x: pts[0].x, y: pts[0].y, s: 0 }
    const last: RoutePolyPoint = pts[pts.length - 1]
    if (s >= last.s) return { x: last.x, y: last.y, s: last.s }
    for (let i: number = 1; i < pts.length; i++) {
      const a: RoutePolyPoint = pts[i - 1]
      const b: RoutePolyPoint = pts[i]
      if (s <= b.s) {
        const segLen: number = b.s - a.s
        const t: number = segLen > 0 ? (s - a.s) / segLen : 0
        return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, s: s }
      }
    }
    return { x: last.x, y: last.y, s: last.s }
  }

  private buildRoutePolyline(nodes: Array<string>): Array<RoutePolyPoint> {
    const pts: Array<RoutePolyPoint> = []
    let acc: number = 0
    for (let i: number = 0; i < nodes.length; i++) {
      const n: GridNode | undefined = this.findGridNodeById(nodes[i])
      if (!n) continue
      const x: number = n.xNorm * this.store.mapW
      const y: number = n.yNorm * this.store.mapH
      if (pts.length > 0) {
        const prev = pts[pts.length - 1]
        acc += Math.hypot(x - prev.x, y - prev.y)
      }
      pts.push({ x: x, y: y, s: acc })
    }
    return pts
  }

  private strokePolyline(ctx: CanvasRenderingContext2D, pts: Array<RoutePolyPoint>, color: string, width: number, alpha: number): void {
    ctx.globalAlpha = alpha
    ctx.strokeStyle = color
    ctx.lineWidth = width
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    ctx.moveTo(pts[0].x, pts[0].y)
    for (let i: number = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i].x, pts[i].y)
    }
    ctx.stroke()
    ctx.globalAlpha = 1
  }

  private routeHighlightThickness(style: RouteHighlightStyle): number {
    const v: number = style.routeHighlight.lineWidth
    if (v <= 0) return 12
    return v
  }

  private activeHighlightNodes(): Array<string> {
    if (this.store.pathNodes.length >= 2) {
      return this.store.pathNodes
    }
    return []
  }

  private debugTishixian(stage: string, message: string): void {
    const sig: string = `${stage}|${message}`
    if (sig === this.lastTishixianDebugSig) return
    this.lastTishixianDebugSig = sig
    this.store.pushLog(`[tishixian] ${stage} ${message}`)
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
    if (this.flatRenderModeEnabled) return 'DETAIL'
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

  private markerFlowPhase(id: string): number {
    let hash: number = 0
    for (let i: number = 0; i < id.length; i++) {
      hash = (hash * 33 + id.charCodeAt(i)) % 1000
    }
    const seed: number = hash / 1000
    return this.routeAnimTick * 0.05 + seed * Math.PI * 2
  }

  private markerFlowBreath(id: string): number {
    const w: number = (Math.sin(this.markerFlowPhase(id)) + 1) / 2
    return 0.58 + 0.42 * w
  }

  private markerFlowRotateDeg(id: string): number {
    const phase: number = this.markerFlowPhase(id)
    const seedDeg: number = (phase * 180 / Math.PI) % 360
    const spinDeg: number = (this.routeAnimTick * 2.2) % 360
    return (seedDeg + spinDeg) % 360
  }

  private markerFlowBorderWidth(): number {
    return 2
  }

  private drawPlacedMarkerFlowBorders(ctx: CanvasRenderingContext2D): void {
    if (this.isOverviewLevel()) return
    for (let i: number = 0; i < this.store.trafficLights.length; i++) {
      const p: any = this.store.trafficLights[i]
      this.drawPlacedMarkerFlowBorder(ctx, p.xNorm, p.yNorm, `traffic-${p.id}`)
    }
    for (let i: number = 0; i < this.store.gatePoints.length; i++) {
      const p: any = this.store.gatePoints[i]
      this.drawPlacedMarkerFlowBorder(ctx, p.xNorm, p.yNorm, `gate-${p.id}`)
    }
    for (let i: number = 0; i < this.store.specialRoadPoints.length; i++) {
      const p: any = this.store.specialRoadPoints[i]
      this.drawPlacedMarkerFlowBorder(ctx, p.xNorm, p.yNorm, `special-${p.id}`)
    }
    for (let i: number = 0; i < this.store.garagePoints.length; i++) {
      const p: any = this.store.garagePoints[i]
      this.drawPlacedMarkerFlowBorder(ctx, p.xNorm, p.yNorm, `garage-${p.id}`)
    }
    for (let i: number = 0; i < this.store.warehousePoints.length; i++) {
      const p: any = this.store.warehousePoints[i]
      this.drawPlacedMarkerFlowBorder(ctx, p.xNorm, p.yNorm, `warehouse-${p.id}`)
    }

    for (let i: number = 0; i < this.store.routeObstaclePoints.length; i++) {
      const p: RouteObstaclePoint = this.store.routeObstaclePoints[i]
      if (this.edgeMarkerSuppressedByNodeBlock(p.edgeId)) continue
      this.drawPlacedMarkerFlowBorder(ctx, p.xNorm, p.yNorm, `obstacle-point-${p.id}`, this.blockedMarkerSize())
    }

    for (let i: number = 0; i < this.store.blockedEdges.length; i++) {
      const edgeId: string = this.store.blockedEdges[i]
      if (!this.edgeMarkerVisible(edgeId)) continue
      const pos: XYPos | undefined = this.store.blockedEdgeMidPos(edgeId)
      if (!pos) continue
      this.drawPlacedMarkerFlowBorderByCenter(ctx, pos.x, pos.y, `blocked-edge-${edgeId}`, this.blockedMarkerSize())
    }

    for (let i: number = 0; i < this.store.gridNodes.length; i++) {
      const n: GridNode = this.store.gridNodes[i]
      if (!this.shouldShowBlockedNodeMarker(n.id)) continue
      this.drawPlacedMarkerFlowBorder(ctx, n.xNorm, n.yNorm, `blocked-node-${n.id}`, this.blockedMarkerSize())
    }
  }

  private drawPlacedMarkerFlowBorder(ctx: CanvasRenderingContext2D, xNorm: number, yNorm: number, markerId: string, markerSize?: number): void {
    const centerX: number = xNorm * this.store.mapW
    const centerY: number = yNorm * this.store.mapH
    this.drawPlacedMarkerFlowBorderByCenter(ctx, centerX, centerY, markerId, markerSize)
  }

  private drawPlacedMarkerFlowBorderByCenter(
    ctx: CanvasRenderingContext2D,
    centerX: number,
    centerY: number,
    markerId: string,
    markerSize?: number
  ): void {
    const iconSize: number = markerSize && markerSize > 0 ? markerSize : this.mapPlacedMarkerSize()
    const size: number = iconSize + this.markerFlowBorderWidth() * 2
    const left: number = centerX - size / 2
    const top: number = centerY - size / 2
    if (!this.isWorldRectVisible(left, top, size, size, 40)) return

    const borderWidth: number = this.markerFlowBorderWidth()
    const breath: number = this.markerFlowBreath(markerId)
    const angle: number = this.markerFlowRotateDeg(markerId)
    const span: number = size * 1.8

    ctx.save()
    ctx.beginPath()
    ctx.rect(left, top, size, size)
    ctx.clip()

    // 黑色基础轨道（常亮）
    ctx.globalAlpha = 0.92
    ctx.lineWidth = borderWidth
    ctx.strokeStyle = '#101010'
    ctx.strokeRect(left + borderWidth / 2, top + borderWidth / 2, size - borderWidth, size - borderWidth)

    ctx.save()
    ctx.translate(centerX, centerY)
    ctx.rotate(angle * Math.PI / 180)
    const gradient = ctx.createLinearGradient(-span, -span, span, span)
    gradient.addColorStop(0.0, 'rgba(255,0,0,0)')
    gradient.addColorStop(0.42, 'rgba(255,0,0,0)')
    gradient.addColorStop(0.50, 'rgba(255,78,78,1.0)')
    gradient.addColorStop(0.58, 'rgba(255,0,0,0)')
    gradient.addColorStop(1.0, 'rgba(255,0,0,0)')
    ctx.globalAlpha = breath
    ctx.fillStyle = gradient
    ctx.fillRect(-span, -span, span * 2, span * 2)
    ctx.restore()

    // 镂空中心，仅保留贴图标矩形边框区域的流光
    ctx.clearRect(left + borderWidth, top + borderWidth, size - borderWidth * 2, size - borderWidth * 2)

    ctx.restore()
    ctx.globalAlpha = 1
  }

  private mapPlacedMarkerSize(): number {
    return 58
  }

  private blockedMarkerSize(): number {
    return 48
  }

  private destinationMarkerSize(): number {
    return 54
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
      return '#27B8FF'// 当前点
    }
    if (this.isPathNext(id)) {
      return '#ffe557ee' // 下一个点
    }
    if (this.isPathVisited(id)) {
      return '#ff4bf506' // 已走过
    }
    if (this.isPathFuture(id)) {
      return '#edf30c0c' // 未走
    }
    if (this.isCurrentNode(id)) {
      return '#27B8FF'// 当前点
    }
    return '#28597A66'// 默认点
  }

  private nodeLabelColor(id: string): string {
    // 1. 如果这个节点是【被挡住/障碍物】 → 文字变浅红色
    if (this.isBlockedNode(id)) return '#FF9E9E'
    // 2. 如果是【当前所在节点】 → 浅蓝色
    if (this.isPathCurrent(id)) {
      return '#73D7FF'
    }
    // 3. 如果是【下一个要走的节点】 → 黄色
    if (this.isPathNext(id)) {
      return '#FFD166'
    }
    // 4. 如果是【已经走过的节点】 → 灰蓝色
    if (this.isPathVisited(id)) {
      return '#86AEC8'
    }
    // 5. 如果是【还没走的未来路径点】 → 天蓝色
    if (this.isPathFuture(id)) {
      return '#5FC7FF'
    }
    // 6. 如果是小车当前吸附的节点（同当前点）→ 浅蓝色
    if (this.isCurrentNode(id)) {
      return '#73D7FF'
    }
    // 7. 其他普通节点 → 灰蓝色
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

  @Builder
  private buildParkingLotGrid(): void {
    Image($rawfile('map/map.png'))
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Fill)
  }

}
