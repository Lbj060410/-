import { Page1Theme } from '../../page1/Page1Theme'
import {
  page2ReplayService,
  Page2ReplayService,
  Page2GalleryReplayItem,
  Page2ObstacleReplayItem
} from '../../../services/replay/Page2ReplayService'
import { BBoxNorm } from '../../../services/recognition/RecognitionResult'

type ReplayTab = 'obstacle' | 'gallery'
const OBSTACLE_REPLAY_LOOP_MS: number = 2000
const GALLERY_BOX_CANVAS_W: number = 320
const GALLERY_BOX_CANVAS_H: number = 250

interface ReplayOverlayBoxViewModel {
  key: string
  label: string
  score: number
  x: number
  y: number
  w: number
  h: number
}

interface Rect2d {
  x: number
  y: number
  w: number
  h: number
}

@Component
export struct Page2ReplayCenter {
  @State private service: Page2ReplayService = page2ReplayService
  @State private tab: ReplayTab = 'obstacle'
  @State private obstacleDetailId: string = ''
  @State private galleryDetailId: string = ''
  @State private playingIndex: number = 0
  @State private activeButtonIndex: number = -1
  private timerId: number = -1
  onClose: () => void = () => {}

  aboutToDisappear(): void {
    this.stopPlaying()
  }

  build(): void {
    Column({ space: 12 }) {
      this.buildHeader()
      if (this.inObstacleDetail()) {
        this.buildObstacleDetailContent()
      } else if (this.inGalleryDetail()) {
        this.buildGalleryDetailContent()
      } else {
        this.buildHistoryButtons()
      }
    }
    .width('100%')
  }

