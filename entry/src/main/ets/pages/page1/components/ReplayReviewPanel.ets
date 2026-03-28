/**
 * 代码指南：
 * 文件： pages/page1/components/ReplayReviewPanel.ets
 * 用途： 避障/识别复盘入口面板（历史墙 + 单次详情）。
 */
import { Page1Theme } from '../Page1Theme'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'
import {
  ReplayDetectionBox,
  ReplaySession,
  ReplaySessionOrigin,
  ReplayTimelineItem,
  ReplayTriggerType
} from '../../../services/replay/ReplayModels'

export type ReplayReviewScope = 'all' | 'vision' | 'vision-page2'

@Component
export struct ReplayReviewPanel {
  @State private sessions: Array<ReplaySession> = []
  @State private selectedId: string = ''
  private timerId: number = -1
  onClose: () => void = () => {}
  scope: ReplayReviewScope = 'all'

  aboutToAppear(): void {
    this.refreshSessions()
    if (this.timerId >= 0) clearInterval(this.timerId)
    this.timerId = setInterval((): void => {
      this.refreshSessions()
    }, 1200) as number
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  build(): void {
    Column({ space: 12 }) {
      this.header()
      if (this.selectedId.length > 0) {
        this.detailView()
      } else {
        this.galleryView()
      }
    }
    .width('100%')
  }

  @Builder
  private header(): void {
    Row() {
      Text(this.selectedId.length > 0 ? '复盘详情' : '历史复盘')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Page1Theme.TEXT_PRIMARY)
      Blank()
      if (this.selectedId.length > 0) {
        Button('返回')
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(12)
          .backgroundColor('#EEF3FF')
          .fontColor(Page1Theme.PRIMARY)
          .fontSize(12)
          .onClick((): void => { this.selectedId = '' })
      }
      Button('关闭')
        .height(30)
        .padding({ left: 12, right: 12 })
        .borderRadius(12)
        .backgroundColor('#F1F5F9')
        .fontColor(Page1Theme.TEXT_SECONDARY)
        .fontSize(12)
        .margin({ left: 8 })
        .onClick((): void => { this.onClose() })
    }
    .width('100%')
  }

