import fs from '@ohos.file.fs'
import image from '@ohos.multimedia.image'
import mediaLibrary from '@ohos.multimedia.mediaLibrary'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'
import { videoStore } from '../../state/VideoStore'
import { BBoxNorm, RecognitionResult } from '../recognition/RecognitionResult'
import { RecognitionSubtype } from '../recognition/RecognitionTask'

export interface Page2ObstacleReplayItem {
  id: string
  tsMs: number
  triggerType: 'SHIGONG' | 'ULTRASONIC_01' | 'VISION'
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
}

interface FrameClipBufferItem {
  tsMs: number
  jpeg: ArrayBuffer
}

const PAGE2_REPLAY_DIR: string = '/data/storage/el2/base/haps/entry/files/page2_replay'
const MAX_OBSTACLE_ITEMS: number = 20
const MAX_GALLERY_ITEMS: number = 20
const MAX_FRAME_BUFFER: number = 36
const FRAME_SAMPLE_INTERVAL_MS: number = 120
const SHIGONG_COOLDOWN_MS: number = 1400

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

  async onVisionObstacleDetected(result: RecognitionResult): Promise<void> {
    if (!result.ok || result.boxes.length <= 0) return
    if (result.subtype !== RecognitionSubtype.BARRIER && result.subtype !== RecognitionSubtype.TRAFFIC_LIGHT) return
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
    const boxedImageRef: string = await this.saveBoxedPixelMapReference(originalPm, result, `${id}_boxed`, false)
    this.pushGallery({
      id,
      tsMs: Date.now(),
      buttonName: this.galleryButtonName(result),
      resultText: this.formatResultText(result),
      originalImageRef,
      boxedImageRef
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
        boxedImageRef: ''
      })
      return
    }
    await this.onGalleryRecognition(pm, result)
  }

  async onGalleryRecognitionFromUri(selectedUri: string, result: RecognitionResult): Promise<void> {
    const id: string = this.nextId('gal')
    const pm: image.PixelMap | undefined = videoStore.snapshotPixelMap
    let boxedImageRef: string = ''
    if (pm) {
      boxedImageRef = await this.saveBoxedPixelMapReference(pm, result, `${id}_boxed`, false)
    }
    if (boxedImageRef.length <= 0) {
      boxedImageRef = selectedUri
    }
    this.pushGallery({
      id,
      tsMs: Date.now(),
      buttonName: this.galleryButtonName(result),
      resultText: this.formatResultText(result),
      originalImageRef: selectedUri,
      boxedImageRef
    })
  }

  async archiveOriginalSnapshotToGallery(pm: image.PixelMap, key: string): Promise<string> {
    return await this.savePixelMapReference(pm, `live_${key}`, true)
  }

  private pushObstacle(item: Page2ObstacleReplayItem): void {
    const next: Array<Page2ObstacleReplayItem> = [item]
    for (let i: number = 0; i < this.obstacleItems.length; i++) {
      next.push(this.obstacleItems[i])
      if (next.length >= MAX_OBSTACLE_ITEMS) break
    }
    this.obstacleItems = next
  }

  private pushGallery(item: Page2GalleryReplayItem): void {
    const next: Array<Page2GalleryReplayItem> = [item]
    for (let i: number = 0; i < this.galleryItems.length; i++) {
      next.push(this.galleryItems[i])
      if (next.length >= MAX_GALLERY_ITEMS) break
    }
    this.galleryItems = next
  }

  private nextId(prefix: string): string {
    this.seq += 1
    return `${prefix}-${Date.now()}-${this.seq}`
  }

  private containsShigong(result: RecognitionResult): boolean {
    if (!result.ok || result.boxes.length <= 0) return false
    for (let i: number = 0; i < result.boxes.length; i++) {
      const key: string = result.boxes[i].label.trim().toLowerCase()
      if (key === 'shigong' || key.indexOf('shigong') >= 0 || result.boxes[i].label.indexOf('施工') >= 0) {
        return true
      }
    }
    return false
  }

  private formatResultText(result: RecognitionResult): string {
    if (!result.ok || result.boxes.length <= 0) return 'No target'
    const topN: number = Math.min(5, result.boxes.length)
    const out: Array<string> = []
    for (let i: number = 0; i < topN; i++) {
      const one: BBoxNorm = result.boxes[i]
      out.push(`${one.label} ${(Math.max(0, one.score) * 100).toFixed(1)}%`)
    }
    return out.join('\n')
  }

  private galleryButtonName(result: RecognitionResult): string {
    if (!result.ok || result.boxes.length <= 0) return 'Recognize Failed'
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
    } catch (_) {
      return ''
    } finally {
      try { copy.release() } catch (_) {}
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
        try { src.release() } catch (_) {}
      }
    } catch (_) {
      return undefined
    } finally {
      try { packer.release() } catch (_) {}
    }
  }

  private async savePixelMapReference(pm: image.PixelMap, key: string, preferGallery: boolean): Promise<string> {
    const packer: image.ImagePacker = image.createImagePacker()
    try {
      const jpeg: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 })
      return await this.saveJpegReference(jpeg, key, preferGallery)
    } catch (_) {
      return ''
    } finally {
      try { packer.release() } catch (_) {}
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
    } catch (_) {
      return ''
    } finally {
      if (fd >= 0) {
        try { await fs.close(fd) } catch (_) {}
      }
      if (lib) {
        try { await lib.release() } catch (_) {}
      }
    }
  }

  private saveJpegToAppFile(jpeg: ArrayBuffer, key: string): string {
    this.ensureDir(PAGE2_REPLAY_DIR)
    const path: string = `${PAGE2_REPLAY_DIR}/${this.safeText(key)}_${Date.now()}.jpg`
    let f: fs.File | undefined = undefined
    try {
      try { fs.unlinkSync(path) } catch (_) {}
      f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
      fs.writeSync(f.fd, jpeg)
      return path
    } catch (_) {
      return ''
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
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
    } catch (_) {
      return false
    }
  }

  private ensureDir(path: string): void {
    try { fs.mkdirSync(path) } catch (_) {}
  }

  private safeText(v: string): string {
    const x: string = v.trim()
    if (x.length <= 0) return 'x'
    return x.replace(/[^0-9A-Za-z_-]/g, '_')
  }
}

export const page2ReplayService: Page2ReplayService = new Page2ReplayService()
