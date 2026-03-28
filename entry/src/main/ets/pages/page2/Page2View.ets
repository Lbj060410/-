/**
 * 代码指南：
 * 文件： pages/page2/Page2View.ets
 * 用途： Page2 UI 视图（视频页面）.
 * 何时修改： 调整 Page2 布局或区域可见性时.
 * 相关文件： pages/page2/Page2Coordinator.ets 以及 services/source/*.
 */

import resourceManager from '@ohos.resourceManager'
import image from '@ohos.multimedia.image'
import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'
import { Page1Theme } from '../page1/Page1Theme'
import { videoStore, VideoStore, DisplayMode } from '../../state/VideoStore'
import { recogStore, RecogStore } from '../../state/RecogStore'
import { BBoxNorm, RecognitionResult } from '../../services/recognition/RecognitionResult'
import {
  RecognitionSubtype,
  RecognitionTaskKind,
  RecognitionTaskRecord,
  RecognitionTaskState,
  RecognitionTaskSource,
  RoiNorm
} from '../../services/recognition/RecognitionTask'
import { page2Coordinator, Page2Coordinator } from './Page2Coordinator'
import { PtzControlPanel } from './components/PtzControlPanel'
import { DiagnosticsPanel } from '../../components/diagnostics/DiagnosticsPanel'
import { Page2ReplayCenter } from './components/Page2ReplayCenter'
import { page2ReplayService } from '../../services/replay/Page2ReplayService'

interface OverlayBoxViewModel {
  key: string
  subtype: RecognitionSubtype
  label: string
  score: number
  x: number
  y: number
  w: number
  h: number
}

interface Rect2d {
  x: number
  y: number
  w: number
  h: number
}

@Component
export struct Page2View {
  @State private videoStore: VideoStore = videoStore
  @State private recogStore: RecogStore = recogStore
  @State private showDiag: boolean = false
  @State private showReplay: boolean = false
  @State private galleryOriginalUri: string = ''

  // 视频显示区域的实际尺寸，由 onAreaChange 更新，用于识别框映射到 UI 坐标
  @State private videoAreaWidth: number = 0
  @State private videoAreaHeight: number = 240

  private c: Page2Coordinator = page2Coordinator
  private xCtrl: XComponentController = new XComponentController()

  aboutToAppear(): void {
    const ctx = globalThis.abilityContext
    if (ctx) {
      const rm: resourceManager.ResourceManager = ctx.resourceManager
      this.c.bindResourceManager(rm)
    } else {
      this.videoStore.setError('ability context is undefined')
    }

    void this.c.start()
  }

  aboutToDisappear(): void {
    // 在切换标签页/页面时保持 page2 流/识别运行。
    // 仍可通过"重启"按钮手动重启。
  }

