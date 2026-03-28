/**
 * 代码指南：
 * 文件： services/replay/ReplayArchiveService.ets
 * 用途： 复盘会话归档中心（触发、时间线、截图与历史查询）。
 */
import fs from '@ohos.file.fs'
import image from '@ohos.multimedia.image'
import { videoStore } from '../../state/VideoStore'
import { RecognitionResult } from '../recognition/RecognitionResult'
import { RecognitionSubtype, RecognitionTaskSource } from '../recognition/RecognitionTask'
import {
  ReplayDetectionBox,
  ReplaySession,
  ReplaySessionOrigin,
  ReplayTimelineItem,
  ReplayTriggerType
} from './ReplayModels'

const REPLAY_DIR: string = '/data/storage/el2/base/haps/entry/files/replay'
const REPLAY_INDEX_PATH: string = `${REPLAY_DIR}/sessions.json`
const MAX_SESSIONS: number = 120
const MAX_TIMELINE: number = 300
const ACTIVE_IDLE_CLOSE_MS: number = 20000
const SNAPSHOT_MIN_INTERVAL_MS: number = 1200

interface ReplayPersistPayload {
  sessions?: Array<ReplaySession>
  seq?: number
}

export class ReplayArchiveService {
  private sessions: Array<ReplaySession> = []
  private activeSessionId: string = ''
  private seq: number = 0
  private lastSnapshotAtMs: number = 0
  private loaded: boolean = false

  listSessions(): Array<ReplaySession> {
    this.ensureLoaded()
    const out: Array<ReplaySession> = []
    for (let i: number = 0; i < this.sessions.length; i++) {
      out.push(this.cloneSession(this.sessions[i]))
    }
    return out
  }

