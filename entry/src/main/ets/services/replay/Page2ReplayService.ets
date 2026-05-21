import fs from '@ohos.file.fs'
import image from '@ohos.multimedia.image'
import mediaLibrary from '@ohos.multimedia.mediaLibrary'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'
import hilog from '@ohos.hilog'
import { videoStore } from '../../state/VideoStore'
import { BBoxNorm, RecognitionResult } from '../recognition/RecognitionResult'
import { RecognitionSubtype } from '../recognition/RecognitionTask'

export interface Page2ObstacleReplayItem {
  id: string
  tsMs: number
  triggerType: 'SHIGONG' | 'ULTRASONIC_01' | 'VISION' | 'OBSTACLE_EDGE'
  buttonName: string
  resultText: string
  decisionText: string
  decisionImageRef: string
  clipFrameRefs: Array<string>
}

export interface Page2GalleryReplayItem {
  id: string
  tsMs: number
  buttonName: string
  resultText: string
  originalImageRef: string
  boxedImageRef: string
  boxes: Array<BBoxNorm>
  imageWidth: number
  imageHeight: number
}

interface FrameClipBufferItem {
  tsMs: number
  jpeg: ArrayBuffer
}

const PAGE2_REPLAY_DIR: string = '/data/storage/el2/base/haps/entry/files/page2_replay'
const MAX_OBSTACLE_ITEMS: number = 20
const MAX_GALLERY_ITEMS: number = 20
const MAX_OBSTACLE_ITEMS_PER_TYPE: number = 3
const MAX_GALLERY_ITEMS_PER_TYPE: number = 3
const MAX_FRAME_BUFFER: number = 20
const FRAME_SAMPLE_INTERVAL_MS: number = 200
const SHIGONG_COOLDOWN_MS: number = 1400
const LOG_DOMAIN: number = 0xFF21
const LOG_TAG: string = 'Page2ReplaySvc'

@Observed
export class Page2ReplayService {
  obstacleItems: Array<Page2ObstacleReplayItem> = []
  galleryItems: Array<Page2GalleryReplayItem> = []

  private frameBuffer: Array<FrameClipBufferItem> = []
  private seq: number = 0
  private lastFrameSampleAtMs: number = 0
  private lastShigongTaskId: string = ''
  private lastShigongAtMs: number = 0
  private lastUltrasonicAtMs: number = 0
  private lastTrafficSignalAtMs: number = 0
  private lastTrafficReplayTaskId: string = ''
  private lastTrafficReplayColor: string = ''
  private lastTrafficReplayAtMs: number = 0
  private lastVisionTaskId: string = ''
  private lastVisionAtMs: number = 0

  ingestFrameJpeg(jpeg: ArrayBuffer, tsMs: number): void {
    if (!jpeg || jpeg.byteLength <= 0) return
    if (tsMs - this.lastFrameSampleAtMs < FRAME_SAMPLE_INTERVAL_MS) return
    this.lastFrameSampleAtMs = tsMs

    const bytes: Uint8Array = new Uint8Array(jpeg)
    const copied: Uint8Array = new Uint8Array(bytes.length)
    copied.set(bytes)

    this.frameBuffer.push({ tsMs, jpeg: copied.buffer })
    if (this.frameBuffer.length > MAX_FRAME_BUFFER) {
      this.frameBuffer.splice(0, this.frameBuffer.length - MAX_FRAME_BUFFER)
    }
  }

  async onShigongRecognition(result: RecognitionResult): Promise<void> {
    if (!this.containsShigong(result)) return
    const nowMs: number = Date.now()
    if (result.taskId.length > 0 && result.taskId === this.lastShigongTaskId) return
    if (nowMs - this.lastShigongAtMs < SHIGONG_COOLDOWN_MS) return
    this.lastShigongTaskId = result.taskId
    this.lastShigongAtMs = nowMs

    const id: string = this.nextId('obs')
    const clipFrameRefs: Array<string> = await this.saveRecentClipFrames(id, 2000)
    const decisionImageRef: string = await this.saveDecisionImage(id, 'shigong')
    this.pushObstacle({
      id,
      tsMs: nowMs,
      triggerType: 'SHIGONG',
      buttonName: 'Shigong Emergency Stop',
      resultText: this.formatResultText(result),
      decisionText: 'Emergency stop and obstacle handling triggered',
      decisionImageRef,
      clipFrameRefs
    })
  }