  build(): void {
    Stack() {
      Row({ space: 0 }) {
        Column() {
          this.buildVideoArea()
        }
        .layoutWeight(70)
        .height('100%')
        .padding(0)

        Column({ space: 16 }) {
          this.buildRecognitionResult()
          this.buildSnapshotArea()
          this.buildControlButtons()
        }
        .layoutWeight(30)
        .height('100%')
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .backgroundColor(Page1Theme.SURFACE)
        .border({ width: { left: 1 }, color: Page1Theme.BORDER })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')

      if (this.showDiag) {
        Stack() {
          Column() {
            Row() {
              Text('Diagnostics')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Page1Theme.TEXT_PRIMARY)

              Blank()

              Button('关闭')
                .height(32)
                .padding({ left: 16, right: 16 })
                .borderRadius(16)
                .backgroundColor('#F1F5F9')
                .fontColor(Page1Theme.TEXT_SECONDARY)
                .onClick((): void => {
                  this.showDiag = false
                })
            }
            .margin({ bottom: 16 })

            DiagnosticsPanel()
          }
          .width('92%')
          .padding(20)
          .borderRadius(Page1Theme.RADIUS_L)
          .backgroundColor(Page1Theme.SURFACE)
          .shadow({ radius: 40, color: '#00000022', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000033')
        .align(Alignment.Bottom)
        .onClick((): void => {
          this.showDiag = false
        })
      }

      if (this.showReplay) {
        Stack() {
          Column() {
            Page2ReplayCenter({
              onClose: (): void => { this.showReplay = false }
            })
          }
          .width('92%')
          .padding(20)
          .borderRadius(Page1Theme.RADIUS_L)
          .backgroundColor(Page1Theme.SURFACE)
          .shadow({ radius: 40, color: '#00000022', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000033')
        .align(Alignment.Bottom)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildVideoArea(): void {
    Column() {
      if (this.videoStore.displayMode === DisplayMode.RTSP) {
        XComponent({
          id: 'page2_video_surface',
          type: 'surface',
          controller: this.xCtrl
        })
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .onLoad((): void => {
            const surfaceId: string = this.xCtrl.getXComponentSurfaceId()
            this.c.bindSurface(surfaceId)
          })
      } else {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#000000')

          if (this.videoStore.livePixelMap) {
            Image(this.videoStore.livePixelMap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .backgroundColor('#00000000')
          } else {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(Page1Theme.PRIMARY)
              Text('Waiting for camera frame...')
                .fontSize(13)
                .fontColor(Page1Theme.TEXT_SECONDARY)
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height('100%')
            .backgroundColor('#000000')
          }

          this.buildLiveOverlay()
        }
        .width('100%')
        .height('100%')
        .clip(true)
        .onAreaChange((oldValue: Area, newValue: Area): void => {
          void oldValue
          this.videoAreaWidth = this.lengthToNumber(newValue.width)
          this.videoAreaHeight = this.lengthToNumber(newValue.height)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  @Builder
  private buildControlButtons(): void {
    Column({ space: 16 }) {
      Text('CAMERA & RECOGNITION')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Page1Theme.TEXT_TERTIARY)
        .width('100%')
        .textAlign(TextAlign.Start)

      Row({ space: 10 }) {
        Text(`IP: ${this.videoStore.cameraHost}`)
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(Page1Theme.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`状态: ${this.cameraConnStateText()}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cameraConnStateColor())
      }
      .width('100%')

      // 第1行：PTZ 上、下、左、右
      Row({ space: 10 }) {
        this.ptzDirBtn('上', () => this.runPtz((svc, h, u, p) => svc.up(h, u, p)))
        this.ptzDirBtn('下', () => this.runPtz((svc, h, u, p) => svc.down(h, u, p)))
        this.ptzDirBtn('左', () => this.runPtz((svc, h, u, p) => svc.left(h, u, p)))
        this.ptzDirBtn('右', () => this.runPtz((svc, h, u, p) => svc.right(h, u, p)))
      }
      .width('100%')

      // 置信度条（按要求模拟视觉效果）
      Row({ space: 12 }) {
        Text('Recognition')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_SECONDARY)
        
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(6).backgroundColor('#E2E8F0').borderRadius(3)
          Row().width('94%').height(6).backgroundColor(Page1Theme.PRIMARY).borderRadius(3)
        }
        .layoutWeight(1)

        Text('94%')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.PRIMARY)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      // 第2行：切换识别、复盘、重启
      Row({ space: 8 }) {
        Button(this.videoStore.recognitionEnabled ? '识别：开' : '识别：关')
          .layoutWeight(2)
          .height(40)
          .borderRadius(6)
          .backgroundColor(this.videoStore.recognitionEnabled ? '#ECFDF5' : '#F8FAFC')
          .fontColor(this.videoStore.recognitionEnabled ? '#059669' : Page1Theme.TEXT_SECONDARY)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.videoStore.recognitionEnabled ? '#D1FAE5' : 'transparent' })
          .onClick((): void => {
            this.videoStore.setRecognitionEnabled(!this.videoStore.recognitionEnabled)
            this.videoStore.setStatus(`识别${this.videoStore.recognitionEnabled ? '开启' : '关闭'}`)
          })

        Button('复盘')
          .layoutWeight(1.5)
          .height(40)
          .borderRadius(6)
          .backgroundColor('#FFFFFF')
          .fontColor(Page1Theme.TEXT_SECONDARY)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: '#E2E8F0' })
          .shadow({ radius: 4, color: '#00000005', offsetX: 0, offsetY: 1 })
          .onClick((): void => {
            this.showReplay = true
          })

        Button('重启')
          .layoutWeight(1.5)
          .height(40)
          .borderRadius(6)
          .backgroundColor('#FEF2F2')
          .fontColor('#EF4444')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: '#FEE2E2' })
          .onClick((): void => {
            this.c.stop()
            void this.c.start()
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('选图')
          .layoutWeight(1)
          .height(36)
          .borderRadius(6)
          .backgroundColor('#FFFFFF')
          .fontColor(Page1Theme.PRIMARY)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: '#DBEAFE' })
          .onClick((): void => {
            void this.pickImageFromGallery()
          })

        Button('切换源')
          .layoutWeight(1)
          .height(36)
          .borderRadius(6)
          .backgroundColor('#FFFFFF')
          .fontColor(Page1Theme.TEXT_SECONDARY)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: '#E2E8F0' })
          .onClick((): void => {
            const toRtsp: boolean = this.videoStore.displayMode !== DisplayMode.RTSP
            if (toRtsp) {
              this.videoStore.setDisplayMode(DisplayMode.RTSP, 'manual switch')
              this.videoStore.setStatus('已切到 RTSP 预览')
            } else {
              this.videoStore.setDisplayMode(DisplayMode.HTTP, 'manual switch')
              this.videoStore.setStatus('已切到 HTTP 预览')
            }
          })

        Button(this.videoStore.page2Yolov26BarrierExperimentalEnabled ? '开障' : '关障')
          .layoutWeight(1)
          .height(36)
          .borderRadius(6)
          .backgroundColor(this.videoStore.page2Yolov26BarrierExperimentalEnabled ? '#EFF6FF' : '#F8FAFC')
          .fontColor(this.videoStore.page2Yolov26BarrierExperimentalEnabled ? '#1D4ED8' : Page1Theme.TEXT_SECONDARY)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.videoStore.page2Yolov26BarrierExperimentalEnabled ? '#BFDBFE' : '#E2E8F0' })
          .onClick((): void => {
            this.videoStore.setPage2Yolov26BarrierEnabled(!this.videoStore.page2Yolov26BarrierExperimentalEnabled)
            this.c.onModelSwitchChanged()
          })

        Button(this.videoStore.page2TrafficEnabled ? '灯开' : '灯关')
          .layoutWeight(1)
          .height(36)
          .borderRadius(6)
          .backgroundColor(this.videoStore.page2TrafficEnabled ? '#ECFDF5' : '#F8FAFC')
          .fontColor(this.videoStore.page2TrafficEnabled ? '#059669' : Page1Theme.TEXT_SECONDARY)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.videoStore.page2TrafficEnabled ? '#BBF7D0' : '#E2E8F0' })
          .onClick((): void => {
            this.videoStore.setPage2TrafficEnabled(!this.videoStore.page2TrafficEnabled)
            this.c.onModelSwitchChanged()
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 16, color: '#00000008', offsetX: 0, offsetY: 2 })
    .border({ width: 1, color: Page1Theme.BORDER })
  }

  @Builder
  private ptzDirBtn(label: string, action: () => void): void {
    Button(label)
      .layoutWeight(1)
      .height(48)
      .borderRadius(6)
      .backgroundColor('#FFFFFF')
      .fontColor(Page1Theme.TEXT_PRIMARY)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .border({ width: 1, color: '#E2E8F0' })
      .shadow({ radius: 4, color: '#00000005', offsetX: 0, offsetY: 1 })
      .onClick(action)
  }

  private async runPtz(op: (svc: any, host: string, user: string, pass: string) => Promise<any>): Promise<void> {
     import('../../services/control/CameraPtzService').then((m) => {
       const svc = new m.CameraPtzService()
       op(svc, this.videoStore.cameraHost, this.videoStore.cameraUser, this.videoStore.cameraPass).catch((e: Error) => {
         console.error('PTZ failed:', e.message)
       })
     })
  }

  @Builder
  private buildLiveOverlay(): void {
    if (this.hasOverlayBoxes()) {
      ForEach(
        this.overlayBoxes(),
        (item: OverlayBoxViewModel): void => {
          Column({ space: 0 }) {
            Row() {
              Text(
                `${this.overlayTag(item.subtype)} ${this.formatClassLabel(item.label)} ${(item.score * 100).toFixed(1)}%`
              )
                .fontSize(10)
                .fontColor('#FFFFFF')
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(3)
                .backgroundColor(this.overlayColor(item.label, item.subtype))
              Blank()
            }
            Blank()
          }
          .width(item.w)
          .height(item.h)
          .padding({ left: 1, right: 1, top: 1, bottom: 1 })
          .border({ width: 2, color: this.overlayColor(item.label, item.subtype) })
          .backgroundColor('#00000011')
          .position({ x: item.x, y: item.y })
        },
        (item: OverlayBoxViewModel): string => item.key
      )
    }
  }

  @Builder
  private buildRecognitionResult(): void {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text('AI RECOGNITION')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      Row({ space: 12 }) {
        Text('Object')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_SECONDARY)
        
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(6).backgroundColor('#E2E8F0').borderRadius(3)
          Row().width('94%').height(6).backgroundColor(Page1Theme.PRIMARY).borderRadius(3)
        }
        .layoutWeight(1)

        Text('94%')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.PRIMARY)
      }
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 16, color: '#00000008', offsetX: 0, offsetY: 2 })
    .border({ width: 1, color: Page1Theme.BORDER })
  }

  @Builder
  private buildSnapshotArea(): void {
    Column({ space: 8 }) {
      Row() {
        Text('Original Snapshot')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Page1Theme.TEXT_PRIMARY)
        Blank()
      }

      if (this.videoStore.snapshotPixelMap) {
        Image(this.videoStore.snapshotPixelMap)
          .width('100%')
          .height(220)
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Page1Theme.CARD_HOVER)
      } else if (this.galleryOriginalUri.length > 0) {
        Image(this.galleryOriginalUri)
          .width('100%')
          .height(220)
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Page1Theme.CARD_HOVER)
      } else {
        Column() {
          Text('No snapshot')
            .fontSize(14)
            .fontColor(Page1Theme.TEXT_TERTIARY)
        }
        .width('100%')
        .height(220)
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Page1Theme.CARD_HOVER)
      }
    }
    .padding(16)
    .borderRadius(Page1Theme.RADIUS_L)
    .backgroundColor(Page1Theme.CARD)
    .border({ width: 1, color: Page1Theme.BORDER })
  }

  @Builder
  private buildQuickStatsGrid(): void {
    Grid() {
      GridItem() { this.statCard('CAMERA', 'Active', '#059669', '#ECFDF5') }
      GridItem() { this.statCard('RESOLUTION', '1080p', '#2F6BFF', '#EEF3FF') }
      GridItem() { this.statCard('LATENCY', '45ms', '#F59E0B', '#FFFBEB') }
      GridItem() { this.statCard('UPTIME', '2:45:10', '#7C3AED', '#F3EEFF') }
    }
    .columnsTemplate('1fr 1fr')
    .rowsTemplate('1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .height(140)
    .width('100%')
  }

  @Builder
  private statCard(label: string, value: string, color: string, bg: string): void {
    Row({ space: 12 }) {
      Stack() {
        Circle({ width: 40, height: 40 }).fill(bg)
        Text('?').fontColor(color).fontSize(24) // placeholder for icon
      }
      Column() {
        Text(label).fontSize(10).fontWeight(FontWeight.Bold).fontColor(Page1Theme.TEXT_TERTIARY)
        Text(value).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Page1Theme.TEXT_PRIMARY).margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .borderRadius(Page1Theme.RADIUS_L)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 24, color: '#0000000B', offsetX: 0, offsetY: 4 })
    .border({ width: 1, color: Page1Theme.BORDER })
  }

  @Builder
  private buildRecognitionPanel(): void {
    Column({ space: 16 }) {
      Row() {
        Column() {
          Text('AI Recognition')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_PRIMARY)
          Text('Object detection status')
            .fontSize(12)
            .fontColor(Page1Theme.TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        
        Blank()
        
        // 切换开关替代
        Button() {
          Circle({ width: 16, height: 16 }).fill('#FFFFFF').shadow({ radius: 2, color: '#00000022', offsetX: 0, offsetY: 1 })
            .translate({ x: this.recogStore.recogBusy ? 10 : -10 })
            .animation({ duration: 200 })
        }
        .width(48)
        .height(24)
        .borderRadius(12)
        .backgroundColor(this.recogStore.recogBusy ? '#059669' : '#E5E7EB')
        .onClick((): void => {
          // toggle logic here if applicable, or visual only
        })
      }

      Column({ space: 12 }) {
        this.recogProgressRow('Person', 94)
        this.recogProgressRow('Vehicle', 89)
        this.recogProgressRow('Obstacle', 76)
      }
    }
    .width('100%')
    .padding(24)
    .borderRadius(Page1Theme.RADIUS_XL)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 24, color: '#0000000B', offsetX: 0, offsetY: 4 })
    .border({ width: 1, color: Page1Theme.BORDER })
  }

  @Builder
  private recogProgressRow(type: string, conf: number): void {
    Row({ space: 12 }) {
      Circle({ width: 8, height: 8 }).fill('#2F6BFF')
      
      Column() {
        Text(type).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Page1Theme.TEXT_PRIMARY)
        // 进度条背景
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(6).backgroundColor('#E5E7EB').borderRadius(3)
          Row().width(`${conf}%`).height(6).backgroundColor(this.confBarColor(conf)).borderRadius(3)
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      Text(`${conf}%`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.confTextColor(conf))
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor('#F9FAFB')
    .border({ width: 1, color: '#F3F4F6' })
  }

  private confBarColor(c: number): string {
    if (c >= 90) return '#10B981'
    if (c >= 75) return '#FBBF24'
    return '#F87171'
  }

  private confTextColor(c: number): string {
    if (c >= 90) return '#059669'
    if (c >= 75) return '#D97706'
    return '#DC2626'
  }

  @Builder
  private buildBottomActions(): void {
    Column({ space: 24 }) {
      Text('PTZ Camera Control')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Page1Theme.TEXT_PRIMARY)
        .width('100%')

      Column() {
        PtzControlPanel({
          cameraHost: this.videoStore.cameraHost,
          cameraUser: this.videoStore.cameraUser,
          cameraPass: this.videoStore.cameraPass
        })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F8FAFC')
      .borderRadius(16)
      .border({ width: 1, color: Page1Theme.BORDER })
    }
    .width('100%')
    .padding(24)
    .borderRadius(Page1Theme.RADIUS_XL)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 24, color: '#0000000B', offsetX: 0, offsetY: 4 })
    .border({ width: 1, color: Page1Theme.BORDER })
  }

  private modeText(mode: DisplayMode): string {
    if (mode === DisplayMode.RTSP) return 'RTSP'
    if (mode === DisplayMode.HTTP) return 'HTTP'
    return 'LOCAL'
  }

  private cameraConnStateText(): string {
    const nowMs: number = Date.now()
    const lastMs: number = this.videoStore.lastFrameTimeMs
    if (lastMs <= 0) return '连接中'
    const ageMs: number = nowMs - lastMs
    if (ageMs <= 2500) return '已连接'
    if (ageMs <= 7000) return '弱连接'
    return '异常'
  }

  private cameraConnStateColor(): string {
    const x: string = this.cameraConnStateText()
    if (x === '已连接') return '#10B981'
    if (x === '弱连接') return '#F59E0B'
    if (x === '异常') return '#EF4444'
    return Page1Theme.TEXT_TERTIARY
  }

  private overlayBoxes(): Array<OverlayBoxViewModel> {
    return this.collectOverlayBoxes()
  }

  private hasOverlayBoxes(): boolean {
    return this.overlayBoxes().length > 0
  }

  private recognitionStatusText(): string {
    return this.recogStore.recogBusy ? 'Running' : 'Idle'
  }

  private latestPage2Yolov26BarrierLiveResult(): RecognitionResult | undefined {
    if (!this.videoStore.page2Yolov26BarrierExperimentalEnabled) return undefined
    const r: RecognitionResult | undefined = this.recogStore.lastRecog

    if (
      r &&
      r.ok &&
        r.kind === RecognitionTaskKind.LIVE &&
        r.source === RecognitionTaskSource.PAGE2_BUTTON &&
        r.subtype === RecognitionSubtype.YOLOV26BARRIER
    ) {
      return r
    }

    return this.findLatestTaskResult(
      RecognitionTaskKind.LIVE,
      RecognitionSubtype.YOLOV26BARRIER,
      RecognitionTaskSource.PAGE2_BUTTON
    )
  }

  private latestPage2TrafficResult(): RecognitionResult | undefined {
    if (!this.videoStore.page2TrafficEnabled) return undefined
    const live: RecognitionResult | undefined = this.findLatestTaskResult(
      RecognitionTaskKind.LIVE,
      RecognitionSubtype.TRAFFIC_LIGHT,
      RecognitionTaskSource.PAGE2_BUTTON
    )
    if (live && live.ok) {
      return live
    }

    const r: RecognitionResult | undefined = this.recogStore.lastSnapshotRecog

    if (
      r &&
      r.ok &&
        r.kind === RecognitionTaskKind.SNAPSHOT &&
        r.source === RecognitionTaskSource.PAGE2_BUTTON &&
        r.subtype === RecognitionSubtype.TRAFFIC_LIGHT
    ) {
      return r
    }

    return this.findLatestTaskResult(
      RecognitionTaskKind.SNAPSHOT,
      RecognitionSubtype.TRAFFIC_LIGHT,
      RecognitionTaskSource.PAGE2_BUTTON
    )
  }

  private findLatestTaskResult(
    kind: RecognitionTaskKind,
    subtype: RecognitionSubtype,
    source: RecognitionTaskSource
  ): RecognitionResult | undefined {
    const tasks = this.recogStore.recogTasks
    for (let i: number = 0; i < tasks.length; i++) {
      const one = tasks[i]
      if (one.kind !== kind) continue
      if (one.subtype !== subtype) continue
      if (one.source !== source) continue
      if (!one.result || !one.result.ok) continue
      return one.result
    }
    return undefined
  }

  private recognitionSummaryText(result: RecognitionResult | undefined): string {
    if (!result || result.boxes.length <= 0) return '-'

    const sorted: Array<BBoxNorm> = result.boxes
      .slice()
      .sort((a: BBoxNorm, b: BBoxNorm): number => b.score - a.score)

    const topN: number = Math.min(3, sorted.length)
    const parts: Array<string> = []

    for (let i: number = 0; i < topN; i++) {
      const box: BBoxNorm = sorted[i]
      parts.push(`${this.formatClassLabel(box.label)} ${(box.score * 100).toFixed(0)}%`)
    }

    return parts.join(' | ')
  }

  private collectOverlayBoxes(): Array<OverlayBoxViewModel> {
    const viewW: number = this.videoAreaWidth
    const viewH: number = this.videoAreaHeight
    const srcW: number = this.videoStore.liveFrameWidth
    const srcH: number = this.videoStore.liveFrameHeight

    if (viewW <= 0 || viewH <= 0 || srcW <= 0 || srcH <= 0) {
      return []
    }

    const contentRect: Rect2d = this.computeContainRect(viewW, viewH, srcW, srcH)
    const overlays: Array<OverlayBoxViewModel> = []

    const yolov26barrier: RecognitionResult | undefined = this.latestPage2Yolov26BarrierLiveResult()
    if (yolov26barrier) {
      this.appendOverlayFromResult(overlays, yolov26barrier, contentRect, srcW, srcH, 12)
    }

    const traffic: RecognitionResult | undefined = this.latestPage2TrafficResult()
    if (traffic) {
      this.appendOverlayFromResult(overlays, traffic, contentRect, srcW, srcH, 8)
    }

    return overlays
  }

  private appendOverlayFromResult(
    out: Array<OverlayBoxViewModel>,
    result: RecognitionResult,
    contentRect: Rect2d,
    srcW: number,
    srcH: number,
    maxCount: number
  ): void {
    const sorted: Array<BBoxNorm> = result.boxes
      .slice()
      .sort((a: BBoxNorm, b: BBoxNorm): number => b.score - a.score)

    const count: number = Math.min(maxCount, sorted.length)
    const maxVisible: number = this.maxVisiblePerSubtype(result.subtype)
    let subtypeVisible: number = this.countSubtype(out, result.subtype)

    for (let i: number = 0; i < count; i++) {
      if (subtypeVisible >= maxVisible) break

      const box: BBoxNorm = sorted[i]
      if (box.score < this.minOverlayScore(result.subtype, box.label)) continue

      const srcRect: Rect2d | undefined = result.subtype === RecognitionSubtype.TRAFFIC_LIGHT
        ? this.toSourcePixelRectInRoi(box, result.roi, srcW, srcH)
        : this.toSourcePixelRect(box, srcW, srcH)

      if (!srcRect) continue

      const drawX: number = contentRect.x + (srcRect.x / srcW) * contentRect.w
      const drawY: number = contentRect.y + (srcRect.y / srcH) * contentRect.h
      const drawW: number = (srcRect.w / srcW) * contentRect.w
      const drawH: number = (srcRect.h / srcH) * contentRect.h

      if (drawW < 2 || drawH < 2) continue

      const drawRect: Rect2d = { x: drawX, y: drawY, w: drawW, h: drawH }
      if (this.isDuplicateOverlay(out, drawRect, result.subtype, box.label, 0.35)) continue

      out.push({
        key: `${result.subtype}-${box.label}-${i}-${Math.round(box.score * 1000)}`,
        subtype: result.subtype,
        label: box.label,
        score: box.score,
        x: drawX,
        y: drawY,
        w: drawW,
        h: drawH
      })

      subtypeVisible += 1
    }
  }

  private minOverlayScore(subtype: RecognitionSubtype, label: string): number {
    if (subtype === RecognitionSubtype.YOLOV26BARRIER) {
      const normalized: string = label.trim().toLowerCase()
      if (normalized === 'trafficlight' || normalized === 'traffic_light') return 0.12
      return 0.2
    }
    if (subtype === RecognitionSubtype.TRAFFIC_LIGHT) return 0.25
    return 0.2
  }

  private maxVisiblePerSubtype(subtype: RecognitionSubtype): number {
    if (subtype === RecognitionSubtype.YOLOV26BARRIER) return 4
    if (subtype === RecognitionSubtype.TRAFFIC_LIGHT) return 1
    return 2
  }

  private countSubtype(out: Array<OverlayBoxViewModel>, subtype: RecognitionSubtype): number {
    let count: number = 0
    for (let i: number = 0; i < out.length; i++) {
      if (out[i].subtype === subtype) {
        count += 1
      }
    }
    return count
  }

  private isDuplicateOverlay(
    out: Array<OverlayBoxViewModel>,
    current: Rect2d,
    subtype: RecognitionSubtype,
    label: string,
    iouThresh: number
  ): boolean {
    for (let i: number = 0; i < out.length; i++) {
      const one: OverlayBoxViewModel = out[i]
      if (one.subtype !== subtype) continue
      if (one.label.trim().toLowerCase() !== label.trim().toLowerCase()) continue

      const iou: number = this.rectIou(current, {
        x: one.x,
        y: one.y,
        w: one.w,
        h: one.h
      })

      if (iou >= iouThresh) return true
    }
    return false
  }

  private rectIou(a: Rect2d, b: Rect2d): number {
    const ax1: number = a.x + a.w
    const ay1: number = a.y + a.h
    const bx1: number = b.x + b.w
    const by1: number = b.y + b.h

    const interW: number = Math.max(0, Math.min(ax1, bx1) - Math.max(a.x, b.x))
    const interH: number = Math.max(0, Math.min(ay1, by1) - Math.max(a.y, b.y))

    if (interW <= 0 || interH <= 0) return 0

    const inter: number = interW * interH
    const union: number = a.w * a.h + b.w * b.h - inter

    if (union <= 0) return 0
    return inter / union
  }

  private toSourcePixelRect(box: BBoxNorm, srcW: number, srcH: number): Rect2d | undefined {
    // 兼容两种输出：
    // 1. 归一化坐标，范围 0 到 1
    // 2. 像素坐标，当前 NCNN 桥接可能直接输出像素值
    const maybeNormalized: boolean = box.w <= 1.0 && box.h <= 1.0
    const rawX: number = maybeNormalized ? box.x * srcW : box.x
    const rawY: number = maybeNormalized ? box.y * srcH : box.y
    const rawW: number = maybeNormalized ? box.w * srcW : box.w
    const rawH: number = maybeNormalized ? box.h * srcH : box.h

    const x0: number = Math.max(0, Math.min(rawX, srcW))
    const y0: number = Math.max(0, Math.min(rawY, srcH))
    const x1: number = Math.max(0, Math.min(rawX + rawW, srcW))
    const y1: number = Math.max(0, Math.min(rawY + rawH, srcH))

    if (x1 <= x0 || y1 <= y0) return undefined

    return {
      x: x0,
      y: y0,
      w: x1 - x0,
      h: y1 - y0
    }
  }

  private toSourcePixelRectInRoi(
    box: BBoxNorm,
    roi: RoiNorm | undefined,
    srcW: number,
    srcH: number
  ): Rect2d | undefined {
    if (!roi) return this.toSourcePixelRect(box, srcW, srcH)

    const rx0: number = Math.max(0, Math.min(roi.x, 1))
    const ry0: number = Math.max(0, Math.min(roi.y, 1))
    const rw: number = Math.max(0, Math.min(roi.w, 1 - rx0))
    const rh: number = Math.max(0, Math.min(roi.h, 1 - ry0))

    if (rw <= 0 || rh <= 0) return undefined

    const roiX: number = rx0 * srcW
    const roiY: number = ry0 * srcH
    const roiW: number = rw * srcW
    const roiH: number = rh * srcH

    if (roiW <= 0 || roiH <= 0) return undefined

    const maybeNormalized: boolean =
      box.x >= 0 && box.y >= 0 && box.w > 0 && box.h > 0 &&
        box.x <= 1 && box.y <= 1 && box.w <= 1 && box.h <= 1

    const cropX: number = maybeNormalized ? box.x * roiW : box.x
    const cropY: number = maybeNormalized ? box.y * roiH : box.y
    const cropW: number = maybeNormalized ? box.w * roiW : box.w
    const cropH: number = maybeNormalized ? box.h * roiH : box.h

    const x0: number = Math.max(0, Math.min(roiX + cropX, srcW))
    const y0: number = Math.max(0, Math.min(roiY + cropY, srcH))
    const x1: number = Math.max(0, Math.min(roiX + cropX + cropW, srcW))
    const y1: number = Math.max(0, Math.min(roiY + cropY + cropH, srcH))

    if (x1 <= x0 || y1 <= y0) return undefined

    return {
      x: x0,
      y: y0,
      w: x1 - x0,
      h: y1 - y0
    }
  }

  private computeContainRect(viewW: number, viewH: number, srcW: number, srcH: number): Rect2d {
    const scale: number = Math.min(viewW / srcW, viewH / srcH)
    const w: number = srcW * scale
    const h: number = srcH * scale

    return {
      x: (viewW - w) * 0.5,
      y: (viewH - h) * 0.5,
      w: w,
      h: h
    }
  }

  private formatClassLabel(label: string): string {
    if (label === 'red') return '红灯'
    if (label === 'yellow') return '黄灯'
    if (label === 'green') return '绿灯'

    const normalized: string = label.trim().toLowerCase()
    if (normalized === 'trafficlight' || normalized === 'traffic_light') return 'traffic-light-marker'
    if (normalized === 'shigong') return 'construction-marker'
    if (normalized === 'getoffthecar') return 'no-get-off'

    return label
  }

  private overlayTag(subtype: RecognitionSubtype): string {
    if (subtype === RecognitionSubtype.YOLOV26BARRIER) return 'B'
    if (subtype === RecognitionSubtype.TRAFFIC_LIGHT) return 'T'
    return '-'
  }

  private overlayColor(label: string, subtype?: RecognitionSubtype): string {
    if (label === 'red') return '#CF1322'
    if (label === 'yellow') return '#D48806'
    if (label === 'green') return '#389E0D'
    if (subtype === RecognitionSubtype.TRAFFIC_LIGHT) return '#13A8A8'
    if (subtype === RecognitionSubtype.YOLOV26BARRIER) return '#1677FF'
    return '#1677FF'
  }

  private previewHeight(): number {
    const baseWidth: number = this.videoAreaWidth > 0 ? this.videoAreaWidth : 360
    const h: number = Math.floor(baseWidth * 9 / 16)
    return Math.max(220, Math.min(340, h))
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

  private async captureSnapshot(): Promise<void> {
    if (!this.videoStore.livePixelMap) {
      this.videoStore.setStatus('Capture failed: no live frame')
      return
    }

    try {
      const packer: image.ImagePacker = image.createImagePacker()
      try {
        const jpeg: ArrayBuffer = await packer.packing(this.videoStore.livePixelMap, {
          format: 'image/jpeg',
          quality: 95
        })

        const previewPm: image.PixelMap | undefined = await this.createPixelMapFromJpeg(jpeg)
        const inferPm: image.PixelMap | undefined = await this.createPixelMapFromJpeg(jpeg)
        if (!previewPm || !inferPm) {
          if (previewPm) {
            try { previewPm.release() } catch (_) {}
          }
          if (inferPm) {
            try { inferPm.release() } catch (_) {}
          }
          throw new Error('Capture decode failed')
        }

        this.videoStore.setSnapshot(previewPm)
        const taskId: string = this.c.enqueueSnapshotRecognitionFromPixelMap(inferPm, RecognitionTaskSource.PAGE2_BUTTON)
        this.videoStore.setStatus(`Capture+recognize queued: ${taskId}`)
      } finally {
        try {
          packer.release()
        } catch (_) {}
      }
    } catch (e) {
      const errMsg: string = e instanceof Error ? e.message : 'Capture failed'
      this.videoStore.setStatus(errMsg)
      console.error('[Page2] captureSnapshot error:', errMsg)
    }
  }

  private async pickImageFromGallery(): Promise<void> {
    try {
      const mediaOk: boolean = await this.ensureMediaReadPermission()
      if (!mediaOk) {
        this.videoStore.setStatus('缺少媒体读取权限，无法识别选图')
        return
      }

      const photoPicker: picker.PhotoViewPicker = new picker.PhotoViewPicker()
      const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions()
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1

      const result: picker.PhotoSelectResult = await photoPicker.select(options)
      const uris: Array<string> = Array.isArray(result.photoUris) ? result.photoUris : []
      if (uris.length <= 0) {
        this.videoStore.setStatus('未选择图片')
        return
      }

      const selectedUri: string = uris[0]
      this.galleryOriginalUri = selectedUri
      this.videoStore.setSnapshot(undefined)

      let taskId: string = ''
      try {
        const pickedPm: image.PixelMap = await this.loadPixelMapFromUri(selectedUri)
        const previewPm: image.PixelMap | undefined = await this.clonePixelMap(pickedPm)
        if (previewPm) {
          this.videoStore.setSnapshot(previewPm)
        }
        taskId = this.c.enqueueSnapshotRecognitionFromPixelMap(
          pickedPm,
          RecognitionTaskSource.GALLERY,
          RecognitionSubtype.YOLOV26BARRIER,
          true
        )
      } catch (_) {
        taskId = this.c.enqueueSnapshotRecognitionFromGalleryUri(
          selectedUri,
          RecognitionSubtype.YOLOV26BARRIER
        )
      }
      this.videoStore.setStatus(`选图识别已提交: ${taskId}`)
      void this.waitAndArchiveGalleryReplay(taskId, selectedUri)
    } catch (e) {
      const errMsg: string = e instanceof Error ? e.message : '选图识别失败'
      this.videoStore.setStatus(errMsg)
      console.error('[Page2] pickImageFromGallery error:', errMsg)
    }
  }

  private async ensureMediaReadPermission(): Promise<boolean> {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) return true
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = ['ohos.permission.READ_MEDIA' as Permissions]
    try {
      const result = await atManager.requestPermissionsFromUser(ctx, perms)
      if (!result || !Array.isArray(result.authResults) || result.authResults.length <= 0) return false
      return result.authResults[0] === 0
    } catch (_) {
      return false
    }
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const root: Record<string, Object | undefined> = globalThis as Record<string, Object | undefined>
    const ctx: common.UIAbilityContext | undefined = root['abilityContext'] as common.UIAbilityContext | undefined
    return ctx
  }

  private async loadPixelMapFromUri(uri: string): Promise<image.PixelMap> {
    const raw: string = uri.trim()
    const viaFd: image.PixelMap | undefined = await this.tryDecodePixelMapByFd(raw)
    if (viaFd) return viaFd

    const noQuery: string = this.stripUriQuery(raw)
    const candidates: Array<string> = []
    const pushUnique = (s: string): void => {
      const one: string = s.trim()
      if (one.length <= 0) return
      for (let i: number = 0; i < candidates.length; i++) {
        if (candidates[i] === one) return
      }
      candidates.push(one)
    }
    pushUnique(raw)
    pushUnique(noQuery)
    try { pushUnique(decodeURIComponent(raw)) } catch (_) {}
    try { pushUnique(decodeURIComponent(noQuery)) } catch (_) {}
    if (noQuery.toLowerCase().startsWith('file://')) {
      const pathRaw: string = noQuery.substring('file://'.length)
      pushUnique(pathRaw)
      try { pushUnique(decodeURIComponent(pathRaw)) } catch (_) {}
    }

    let firstErr: string = ''
    for (let i: number = 0; i < candidates.length; i++) {
      let src: image.ImageSource | undefined = undefined
      try {
        src = image.createImageSource(candidates[i])
        if (!src) continue
        return await src.createPixelMap()
      } catch (e) {
        if (firstErr.length <= 0) firstErr = this.errorToText(e)
      } finally {
        if (src) {
          try { src.release() } catch (_) {}
        }
      }
    }
    const scheme: string = this.uriScheme(raw)
    const detail: string = firstErr.length > 0 ? `, err=${firstErr}` : ''
    throw new Error(`gallery image decode failed, scheme=${scheme}${detail}`)
  }

  private async tryDecodePixelMapByFd(uri: string): Promise<image.PixelMap | undefined> {
    if (uri.length <= 0) return undefined
    let f: fs.File | undefined = undefined
    let src: image.ImageSource | undefined = undefined
    try {
      f = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      src = image.createImageSource(f.fd)
      if (!src) return undefined
      return await src.createPixelMap()
    } catch (_) {
      return undefined
    } finally {
      if (src) {
        try { src.release() } catch (_) {}
      }
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  private stripUriQuery(uri: string): string {
    const qPos: number = uri.indexOf('?')
    const hPos: number = uri.indexOf('#')
    let end: number = uri.length
    if (qPos >= 0 && qPos < end) end = qPos
    if (hPos >= 0 && hPos < end) end = hPos
    return uri.substring(0, end)
  }

  private uriScheme(uri: string): string {
    const pos: number = uri.indexOf('://')
    if (pos <= 0) return 'unknown'
    return uri.substring(0, pos).toLowerCase()
  }

  private errorToText(e: Object): string {
    if (e instanceof Error) return e.message.length > 0 ? e.message : 'unknown error'
    try {
      const txt: string = JSON.stringify(e)
      return txt.length > 0 ? txt : 'unknown error'
    } catch (_) {
      return 'unknown error'
    }
  }

  private async createPixelMapFromJpeg(jpeg: ArrayBuffer): Promise<image.PixelMap | undefined> {
    const src: image.ImageSource = image.createImageSource(jpeg)
    try {
      return await src.createPixelMap()
    } catch (_) {
      return undefined
    } finally {
      try { src.release() } catch (_) {}
    }
  }

  private async clonePixelMap(pm: image.PixelMap): Promise<image.PixelMap | undefined> {
    const packer: image.ImagePacker = image.createImagePacker()
    try {
      const jpeg: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 92 })
      return await this.createPixelMapFromJpeg(jpeg)
    } catch (_) {
      return undefined
    } finally {
      try { packer.release() } catch (_) {}
    }
  }

  private async waitAndArchiveGalleryReplay(taskId: string, selectedUri: string): Promise<void> {
    const startedAt: number = Date.now()
    const timeoutMs: number = 12000
    while (Date.now() - startedAt < timeoutMs) {
      const task: RecognitionTaskRecord | undefined = this.findTaskById(taskId)
      if (task && task.result) {
        await page2ReplayService.onGalleryRecognitionFromUri(selectedUri, task.result)
        return
      }
      if (task && this.isTaskTerminal(task.state)) {
        await page2ReplayService.onGalleryRecognitionFromUri(
          selectedUri,
          this.fallbackRecognitionResult(taskId, task)
        )
        return
      }
      await this.sleep(150)
    }
    await page2ReplayService.onGalleryRecognitionFromUri(
      selectedUri,
      this.fallbackRecognitionResult(taskId, undefined, 'wait result timeout')
    )
  }

  private findTaskById(taskId: string): RecognitionTaskRecord | undefined {
    const tasks = this.recogStore.recogTasks
    for (let i: number = 0; i < tasks.length; i++) {
      if (tasks[i].id === taskId) return tasks[i]
    }
    return undefined
  }

  private isTaskTerminal(state: RecognitionTaskState): boolean {
    return state === RecognitionTaskState.SUCCESS ||
      state === RecognitionTaskState.FAILED ||
      state === RecognitionTaskState.CANCELED ||
      state === RecognitionTaskState.TIMEOUT ||
      state === RecognitionTaskState.DROPPED
  }

  private fallbackRecognitionResult(
    taskId: string,
    task?: RecognitionTaskRecord,
    reason: string = ''
  ): RecognitionResult {
    return {
      taskId,
      kind: task ? task.kind : RecognitionTaskKind.SNAPSHOT,
      subtype: task ? task.subtype : RecognitionSubtype.YOLOV26BARRIER,
      source: task ? task.source : RecognitionTaskSource.GALLERY,
      tsMs: Date.now(),
      costMs: task ? task.costMs : 0,
      engine: task && task.engine.length > 0 ? task.engine : 'unknown',
      boxes: [],
      texts: [],
      ok: false,
      errorText: task && task.errorText.length > 0
        ? task.errorText
        : (reason.length > 0 ? reason : 'recognition failed')
    }
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout((): void => resolve(), Math.max(1, ms))
    })
  }
}
