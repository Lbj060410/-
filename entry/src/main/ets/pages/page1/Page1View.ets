/**
 * 代码指南：
 * 文件： pages/page1/Page1View.ets
 * 用途： Page1 composition and lifecycle binding between coordinator/store and UI components.
 * 何时修改： rearranging Page1 layout or adding/removing high-level panels.
 * 相关文件： app/Page1Coordinator.ets, app/Page1UiStore.ets, components/page1/*.
 */
// entry/src/main/ets/pages/page1/Page1View.ets

import { page1Store, Page1UiStore } from './app/Page1UiStore'
import { page1Coordinator } from './app/Page1Coordinator'
import { Page1Theme } from './Page1Theme'
import { SandboxMap } from './components/SandboxMap'
import { CarStatusCard } from './components/CarStatusCard'
import { ControlPanel } from './components/ControlPanel'

import { DiagnosticsPanel } from '../../components/diagnostics/DiagnosticsPanel'

@Component
export struct Page1View {
  @State private store: Page1UiStore = page1Store
  @State private showDiag: boolean = false
  private startDeferredTimerId: number = -1

  aboutToAppear(): void {
    page1Coordinator.bind(this.store)
    this.clearDeferredStart()
    // 先完成首帧渲染，再启动 Page1 后台任务（TCP / 调度循环），缩短“打开即卡顿”体感。
    this.startDeferredTimerId = setTimeout((): void => {
      this.startDeferredTimerId = -1
      void page1Coordinator.start()
    }, 220) as number
  }

  aboutToDisappear(): void {
    this.clearDeferredStart()
    // 保持协调器在标签页/页面切换时运行，以便 TCP/自动跟随/障碍逻辑
    // continue in background; full teardown is handled by explicit app/page stop paths.
  }

  private clearDeferredStart(): void {
    if (this.startDeferredTimerId >= 0) {
      clearTimeout(this.startDeferredTimerId)
      this.startDeferredTimerId = -1
    }
  }

  build(): void {
    Stack() {
      Row({ space: 10 }) {
        Column() {
          SandboxMap({ fullHeightMap: true })
        }
        .layoutWeight(65)
        .height('100%')
        .padding({ left: 10, right: 0, top: 10, bottom: 10 })

        Column({ space: 10 }) {
          Scroll() {
            Column({ space: 10 }) {
              this.buildDestinationBar()
              CarStatusCard({})
              ControlPanel({ onDiag: (): void => { this.showDiag = true } })
              Column() {}.height(4)
            }
            .width('100%')
            .padding({ left: 2, right: 2, top: 2, bottom: 2 })
          }
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.None)
          .width('100%')
        }
        .layoutWeight(35)
        .height('100%')
        .padding({ left: 0, right: 10, top: 10, bottom: 10 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Page1Theme.BG)

      if (this.showDiag) {
        Stack() {
          Column() {
            Row() {
              Text('Diagnostics Console')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Page1Theme.TEXT_PRIMARY)
              Blank()
              Button('关闭')
                .height(32)
                .padding({ left: 16, right: 16 })
                .borderRadius(16)
                .fontSize(13)
                .backgroundColor('#F1F5F9')
                .fontColor(Page1Theme.TEXT_SECONDARY)
                .onClick((): void => { this.showDiag = false })
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
        .onClick((): void => { this.showDiag = false })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildPageHeader(): void {
    Row() {
      Column({ space: 2 }) {
        Text('Mission Console')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
        Text('路径规划 / 态势感知 / 手动控制')
          .fontSize(12)
          .fontColor(Page1Theme.TEXT_SECONDARY)
      }
      Blank()
      Text(this.store.autoFollowEnabled ? 'FOLLOW ON' : 'FOLLOW OFF')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.store.autoFollowEnabled ? Page1Theme.SUCCESS : Page1Theme.TEXT_TERTIARY)
        .borderRadius(12)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(Page1Theme.RADIUS_M)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 10, color: '#00000008', offsetX: 0, offsetY: 2 })
  }

  @Builder
  private buildDestinationBar(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.store.destDraft, placeholder: '输入目的地（例如：A2 / D4 / G6）' })
          .layoutWeight(1)
          .height(Page1Theme.INPUT_HEIGHT)
          .backgroundColor('#F8FAFC')
          .borderRadius(14)
          .fontSize(14)
          .fontColor(Page1Theme.TEXT_PRIMARY)
          .placeholderColor(Page1Theme.TEXT_TERTIARY)
          .padding({ left: 14, right: 14 })
          .onChange((v: string): void => {
            this.store.destDraft = v
          })

        Button('应用')
          .height(Page1Theme.INPUT_HEIGHT)
          .padding({ left: 20, right: 20 })
          .borderRadius(14)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(Page1Theme.PRIMARY)
          .fontColor('#FFFFFF')
          .onClick(async (): Promise<void> => {
            await page1Coordinator.startManualRoute(this.store.destDraft)
          })
      }

      Text(this.store.destApplied.length > 0 ? `目的地：${this.store.destApplied}` : '目的地：未设置')
        .fontSize(12)
        .fontColor(Page1Theme.TEXT_SECONDARY)
        .margin({ left: 4 })

    }
    .padding(16)
    .borderRadius(Page1Theme.RADIUS_L)
    .backgroundColor(Page1Theme.CARD)
    .shadow({ radius: 16, color: '#1E293B0A', offsetX: 0, offsetY: 4 })
  }
}