  async onUltrasonicObstacleSignal(note: string): Promise<void> {
    const nowMs: number = Date.now()
    if (nowMs - this.lastUltrasonicAtMs < 1000) return
    this.lastUltrasonicAtMs = nowMs

    const id: string = this.nextId('obs')
    const clipFrameRefs: Array<string> = await this.saveRecentClipFrames(id, 2000)
    const decisionImageRef: string = await this.saveDecisionImage(id, 'ultrasonic01')
    this.pushObstacle({
      id,
      tsMs: nowMs,
      triggerType: 'ULTRASONIC_01',
      buttonName: '0x01 Obstacle Emergency Stop',
      resultText: note.length > 0 ? note : 'Received obstacle signal 0x01',
      decisionText: 'Emergency stop, waiting for obstacle flow/replan',
      decisionImageRef,
      clipFrameRefs
    })
  }

  async onObstacleEdgeDetected(fromId: string, toId: string): Promise<void> {
    const nowMs: number = Date.now()
    const from: string = fromId.trim().toUpperCase()
    const to: string = toId.trim().toUpperCase()
    if (from.length <= 0 || to.length <= 0) return

    const id: string = this.nextId('obs')
    const clipFrameRefs: Array<string> = await this.saveRecentClipFrames(id, 2000)
    const decisionImageRef: string = await this.saveDecisionImage(id, 'obstacle_edge')
    this.pushObstacle({
      id,
      tsMs: nowMs,
      triggerType: 'OBSTACLE_EDGE',
      buttonName: `Obstacle Edge: ${from}|${to}`,
      resultText: '路段障碍',
      decisionText: '路段障碍上报，已标记并触发重规划',
      decisionImageRef,
      clipFrameRefs
    })
  }

  async onTrafficLightSignal(note: string): Promise<void> {
    const nowMs: number = Date.now()
    if (nowMs - this.lastTrafficSignalAtMs < 1000) return
    this.lastTrafficSignalAtMs = nowMs

    const id: string = this.nextId('obs')
    const clipFrameRefs: Array<string> = await this.saveRecentClipFrames(id, 2000)
    const decisionImageRef: string = await this.saveDecisionImage(id, 'traffic_signal_06')
    this.pushObstacle({
      id,
      tsMs: nowMs,
      triggerType: 'VISION',
      buttonName: 'Traffic Signal 0x06',
      resultText: note.length > 0 ? note : '收到 0x06 交通灯识别触发',
      decisionText: '收到0x06，已触发交通灯识别并截取画面',
      decisionImageRef,
      clipFrameRefs
    })
  }

  async onTrafficLightRecognition(result: RecognitionResult): Promise<void> {
    if (!result.ok || result.subtype !== RecognitionSubtype.TRAFFIC_LIGHT || result.boxes.length <= 0) return
    const color: string = this.pickTrafficLightColor(result)
    if (color !== 'red' && color !== 'green') return

    const nowMs: number = Date.now()
    if (result.taskId.length > 0 &&
      result.taskId === this.lastTrafficReplayTaskId &&
      color === this.lastTrafficReplayColor) return
    if (color === this.lastTrafficReplayColor && nowMs - this.lastTrafficReplayAtMs < 1500) return

    this.lastTrafficReplayTaskId = result.taskId
    this.lastTrafficReplayColor = color
    this.lastTrafficReplayAtMs = nowMs

    const id: string = this.nextId('obs')
    const clipFrameRefs: Array<string> = await this.saveRecentClipFrames(id, 2000)
    const decisionImageRef: string = await this.saveDecisionImage(id, `traffic_${color}`)
    const colorText: string = color === 'red' ? 'Red' : 'Green'
    this.pushObstacle({
      id,
      tsMs: nowMs,
      triggerType: 'VISION',
      buttonName: `Traffic ${colorText}`,
      resultText: this.formatResultText(result),
      decisionText: `${colorText} traffic light recognized`,
      decisionImageRef,
      clipFrameRefs
    })
  }

