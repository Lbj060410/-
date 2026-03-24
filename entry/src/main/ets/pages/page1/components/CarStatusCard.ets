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

@Component
export struct CarStatusCard {
  @State private store: Page1UiStore = page1Store

  build() {
    Column({ space: 12 }) {
      Grid() {
        GridItem() { this.telemetryCard('SPEED', `${this.store.telemetry.speed}`, 'cm/s', '#2F6BFF', '#EEF3FF') }
        GridItem() { this.telemetryCard('HEADING', `${this.store.telemetry.headingDeg}°`, 'NE', '#7C3AED', '#F3EEFF') }
        GridItem() { this.telemetryCard('DISTANCE', `${this.store.telemetry.ultraFrontCm}`, 'cm (front)', '#0891B2', '#ECFBFF') }
        GridItem() { this.telemetryCard('SENSORS', `${this.store.telemetry.lightLux}`, 'lux (light)', '#059669', '#ECFDF5') }
      }
      .columnsTemplate('1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .height(240) // 根据需要调整高度
      .width('100%')

      // 动作和队列卡片
      Column({ space: 8 }) {
        Text('PATH NODES QUEUE')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .margin({ top: 4 })

        Text(this.pathText())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
          .padding(12)
          .backgroundColor('#F8FAFC')
          .borderRadius(12)
          .width('100%')
          .border({ width: 1, color: Page1Theme.BORDER })

        Row() {
          Text('CURRENT ACTION')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_TERTIARY)
          Blank()
          Text(this.store.actionText)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.PRIMARY)
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

  @Builder
  private telemetryCard(label: string, value: string, unit: string, color: string, bg: string): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 顶部渐变强调线（使用细矩形或边框顶部模拟）
        Row().width('100%').height(2).backgroundColor(color).opacity(0.8)
          .borderRadius({ topLeft: Page1Theme.RADIUS_M, topRight: Page1Theme.RADIUS_M })
          .position({ x: 0, y: 0 })

        Column() {
          Row() {
            Text(label)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(Page1Theme.TEXT_TERTIARY)
            Blank()
            // 图标背景
            Stack() {
              Circle({ width: 32, height: 32 }).fill(bg)
              // 暂时使用文字图标代替
              Text('•').fontColor(color).fontSize(16)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Text(value)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(color === '#059669' ? '#059669' : Page1Theme.TEXT_PRIMARY)

          Text(unit)
            .fontSize(11)
            .fontColor(Page1Theme.TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .padding(16)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Page1Theme.CARD)
      .borderRadius(Page1Theme.RADIUS_L)
      .shadow({ radius: 24, color: '#0000000B', offsetX: 0, offsetY: 4 })
      .border({ width: 1, color: Page1Theme.BORDER })
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