  getSession(id: string): ReplaySession | undefined {
    this.ensureLoaded()
    const key: string = id.trim()
    if (key.length <= 0) return undefined
    for (let i: number = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === key) return this.cloneSession(this.sessions[i])
    }
    return undefined
  }

  onObstacleTriggered(kind: ReplayTriggerType, note: string): void {
    this.ensureLoaded()
    const sid: string = this.ensureActive(kind, note, 'PAGE1')
    this.appendTimeline(sid, 'trigger', note)
    void this.captureSnapshotForSession(sid, 'trigger')
  }

  onRecognition(result: RecognitionResult): void {
    this.ensureLoaded()
    if (!result.ok || result.boxes.length <= 0) return
    if (result.subtype !== RecognitionSubtype.YOLOV26BARRIER &&
      result.subtype !== RecognitionSubtype.TRAFFIC_LIGHT) return

    const trigger: ReplayTriggerType =
      result.subtype === RecognitionSubtype.TRAFFIC_LIGHT ? 'TRAFFIC_LIGHT' : 'VISION_YOLOV26BARRIER'
    const origin: ReplaySessionOrigin = this.mapOriginFromSource(result.source)
    const sid: string = this.ensureActive(trigger, '识别触发', origin)
    const detail: string = `${result.engine} boxes=${result.boxes.length} src=${this.sourceText(result.source)}`
    this.appendTimeline(sid, 'recognition', detail)
    if (result.boxes.length > 0) {
      this.appendTimeline(sid, 'targets', this.formatDetectionSummary(result))
    }
    this.updateSessionDetections(sid, result)

    const nowMs: number = Date.now()
    if (nowMs - this.lastSnapshotAtMs >= SNAPSHOT_MIN_INTERVAL_MS) {
      this.lastSnapshotAtMs = nowMs
      void this.captureSnapshotForSession(sid, 'recog')
    }
  }

  onPathReplanned(oldPath: Array<string>, newPath: Array<string>, reason: string): void {
    this.ensureLoaded()
    if (oldPath.length <= 0 || newPath.length <= 0) return
    if (this.samePath(oldPath, newPath)) return

    const sid: string = this.ensureActive('REPLAN', reason.length > 0 ? reason : '路径重规划', 'PAGE1')
    const s: ReplaySession | undefined = this.getSessionRef(sid)
    if (!s) return
    s.oldPath = this.cloneArray(oldPath)
    s.newPath = this.cloneArray(newPath)
    this.appendTimeline(sid, 'path', `路径变化 ${oldPath.join('->')} => ${newPath.join('->')}`)
  }

  onAction(actionText: string, source: string): void {
    this.ensureLoaded()
    const sid: string = this.activeSessionId.trim()
    if (sid.length <= 0) return
    const s: ReplaySession | undefined = this.getSessionRef(sid)
    if (!s) return

    const item: string = `${Date.now()} | ${source} | ${actionText}`
    s.actions.unshift(item)
    if (s.actions.length > 120) s.actions.pop()
    this.appendTimeline(sid, 'action', `${source}:${actionText}`)
  }

  onAck(status: number): void {
    this.ensureLoaded()
    const sid: string = this.activeSessionId.trim()
    if (sid.length <= 0) return
    this.appendTimeline(sid, 'ack', `BD状态=0x${(status & 0xff).toString(16).toUpperCase().padStart(2, '0')}`)
  }

  closeActive(reason: string): void {
    this.ensureLoaded()
    const sid: string = this.activeSessionId.trim()
    if (sid.length <= 0) return
    const s: ReplaySession | undefined = this.getSessionRef(sid)
    if (!s) {
      this.activeSessionId = ''
      return
    }
    s.endAtMs = Date.now()
    s.durationMs = Math.max(0, s.endAtMs - s.startAtMs)
    this.appendTimeline(sid, 'close', reason.length > 0 ? reason : '结束')
    this.activeSessionId = ''
    this.persistIndex()
  }

  private ensureActive(trigger: ReplayTriggerType, title: string, origin: ReplaySessionOrigin): string {
    this.closeIdleIfNeeded()

    const nowMs: number = Date.now()
    const activeId: string = this.activeSessionId.trim()
    if (activeId.length > 0) {
      const old: ReplaySession | undefined = this.getSessionRef(activeId)
      if (old) {
        if (old.origin === origin && old.triggerType === trigger) {
          old.endAtMs = nowMs
          old.durationMs = Math.max(0, old.endAtMs - old.startAtMs)
          return activeId
        }
        this.closeActive(`切换会话 ${old.origin}/${old.triggerType} -> ${origin}/${trigger}`)
      }
    }

    const id: string = `replay-${nowMs}-${++this.seq}`
    const session: ReplaySession = {
      id: id,
      triggerType: trigger,
      origin: origin,
      startAtMs: nowMs,
      endAtMs: nowMs,
      durationMs: 0,
      title: title.length > 0 ? title : trigger,
      coverImagePath: '',
      snapshotPaths: [],
      oldPath: [],
      newPath: [],
      actions: [],
      detections: [],
      timeline: []
    }

    this.sessions.unshift(session)
    if (this.sessions.length > MAX_SESSIONS) {
      this.sessions.splice(MAX_SESSIONS, this.sessions.length - MAX_SESSIONS)
    }
    this.activeSessionId = id
    this.persistIndex()
    return id
  }

  private closeIdleIfNeeded(): void {
    const sid: string = this.activeSessionId.trim()
    if (sid.length <= 0) return
    const s: ReplaySession | undefined = this.getSessionRef(sid)
    if (!s) {
      this.activeSessionId = ''
      return
    }
    const lastTs: number = this.lastTimelineTs(s.timeline, s.startAtMs)
    if (Date.now() - lastTs >= ACTIVE_IDLE_CLOSE_MS) {
      this.closeActive('空闲自动结束')
    }
  }

  private lastTimelineTs(items: Array<ReplayTimelineItem>, fallback: number): number {
    if (items.length <= 0) return fallback
    return items[0].tsMs
  }

  private appendTimeline(sessionId: string, kind: string, text: string): void {
    const s: ReplaySession | undefined = this.getSessionRef(sessionId)
    if (!s) return

    const item: ReplayTimelineItem = {
      tsMs: Date.now(),
      kind: kind,
      text: text
    }
    s.timeline.unshift(item)
    if (s.timeline.length > MAX_TIMELINE) {
      s.timeline.splice(MAX_TIMELINE, s.timeline.length - MAX_TIMELINE)
    }
    s.endAtMs = item.tsMs
    s.durationMs = Math.max(0, s.endAtMs - s.startAtMs)
    this.persistIndex()
  }

  private getSessionRef(id: string): ReplaySession | undefined {
    for (let i: number = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === id) return this.sessions[i]
    }
    return undefined
  }

  private async captureSnapshotForSession(sessionId: string, tag: string): Promise<void> {
    const s: ReplaySession | undefined = this.getSessionRef(sessionId)
    if (!s) return

    const pm: image.PixelMap | undefined = videoStore.snapshotPixelMap ?? videoStore.livePixelMap
    if (!pm) return

    const path: string | undefined = await this.savePixelMap(pm, sessionId, tag)
    if (!path) return

    s.snapshotPaths.unshift(path)
    if (s.snapshotPaths.length > 24) {
      s.snapshotPaths.splice(24, s.snapshotPaths.length - 24)
    }
    if (s.coverImagePath.length <= 0) {
      s.coverImagePath = path
    }
    this.persistIndex()
  }

  private async savePixelMap(pm: image.PixelMap, sid: string, tag: string): Promise<string | undefined> {
    this.ensureDir(REPLAY_DIR)
    const safeSid: string = this.safeText(sid)
    const safeTag: string = this.safeText(tag)
    const path: string = `${REPLAY_DIR}/${safeSid}_${safeTag}_${Date.now()}.jpg`

    let packer: image.ImagePacker | undefined = undefined
    let f: fs.File | undefined = undefined
    try {
      packer = image.createImagePacker()
      const jpeg: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 88 })
      f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
      fs.writeSync(f.fd, jpeg)
      return path
    } catch (_) {
      return undefined
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
      if (packer) {
        try { packer.release() } catch (_) {}
      }
    }
  }

  private ensureDir(dir: string): void {
    try { fs.mkdirSync(dir) } catch (_) {}
  }

  private ensureLoaded(): void {
    if (this.loaded) return
    this.loaded = true
    this.loadIndex()
  }

  private loadIndex(): void {
    this.ensureDir(REPLAY_DIR)
    let f: fs.File | undefined = undefined
    try {
      f = fs.openSync(REPLAY_INDEX_PATH, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(REPLAY_INDEX_PATH)
      const size: number = Number(stat.size)
      if (!Number.isFinite(size) || size <= 0) return

      const buf: ArrayBuffer = new ArrayBuffer(size)
      const readLen: number = fs.readSync(f.fd, buf)
      if (!Number.isFinite(readLen) || readLen <= 0) return

      const text: string = this.bytesToText(new Uint8Array(buf.slice(0, readLen)))
      const obj: Object = JSON.parse(text) as Object
      const payload: ReplayPersistPayload = obj as ReplayPersistPayload
      const srcSessions: Array<ReplaySession> = Array.isArray(payload.sessions) ? payload.sessions : []
      this.sessions = this.normalizeSessions(srcSessions)
      this.seq = Math.max(this.seqFromSessions(this.sessions), this.toSafeInt(payload.seq))
      this.activeSessionId = ''
    } catch (_) {
      this.sessions = []
      this.activeSessionId = ''
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  private persistIndex(): void {
    const payload: ReplayPersistPayload = {
      sessions: this.sessions,
      seq: this.seq
    }
    let f: fs.File | undefined = undefined
    try {
      this.ensureDir(REPLAY_DIR)
      const text: string = JSON.stringify(payload)
      try { fs.unlinkSync(REPLAY_INDEX_PATH) } catch (_) {}
      f = fs.openSync(
        REPLAY_INDEX_PATH,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND
      )
      fs.writeSync(f.fd, text)
    } catch (_) {
      // ignore persistence failure; runtime memory still keeps replay data
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  private normalizeSessions(input: Array<ReplaySession>): Array<ReplaySession> {
    const out: Array<ReplaySession> = []
    for (let i: number = 0; i < input.length; i++) {
      const one: ReplaySession = input[i]
      if (!one || typeof one !== 'object') continue
      if (typeof one.id !== 'string' || one.id.trim().length <= 0) continue
      out.push(this.cloneSession(one))
      if (out.length >= MAX_SESSIONS) break
    }
    return out
  }

  private seqFromSessions(input: Array<ReplaySession>): number {
    let best: number = 0
    for (let i: number = 0; i < input.length; i++) {
      const id: string = input[i].id
      const m: RegExpMatchArray | null = id.match(/-(\d+)$/)
      if (!m || m.length <= 1) continue
      const v: number = Number.parseInt(m[1], 10)
      if (Number.isFinite(v) && v > best) best = v
    }
    return best
  }

  private toSafeInt(v: number | undefined): number {
    if (typeof v !== 'number' || !Number.isFinite(v)) return 0
    return Math.max(0, Math.floor(v))
  }

  private bytesToText(bytes: Uint8Array): string {
    let out: string = ''
    let i: number = 0
    while (i < bytes.length) {
      const b0: number = bytes[i] & 0xff
      if (b0 < 0x80) {
        out += String.fromCharCode(b0)
        i += 1
        continue
      }

      if ((b0 & 0xe0) === 0xc0 && i + 1 < bytes.length) {
        const b1: number = bytes[i + 1] & 0x3f
        const cp: number = ((b0 & 0x1f) << 6) | b1
        out += String.fromCharCode(cp)
        i += 2
        continue
      }

      if ((b0 & 0xf0) === 0xe0 && i + 2 < bytes.length) {
        const b1: number = bytes[i + 1] & 0x3f
        const b2: number = bytes[i + 2] & 0x3f
        const cp: number = ((b0 & 0x0f) << 12) | (b1 << 6) | b2
        out += String.fromCharCode(cp)
        i += 3
        continue
      }

      if ((b0 & 0xf8) === 0xf0 && i + 3 < bytes.length) {
        const b1: number = bytes[i + 1] & 0x3f
        const b2: number = bytes[i + 2] & 0x3f
        const b3: number = bytes[i + 3] & 0x3f
        const cp: number = ((b0 & 0x07) << 18) | (b1 << 12) | (b2 << 6) | b3
        const v: number = cp - 0x10000
        const high: number = 0xd800 + ((v >> 10) & 0x3ff)
        const low: number = 0xdc00 + (v & 0x3ff)
        out += String.fromCharCode(high, low)
        i += 4
        continue
      }

      out += '?'
      i += 1
    }
    return out
  }

  private safeText(v: string): string {
    const x: string = v.trim()
    if (x.length <= 0) return 'x'
    return x.replace(/[^0-9A-Za-z_-]/g, '_')
  }

  private samePath(a: Array<string>, b: Array<string>): boolean {
    if (a.length !== b.length) return false
    for (let i: number = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false
    }
    return true
  }

  private cloneArray(src: Array<string>): Array<string> {
    const out: Array<string> = []
    for (let i: number = 0; i < src.length; i++) out.push(src[i])
    return out
  }

  private cloneSession(src: ReplaySession): ReplaySession {
    const timelineSrc: Array<ReplayTimelineItem> = Array.isArray(src.timeline) ? src.timeline : []
    return {
      id: typeof src.id === 'string' ? src.id : '',
      triggerType: this.normalizeTriggerType(src.triggerType),
      origin: this.normalizeOrigin(src.origin),
      startAtMs: this.toSafeInt(src.startAtMs),
      endAtMs: this.toSafeInt(src.endAtMs),
      durationMs: this.toSafeInt(src.durationMs),
      title: typeof src.title === 'string' ? src.title : '',
      coverImagePath: typeof src.coverImagePath === 'string' ? src.coverImagePath : '',
      snapshotPaths: this.cloneArray(Array.isArray(src.snapshotPaths) ? src.snapshotPaths : []),
      oldPath: this.cloneArray(Array.isArray(src.oldPath) ? src.oldPath : []),
      newPath: this.cloneArray(Array.isArray(src.newPath) ? src.newPath : []),
      actions: this.cloneArray(Array.isArray(src.actions) ? src.actions : []),
      detections: this.cloneDetections(Array.isArray(src.detections) ? src.detections : []),
      timeline: timelineSrc.map((x: ReplayTimelineItem): ReplayTimelineItem => ({
        tsMs: this.toSafeInt(x?.tsMs),
        kind: typeof x?.kind === 'string' ? x.kind : '',
        text: typeof x?.text === 'string' ? x.text : ''
      }))
    }
  }

  private normalizeTriggerType(v: ReplayTriggerType): ReplayTriggerType {
    if (v === 'ULTRASONIC' || v === 'VISION_YOLOV26BARRIER' || v === 'TRAFFIC_LIGHT' || v === 'REPLAN') {
      return v
    }
    return 'REPLAN'
  }

  private normalizeOrigin(v: ReplaySessionOrigin | undefined): ReplaySessionOrigin {
    if (v === 'PAGE1' || v === 'PAGE2' || v === 'PAGE4' || v === 'GALLERY' || v === 'CAR') {
      return v
    }
    return 'UNKNOWN'
  }

  private mapOriginFromSource(source: RecognitionTaskSource): ReplaySessionOrigin {
    if (source === RecognitionTaskSource.PAGE2_BUTTON) return 'PAGE2'
    if (source === RecognitionTaskSource.GALLERY) return 'GALLERY'
    if (source === RecognitionTaskSource.CAR_FRAME_TRIGGER) return 'CAR'
    if (source === RecognitionTaskSource.PAGE4_TAP || source === RecognitionTaskSource.PAGE4_LIVE) return 'PAGE4'
    return 'UNKNOWN'
  }

  private sourceText(source: RecognitionTaskSource): string {
    if (source === RecognitionTaskSource.PAGE2_BUTTON) return 'PAGE2'
    if (source === RecognitionTaskSource.GALLERY) return 'GALLERY'
    if (source === RecognitionTaskSource.CAR_FRAME_TRIGGER) return 'CAR'
    if (source === RecognitionTaskSource.PAGE4_TAP) return 'PAGE4_TAP'
    if (source === RecognitionTaskSource.PAGE4_LIVE) return 'PAGE4_LIVE'
    return 'UNKNOWN'
  }

  private updateSessionDetections(sessionId: string, result: RecognitionResult): void {
    const s: ReplaySession | undefined = this.getSessionRef(sessionId)
    if (!s) return
    const out: Array<ReplayDetectionBox> = []
    const maxItems: number = Math.min(20, result.boxes.length)
    for (let i: number = 0; i < maxItems; i++) {
      const b = result.boxes[i]
      out.push({
        label: typeof b.label === 'string' ? b.label : '-',
        score: Number.isFinite(b.score) ? b.score : 0,
        x: Number.isFinite(b.x) ? b.x : 0,
        y: Number.isFinite(b.y) ? b.y : 0,
        w: Number.isFinite(b.w) ? b.w : 0,
        h: Number.isFinite(b.h) ? b.h : 0
      })
    }
    s.detections = out
    this.persistIndex()
  }

  private formatDetectionSummary(result: RecognitionResult): string {
    const topN: number = Math.min(3, result.boxes.length)
    const chunks: Array<string> = []
    for (let i: number = 0; i < topN; i++) {
      const one = result.boxes[i]
      const scoreText: string = (Math.max(0, one.score) * 100).toFixed(1)
      chunks.push(`${one.label} ${scoreText}%`)
    }
    return chunks.join(' | ')
  }

  private cloneDetections(src: Array<ReplayDetectionBox>): Array<ReplayDetectionBox> {
    const out: Array<ReplayDetectionBox> = []
    for (let i: number = 0; i < src.length; i++) {
      const one: ReplayDetectionBox = src[i]
      out.push({
        label: typeof one.label === 'string' ? one.label : '',
        score: Number.isFinite(one.score) ? one.score : 0,
        x: Number.isFinite(one.x) ? one.x : 0,
        y: Number.isFinite(one.y) ? one.y : 0,
        w: Number.isFinite(one.w) ? one.w : 0,
        h: Number.isFinite(one.h) ? one.h : 0
      })
    }
    return out
  }
}

export const replayArchiveService: ReplayArchiveService = new ReplayArchiveService()


