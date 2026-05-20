import { Page1Theme } from '../../page1/Page1Theme'
import { AssistantMessage } from '../modules/Page4SessionModule'
import { Page4UiLayer } from './Page4UiLayer'
import { PAGE4_PANEL } from '../Page4Styles'

export interface Page4ChatPanelProps {
  chatScroller: Scroller
  messages: Array<AssistantMessage>
  assistantBusy: boolean
  queryThinkingVisible: boolean
  queryThinkingStageText: string
  queryThinkingProgressPct: number
}

function clampQueryThinkingPct(v: number): number {
  return Math.max(0, Math.min(100, Math.round(v)))
}

function queryThinkingPctText(v: number): string {
  return `${clampQueryThinkingPct(v)}%`
}

@Builder
export function Page4ChatPanel(props: Page4ChatPanelProps): void {
  Column() {
    Scroll(props.chatScroller) {
      Column({ space: 24 }) {
        ForEach(props.messages, (msg: AssistantMessage) => {
          Row() {
            if (msg.role === 'assistant') {
              Column({ space: 4 }) {
                Text(msg.text)
                  .fontSize(15)
                  .fontColor(Page1Theme.TEXT_PRIMARY)
                  .padding({ left: 18, right: 18, top: 14, bottom: 14 })
                  .borderRadius({ topLeft: 4, topRight: 20, bottomLeft: 20, bottomRight: 20 })
                  .backgroundColor(PAGE4_PANEL.CHAT_ASSIST_BG)
                  .border({ width: 1, color: PAGE4_PANEL.CHAT_ASSIST_BORDER })
                  .constraintSize({ maxWidth: '80%' })
                Text(Page4UiLayer.formatTime(msg.tsMs))
                  .fontSize(11)
                  .fontColor(Page1Theme.TEXT_TERTIARY)
                  .margin({ left: 6 })
              }
              .alignItems(HorizontalAlign.Start)
              Blank()
            } else {
              Blank()
              Column({ space: 4 }) {
                Text(msg.text)
                  .fontSize(15)
                  .fontColor('#FFFFFF')
                  .padding({ left: 18, right: 18, top: 14, bottom: 14 })
                  .borderRadius({ topLeft: 20, topRight: 4, bottomLeft: 20, bottomRight: 20 })
                  .linearGradient(Page1Theme.PRIMARY_GRADIENT)
                  .shadow({ radius: 16, color: '#2F6BFF4D', offsetX: 0, offsetY: 6 })
                  .constraintSize({ maxWidth: '80%' })
                Text(Page4UiLayer.formatTime(msg.tsMs))
                  .fontSize(11)
                  .fontColor(Page1Theme.TEXT_TERTIARY)
                  .margin({ right: 6 })
              }
              .alignItems(HorizontalAlign.End)
            }
          }
          .width('100%')
        }, (msg: AssistantMessage): string => msg.id)

        if (props.queryThinkingVisible) {
          Column({ space: 6 }) {
            Row() {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(Page1Theme.PRIMARY)
              Text(props.queryThinkingStageText)
                .fontSize(12)
                .fontColor(Page1Theme.TEXT_TERTIARY)
                .margin({ left: 8 })
              Blank()
              Text(queryThinkingPctText(props.queryThinkingProgressPct))
                .fontSize(11)
                .fontColor(Page1Theme.TEXT_TERTIARY)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width('100%')
                .height(6)
                .borderRadius(999)
                .backgroundColor('#162032')
              Row()
                .width(queryThinkingPctText(props.queryThinkingProgressPct))
                .height(6)
                .borderRadius(999)
                .linearGradient(Page1Theme.PRIMARY_GRADIENT)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 2, right: 2, top: 2, bottom: 2 })
        }
      }
      .width('100%')
      .padding({ top: 0, bottom: 32, left: 24, right: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .edgeEffect(EdgeEffect.None)
    .scrollBar(BarState.Off)
  }
  .width('100%')
  .layoutWeight(1)
}
