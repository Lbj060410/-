/**
 * 代码指南：
 * 文件： services/recognition/RecognitionReportService.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
import { CarProtocolService, CarSendMode } from '../control/CarProtocolService'
import { trafficSignalArbiter } from '../control/TrafficSignalArbiter'
import { RecogStore } from '../../state/RecogStore'
import { videoStore } from '../../state/VideoStore'
import { RecognitionResult } from './RecognitionResult'
import { RecognitionSubtype, RecognitionTaskKind, RecognitionTaskSource } from './RecognitionTask'
import { EncodedPayload12B, RecogPayload, RecogPayloadKind } from './RecogPayload'
import { RecognitionResultViewHelper } from './RecognitionResultViewHelper'

export class RecognitionReportService {
  private readonly store: RecogStore
  private readonly proto: CarProtocolService = new CarProtocolService()
  private boundProto?: CarProtocolService
  private lastTrafficSignalTaskId: string = ''
  private lastTrafficSignalToken: string = ''
  private lastTrafficSignalSentAtMs: number = 0
  private readonly trafficSignalSendMinIntervalMs: number = 15000
  private trafficSignalSendBusy: boolean = false

  constructor(store: RecogStore) {
    this.store = store
    // 默认为真实设备调试；实际发送仍取决于 TCP 绑定/连接。
    this.proto.setMode(CarSendMode.REAL_SEND)
  }

  bindProtocolService(proto: CarProtocolService): void {
    this.boundProto = proto
  }

  setMode(mode: CarSendMode): void {
    this.proto.setMode(mode)
    if (this.boundProto) this.boundProto.setMode(mode)
  }

  async maybeAutoReport(result: RecognitionResult): Promise<void> {
    if (!this.store.autoReportEnabled) return
    if (!result.ok) return

    if (result.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
      await this.maybeSendTrafficSignalCommand(result)
      return
    }

    const encoded: EncodedPayload12B | null = this.tryEncode(result)
    if (!encoded) return

    // 旧 12B 上报接口已下线；当前保留本地识别结果，不再向小车发送该类旧协议上报帧。
    void encoded
  }

  private currentProto(): CarProtocolService {
    return this.boundProto ?? this.proto
  }

  private async maybeSendTrafficSignalCommand(result: RecognitionResult): Promise<void> {
    if (result.kind !== RecognitionTaskKind.LIVE) return
    if (result.source !== RecognitionTaskSource.PAGE2_BUTTON) return
    if (!videoStore.recognitionEnabled || !videoStore.page2TrafficEnabled) return

    const token: string = this.normalizeTrafficLightToken(
      RecognitionResultViewHelper.bestTextForSubtype(result, RecognitionSubtype.TRAFFIC_LIGHT)
    )
    if (token !== 'R' && token !== 'G') return
    if (this.trafficSignalSendBusy) return

    const taskId: string = result.taskId || ''
    const nowMs: number = Date.now()
    if (taskId.length > 0 && taskId === this.lastTrafficSignalTaskId && token === this.lastTrafficSignalToken) return
    if (token === this.lastTrafficSignalToken && (nowMs - this.lastTrafficSignalSentAtMs) < this.trafficSignalSendMinIntervalMs) return

    this.trafficSignalSendBusy = true
    try {
      const p: CarProtocolService = this.currentProto()
      const rs = await trafficSignalArbiter.send(p, token as 'R' | 'G', 'BYPASS', this.trafficSignalSendMinIntervalMs)
      if (!rs.sent) return
      this.lastTrafficSignalTaskId = taskId
      this.lastTrafficSignalToken = token
      this.lastTrafficSignalSentAtMs = nowMs
    } finally {
      this.trafficSignalSendBusy = false
    }
  }

  private tryEncode(result: RecognitionResult): EncodedPayload12B | null {
    // 保留交通灯结果的本地 UI 使用；不向车辆报告 TRAFFIC_LIGHT。
    if (result.subtype === RecognitionSubtype.TRAFFIC_LIGHT) return null
    if (result.subtype !== RecognitionSubtype.PLATE &&
      result.subtype !== RecognitionSubtype.QR) return null

    const payload: RecogPayload | null = this.buildPayload(result)
    if (!payload) return null
    if (payload.confidence < this.reportThreshold(result)) return null

    const encoded8: Uint8Array = this.encode8(payload)
    const h: number = this.headerByPayloadKind(payload.kind)
    const tag: string = `${RecogPayloadKind[payload.kind]} conf=${Math.round(payload.confidence * 100)} text=${payload.text}`

    return { headerH: h, payload8: encoded8, tag }
  }

  private buildPayload(result: RecognitionResult): RecogPayload | null {
    let text: string = ''
    let conf: number = 0

    const best: string = RecognitionResultViewHelper.bestTextForSubtype(result, result.subtype)
    if (best.length > 0) {
      text = best
      conf = result.texts.length > 0 ? result.texts[0].score : (result.boxes.length > 0 ? result.boxes[0].score : 0)
    }

    if (text.length <= 0 && result.texts.length > 0) {
      text = result.texts[0].text
      conf = result.texts[0].score
    } else if (text.length <= 0 && result.boxes.length > 0) {
      text = result.boxes[0].label
      conf = result.boxes[0].score
    }

    if (result.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
      text = this.normalizeTrafficLightToken(text)
      if (text.length <= 0) {
        for (let i: number = 0; i < result.boxes.length; i++) {
          text = this.normalizeTrafficLightToken(result.boxes[i].label)
          if (text.length > 0) break
        }
      }
      if (text.length <= 0) {
        for (let i: number = 0; i < result.texts.length; i++) {
          text = this.normalizeTrafficLightToken(result.texts[i].text)
          if (text.length > 0) break
        }
      }
    } else {
      text = this.sanitizeAscii(text, 16)
    }
    if (text.length <= 0) return null

    const kind: RecogPayloadKind = (result.subtype === RecognitionSubtype.QR)
      ? RecogPayloadKind.QR
      : (result.subtype === RecognitionSubtype.TRAFFIC_LIGHT ? RecogPayloadKind.TRAFFIC_LIGHT : RecogPayloadKind.PLATE)
    return { kind, confidence: conf, text }
  }

  private headerByPayloadKind(kind: RecogPayloadKind): number {
    if (kind === RecogPayloadKind.PLATE) return 0xD1
    if (kind === RecogPayloadKind.QR) return 0xD2
    return 0xD3
  }

  private reportThreshold(result: RecognitionResult): number {
    // 交通灯实时识别置信度通常低于车牌/二维码 OCR 置信度。
    // 保持 PLATE/QR 的全局阈值，但避免丢弃几乎所有交通灯报告。
    if (result.subtype === RecognitionSubtype.TRAFFIC_LIGHT) {
      return Math.min(this.store.autoReportThreshold, 0.25)
    }
    return this.store.autoReportThreshold
  }

  private normalizeTrafficLightToken(input: string): string {
    if (input.length <= 0) return ''
    const raw: string = input.trim()
    if (raw.length <= 0) return ''
    if (raw.indexOf('红') >= 0) return 'R'
    if (raw.indexOf('绿') >= 0) return 'G'
    if (raw.indexOf('黄') >= 0) return 'Y'

    const normalized: string = raw
      .toLowerCase()
      .replace(/[\s\-]+/g, '_')

    if (normalized.indexOf('red') >= 0 || normalized.indexOf('stop') >= 0 || normalized.indexOf('hong') >= 0) return 'R'
    if (normalized.indexOf('green') >= 0 || normalized.indexOf('go') >= 0 || normalized.indexOf('lv') >= 0 || normalized.indexOf('lu') >= 0) return 'G'
    if (normalized.indexOf('yellow') >= 0 || normalized.indexOf('amber') >= 0 || normalized.indexOf('huang') >= 0) return 'Y'
    return ''
  }

  private encode8(p: RecogPayload): Uint8Array {
    const out: Uint8Array = new Uint8Array(8)
    out[0] = p.kind & 0xff
    out[1] = Math.max(0, Math.min(100, Math.round(p.confidence * 100))) & 0xff

    const textBytes: Uint8Array = this.asciiToBytes(p.text, 6)
    for (let i: number = 0; i < 6; i++) {
      out[2 + i] = textBytes[i]
    }
    return out
  }

  private asciiToBytes(s: string, fixedLen: number): Uint8Array {
    const out: Uint8Array = new Uint8Array(fixedLen)
    for (let i: number = 0; i < fixedLen; i++) {
      if (i >= s.length) {
        out[i] = 0
        continue
      }
      out[i] = s.charCodeAt(i) & 0xff
    }
    return out
  }

  private sanitizeAscii(s: string, maxLen: number): string {
    let out: string = ''
    const limit: number = Math.min(s.length, maxLen)
    for (let i: number = 0; i < limit; i++) {
      const code: number = s.charCodeAt(i)
      if (code >= 32 && code <= 126) {
        out += String.fromCharCode(code)
      }
    }
    return out
  }
}
