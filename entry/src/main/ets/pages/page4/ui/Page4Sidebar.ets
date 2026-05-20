import { Page1Theme } from '../../page1/Page1Theme'
import { HistorySession } from '../modules/Page4SessionModule'
import { PAGE4_BUTTON, PAGE4_PANEL, page4BtnBg, page4BtnBorder, page4BtnFg } from '../Page4Styles'

export interface Page4SidebarProps {
  historyTitles: Array<string>
  historySessions: Array<HistorySession>
  onOpenHistory: (session: HistorySession) => void
}

@Builder
export function Page4Sidebar(props: Page4SidebarProps): void {
  Column() {
    Row({ space: 12 }) {
      Stack() {
        Circle({ width: 40, height: 40 }).fill('rgba(0, 245, 212, 0.16)')
        Text('WPW')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
      }
      Column() {
        Text('智能助理')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
        Text('随时待命')
          .fontSize(12)
          .fontColor(Page1Theme.SUCCESS)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 40, left: 24, right: 24, bottom: 20 })

    Column() {
      Text('历史记录')
        .fontSize(12)
        .fontColor(Page1Theme.TEXT_TERTIARY)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, bottom: 12 })
      Scroll() {
        Column({ space: 8 }) {
          ForEach(props.historyTitles, (title: string, index: number) => {
            Button() {
              Text(title)
                .fontSize(13)
                .fontColor(page4BtnFg(false))
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(PAGE4_BUTTON.HEIGHT_MD)
            .padding({ left: 14, right: 14 })
            .backgroundColor(page4BtnBg(false))
            .borderRadius(PAGE4_BUTTON.RADIUS)
            .border({ width: 1, color: page4BtnBorder(false) })
            .stateEffect(false)
            .onClick((): void => {
              if (index >= props.historySessions.length) return
              props.onOpenHistory(props.historySessions[index])
            })
          }, (title: string, index: number): string => `${title}-${index}`)
        }
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }
  .width('30%')
  .height('100%')
  .backgroundColor(PAGE4_PANEL.SIDEBAR_BG)
  .border({ width: { right: 1 }, color: PAGE4_PANEL.SIDEBAR_BORDER })
  .transition({ type: TransitionType.All, translate: { x: -200 }, opacity: 0 })
}