  @Builder
  private galleryView(): void {
    if (this.sessions.length <= 0) {
      Column() {
        Text('暂无复盘记录')
          .fontSize(14)
          .fontColor(Page1Theme.TEXT_TERTIARY)
      }
      .width('100%')
      .height(280)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#F8FAFC')
      .borderRadius(12)
    } else {
      Scroll() {
        Grid() {
          ForEach(this.sessions, (s: ReplaySession): void => {
            GridItem() {
              this.sessionCard(s)
            }
          }, (s: ReplaySession): string => s.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
      }
      .width('100%')
      .height(460)
      .edgeEffect(EdgeEffect.None)
      .scrollBar(BarState.Auto)
    }
  }

  @Builder
  private sessionCard(s: ReplaySession): void {
    Button() {
      Column({ space: 8 }) {
        if (s.coverImagePath.length > 0) {
          Image(s.coverImagePath)
            .width('100%')
            .height(120)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
        } else {
          Column() {
            Text('无截图')
              .fontSize(12)
              .fontColor(Page1Theme.TEXT_TERTIARY)
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F1F5F9')
          .borderRadius(10)
        }
        Text(s.title)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.formatTime(s.startAtMs)} | ${Math.round(s.durationMs / 1000)}s`)
          .fontSize(11)
          .fontColor(Page1Theme.TEXT_TERTIARY)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({ width: 1, color: '#E2E8F0' })
    .stateEffect(false)
    .onClick((): void => {
      this.selectedId = s.id
    })
  }

  @Builder
  private detailView(): void {
    if (!this.hasSelectedSession()) {
      Text('记录不存在')
        .fontSize(13)
        .fontColor(Page1Theme.TEXT_TERTIARY)
    } else {
      Scroll() {
        Column({ space: 12 }) {
          if (this.selectedCoverPath().length > 0) {
            Image(this.selectedCoverPath())
              .width('100%')
              .height(220)
              .objectFit(ImageFit.Contain)
              .backgroundColor('#000000')
              .borderRadius(10)
          }
          this.infoLine('触发类型', this.selectedTriggerType())
          this.infoLine('来源', this.selectedOriginText())
          this.infoLine('发生时间', this.selectedStartTimeText())
          this.infoLine('过程耗时', this.selectedDurationText())
          this.infoLine('截图数量', this.selectedSnapshotCountText())
          this.infoLine('路径变化', this.selectedPathChangeText())

          Text('框选目标')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_PRIMARY)
            .width('100%')
            .margin({ top: 8 })
          ForEach(this.selectedDetections(), (d: ReplayDetectionBox): void => {
            Text(
              `${d.label} ${(d.score * 100).toFixed(1)}% | x=${d.x.toFixed(3)} y=${d.y.toFixed(3)} w=${d.w.toFixed(3)} h=${d.h.toFixed(3)}`
            )
              .fontSize(12)
              .fontColor(Page1Theme.TEXT_SECONDARY)
              .width('100%')
              .padding({ top: 3, bottom: 3 })
          }, (d: ReplayDetectionBox, i: number): string => `${d.label}-${i}-${Math.round(d.score * 1000)}`)

          Text('动作记录')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_PRIMARY)
            .width('100%')
          ForEach(this.selectedActions(), (a: string): void => {
            Text(a)
              .fontSize(12)
              .fontColor(Page1Theme.TEXT_SECONDARY)
              .width('100%')
              .padding({ top: 4, bottom: 4 })
          }, (a: string, i: number): string => `${a}-${i}`)

          Text('时间线')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_PRIMARY)
            .width('100%')
            .margin({ top: 8 })
          ForEach(this.selectedTimeline(), (t: ReplayTimelineItem): void => {
            Text(`${this.formatTime(t.tsMs)} | ${t.kind} | ${t.text}`)
              .fontSize(12)
              .fontColor(Page1Theme.TEXT_SECONDARY)
              .width('100%')
              .padding({ top: 3, bottom: 3 })
          }, (t: ReplayTimelineItem, i: number): string => `${t.tsMs}-${i}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(480)
      .edgeEffect(EdgeEffect.None)
    }
  }

  @Builder
  private infoLine(label: string, value: string): void {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(Page1Theme.TEXT_TERTIARY)
      Blank()
      Text(value.length > 0 ? value : '-')
        .fontSize(12)
        .fontColor(Page1Theme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  private refreshSessions(): void {
    const allSessions: Array<ReplaySession> = replayArchiveService.listSessions()
    this.sessions = this.filterSessionsByScope(allSessions, this.scope)
    if (this.selectedId.length > 0 && !this.hasSelectedSession()) {
      this.selectedId = ''
    }
  }

  private filterSessionsByScope(sessions: Array<ReplaySession>, scope: ReplayReviewScope): Array<ReplaySession> {
    if (scope === 'all') return sessions

    const out: Array<ReplaySession> = []
    for (let i: number = 0; i < sessions.length; i++) {
      const one: ReplaySession = sessions[i]
      if (!this.isVisionSession(one.triggerType)) continue
      if (scope === 'vision-page2' && !this.isPage2VisionSession(one.origin)) continue
      out.push(one)
    }
    return out
  }

  private isPage2VisionSession(origin: ReplaySessionOrigin): boolean {
    if (origin === 'PAGE2') return true
    if (origin === 'GALLERY') return true
    return false
  }

  private isVisionSession(triggerType: ReplayTriggerType): boolean {
    return triggerType === 'VISION_YOLOV26BARRIER' || triggerType === 'TRAFFIC_LIGHT'
  }

  private selectedSession(): ReplaySession | undefined {
    if (this.selectedId.length <= 0) return undefined
    for (let i: number = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === this.selectedId) return this.sessions[i]
    }
    return undefined
  }

  private hasSelectedSession(): boolean {
    return this.selectedSession() !== undefined
  }

  private selectedCoverPath(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return ''
    return s.coverImagePath
  }

  private selectedTriggerType(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return '-'
    return s.triggerType
  }

  private selectedOriginText(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return '-'
    return s.origin
  }

  private selectedStartTimeText(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return '-'
    return this.formatTime(s.startAtMs)
  }

  private selectedDurationText(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return '-'
    return `${Math.round(s.durationMs / 1000)} 秒`
  }

  private selectedSnapshotCountText(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return '0'
    return `${s.snapshotPaths.length}`
  }

  private selectedPathChangeText(): string {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return '-'
    return `${s.oldPath.join('->')} => ${s.newPath.join('->')}`
  }

  private selectedDetections(): Array<ReplayDetectionBox> {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return []
    return s.detections
  }

  private selectedActions(): Array<string> {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return []
    return s.actions
  }

  private selectedTimeline(): Array<ReplayTimelineItem> {
    const s: ReplaySession | undefined = this.selectedSession()
    if (!s) return []
    return s.timeline
  }

  private formatTime(tsMs: number): string {
    const d: Date = new Date(tsMs)
    const y: number = d.getFullYear()
    const m: string = `${d.getMonth() + 1}`.padStart(2, '0')
    const day: string = `${d.getDate()}`.padStart(2, '0')
    const hh: string = `${d.getHours()}`.padStart(2, '0')
    const mm: string = `${d.getMinutes()}`.padStart(2, '0')
    const ss: string = `${d.getSeconds()}`.padStart(2, '0')
    return `${y}-${m}-${day} ${hh}:${mm}:${ss}`
  }
}

