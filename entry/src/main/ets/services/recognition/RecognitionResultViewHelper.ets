/**
 * 代码指南：
 * 文件： services/recognition/RecognitionResultViewHelper.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
import { RecogStore } from '../../state/RecogStore'
import { RecognitionSubtype, RecognitionTaskSource } from './RecognitionTask'
import { RecognitionResult } from './RecognitionResult'

export interface LabelCountItem {
  label: string
  count: number
}

export class RecognitionResultViewHelper {
  static latestOkResultBySubtype(store: RecogStore, subtype: RecognitionSubtype): RecognitionResult | undefined {
    return this.latestResultBySubtype(store, subtype, undefined)
  }

  static latestOkResultBySubtypeForSources(
    store: RecogStore,
    subtype: RecognitionSubtype,
    allowedSources: Array<RecognitionTaskSource>
  ): RecognitionResult | undefined {
    return this.latestResultBySubtype(store, subtype, allowedSources)
  }

  static countsBySubtype(store: RecogStore, subtype: RecognitionSubtype): Array<LabelCountItem> {
    const r: RecognitionResult | undefined = this.latestResultBySubtype(store, subtype, undefined)
    if (!r) return []
    return this.countLabels(r)
  }

  static countsBySubtypeForSources(
    store: RecogStore,
    subtype: RecognitionSubtype,
    allowedSources: Array<RecognitionTaskSource>
  ): Array<LabelCountItem> {
    const r: RecognitionResult | undefined = this.latestResultBySubtype(store, subtype, allowedSources)
    if (!r) return []
    return this.countLabels(r)
  }

  static textsBySubtype(store: RecogStore, subtype: RecognitionSubtype): Array<string> {
    const r: RecognitionResult | undefined = this.latestResultBySubtype(store, subtype, undefined)
    if (!r) return []
    return this.textsFromResultBySubtype(r, subtype)
  }

  static textsBySubtypeForSources(
    store: RecogStore,
    subtype: RecognitionSubtype,
    allowedSources: Array<RecognitionTaskSource>
  ): Array<string> {
    const r: RecognitionResult | undefined = this.latestResultBySubtype(store, subtype, allowedSources)
    if (!r) return []
    return this.textsFromResultBySubtype(r, subtype)
  }

  static textsFromResultBySubtype(r: RecognitionResult, subtype: RecognitionSubtype): Array<string> {
    const raw: Array<string> = this.extractTexts(r)
    if (subtype === RecognitionSubtype.PLATE) {
      const fromText: Array<string> = this.extractPlateTexts(raw)
      if (fromText.length > 0) return fromText
      return this.extractPlateTextsFromBoxes(r)
    }
    if (subtype === RecognitionSubtype.QR || subtype === RecognitionSubtype.BARCODE) {
      return this.extractQrTexts(raw)
    }
    return raw
  }

  static bestTextForSubtype(r: RecognitionResult, subtype: RecognitionSubtype): string {
    const arr: Array<string> = this.textsFromResultBySubtype(r, subtype)
    return arr.length > 0 ? arr[0] : ''
  }

  static plateHint(): string {
    return '当前离线模型未解码到车牌文本，可重试或更换车牌OCR模型'
  }

  static qrHint(): string {
    return '当前离线模型未解码到二维码文本'
  }

  static vehicleModelText(store: RecogStore): string {
    const values: Array<string> = this.textsBySubtype(store, RecognitionSubtype.VEHICLE)
    if (values.length > 0) return values[0]
    return '-'
  }

  static vehicleModelTextForSources(store: RecogStore, allowedSources: Array<RecognitionTaskSource>): string {
    const values: Array<string> = this.textsBySubtypeForSources(store, RecognitionSubtype.VEHICLE, allowedSources)
    if (values.length > 0) return values[0]
    return '-'
  }

  static vehicleColorText(store: RecogStore): string {
    const counts: Array<LabelCountItem> = this.countsBySubtype(store, RecognitionSubtype.COLOR)
    const s: string = this.dominantLabel(counts)
    return s.length > 0 ? s : '-'
  }

  static vehicleColorTextForSources(store: RecogStore, allowedSources: Array<RecognitionTaskSource>): string {
    const counts: Array<LabelCountItem> = this.countsBySubtypeForSources(store, RecognitionSubtype.COLOR, allowedSources)
    const s: string = this.dominantLabel(counts)
    return s.length > 0 ? s : '-'
  }

  static trafficLightText(store: RecogStore): string {
    const r: RecognitionResult | undefined = this.latestResultBySubtype(store, RecognitionSubtype.TRAFFIC_LIGHT, undefined)
    if (!r) return '-'

    const textValues: Array<string> = this.extractTexts(r)
    if (textValues.length > 0) {
      return textValues[0]
    }

    const counts: Array<LabelCountItem> = this.countLabels(r)
    const s: string = this.dominantLabel(counts)
    return s.length > 0 ? s : '-'
  }

  static trafficLightTextForSources(store: RecogStore, allowedSources: Array<RecognitionTaskSource>): string {
    const r: RecognitionResult | undefined = this.latestResultBySubtype(store, RecognitionSubtype.TRAFFIC_LIGHT, allowedSources)
    if (!r) return '-'

    const textValues: Array<string> = this.extractTexts(r)
    if (textValues.length > 0) {
      return textValues[0]
    }

    const counts: Array<LabelCountItem> = this.countLabels(r)
    const s: string = this.dominantLabel(counts)
    return s.length > 0 ? s : '-'
  }

  private static latestResultBySubtype(
    store: RecogStore,
    subtype: RecognitionSubtype,
    allowedSources: Array<RecognitionTaskSource> | undefined
  ): RecognitionResult | undefined {
    for (let i: number = 0; i < store.recogTasks.length; i++) {
      const task = store.recogTasks[i]
      if (task.subtype === subtype &&
        task.result &&
        task.result.ok &&
        this.isSourceAllowed(task.result.source, allowedSources)) {
        return task.result
      }
    }

    if (store.lastSnapshotRecog &&
      store.lastSnapshotRecog.subtype === subtype &&
      store.lastSnapshotRecog.ok &&
      this.isSourceAllowed(store.lastSnapshotRecog.source, allowedSources)) {
      return store.lastSnapshotRecog
    }

    if (store.lastRecog &&
      store.lastRecog.subtype === subtype &&
      store.lastRecog.ok &&
      this.isSourceAllowed(store.lastRecog.source, allowedSources)) {
      return store.lastRecog
    }

    return undefined
  }

  private static isSourceAllowed(
    source: RecognitionTaskSource,
    allowedSources: Array<RecognitionTaskSource> | undefined
  ): boolean {
    if (!allowedSources || allowedSources.length <= 0) return true
    for (let i: number = 0; i < allowedSources.length; i++) {
      if (allowedSources[i] === source) return true
    }
    return false
  }

  private static countLabels(r: RecognitionResult): Array<LabelCountItem> {
    const bucket: Record<string, number> = {}
    const order: Array<string> = []

    for (let i: number = 0; i < r.boxes.length; i++) {
      const label: string = this.normalizeCountLabel(r.boxes[i].label)
      if (label.length <= 0) continue

      if (bucket[label] === undefined) {
        bucket[label] = 1
        order.push(label)
      } else {
        bucket[label] += 1
      }
    }

    const out: Array<LabelCountItem> = []
    for (let i: number = 0; i < order.length; i++) {
      const k: string = order[i]
      out.push({ label: k, count: bucket[k] })
    }
    return out
  }

  private static extractTexts(r: RecognitionResult): Array<string> {
    const out: Array<string> = []
    const seen: Record<string, boolean> = {}

    for (let i: number = 0; i < r.texts.length; i++) {
      const t: string = this.normalizeText(r.texts[i].text)
      if (t.length <= 0 || seen[t]) continue
      seen[t] = true
      out.push(t)
    }

    if (out.length <= 0) {
      for (let i: number = 0; i < r.boxes.length; i++) {
        const t: string = this.normalizeText(r.boxes[i].label)
        if (t.length <= 0 || seen[t]) continue
        seen[t] = true
        out.push(t)
      }
    }

    return out
  }

  private static extractPlateTexts(values: Array<string>): Array<string> {
    const out: Array<string> = []
    const seen: Record<string, boolean> = {}
    for (let i: number = 0; i < values.length; i++) {
      const n: string = this.normalizePlate(values[i])
      if (n.length <= 0 || seen[n]) continue
      seen[n] = true
      out.push(n)
    }
    return out
  }

  private static extractPlateTextsFromBoxes(r: RecognitionResult): Array<string> {
    const tokens: Array<{ x: number, s: string }> = []
    for (let i: number = 0; i < r.boxes.length; i++) {
      const b = r.boxes[i]
      const s: string = this.normalizePlateToken(b.label)
      if (s.length <= 0) continue
      tokens.push({ x: b.x, s })
    }
    if (tokens.length <= 0) return []

    tokens.sort((a, b): number => a.x - b.x)
    let joined: string = ''
    for (let i: number = 0; i < tokens.length; i++) {
      joined += tokens[i].s
    }

    const normalized: string = this.normalizePlate(joined)
    if (normalized.length <= 0) return []
    return [normalized]
  }

  private static extractQrTexts(values: Array<string>): Array<string> {
    const out: Array<string> = []
    const seen: Record<string, boolean> = {}
    for (let i: number = 0; i < values.length; i++) {
      const n: string = this.normalizeQr(values[i])
      if (n.length <= 0 || seen[n]) continue
      seen[n] = true
      out.push(n)
    }
    return out
  }

  private static normalizePlate(v: string): string {
    let s: string = v.trim().toUpperCase()
    s = s.replace(/[^0-9A-Z\u4E00-\u9FA5]/g, '')
    if (s.length <= 0) return ''

    // Some OCR engines emit a leading "国"; legacy project strips it.
    if (s.length > 1 && s[0] === '国') {
      s = s.substring(1)
    }

    s = this.correctPlateAmbiguousChars(s)

    if (/^[\u4E00-\u9FA5][A-Z][A-Z0-9]{5,7}$/.test(s)) return s
    if (/^[A-Z][A-Z0-9]{5,7}$/.test(s)) return s
    if (/^[A-Z]\d{3}[A-Z]\d$/.test(s)) return s

    const m1: RegExpMatchArray | null = s.match(/[\u4E00-\u9FA5][A-Z][A-Z0-9]{5,7}/)
    if (m1 && m1.length > 0) return m1[0]

    const m2: RegExpMatchArray | null = s.match(/[A-Z][A-Z0-9]{5,7}/)
    if (m2 && m2.length > 0) return m2[0]

    const m3: RegExpMatchArray | null = s.match(/[A-Z]\d{3}[A-Z]\d/)
    if (m3 && m3.length > 0) return m3[0]

    return ''
  }

  private static normalizePlateToken(v: string): string {
    let s: string = v.trim().toUpperCase()
    if (s.length <= 0) return ''
    if (s === 'PLATE' || s === 'CARPLATE' || s === 'LICENSEPLATE' || s === 'LP') return ''
    if (/^CLS\d+$/.test(s)) return ''

    s = s.replace(/[^0-9A-Z\u4E00-\u9FA5]/g, '')
    if (s.length <= 0 || s.length > 2) return ''
    if (s.length === 1) return s

    // Keep 2-char tokens only when they look like province+alpha or alpha+digit pairs.
    if (/^[\u4E00-\u9FA5][A-Z]$/.test(s)) return s
    if (/^[A-Z0-9]{2}$/.test(s)) return s
    return ''
  }

  private static correctPlateAmbiguousChars(s: string): string {
    if (s.length <= 0) return s

    const chars: Array<string> = []
    for (let i: number = 0; i < s.length; i++) {
      chars.push(s[i])
    }

    let start: number = 0
    if (/^[\u4E00-\u9FA5]$/.test(chars[0])) {
      start = 1
    }

    if (start < chars.length) {
      chars[start] = this.toLikelyLetter(chars[start])
    }
    for (let i: number = start + 1; i < chars.length; i++) {
      chars[i] = this.toLikelyAlnum(chars[i])
    }

    return chars.join('')
  }

  private static toLikelyLetter(ch: string): string {
    if (ch === '0') return 'O'
    if (ch === '1') return 'I'
    if (ch === '2') return 'Z'
    if (ch === '5') return 'S'
    if (ch === '6') return 'G'
    if (ch === '8') return 'B'
    return ch
  }

  private static toLikelyAlnum(ch: string): string {
    if (ch === 'O' || ch === 'D' || ch === 'Q') return '0'
    if (ch === 'I' || ch === 'L') return '1'
    if (ch === 'Z') return '2'
    if (ch === 'S') return '5'
    if (ch === 'G') return '6'
    if (ch === 'B') return '8'
    return ch
  }

  private static normalizeQr(v: string): string {
    let s: string = v.trim()
    s = s.replace(/[\r\n\t]/g, '').trim()
    if (s.length < 1 || s.length > 512) return ''

    const compact: string = s.replace(/\s+/g, '')
    if (compact.length < 1 || compact.length > 512) return ''

    const lower: string = compact.toLowerCase()
    if (lower === 'qr' || lower === 'qrcode' || lower === 'barcode' || lower === 'screen') {
      return ''
    }
    if (/^cls\d+$/i.test(compact)) return ''
    if (lower.indexOf('mock/') >= 0 || lower.indexOf('mock:') >= 0) return ''
    if (!/[0-9A-Za-z\u4E00-\u9FA5]/.test(s)) return ''

    return s
  }

  private static dominantLabel(items: Array<LabelCountItem>): string {
    if (items.length <= 0) return ''
    let best: LabelCountItem = items[0]
    for (let i: number = 1; i < items.length; i++) {
      if (items[i].count > best.count) {
        best = items[i]
      }
    }
    return best.label
  }

  private static normalizeText(v: string): string {
    return v.trim()
  }

  private static normalizeCountLabel(v: string): string {
    return v.trim().toLowerCase()
  }
}


