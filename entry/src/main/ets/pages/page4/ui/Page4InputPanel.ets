import { PAGE4_BUTTON, PAGE4_INPUT, PAGE4_PANEL, page4BtnBg, page4BtnBorder, page4BtnFg } from '../Page4Styles'

export interface Page4InputPanelProps {
  inputMode: 'text' | 'voice'
  inputText: string
  voiceRecording: boolean
  onToggleMode: () => void
  onInputChange: (v: string) => void
  onSubmitText: () => void
  onVoiceTouch: (event: TouchEvent) => void
}

@Builder
export function Page4InputPanel(props: Page4InputPanelProps): void {
  Row({ space: 12 }) {
    Button() {
      Image(props.inputMode === 'voice' ? $rawfile('icon/文字输入.png') : $rawfile('icon/语音输入.png'))
        .width(24)
        .height(24)
    }
    .width(PAGE4_BUTTON.HEIGHT_LG)
    .height(PAGE4_BUTTON.HEIGHT_LG)
    .backgroundColor(page4BtnBg(false))
    .borderRadius(PAGE4_BUTTON.RADIUS)
    .border({ width: 1, color: page4BtnBorder(false) })
    .stateEffect(false)
    .onClick((): void => {
      animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, (): void => props.onToggleMode())
    })

    if (props.inputMode === 'text') {
      TextInput({ text: props.inputText, placeholder: '发送指令或提问...' })
        .layoutWeight(1)
        .height(PAGE4_INPUT.HEIGHT)
        .backgroundColor(PAGE4_INPUT.BG)
        .borderRadius(PAGE4_INPUT.RADIUS)
        .fontSize(15)
        .fontColor(PAGE4_INPUT.TEXT_COLOR)
        .placeholderColor(PAGE4_INPUT.PLACEHOLDER_COLOR)
        .padding({ left: 20, right: 20 })
        .border({ width: 1, color: PAGE4_INPUT.BORDER_COLOR })
        .onChange((v: string): void => props.onInputChange(v))
        .onSubmit((): void => props.onSubmitText())

      if (props.inputText.length > 0) {
        Button('发送')
          .height(PAGE4_BUTTON.HEIGHT_LG)
          .padding({ left: 14, right: 14 })
          .constraintSize({ minWidth: 76 })
          .borderRadius(PAGE4_BUTTON.RADIUS)
          .backgroundColor(page4BtnBg(true))
          .fontColor(page4BtnFg(true))
          .fontSize(PAGE4_BUTTON.FONT_SIZE_MD)
          .fontWeight(FontWeight.Bold)
          .border({ width: 1, color: page4BtnBorder(true) })
          .transition({ type: TransitionType.Insert, scale: { x: 0.1, y: 0.1 } })
          .onClick((): void => props.onSubmitText())
      }
    } else {
      Button(props.voiceRecording ? '松开发送 / 滑动取消' : '按住说话')
        .layoutWeight(1)
        .height(PAGE4_BUTTON.HEIGHT_LG)
        .backgroundColor(page4BtnBg(props.voiceRecording))
        .fontColor(page4BtnFg(props.voiceRecording))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .borderRadius(PAGE4_BUTTON.RADIUS)
        .border({ width: 1, color: page4BtnBorder(props.voiceRecording) })
        .onTouch((event: TouchEvent): void => props.onVoiceTouch(event))
    }
  }
  .width('100%')
  .padding({ left: 16, right: 16, top: 16, bottom: 20 })
  .backgroundColor(PAGE4_PANEL.INPUT_BG)
  .border({ width: { top: 1 }, color: PAGE4_PANEL.INPUT_BORDER })
}
