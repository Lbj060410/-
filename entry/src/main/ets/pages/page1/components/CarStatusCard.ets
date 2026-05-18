/**
 * 代码指南：
 * 文件：pages/page1/components/CarStatusCard.ets
 * 用途：仅限 Page1 视觉组件（地图/状态/控制渲染）。
 * 何时修改：修改视图样式、控件或纯显示交互时。
 * 相关文件：状态来自 app/Page1UiStore.ets，动作路由到 app/Page1Coordinator.ets。
 */
// entry/src/main/ets/pages/page1/components/CarStatusCard.ets

import { page1Store, Page1UiStore, RiskLevel, CarConnState } from '../app/Page1UiStore'
import { PoseSource } from '../types/PoseTypes'
import { GridIdCodec, GridCoord } from '../app/PathPlannerAStar'
import { Page1Theme } from '../Page1Theme'
import { CARD_ACCENT, PATH_CARD, STATUS, CARD } from '../Page1Styles'

@Component
export struct CarStatusCard {
  @State private store: Page1UiStore = page1Store
  @State private speedText: string = '0'
  @State private headingText: string = '0°'
  @State private headingDir: string = 'N'
  @State private distanceText: string = '0'
  @State private lightText: string = '0'
  @State private renderTick: number = 0
  private syncTimerId: number = -1

  aboutToAppear(): void {
    this.refreshViewState()
    if (this.syncTimerId >= 0) clearInterval(this.syncTimerId)
    this.syncTimerId = setInterval((): void => {
      this.renderTick += 1
      this.refreshViewState()
    }, 120) as number
  }

  aboutToDisappear(): void {
    if (this.syncTimerId >= 0) {
      clearInterval(this.syncTimerId)
      this.syncTimerId = -1
    }
  }

  build() {
    Column({ space: 12 }) {
      Grid() {
        GridItem() { this.speedCard() }
        GridItem() { this.headingCard() }
        GridItem() { this.distanceCard() }
        GridItem() { this.lightCard() }
      }
      .columnsTemplate('1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .height(240) // 根据需要调整高度
      .width('100%')

      // 动作和队列卡片
      Column({ space: 8 }) {
        Text('路径节点队列')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .margin({ top: 4 })

        Text(this.pathText())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(PATH_CARD.TEXT_COLOR)
          .padding(PATH_CARD.PADDING)
          .backgroundColor(PATH_CARD.BG)
          .borderRadius(PATH_CARD.RADIUS)
          .width('100%')
          .border({ width: 1, color: PATH_CARD.BORDER_COLOR })

        Row() {
          Text('当前动作')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_TERTIARY)
          Blank()
          Text(this.store.actionText)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(STATUS.ACTION)
        }
        .width('100%')
        .padding({ top: 8 })
      }
      .width('100%')
      .padding(16)
      .borderRadius(Page1Theme.RADIUS_L)
      .backgroundColor(Page1Theme.CARD)
      .shadow({ radius: 24, color: '#0000000B', offsetX: 0, offsetY: 4 })
      .border({ width: 1, color: Page1Theme.BORDER })
    }
    .width('100%')
  }

  private refreshViewState(): void {
    this.speedText = `${this.store.metricSpeedCms}`

    if (this.store.realSendEnabled) {
      const showHeadingDeg: number =
        this.store.metricHeadingDeg !== 0 ? this.store.metricHeadingDeg : this.store.telemetry.headingDeg
      this.headingText = `${Math.round(showHeadingDeg)}°`
      this.headingDir = this.dirFromDeg(showHeadingDeg)
      this.distanceText = `${this.store.metricDistanceCm}`
      this.lightText = `${this.store.metricLightLux}`
    } else {
      this.headingText = `${Math.round(this.store.metricHeadingDeg)}°`
      this.headingDir = this.store.metricHeadingText
      this.distanceText = `${this.store.metricDistanceCm}`
      this.lightText = `${this.store.metricLightLux}`
    }
  }

