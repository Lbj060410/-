/**
 * 代码指南：
 * 文件：pages/page1/components/ControlPanel.ets
 * 用途：仅限 Page1 视觉组件（地图/状态/控制渲染）。
 * 何时修改：修改视图样式、控件或纯显示交互时。
 * 相关文件：状态来自 app/Page1UiStore.ets，动作路由到 app/Page1Coordinator.ets。
 */
// entry/src/main/ets/pages/page1/components/ControlPanel.ets

import { page1Store, Page1UiStore, CarConnState } from '../app/Page1UiStore'
import { Page1Action } from '../types/Page1Types'
import { page1Coordinator } from '../app/Page1Coordinator'
import { Page1Theme } from '../Page1Theme'

@Component
export struct ControlPanel {
  @State private store: Page1UiStore = page1Store
  @State private custom0AInput: string = ''
  onDiag: () => void = () => {}

  build() {
    Column({ space: 16 }) {
      // 顶部模式行（为逻辑需要保留但样式更好）
      Row({ space: 8 }) {
        Button(this.store.realSendEnabled ? '真车' : '模拟')
          .layoutWeight(1)
          .height(44)
          .borderRadius(14)
          .backgroundColor(this.store.realSendEnabled ? '#FEF2F2' : '#F8FAFC')
          .fontColor(this.store.realSendEnabled ? '#EF4444' : Page1Theme.TEXT_SECONDARY)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.store.realSendEnabled ? '#FEE2E2' : Page1Theme.BORDER })
          .onClick((): void => {
            this.store.toggleRealSend()
          })

        Button(this.store.obstacleEditEnabled ? '设障：开' : '设障：关')
          .layoutWeight(1)
          .height(44)
          .borderRadius(14)
          .backgroundColor(this.store.obstacleEditEnabled ? '#FEF3C7' : '#FFFBEB')
          .fontColor('#D97706')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: '#FEF3C7' })
          .onClick((): void => {
            this.store.toggleObstacleEdit()
          })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                this.store.clearBlockedNodes()
                this.store.pushLog('障碍编辑：长按已清空障碍')
              })
          )

        Button(this.targetBtnText())
          .layoutWeight(1)
          .height(44)
          .borderRadius(14)
          .backgroundColor(this.targetBtnBg())
          .fontColor('#7C3AED')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: '#EDE9FE' })
          .onClick((): void => {
            this.onTargetPickBtn()
          })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                this.clearTargetSelection()
              })
          )
      }
      .width('100%')

      // 车辆控制
      Column({ space: 16 }) {
        Row() {
          Blank()
          Button('诊断')
            .height(24)
            .padding({ left: 10, right: 10 })
            .borderRadius(12)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#F1F5F9')
            .fontColor(Page1Theme.TEXT_SECONDARY)
            .onClick((): void => {
              this.onDiag()
            })
        }
        .width('100%')

        Text('VEHICLE CONTROL')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Start)

        Row({ space: 8 }) {
          TextInput({ text: this.custom0AInput, placeholder: '输入指令码' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#F8FAFC')
            .borderRadius(12)
            .fontSize(13)
            .fontColor(Page1Theme.TEXT_PRIMARY)
            .padding({ left: 12, right: 12 })
            .onChange((v: string): void => {
              this.custom0AInput = v
            })
            .onSubmit((): void => {
              void this.onSendCustom0A()
            })

          Button('发送')
            .height(40)
            .padding({ left: 14, right: 14 })
            .borderRadius(12)
            .backgroundColor('#EEF2FF')
            .fontColor('#3730A3')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .border({ width: 1, color: '#C7D2FE' })
            .onClick((): void => {
              void this.onSendCustom0A()
            })
        }
        .width('100%')

        // 第1行：基本移动
        Row({ space: 10 }) {
          this.controlBtn('前进', Page1Action.GO, 'basic')
          this.controlBtn('后退', Page1Action.BACK, 'basic')
          this.controlBtn('左转', Page1Action.LEFT, 'basic')
          this.controlBtn('右转', Page1Action.RIGHT, 'basic')
        }
        .width('100%')

        // 第2行：高级动作
        Row({ space: 10 }) {
          this.controlBtn('左半转', Page1Action.LEFT_HALF, 'advanced')
          this.controlBtn('右半转', Page1Action.RIGHT_HALF, 'advanced')
          this.controlBtn('掉头', Page1Action.UTURN, 'advanced')
          this.controlBtn('急停', Page1Action.SCRAM, 'danger')
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
    .width('100%')
  }

  @Builder
  private controlBtn(label: string, action: Page1Action, style: 'basic' | 'advanced' | 'danger'): void {
    Button() {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(
          style === 'danger' ? '#EF4444' : 
          (style === 'basic' ? Page1Theme.TEXT_PRIMARY : Page1Theme.TEXT_SECONDARY)
        )
    }
    .layoutWeight(1)
    .height(48)
    .borderRadius(6)
    .backgroundColor(
      style === 'danger' ? '#FEF2F2' : 
      (style === 'basic' ? '#FFFFFF' : '#F8FAFC')
    )
    .border({ 
      width: 1, 
      color: style === 'danger' ? '#FEE2E2' : (style === 'basic' ? '#E2E8F0' : 'transparent') 
    })
    .shadow(style === 'basic' ? { radius: 4, color: '#00000005', offsetX: 0, offsetY: 1 } : { radius: 0 })
    .onClick((): void => {
      void page1Coordinator.onAction(action)
    })
  }

  private modeBtnText(): string {
    if (this.store.realSendEnabled) return '真车模式：真实发送'
    return '模拟模式：仅模拟'
  }

  private modeBtnBg(): string {
    if (this.store.realSendEnabled) return Page1Theme.DANGER
    return Page1Theme.CARD_HOVER
  }

  private modeBtnFg(): string {
    return Page1Theme.TEXT_PRIMARY
  }

  private modeHintText(): string {
    if (!this.store.realSendEnabled) return 'DRY_RUN：未连接也可点按钮，只打日志不发帧'
    if (this.store.connState === CarConnState.CONNECTED) return 'REAL_SEND：已连接，将真实发送控制帧'
    return 'REAL_SEND：但当前未连接，点击控制只记录日志（不会真实发送）'
  }

  private onToggleRealSend(): void {
    this.store.toggleRealSend()
  }

  private followBtnText(): string {
    return this.store.autoFollowEnabled ? '自动跟随：开' : '自动跟随：关'
  }

  private followBtnBg(): string {
    if (this.store.autoFollowEnabled) return Page1Theme.SUCCESS
    return Page1Theme.CARD_HOVER
  }

  private followBtnFg(): string {
    return this.store.autoFollowEnabled ? '#0D2A22' : Page1Theme.TEXT_PRIMARY
  }

  private onToggleAutoFollow(): void {
    this.store.autoFollowEnabled = !this.store.autoFollowEnabled
    this.store.pushLog(`AUTO_FOLLOW：${this.store.autoFollowEnabled ? 'ON' : 'OFF'}`)
  }

  private targetBtnText(): string {
    if (this.store.targetPickEnabled) return '目标：选点中'
    if (this.store.mapTargetPendingSend) return '目标：确认发送'
    return '目标'
  }

  private targetBtnBg(): string {
    if (this.store.targetPickEnabled) return '#EDE9FE'
    if (this.store.mapTargetPendingSend) return '#DDD6FE'
    return '#F3EEFF'
  }

  private onTargetPickBtn(): void {
    if (this.store.mapTargetPendingSend) {
      this.store.mapTargetPendingSend = false
      void page1Coordinator.startManualRoute(this.store.destDraft)
      return
    }
    this.store.toggleTargetPick()
  }

  private clearTargetSelection(): void {
    const hadSelection: boolean =
      this.store.targetPickEnabled ||
      this.store.mapTargetPendingSend ||
      this.store.destDraft.trim().length > 0 ||
      this.store.destApplied.trim().length > 0
    this.store.targetPickEnabled = false
    this.store.mapTargetPendingSend = false
    this.store.destDraft = ''
    this.store.destApplied = ''
    if (hadSelection) {
      this.store.setAction('目标清空')
      this.store.pushLog('目标点选：长按已清空')
    }
  }

  private parseCustom0AInput(): number | undefined {
    let raw: string = this.custom0AInput.trim().toUpperCase()
    if (raw.length <= 0) return undefined
    if (raw.startsWith('0X')) raw = raw.substring(2)
    if (!/^[0-9A-F]{1,2}$/.test(raw)) return undefined
    const parsed: number = Number.parseInt(raw, 16)
    if (!Number.isFinite(parsed)) return undefined
    if (parsed < 0 || parsed > 0xFF) return undefined
    return parsed
  }

  private async onSendCustom0A(): Promise<void> {
    const code: number | undefined = this.parseCustom0AInput()
    if (code === undefined) {
      this.store.pushLog('自定义0x0A输入非法：请输入 1~2 位十六进制（如 1 / A / 1C / 0x0A）')
      this.store.setAction('自定义0x0A输入错误')
      return
    }
    await page1Coordinator.sendCustomControl0A(code)
  }

  private alarmBtnText(): string {
    return this.store.alarmEnabled ? '警报关闭' : '警报开启'
  }
}
