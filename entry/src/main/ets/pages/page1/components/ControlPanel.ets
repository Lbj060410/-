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
import { CONTROL_PANEL, INPUT } from '../Page1Styles'

@Component
export struct ControlPanel {
  @State isInputFocused: boolean = false
  @State private store: Page1UiStore = page1Store
  @State private custom0AInput: string = ''
  @State private customChainBytes: Array<number> = []
  onDiag: () => void = () => {}
  onMore: () => void = () => {}
  onTrafficLight: () => void = () => {}
  onGate: () => void = () => {}

  build() {
    Column({ space: 16 }) {
      // 顶部模式行（为逻辑需要保留但样式更好）
      Row({ space: 8 }) {
        Button(this.store.realSendEnabled ? '真车' : '模拟')
          .layoutWeight(1)
          .height(CONTROL_PANEL.MODE_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.MODE_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(this.store.realSendEnabled))
          .fontColor(this.trafficBtnFg(this.store.realSendEnabled))
          .fontSize(CONTROL_PANEL.MODE_BTN_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.trafficBtnBorder(this.store.realSendEnabled) })
          .onClick((): void => {
            this.store.toggleRealSend()
          })

        Button(this.store.obstacleEditEnabled ? '设障：开' : '设障：关')
          .layoutWeight(1)
          .height(CONTROL_PANEL.MODE_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.MODE_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(this.store.obstacleEditEnabled))
          .fontColor(this.trafficBtnFg(this.store.obstacleEditEnabled))
          .fontSize(CONTROL_PANEL.MODE_BTN_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.trafficBtnBorder(this.store.obstacleEditEnabled) })
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
          .height(CONTROL_PANEL.MODE_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.MODE_BTN_RADIUS)
          .backgroundColor(this.targetBtnBg())
          .fontColor(this.trafficBtnFg(this.store.targetPickEnabled || this.store.mapTargetPendingSend))
          .fontSize(CONTROL_PANEL.MODE_BTN_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.trafficBtnBorder(this.store.targetPickEnabled || this.store.mapTargetPendingSend) })
          .onClick((): void => {
            this.onTargetPickBtn()
          })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                this.clearTargetSelection()
              })
          )

        Button('更多')
          .layoutWeight(1)
          .height(CONTROL_PANEL.MODE_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.MODE_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(false))
          .fontColor(this.trafficBtnFg(false))
          .fontSize(CONTROL_PANEL.MODE_BTN_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: this.trafficBtnBorder(false) })
          .onClick((): void => {
            this.onMore()
          })
      }
      .width('100%')

      // 车辆控制
      Column({ space: 16 }) {
        Row() {
          Blank()
          Button('诊断')
            .height(CONTROL_PANEL.DIAG_BTN_HEIGHT)
            .padding({ left: 10, right: 10 })
            .borderRadius(CONTROL_PANEL.DIAG_BTN_RADIUS)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.trafficBtnBg(false))
            .fontColor(this.trafficBtnFg(false))
            .border({ width: 1, color: this.trafficBtnBorder(false) })
            .onClick((): void => {
              this.onDiag()
            })
        }
        .width('100%')

        Text('车辆控制')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Start)

        Row({ space: 8 }) {
          TextInput({ text: this.custom0AInput, placeholder: '分段输入：A@ 然后 1' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(INPUT.BG)
            .borderRadius(12)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .placeholderColor(INPUT.PLACEHOLDER_COLOR)
            .border({
              width: 1,
              // 聚焦时切换为极光青（INPUT.BORDER_FOCUS），平时为隐形微澜（INPUT.BORDER_COLOR）
              color: this.isInputFocused ? INPUT.BORDER_FOCUS : INPUT.BORDER_COLOR
            })
              // 监听聚焦和失焦事件
            .onFocus(() => {
              this.isInputFocused = true
            })
            .onBlur(() => {
              this.isInputFocused = false
            })
            .padding({ left: 12, right: 12 })
            .onChange((v: string): void => {
              this.custom0AInput = v
            })
            .onSubmit((): void => {
              void this.onSendCustom0A()
            })

          Button('发送')
            .height(CONTROL_PANEL.SEND_BTN_HEIGHT)
            .padding({ left: 14, right: 14 })
            .borderRadius(CONTROL_PANEL.SEND_BTN_RADIUS)
            .backgroundColor(this.trafficBtnBg(false))
            .fontColor(this.trafficBtnFg(false))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .border({ width: 1, color: this.trafficBtnBorder(false) })
            .onClick((): void => {
              void this.onSendCustom0A()
            })
        }
        .width('100%')

        Row({ space: 10 }) {
          Button() {
            Text('特殊路段')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(this.store.specialRoadEditEnabled))
          }
            .layoutWeight(1)
            .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
            .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
            .backgroundColor(this.trafficBtnBg(this.store.specialRoadEditEnabled))
            .stateEffect(false)
            .border({ width: 1, color: this.trafficBtnBorder(this.store.specialRoadEditEnabled) })
            .onClick((): void => {
              this.store.toggleSpecialRoadEdit()
            })
            .gesture(
              LongPressGesture()
                .onAction((): void => {
                  void page1Coordinator.clearSpecialSegmentByUi()
                  this.store.specialRoadEditEnabled = false
                })
            )

          Button() {
            Text('设置车库')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(this.store.garageEditEnabled))
          }
            .layoutWeight(1)
            .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
            .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
            .backgroundColor(this.trafficBtnBg(this.store.garageEditEnabled))
            .stateEffect(false)
            .border({ width: 1, color: this.trafficBtnBorder(this.store.garageEditEnabled) })
            .onClick((): void => {
              this.store.toggleGarageEdit()
            })
            .gesture(
              LongPressGesture()
                .onAction((): void => {
                  void page1Coordinator.clearGarageByUi()
                  this.store.garageEditEnabled = false
                })
            )

          Button() {
            Text('停止任务')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(false))
          }
            .layoutWeight(1)
            .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
            .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
            .backgroundColor(this.trafficBtnBg(false))
            .stateEffect(false)
            .border({ width: 1, color: this.trafficBtnBorder(false) })
            .onClick((): void => {
              void page1Coordinator.stopTaskByUi()
            })

          Button() {
            Text('继续任务')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(false))
          }
            .layoutWeight(1)
            .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
            .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
            .backgroundColor(this.trafficBtnBg(false))
            .stateEffect(false)
            .border({ width: 1, color: this.trafficBtnBorder(false) })
            .onClick((): void => {
              void page1Coordinator.resumeTaskByUi()
            })
        }
        .width('100%')

        // 第2行：高级动作
        Row({ space: 10 }) {
          Button() {
            Text(this.store.trafficLightEditEnabled ? '交通灯：开' : '交通灯')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(this.store.trafficLightEditEnabled))
          }
          .layoutWeight(1)
          .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(this.store.trafficLightEditEnabled))
          .border({ width: 1, color: this.trafficBtnBorder(this.store.trafficLightEditEnabled) })
          .onClick((): void => { this.onTrafficLight() })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                void page1Coordinator.clearTrafficLightsByUi()
                this.store.trafficLightEditEnabled = false
              })
          )

          Button() {
            Text(this.store.gateEditEnabled ? '道闸：开' : '道闸')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(this.store.gateEditEnabled))
          }
          .layoutWeight(1)
          .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(this.store.gateEditEnabled))
          .border({ width: 1, color: this.trafficBtnBorder(this.store.gateEditEnabled) })
          .onClick((): void => {
            this.onGate()
          })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                void page1Coordinator.clearBarrierByUi()
                this.store.gateEditEnabled = false
              })
          )

          Button() {
            Text('设置仓库')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(this.store.warehouseEditEnabled))
          }
          .layoutWeight(1)
          .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(this.store.warehouseEditEnabled))
          .stateEffect(false)
          .border({ width: 1, color: this.trafficBtnBorder(this.store.warehouseEditEnabled) })
          .onClick((): void => {
            this.store.toggleWarehouseEdit()
          })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                void page1Coordinator.clearWarehouseByUi()
                this.store.warehouseEditEnabled = false
              })
          )

          Button() {
            Text('清图')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.trafficBtnFg(false))
          }
          .layoutWeight(1)
          .height(CONTROL_PANEL.ACTION_BTN_HEIGHT)
          .borderRadius(CONTROL_PANEL.ACTION_BTN_RADIUS)
          .backgroundColor(this.trafficBtnBg(false))
          .border({ width: 1, color: this.trafficBtnBorder(false) })
          .shadow({ radius: 0 })
          .onClick((): void => {
            void page1Coordinator.resetNetworkMap()
          })
        }
        .width('100%')
      }
      .padding(20)
      .width('100%')
      .borderRadius(8)
      .backgroundColor(Page1Theme.CARD)
      .shadow({ radius: 10, color: 'rgba(110,168,255,0.12)', offsetX: 0, offsetY: 2 })
      .backgroundBlurStyle(BlurStyle.Thin)
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
      // 比赛讲解点：所有手动动作统一收口到 onAction，便于展示“统一控制入口”
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
    if (this.store.targetPickEnabled) return this.trafficBtnBg(true)
    if (this.store.mapTargetPendingSend) return this.trafficBtnBg(true)
    return this.trafficBtnBg(false)
  }

  private trafficBtnBg(active: boolean): string {
    if (active) return CONTROL_PANEL.BG_ACTIVE
    return CONTROL_PANEL.BG_IDLE
  }

  private trafficBtnBorder(active: boolean): string {
    if (active) return CONTROL_PANEL.BORDER_ACTIVE
    return CONTROL_PANEL.BORDER_IDLE
  }

  private trafficBtnFg(active: boolean): string {
    if (active) return CONTROL_PANEL.FG_ACTIVE
    return CONTROL_PANEL.FG_IDLE
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

  private parseHexByte(raw: string): number | undefined {
    let x: string = raw.trim().toUpperCase()
    if (x.startsWith('0X')) x = x.substring(2)
    if (!/^[0-9A-F]{1,2}$/.test(x)) return undefined
    const v: number = Number.parseInt(x, 16)
    if (!Number.isFinite(v) || v < 0 || v > 0xFF) return undefined
    return v
  }

  private async onSendCustom0A(): Promise<void> {
    let raw: string = this.custom0AInput.trim().toUpperCase()
    if (raw.length <= 0) return

    const hasContinue: boolean = raw.endsWith('@')
    if (hasContinue) raw = raw.substring(0, raw.length - 1).trim()
    const tokens: Array<string> = raw.split(/[\s,]+/).filter((x: string): boolean => x.trim().length > 0)
    if (tokens.length !== 1) {
      this.store.pushLog('输入非法：每次只能输入1个字节（如 A / 1 / 0A），末尾@表示继续')
      this.store.setAction('自定义指令输入错误')
      return
    }
    const b: number | undefined = this.parseHexByte(tokens[0])
    if (b === undefined) {
      this.store.pushLog('输入非法：每次只能输入1个字节（如 A / 1 / 0A），末尾@表示继续')
      this.store.setAction('自定义指令输入错误')
      return
    }
    this.customChainBytes.push(b)
    this.custom0AInput = ''

    if (hasContinue) {
      this.store.pushLog(`分段录入：+0x${b.toString(16).toUpperCase().padStart(2, '0')}（继续）`)
      return
    }

    if (this.customChainBytes.length < 2) {
      this.store.pushLog('发送失败：至少需要2字节（组号+子命令）')
      this.store.setAction('自定义指令长度不足')
      this.customChainBytes = []
      return
    }

    const bytes: Array<number> = this.customChainBytes
    this.customChainBytes = []
    const group: number = bytes[0] & 0xFF
    const sub: number = bytes[1] & 0xFF
    const ext: Uint8Array = new Uint8Array(Math.max(0, bytes.length - 2))
    for (let i: number = 2; i < bytes.length; i++) ext[i - 2] = bytes[i] & 0xFF
    await page1Coordinator.sendCustomGroupCommand(group, sub, ext)
  }

  private alarmBtnText(): string {
    return this.store.alarmEnabled ? '警报关闭' : '警报开启'
  }
}