  async onVisionObstacleDetected(result: RecognitionResult): Promise<void> {
    if (!result.ok || result.boxes.length <= 0) return
    if (result.subtype !== RecognitionSubtype.YOLOV26BARRIER && result.subtype !== RecognitionSubtype.TRAFFIC_LIGHT) return
    const nowMs: number = Date.now()
    if (result.taskId.length > 0 && result.taskId === this.lastVisionTaskId) return
    if (nowMs - this.lastVisionAtMs < 1600) return
    this.lastVisionTaskId = result.taskId
    this.lastVisionAtMs = nowMs

    const id: string = this.nextId('obs')
    const clipFrameRefs: Array<string> = await this.saveRecentClipFrames(id, 2000)
    const decisionImageRef: string = await this.saveDecisionImage(id, 'vision')
    this.pushObstacle({
      id,
      tsMs: nowMs,
      triggerType: 'VISION',
      buttonName: this.galleryButtonName(result),
      resultText: this.formatResultText(result),
      decisionText: 'Vision trigger snapshot and obstacle handling',
      decisionImageRef,
      clipFrameRefs
    })
  }

  async onGalleryRecognition(originalPm: image.PixelMap, result: RecognitionResult): Promise<void> {
    const id: string = this.nextId('gal')
    const originalImageRef: string = await this.savePixelMapReference(originalPm, `${id}_origin`, false)
    let imgW: number = 0
    let imgH: number = 0
    try {
      const info: image.ImageInfo = await originalPm.getImageInfo()
      imgW = Math.max(0, info.size.width)
      imgH = Math.max(0, info.size.height)
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '读取原图尺寸失败: %{public}s',
        e instanceof Error ? e.message : String(e))
    }
    const boxes: Array<BBoxNorm> = await this.cloneBoxesForReplay(result, imgW, imgH)
    this.pushGallery({
      id,
      tsMs: Date.now(),
      buttonName: this.galleryButtonName(result),
      resultText: this.formatResultText(result),
      originalImageRef,
      boxedImageRef: originalImageRef,
      boxes,
      imageWidth: imgW,
      imageHeight: imgH
    })
  }

  async onGalleryRecognitionFromSnapshot(result: RecognitionResult): Promise<void> {
    const pm: image.PixelMap | undefined = videoStore.snapshotPixelMap
    if (!pm) {
      this.pushGallery({
        id: this.nextId('gal'),
        tsMs: Date.now(),
        buttonName: this.galleryButtonName(result),
        resultText: this.formatResultText(result),
        originalImageRef: '',
        boxedImageRef: '',
        boxes: await this.cloneBoxesForReplay(result, 0, 0),
        imageWidth: 0,
        imageHeight: 0
      })
      return
    }
    await this.onGalleryRecognition(pm, result)
  }

  async onGalleryRecognitionFromUri(selectedUri: string, result: RecognitionResult): Promise<void> {
    const id: string = this.nextId('gal')
    const boxedImageRef: string = selectedUri
    let imgW: number = 0
    let imgH: number = 0
    let pm: image.PixelMap | undefined = videoStore.snapshotPixelMap
    if (!pm) {
      pm = await this.loadPixelMapFromUriSafe(selectedUri)
    }
    if (pm) {
      try {
        const info: image.ImageInfo = await pm.getImageInfo()
        imgW = Math.max(0, info.size.width)
        imgH = Math.max(0, info.size.height)
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '读取选图尺寸失败: %{public}s',
          e instanceof Error ? e.message : String(e))
      }
      if (pm !== videoStore.snapshotPixelMap) {
        try { pm.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
    }
    const boxes: Array<BBoxNorm> = await this.cloneBoxesForReplay(result, imgW, imgH)
    this.pushGallery({
      id,
      tsMs: Date.now(),
      buttonName: this.galleryButtonName(result),
      resultText: this.formatResultText(result),
      originalImageRef: selectedUri,
      boxedImageRef,
      boxes,
      imageWidth: imgW,
      imageHeight: imgH
    })
  }

  private async cloneBoxesForReplay(result: RecognitionResult, imgW: number, imgH: number): Promise<Array<BBoxNorm>> {
    void imgW
    void imgH
    const out: Array<BBoxNorm> = []
    const src: Array<BBoxNorm> = Array.isArray(result.boxes) ? result.boxes : []
    for (let i: number = 0; i < src.length; i++) {
      const one: BBoxNorm = src[i]
      out.push({
        x: one.x,
        y: one.y,
        w: one.w,
        h: one.h,
        score: one.score,
        label: one.label
      })
    }
    return out
  }

  private async loadPixelMapFromUriSafe(uri: string): Promise<image.PixelMap | undefined> {
    const one: string = uri.trim()
    if (one.length <= 0) return undefined
    const candidates: Array<string> = []
    const pushUnique = (s: string): void => {
      const v: string = s.trim()
      if (v.length <= 0) return
      for (let i: number = 0; i < candidates.length; i++) {
        if (candidates[i] === v) return
      }
      candidates.push(v)
    }
    pushUnique(one)
    try { pushUnique(decodeURIComponent(one)) } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '解析URI解码候选失败: %{public}s',
        e instanceof Error ? e.message : String(e))
    }
    if (one.toLowerCase().startsWith('file://')) {
      const pathRaw: string = one.substring('file://'.length)
      pushUnique(pathRaw)
      try { pushUnique(decodeURIComponent(pathRaw)) } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '解析file URI解码候选失败: %{public}s',
          e instanceof Error ? e.message : String(e))
      }
    }

    for (let i: number = 0; i < candidates.length; i++) {
      let src: image.ImageSource | undefined = undefined
      try {
        src = image.createImageSource(candidates[i])
        if (!src) continue
        return await src.createPixelMap()
      } catch (e) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '从URI候选创建PixelMap失败 candidate=%{public}s: %{public}s',
          candidates[i], e instanceof Error ? e.message : String(e))
      } finally {
        if (src) {
          try { src.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
        }
      }
    }
    return undefined
  }

  async archiveOriginalSnapshotToGallery(pm: image.PixelMap, key: string): Promise<string> {
    return await this.savePixelMapReference(pm, `live_${key}`, true)
  }

  private pushObstacle(item: Page2ObstacleReplayItem): void {
    const next: Array<Page2ObstacleReplayItem> = [item]
    let sameTypeCount: number = 1
    const bucket: string = this.obstacleBucket(item)
    const cap: number = this.obstacleCapForBucket(bucket)
    for (let i: number = 0; i < this.obstacleItems.length; i++) {
      const oldItem: Page2ObstacleReplayItem = this.obstacleItems[i]
      if (this.obstacleBucket(oldItem) === bucket) {
        if (sameTypeCount >= cap) {
          this.recycleObstacleItem(oldItem)
          continue
        }
        sameTypeCount += 1
      }
      next.push(oldItem)
    }

    if (next.length > MAX_OBSTACLE_ITEMS) {
      for (let i: number = MAX_OBSTACLE_ITEMS; i < next.length; i++) {
        this.recycleObstacleItem(next[i])
      }
      next.splice(MAX_OBSTACLE_ITEMS, next.length - MAX_OBSTACLE_ITEMS)
    }
    this.obstacleItems = next
  }

  private pushGallery(item: Page2GalleryReplayItem): void {
    const next: Array<Page2GalleryReplayItem> = [item]
    let sameTypeCount: number = 1
    const cap: number = this.galleryCap()
    for (let i: number = 0; i < this.galleryItems.length; i++) {
      const oldItem: Page2GalleryReplayItem = this.galleryItems[i]
      if (oldItem.buttonName === item.buttonName) {
        if (sameTypeCount >= cap) {
          continue
        }
        sameTypeCount += 1
      }
      next.push(oldItem)
      if (next.length >= MAX_GALLERY_ITEMS) break
    }
    this.galleryItems = next
  }

  private nextId(prefix: string): string {
    this.seq += 1
    return `${prefix}-${Date.now()}-${this.seq}`
  }

  private obstacleCap(): number {
    return MAX_OBSTACLE_ITEMS_PER_TYPE
  }

  private obstacleCapForBucket(bucket: string): number {
    if (bucket === 'TRAFFIC_RED' || bucket === 'TRAFFIC_GREEN') return 1
    return this.obstacleCap()
  }

  private galleryCap(): number {
    return MAX_GALLERY_ITEMS_PER_TYPE
  }

  private obstacleBucket(item: Page2ObstacleReplayItem): string {
    if (item.triggerType === 'ULTRASONIC_01') return 'ULTRASONIC_01'
    if (item.buttonName === 'Traffic Red') return 'TRAFFIC_RED'
    if (item.buttonName === 'Traffic Green') return 'TRAFFIC_GREEN'
    return 'VISION_OBSTACLE'
  }

  private recycleObstacleItem(item: Page2ObstacleReplayItem): void {
    this.tryDeleteLocalRef(item.decisionImageRef)
    for (let i: number = 0; i < item.clipFrameRefs.length; i++) {
      this.tryDeleteLocalRef(item.clipFrameRefs[i])
    }
  }

  private tryDeleteLocalRef(ref: string): void {
    const path: string = ref.trim()
    if (path.length <= 0) return
    if (!path.startsWith(PAGE2_REPLAY_DIR)) return
    try { fs.unlinkSync(path) } catch (_) { /* 资源释放失败可安全忽略 */ }
  }

  private containsShigong(result: RecognitionResult): boolean {
    if (!result.ok || result.boxes.length <= 0) return false
    for (let i: number = 0; i < result.boxes.length; i++) {
      const key: string = result.boxes[i].label.trim().toLowerCase()
      if (key === 'shigong' || key.indexOf('shigong') >= 0 || result.boxes[i].label.indexOf('鏂藉伐') >= 0) {
        return true
      }
    }
    return false
  }

  private formatResultText(result: RecognitionResult): string {
    if (!result.ok || result.boxes.length <= 0) {
      const err: string = (result.errorText ?? '').trim()
      return err.length > 0 ? `Failed: ${err}` : 'Failed: No target'
    }
    const topN: number = Math.min(5, result.boxes.length)
    const out: Array<string> = []
    for (let i: number = 0; i < topN; i++) {
      const one: BBoxNorm = result.boxes[i]
      const xywh: string = `(${one.x.toFixed(3)}, ${one.y.toFixed(3)}, ${one.w.toFixed(3)}, ${one.h.toFixed(3)})`
      out.push(`${one.label} ${(Math.max(0, one.score) * 100).toFixed(1)}% ${xywh}`)
    }
    return out.join('\n')
  }

  private pickTrafficLightColor(result: RecognitionResult): string {
    let bestLabel: string = ''
    let bestScore: number = -1
    for (let i: number = 0; i < result.boxes.length; i++) {
      const one: BBoxNorm = result.boxes[i]
      const label: string = one.label.trim().toLowerCase()
      if (label !== 'red' && label !== 'green' && label !== 'yellow') continue
      if (one.score > bestScore) {
        bestScore = one.score
        bestLabel = label
      }
    }
    return bestLabel
  }

  private galleryButtonName(result: RecognitionResult): string {
    if (!result.ok || result.boxes.length <= 0) {
      const err: string = (result.errorText ?? '').trim()
      if (err.length <= 0) return 'Recognize Failed'
      const shortErr: string = err.length > 18 ? `${err.substring(0, 18)}...` : err
      return `Failed: ${shortErr}`
    }
    const one: BBoxNorm = result.boxes[0]
    return `${one.label} ${(Math.max(0, one.score) * 100).toFixed(0)}%`
  }

  private async saveRecentClipFrames(id: string, durationMs: number): Promise<Array<string>> {
    const nowMs: number = Date.now()
    const beginMs: number = nowMs - Math.max(200, durationMs)
    const picked: Array<FrameClipBufferItem> = []
    for (let i: number = 0; i < this.frameBuffer.length; i++) {
      const one: FrameClipBufferItem = this.frameBuffer[i]
      if (one.tsMs >= beginMs) picked.push(one)
    }
    const out: Array<string> = []
    for (let i: number = 0; i < picked.length; i++) {
      const key: string = `${id}_clip_${i}_${picked[i].tsMs}`
      const ref: string = await this.saveJpegReference(picked[i].jpeg, key, true)
      if (ref.length > 0) out.push(ref)
    }
    return out
  }

  private async saveDecisionImage(id: string, tag: string): Promise<string> {
    const pm: image.PixelMap | undefined = videoStore.snapshotPixelMap ?? videoStore.livePixelMap
    if (!pm) return ''
    return await this.savePixelMapReference(pm, `${id}_${tag}`, true)
  }

  private async saveBoxedPixelMapReference(
    pm: image.PixelMap,
    result: RecognitionResult,
    key: string,
    preferGallery: boolean
  ): Promise<string> {
    if (!result.ok || result.boxes.length <= 0) return ''
    const top: BBoxNorm = result.boxes[0]
    const copy: image.PixelMap | undefined = await this.clonePixelMap(pm)
    if (!copy) return ''
    try {
      const info: image.ImageInfo = await copy.getImageInfo()
      const region: image.Region | undefined = this.boxToRegion(top, info.size.width, info.size.height)
      if (!region) return ''
      await copy.crop(region)
      return await this.savePixelMapReference(copy, key, preferGallery)
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '保存裁剪框图片失败 key=%{public}s: %{public}s',
        key, e instanceof Error ? e.message : String(e))
      return ''
    } finally {
      try { copy.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
    }
  }

  private boxToRegion(box: BBoxNorm, imgW: number, imgH: number): image.Region | undefined {
    if (imgW <= 0 || imgH <= 0) return undefined
    const normalized: boolean =
      box.x >= 0 && box.y >= 0 && box.w > 0 && box.h > 0 &&
      box.x <= 1 && box.y <= 1 && box.w <= 1 && box.h <= 1
    let x0: number = normalized ? box.x * imgW : box.x
    let y0: number = normalized ? box.y * imgH : box.y
    let x1: number = normalized ? (box.x + box.w) * imgW : (box.x + box.w)
    let y1: number = normalized ? (box.y + box.h) * imgH : (box.y + box.h)
    x0 = Math.max(0, Math.min(imgW, x0))
    y0 = Math.max(0, Math.min(imgH, y0))
    x1 = Math.max(0, Math.min(imgW, x1))
    y1 = Math.max(0, Math.min(imgH, y1))
    if (x1 <= x0 || y1 <= y0) return undefined
    return {
      x: Math.floor(x0),
      y: Math.floor(y0),
      size: {
        width: Math.max(1, Math.ceil(x1 - x0)),
        height: Math.max(1, Math.ceil(y1 - y0))
      }
    }
  }

  private async clonePixelMap(pm: image.PixelMap): Promise<image.PixelMap | undefined> {
    const packer: image.ImagePacker = image.createImagePacker()
    try {
      const data: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 })
      const src: image.ImageSource = image.createImageSource(data)
      try {
        return await src.createPixelMap()
      } finally {
        try { src.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '克隆PixelMap失败: %{public}s',
        e instanceof Error ? e.message : String(e))
      return undefined
    } finally {
      try { packer.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
    }
  }

  private async savePixelMapReference(pm: image.PixelMap, key: string, preferGallery: boolean): Promise<string> {
    const packer: image.ImagePacker = image.createImagePacker()
    try {
      const jpeg: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 })
      return await this.saveJpegReference(jpeg, key, preferGallery)
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '编码并保存图片失败 key=%{public}s: %{public}s',
        key, e instanceof Error ? e.message : String(e))
      return ''
    } finally {
      try { packer.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
    }
  }

  private async saveJpegReference(jpeg: ArrayBuffer, key: string, preferGallery: boolean): Promise<string> {
    if (preferGallery) {
      const ctx: common.UIAbilityContext | undefined = this.getUiContext()
      if (ctx && await this.ensureMediaPermission(ctx)) {
        const uri: string = await this.saveJpegToGallery(ctx, jpeg, key)
        if (uri.length > 0) return uri
      }
    }
    return this.saveJpegToAppFile(jpeg, key)
  }

  private async saveJpegToGallery(ctx: common.UIAbilityContext, jpeg: ArrayBuffer, key: string): Promise<string> {
    let lib: mediaLibrary.MediaLibrary | undefined = undefined
    let fd: number = -1
    try {
      lib = mediaLibrary.getMediaLibrary(ctx)
      const imageRoot: string = await lib.getPublicDirectory(mediaLibrary.DirectoryType.DIR_IMAGE)
      const displayName: string = `page2_replay_${Date.now()}_${this.safeText(key)}.jpg`
      const asset: mediaLibrary.FileAsset =
        await lib.createAsset(mediaLibrary.MediaType.IMAGE, displayName, imageRoot)
      fd = await asset.open('rw')
      await fs.write(fd, jpeg)
      await fs.fsync(fd)
      await asset.close(fd)
      fd = -1
      return asset.uri
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '写入媒体库失败 key=%{public}s: %{public}s',
        key, e instanceof Error ? e.message : String(e))
      return ''
    } finally {
      if (fd >= 0) {
        try { await fs.close(fd) } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
      if (lib) {
        try { await lib.release() } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
    }
  }

  private saveJpegToAppFile(jpeg: ArrayBuffer, key: string): string {
    this.ensureDir(PAGE2_REPLAY_DIR)
    const path: string = `${PAGE2_REPLAY_DIR}/${this.safeText(key)}_${Date.now()}.jpg`
    let f: fs.File | undefined = undefined
    try {
      try { fs.unlinkSync(path) } catch (_) { /* 资源释放失败可安全忽略 */ }
      f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
      fs.writeSync(f.fd, jpeg)
      return path
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '写入应用文件失败 path=%{public}s: %{public}s',
        path, e instanceof Error ? e.message : String(e))
      return ''
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
    }
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const ctx = globalThis.abilityContext as common.UIAbilityContext
    if (!ctx) return undefined
    return ctx
  }

  private async ensureMediaPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = [
      'ohos.permission.READ_MEDIA' as Permissions,
      'ohos.permission.WRITE_MEDIA' as Permissions
    ]
    try {
      const result = await atManager.requestPermissionsFromUser(ctx, perms)
      for (let i: number = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) return false
      }
      return true
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '申请媒体权限失败: %{public}s',
        e instanceof Error ? e.message : String(e))
      return false
    }
  }

  private ensureDir(path: string): void {
    try { fs.mkdirSync(path) } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '创建目录失败 path=%{public}s: %{public}s',
        path, e instanceof Error ? e.message : String(e))
    }
  }

  private safeText(v: string): string {
    const x: string = v.trim()
    if (x.length <= 0) return 'x'
    return x.replace(/[^0-9A-Za-z_-]/g, '_')
  }
}

export const page2ReplayService: Page2ReplayService = new Page2ReplayService()