  private dirFromDeg(v: number): string {
    let x: number = v % 360
    if (x < 0) x += 360
    const idx: number = Math.round(x / 45) % 8
    if (idx === 0) return 'N'
    if (idx === 1) return 'NE'
    if (idx === 2) return 'E'
    if (idx === 3) return 'SE'
    if (idx === 4) return 'S'
    if (idx === 5) return 'SW'
    if (idx === 6) return 'W'
    return 'NW'
  }

  @Builder
  private speedCard(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row().width('100%').height(CARD.ACCENT_HEIGHT).backgroundColor(CARD_ACCENT.SPEED).opacity(0.8)
          .borderRadius({ topLeft: 6, topRight: 6 })
          .position({ x: 0, y: 0 })

        Column() {
          Row() {
            Text('速度').fontSize(CARD.LABEL_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
            Blank()
            Stack() {
              Circle({ width: CARD.ICON_SIZE, height: CARD.ICON_SIZE }).fill(CARD_ACCENT.SPEED_BG)
              Text('•').fontColor(CARD_ACCENT.SPEED).fontSize(16)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Text(this.speedText).fontSize(CARD.VALUE_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
          Text('cm/s').fontSize(CARD.LABEL_FONT).fontColor(CARD.TEXT_COLOR).margin({ top: 4 })
        }
        .padding(CARD.PADDING)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CARD.BG)
      .borderRadius(CARD.RADIUS)
      .shadow({ radius: CARD.SHADOW.radius, color: CARD.SHADOW.color, offsetX: 0, offsetY: CARD.SHADOW.offsetY })
      .border({ width: 1, color: CARD.BG })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private headingCard(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row().width('100%').height(CARD.ACCENT_HEIGHT).backgroundColor(CARD_ACCENT.HEADING).opacity(0.8)
          .borderRadius({ topLeft: 6, topRight: 6 })
          .position({ x: 0, y: 0 })

        Column() {
          Row() {
            Text('方向').fontSize(CARD.LABEL_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
            Blank()
            Stack() {
              Circle({ width: CARD.ICON_SIZE, height: CARD.ICON_SIZE }).fill(CARD_ACCENT.HEADING_BG)
              Text('•').fontColor(CARD_ACCENT.HEADING).fontSize(16)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Text(this.headingText).fontSize(CARD.VALUE_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
          Text(this.headingDir).fontSize(CARD.LABEL_FONT).fontColor(CARD.TEXT_COLOR).margin({ top: 4 })
        }
        .padding(CARD.PADDING)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CARD.BG)
      .borderRadius(CARD.RADIUS)
      .shadow({ radius: CARD.SHADOW.radius, color: CARD.SHADOW.color, offsetX: 0, offsetY: CARD.SHADOW.offsetY })
      .border({ width: 1, color: CARD.BG })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private distanceCard(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row().width('100%').height(CARD.ACCENT_HEIGHT).backgroundColor(CARD_ACCENT.DISTANCE).opacity(0.8)
          .borderRadius({ topLeft: 6, topRight: 6 })
          .position({ x: 0, y: 0 })

        Column() {
          Row() {
            Text('距离').fontSize(CARD.LABEL_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
            Blank()
            Stack() {
              Circle({ width: CARD.ICON_SIZE, height: CARD.ICON_SIZE }).fill(CARD_ACCENT.DISTANCE_BG)
              Text('•').fontColor(CARD_ACCENT.DISTANCE).fontSize(16)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Text(this.distanceText).fontSize(CARD.VALUE_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
          Text('km').fontSize(CARD.LABEL_FONT).fontColor(CARD.TEXT_COLOR).margin({ top: 4 })
        }
        .padding(CARD.PADDING)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CARD.BG)
      .borderRadius(CARD.RADIUS)
      .shadow({ radius: CARD.SHADOW.radius, color: CARD.SHADOW.color, offsetX: 0, offsetY: CARD.SHADOW.offsetY })
      .border({ width: 1, color: CARD.BG })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private lightCard(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row().width('100%').height(CARD.ACCENT_HEIGHT).backgroundColor(CARD_ACCENT.LIGHT).opacity(0.8)
          .borderRadius({ topLeft: 6, topRight: 6 })
          .position({ x: 0, y: 0 })

        Column() {
          Row() {
            Text('光照强度').fontSize(CARD.LABEL_FONT).fontWeight(FontWeight.Bold).fontColor(CARD.TEXT_COLOR)
            Blank()
            Stack() {
              Circle({ width: CARD.ICON_SIZE, height: CARD.ICON_SIZE }).fill(CARD_ACCENT.LIGHT_BG)
              Text('•').fontColor(CARD_ACCENT.LIGHT).fontSize(16)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Text(this.lightText).fontSize(CARD.VALUE_FONT).fontWeight(FontWeight.Bold).fontColor(CARD_ACCENT.LIGHT)
          Text('lux').fontSize(CARD.LABEL_FONT).fontColor(CARD.TEXT_COLOR).margin({ top: 4 })
        }
        .padding(CARD.PADDING)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CARD.BG)
      .borderRadius(CARD.RADIUS)
      .shadow({ radius: CARD.SHADOW.radius, color: CARD.SHADOW.color, offsetX: 0, offsetY: CARD.SHADOW.offsetY })
      .border({ width: 1, color: CARD.BG })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }

  private poseText(): string {
    const x: string = this.store.pose.xNorm.toFixed(3)
    const y: string = this.store.pose.yNorm.toFixed(3)
    return `${x},${y}`
  }

  private confText(): string {
    return this.store.pose.confidence.toFixed(2)
  }

  private sourceText(): string {
    if (this.store.pose.source === PoseSource.RFID_CORRECT) return 'RFID'
    if (this.store.pose.source === PoseSource.DEAD_RECKONING) return 'DR'
    if (this.store.pose.source === PoseSource.MANUAL) return 'MANUAL'
    return 'INIT'
  }

  private pathText(): string {
    if (this.store.pathNodes.length === 0) return '—'
    const arr: Array<string> = []
    for (let i: number = 0; i < this.store.pathNodes.length; i++) {
      const n: string = this.store.pathNodes[i]
      if (i === this.store.pathIndex) arr.push(`[${n}]`)
      else arr.push(n)
    }
    return arr.join(' → ')
  }

  private followText(): string {
    const total: number = this.store.pathNodes.length
    if (total <= 1) return 'FOLLOW: —'

    const idx: number = this.store.pathIndex
    const curId: string = (idx >= 0 && idx < total) ? this.store.pathNodes[idx] : ''
    const nextId: string = (idx + 1 >= 0 && idx + 1 < total) ? this.store.pathNodes[idx + 1] : ''
    const dir: string = this.dirBetween(curId, nextId)

    const shownCur: string = (curId.length > 0) ? curId : '—'
    const shownNext: string = (nextId.length > 0) ? nextId : '—'
    const step: string = `${Math.min(idx + 1, total)}/${total}`

    return `FOLLOW: ${step} | cur=${shownCur} next=${shownNext} | dir=${dir}`
  }

  private dirBetween(fromId: string, toId: string): string {
    if (fromId.length === 0 || toId.length === 0) return '—'
    const a: GridCoord | undefined = GridIdCodec.parse(fromId)
    const b: GridCoord | undefined = GridIdCodec.parse(toId)
    if (!a || !b) return '—'

    const dx: number = b.col - a.col
    const dy: number = b.row - a.row

    if (dx === 1 && dy === 0) return 'RIGHT'
    if (dx === -1 && dy === 0) return 'LEFT'
    if (dx === 0 && dy === 1) return 'DOWN'
    if (dx === 0 && dy === -1) return 'UP'
    return '—'
  }

  private riskColor(): string {
    if (this.store.riskLevel === RiskLevel.DANGER) return '#FF3B30'
    if (this.store.riskLevel === RiskLevel.WARN) return '#FF9500'
    return '#34C759'
  }

  private connColor(): string {
    if (this.store.connState === CarConnState.CONNECTED) return '#34C759'
    if (this.store.connState === CarConnState.RECONNECTING) return '#FF9500'
    if (this.store.connState === CarConnState.FAILED) return '#FF3B30'
    return Page1Theme.TEXT_SECONDARY
  }
}
