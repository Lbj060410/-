import { Page1Theme } from '../../page1/Page1Theme'
import { PAGE4_BUTTON, PAGE4_PANEL, page4BtnBg, page4BtnBorder, page4BtnFg } from '../Page4Styles'

export interface Page4TopNavBarProps {
  showSidebar: boolean
  currentChatTitle: string
  voiceReplyEnabled: boolean
  onToggleSidebar: () => void
  onToggleVoiceReply: () => void
  onNewChat: () => void
}

@Builder
export function Page4TopNavBar(props: Page4TopNavBarProps): void {
  Row() {
    Button() {
      Image(props.showSidebar ? $rawfile('icon/关闭侧边栏.png') : $rawfile('icon/开启侧边栏.png'))
        .width(20)
        .height(20)
    }
    .width(PAGE4_BUTTON.HEIGHT_SM)
    .height(PAGE4_BUTTON.HEIGHT_SM)
    .padding(0)
    .backgroundColor(page4BtnBg(false))
    .borderRadius(PAGE4_BUTTON.RADIUS)
    .border({ width: 1, color: page4BtnBorder(false) })
    .stateEffect(false)
    .onClick((): void => props.onToggleSidebar())

    Blank()
    Text(props.currentChatTitle)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontFamily('STSong')
      .fontColor(Page1Theme.TEXT_PRIMARY)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Blank()

    Row({ space: 10 }) {
      Button() {
        Image(props.voiceReplyEnabled ? $rawfile('icon/语音播报开启.png') : $rawfile('icon/语音播报关闭.png'))
          .width(20)
          .height(20)
      }
      .height(PAGE4_BUTTON.HEIGHT_SM)
      .width(PAGE4_BUTTON.HEIGHT_SM)
      .padding(0)
      .backgroundColor(page4BtnBg(props.voiceReplyEnabled))
      .borderRadius(PAGE4_BUTTON.RADIUS)
      .border({ width: 1, color: page4BtnBorder(props.voiceReplyEnabled) })
      .stateEffect(false)
      .onClick((): void => props.onToggleVoiceReply())

      Button() {
        Image($rawfile('icon/添加新对话.png'))
          .width(20)
          .height(20)
      }
      .height(PAGE4_BUTTON.HEIGHT_SM)
      .width(PAGE4_BUTTON.HEIGHT_SM)
      .padding(0)
      .backgroundColor(page4BtnBg(false))
      .borderRadius(PAGE4_BUTTON.RADIUS)
      .border({ width: 1, color: page4BtnBorder(false) })
      .stateEffect(false)
      .onClick((): void => props.onNewChat())
    }
  }
  .width('100%')
  .height(74)
  .padding({ left: 16, right: 16 })
  .margin({ top: 15 })
  .backgroundColor(PAGE4_PANEL.NAV_BG)
  .border({ width: { bottom: 1 }, color: PAGE4_PANEL.NAV_BORDER })
  .alignItems(VerticalAlign.Bottom)
  .zIndex(10)
}
