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
import { MORE_PANEL, MODAL } from './Page1Styles'
import { Page1Action } from './types/Page1Types'
import { SandboxMap } from './components/SandboxMap'
import { CarStatusCard } from './components/CarStatusCard'
import { ControlPanel } from './components/ControlPanel'
import { ReplayReviewPanel } from './components/ReplayReviewPanel'

import { DiagnosticsPanel } from '../../components/diagnostics/DiagnosticsPanel'
import { CarProtocolService } from '../../services/control/CarProtocolService'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'

@Component
export struct Page1View {
  @State private store: Page1UiStore = page1Store
  @State private showDiag: boolean = false
  @State private showReplay: boolean = false
  @State private showMorePanel: boolean = false
  private startDeferredTimerId: number = -1

  aboutToAppear(): void {
    page1Coordinator.bind(this.store)
    this.clearDeferredStart()

    // 请求麦克风权限
    this.requestMicrophonePermission()

    // 先完成首帧渲染，再启动 Page1 后台任务（TCP / 调度循环），缩短”打开即卡顿”体感。
    this.startDeferredTimerId = setTimeout((): void => {
      this.startDeferredTimerId = -1
      void page1Coordinator.start()
    }, 220) as number
  }

  private requestMicrophonePermission(): void {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      atManager.requestPermissionsFromUser(getContext(this) as common.UIAbilityContext, ['ohos.permission.MICROPHONE'])
        .then((): void => {
          // 权限请求完成，无需额外处理
        })
        .catch((): void => {
          // 权限请求失败，也无需处理，用户后续使用语音功能时会再次请求
        })
    } catch (_) {
      // 权限请求异常，不影响主流程
    }
  }

  aboutToDisappear(): void {
    this.clearDeferredStart()
    // 保持协调器在标签页/页面切换时运行，以便 TCP/自动跟随/障碍逻辑
    // continue in background; full teardown is handled by explicit app/page stop paths.
  }

  onPageShow(): void {
    page1Coordinator.bind(this.store)
    void page1Coordinator.start()
    void page1Coordinator.connectTcp(this.store.connIp, this.store.connPort)
  }

  onPageHide(): void {
    page1Coordinator.pausePage()
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
              CarStatusCard({})
              ControlPanel({
                onDiag: (): void => { this.showDiag = true },
                onMore: (): void => { this.showMorePanel = true },
                onTrafficLight: (): void => { this.store.toggleTrafficLightEdit() },
                onGate: (): void => { this.store.toggleGateEdit() }
              })
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
              Text('诊断日志')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Page1Theme.TEXT_PRIMARY)
              Blank()
              Button('关闭')
                .height(32)
                .padding({ left: 16, right: 16 })
                .borderRadius(16)
                .fontSize(13)
                .backgroundColor(Page1Theme.CARD_HOVER)
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
          .border({ width: 1, color: Page1Theme.BORDER })
          .shadow({ radius: 18, color: 'rgba(110,168,255,0.12)', offsetX: 0, offsetY: 4 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(MODAL.OVERLAY_BG)
        .align(Alignment.Bottom)
        .onClick((): void => { this.showDiag = false })
      }

      if (this.showReplay) {
        Stack() {
          Column() {
            ReplayReviewPanel({
              onClose: (): void => { this.showReplay = false }
            })
          }
          .width('92%')
          .padding(20)
          .borderRadius(Page1Theme.RADIUS_L)
          .backgroundColor(Page1Theme.SURFACE)
          .border({ width: 1, color: Page1Theme.BORDER })
          .shadow({ radius: 18, color: 'rgba(110,168,255,0.12)', offsetX: 0, offsetY: 4 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(MODAL.OVERLAY_BG)
        .align(Alignment.Bottom)
        .onClick((): void => { this.showReplay = false })
      }

      if (this.showMorePanel) {
        Stack() {
          Row() {
            Blank()
            Column({ space: 10 }) {
              Row() {
                Text('更多')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Page1Theme.TEXT_PRIMARY)
                Blank()
                Button('关闭')
                  .height(MODAL.CLOSE_BTN_HEIGHT)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(MODAL.CLOSE_BTN_RADIUS)
                  .fontSize(12)
                  .backgroundColor(MODAL.CLOSE_BTN_BG)
                  .fontColor(MODAL.CLOSE_BTN_FG)
                  .onClick((): void => { this.showMorePanel = false })
              }
              .width('100%')


              Button('前进')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.GO)
                })

              Button('后退')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.BACK)
                })

              Button('左转')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.LEFT)
                })

              Button('右转')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.RIGHT)
                })

              Button('左半转')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.LEFT_HALF)
                })

              Button('右半转')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.RIGHT_HALF)
                })

              Button('掉头')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.onAction(Page1Action.UTURN)
                })

              Button('预设1')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.presetOneByUi()

                })

              Button('预设2')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.presetTwoByUi()
                })

              Button('预设3')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.presetThreeByUi()
                })

              Button('预设4')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.presetFourByUi()
                })

              Button('检查连接')
                .width('100%')
                .height(MORE_PANEL.BTN_HEIGHT)
                .borderRadius(MORE_PANEL.BTN_RADIUS)
                .backgroundColor(MORE_PANEL.BG)
                .fontColor(MORE_PANEL.FG)
                .border({ width: 1, color: MORE_PANEL.BORDER })
                .onClick((): void => {
                  void page1Coordinator.jianchaconncet()
                })
            }
            .width('30%')
            .height('100%')
            .padding(12)
            .backgroundColor(Page1Theme.SURFACE)
            .border({ width: 1, color: Page1Theme.BORDER })
            .shadow({ radius: 12, color: 'rgba(110,168,255,0.12)', offsetX: -2, offsetY: 0 })
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(MODAL.OVERLAY_BG)
        .onClick((): void => { this.showMorePanel = false })
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

}