  @Builder
  private buildHeader(): void {
    Row() {
      Text('Replay Center')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Page1Theme.TEXT_PRIMARY)
      Blank()
      if (this.inObstacleDetail() || this.inGalleryDetail()) {
        Button('Close Detail')
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(12)
          .backgroundColor('#EEF3FF')
          .fontColor(Page1Theme.PRIMARY)
          .fontSize(12)
          .onClick((): void => {
            this.stopPlaying()
            this.obstacleDetailId = ''
            this.galleryDetailId = ''
          })
      }
      Button('Close')
        .height(30)
        .padding({ left: 12, right: 12 })
        .borderRadius(12)
        .backgroundColor('#F1F5F9')
        .fontColor(Page1Theme.TEXT_SECONDARY)
        .fontSize(12)
        .margin({ left: 8 })
        .onClick((): void => {
          this.stopPlaying()
          this.onClose()
        })
    }
    .width('100%')
  }

  @Builder
  private buildHistoryButtons(): void {
    Column({ space: 10 }) {
      this.buildTabSwitch()
      if (this.currentButtons().length <= 0) {
        Column() {
          Text('No replay records yet')
            .fontSize(13)
            .fontColor(Page1Theme.TEXT_TERTIARY)
        }
        .width('100%')
        .height(320)
        .justifyContent(FlexAlign.Center)
        .borderRadius(10)
        .backgroundColor('#F8FAFC')
      } else {
        Scroll() {
          Grid() {
            ForEach(this.currentButtons(), (name: string, idx: number): void => {
              GridItem() {
                Button(name)
                  .width('100%')
                  .height('100%')
                  .borderRadius(10)
                  .backgroundColor(this.activeButtonIndex === idx ? '#DBEAFE' : '#FFFFFF')
                  .fontColor(this.activeButtonIndex === idx ? '#1D4ED8' : Page1Theme.TEXT_PRIMARY)
                  .fontSize(11)
                  .border({ width: 1, color: this.activeButtonIndex === idx ? '#3B82F6' : '#E2E8F0' })
                  .onClick((): void => {
                    this.activeButtonIndex = idx
                    this.openDetailByIndex(idx)
                  })
              }
            }, (name: string, idx: number): string => `${name}-${idx}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .rowsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
        }
        .height(320)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .width('100%')
  }

  @Builder
  private buildTabSwitch(): void {
    Row({ space: 10 }) {
      this.tabBtn('Obstacle Replay', this.tab === 'obstacle', () => {
        this.tab = 'obstacle'
        this.activeButtonIndex = -1
      })
      this.tabBtn('Gallery Replay', this.tab === 'gallery', () => {
        this.tab = 'gallery'
        this.activeButtonIndex = -1
      })
    }
    .width('100%')
  }

  @Builder
  private tabBtn(text: string, active: boolean, onClick: () => void): void {
    Button(text)
      .layoutWeight(1)
      .height(36)
      .borderRadius(10)
      .backgroundColor(active ? '#2563EB' : '#FFFFFF')
      .fontColor(active ? '#FFFFFF' : '#111111')
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .border({ width: 1, color: active ? '#1D4ED8' : '#E2E8F0' })
      .onClick(onClick)
  }

  @Builder
  private buildObstacleDetailContent(): void {
    if (!this.hasSelectedObstacleItem()) {
      Text('Record not found').fontSize(13).fontColor(Page1Theme.TEXT_TERTIARY)
    } else {
      this.buildObstacleDetail(this.selectedObstacleItem() as Page2ObstacleReplayItem)
    }
  }

  @Builder
  private buildObstacleDetail(item: Page2ObstacleReplayItem): void {
    Row({ space: 10 }) {
      Column() {
        if (item.clipFrameRefs.length > 0) {
          Image(item.clipFrameRefs[this.playingFrameIndex(item)])
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .backgroundColor('#000000')
        } else {
          Column() {
            Text('No 2s clip')
              .fontSize(13)
              .fontColor(Page1Theme.TEXT_TERTIARY)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        }
      }
      .width('65%')
      .height(520)
      .borderRadius(10)
      .clip(true)
      .backgroundColor('#0B1220')

      Column({ space: 8 }) {
        this.detailLine('Time', this.formatTime(item.tsMs))
        this.detailLine('Type', item.triggerType)
        this.detailLine('Decision', item.decisionText)
        Text('Recognition Summary')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 6 })
        Text(item.resultText)
          .fontSize(12)
          .fontColor(Page1Theme.TEXT_SECONDARY)
          .width('100%')
        if (item.decisionImageRef.length > 0) {
          Text('Decision Frame')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Page1Theme.TEXT_PRIMARY)
            .width('100%')
            .margin({ top: 6 })
          Image(item.decisionImageRef)
            .width('100%')
            .height(180)
            .objectFit(ImageFit.Contain)
            .backgroundColor('#F8FAFC')
            .borderRadius(8)
        }
      }
      .width('35%')
      .height(520)
      .padding(8)
      .backgroundColor('#FFFFFF')
      .borderRadius(10)
    }
    .width('100%')
  }

  @Builder
  private buildGalleryDetailContent(): void {
    if (!this.hasSelectedGalleryItem()) {
      Text('Record not found').fontSize(13).fontColor(Page1Theme.TEXT_TERTIARY)
    } else {
      this.buildGalleryDetail(this.selectedGalleryItem() as Page2GalleryReplayItem)
    }
  }

  @Builder
  private buildGalleryDetail(item: Page2GalleryReplayItem): void {
    Row({ space: 10 }) {
      Column({ space: 8 }) {
        Text('Original')
          .fontSize(12)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .width('100%')
        Image(item.originalImageRef)
          .width(GALLERY_BOX_CANVAS_W)
          .height(GALLERY_BOX_CANVAS_H)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#F8FAFC')
          .borderRadius(8)
        Text('Box Overlay')
          .fontSize(12)
          .fontColor(Page1Theme.TEXT_TERTIARY)
          .width('100%')
        this.buildGalleryOverlay(item)
      }
      .width('50%')
      .height(540)

      Column({ space: 10 }) {
        this.detailLine('Time', this.formatTime(item.tsMs))
        this.detailLine('Button', item.buttonName)
        Text('Recognition Result')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
          .width('100%')
        Text(item.resultText)
          .fontSize(12)
          .fontColor(Page1Theme.TEXT_SECONDARY)
          .width('100%')
      }
      .width('50%')
      .height(540)
      .padding(8)
      .backgroundColor('#FFFFFF')
      .borderRadius(10)
    }
    .width('100%')
  }

  @Builder
  private buildGalleryOverlay(item: Page2GalleryReplayItem): void {
    if (item.originalImageRef.length <= 0) {
      Column() {
        Text('No image').fontSize(12).fontColor(Page1Theme.TEXT_TERTIARY)
      }
      .width('100%').height(250).justifyContent(FlexAlign.Center)
      .backgroundColor('#F8FAFC').borderRadius(8)
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(item.originalImageRef)
          .width(GALLERY_BOX_CANVAS_W)
          .height(GALLERY_BOX_CANVAS_H)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#F8FAFC')
          .borderRadius(8)

        ForEach(this.overlayBoxes(item), (box: ReplayOverlayBoxViewModel, idx: number): void => {
          Column() {}
            .width(Math.max(1, Math.round(box.w)))
            .height(Math.max(1, Math.round(box.h)))
            .border({ width: 2, color: '#22C55E' })
            .backgroundColor('#00000000')
            .position({
              x: Math.round(box.x),
              y: Math.round(box.y)
            })
        }, (box: ReplayOverlayBoxViewModel, idx: number): string => box.key)
      }
      .width(GALLERY_BOX_CANVAS_W)
      .height(GALLERY_BOX_CANVAS_H)
      .backgroundColor('#F8FAFC')
      .borderRadius(8)
      .clip(true)
    }
  }

  private overlayBoxes(item: Page2GalleryReplayItem): Array<ReplayOverlayBoxViewModel> {
    const out: Array<ReplayOverlayBoxViewModel> = []
    const src: Array<BBoxNorm> = Array.isArray(item.boxes) ? item.boxes : []
    const srcW: number = item.imageWidth > 0 ? item.imageWidth : GALLERY_BOX_CANVAS_W
    const srcH: number = item.imageHeight > 0 ? item.imageHeight : GALLERY_BOX_CANVAS_H
    const contentRect: Rect2d = this.computeContainRect(GALLERY_BOX_CANVAS_W, GALLERY_BOX_CANVAS_H, srcW, srcH)
    for (let i: number = 0; i < src.length; i++) {
      const b: BBoxNorm = src[i]
      const srcRect: Rect2d | undefined = this.toSourcePixelRectLikePage2(b, srcW, srcH)
      if (!srcRect) continue
      const drawX: number = contentRect.x + (srcRect.x / srcW) * contentRect.w
      const drawY: number = contentRect.y + (srcRect.y / srcH) * contentRect.h
      const drawW: number = (srcRect.w / srcW) * contentRect.w
      const drawH: number = (srcRect.h / srcH) * contentRect.h
      if (drawW < 2 || drawH < 2) continue
      out.push({
        key: `${b.label}-${i}-${Math.round(b.score * 1000)}`,
        label: b.label,
        score: b.score,
        x: drawX,
        y: drawY,
        w: drawW,
        h: drawH
      })
      if (out.length >= 12) break
    }
    return out
  }

  // Keep this mapping aligned with Page2View.toSourcePixelRect behavior.
  private toSourcePixelRectLikePage2(box: BBoxNorm, srcW: number, srcH: number): { x: number, y: number, w: number, h: number } | undefined {
    const maybeNormalized: boolean = box.w <= 1.0 && box.h <= 1.0
    const rawX: number = maybeNormalized ? box.x * srcW : box.x
    const rawY: number = maybeNormalized ? box.y * srcH : box.y
    const rawW: number = maybeNormalized ? box.w * srcW : box.w
    const rawH: number = maybeNormalized ? box.h * srcH : box.h

    let x0: number = Math.max(0, Math.min(rawX, srcW))
    let y0: number = Math.max(0, Math.min(rawY, srcH))
    let x1: number = Math.max(0, Math.min(rawX + rawW, srcW))
    let y1: number = Math.max(0, Math.min(rawY + rawH, srcH))

    if (x1 <= x0 || y1 <= y0) {
      // Fallback for corner-format (x1,y1,x2,y2)
      x0 = Math.max(0, Math.min(Math.min(rawX, rawW), srcW))
      y0 = Math.max(0, Math.min(Math.min(rawY, rawH), srcH))
      x1 = Math.max(0, Math.min(Math.max(rawX, rawW), srcW))
      y1 = Math.max(0, Math.min(Math.max(rawY, rawH), srcH))
      if (x1 <= x0 || y1 <= y0) return undefined
    }

    return {
      x: x0,
      y: y0,
      w: x1 - x0,
      h: y1 - y0
    }
  }

  private computeContainRect(viewW: number, viewH: number, srcW: number, srcH: number): Rect2d {
    const scale: number = Math.min(viewW / srcW, viewH / srcH)
    const w: number = srcW * scale
    const h: number = srcH * scale
    return {
      x: (viewW - w) * 0.5,
      y: (viewH - h) * 0.5,
      w,
      h
    }
  }

  @Builder
  private detailLine(label: string, value: string): void {
    Row() {
      Text(label).fontSize(12).fontColor(Page1Theme.TEXT_TERTIARY)
      Blank()
      Text(value).fontSize(12).fontColor(Page1Theme.TEXT_PRIMARY).maxLines(1)
    }
    .width('100%')
  }

  private currentButtons(): Array<string> {
    const out: Array<string> = []
    if (this.tab === 'obstacle') {
      const src: Array<Page2ObstacleReplayItem> = this.service.obstacleItems
      const count: number = Math.min(20, src.length)
      for (let i: number = 0; i < count; i++) out.push(src[i].buttonName)
      return out
    }
    const src: Array<Page2GalleryReplayItem> = this.service.galleryItems
    const count: number = Math.min(20, src.length)
    for (let i: number = 0; i < count; i++) out.push(src[i].buttonName)
    return out
  }

  private openDetailByIndex(index: number): void {
    if (this.tab === 'obstacle') {
      const item: Page2ObstacleReplayItem | undefined = this.service.obstacleItems[index]
      if (!item) return
      this.galleryDetailId = ''
      this.obstacleDetailId = item.id
      this.playingIndex = 0
      this.startPlaying()
      return
    }
    const item: Page2GalleryReplayItem | undefined = this.service.galleryItems[index]
    if (!item) return
    this.stopPlaying()
    this.obstacleDetailId = ''
    this.galleryDetailId = item.id
  }

  private inObstacleDetail(): boolean {
    return this.obstacleDetailId.length > 0
  }

  private inGalleryDetail(): boolean {
    return this.galleryDetailId.length > 0
  }

  private selectedObstacleItem(): Page2ObstacleReplayItem | undefined {
    if (this.obstacleDetailId.length <= 0) return undefined
    const src: Array<Page2ObstacleReplayItem> = this.service.obstacleItems
    for (let i: number = 0; i < src.length; i++) {
      if (src[i].id === this.obstacleDetailId) return src[i]
    }
    return undefined
  }

  private hasSelectedObstacleItem(): boolean {
    return this.selectedObstacleItem() !== undefined
  }

  private selectedGalleryItem(): Page2GalleryReplayItem | undefined {
    if (this.galleryDetailId.length <= 0) return undefined
    const src: Array<Page2GalleryReplayItem> = this.service.galleryItems
    for (let i: number = 0; i < src.length; i++) {
      if (src[i].id === this.galleryDetailId) return src[i]
    }
    return undefined
  }

  private hasSelectedGalleryItem(): boolean {
    return this.selectedGalleryItem() !== undefined
  }

  private startPlaying(): void {
    if (this.timerId >= 0) clearInterval(this.timerId)
    const item: Page2ObstacleReplayItem | undefined = this.selectedObstacleItem()
    const frameCount: number = item ? item.clipFrameRefs.length : 0
    const stepMs: number = frameCount > 0
      ? Math.max(60, Math.round(OBSTACLE_REPLAY_LOOP_MS / frameCount))
      : 160
    this.timerId = setInterval((): void => {
      const item: Page2ObstacleReplayItem | undefined = this.selectedObstacleItem()
      if (!item || item.clipFrameRefs.length <= 0) return
      this.playingIndex = (this.playingIndex + 1) % item.clipFrameRefs.length
    }, stepMs) as number
  }

  private stopPlaying(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private playingFrameIndex(item: Page2ObstacleReplayItem): number {
    if (item.clipFrameRefs.length <= 0) return 0
    const idx: number = this.playingIndex % item.clipFrameRefs.length
    return idx < 0 ? 0 : idx
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
