/**
 * 代码指南：
 * 文件： services/assistant/TencentAsrRealtimeService.ets
 * 用途： 基于 WebSocket 实现腾讯云实时语音识别，用于低延迟语音转文字.
 * 何时修改： WebSocket 协议、响应格式或签名规则发生变更时.
 * 相关文件： services/assistant/Page4TencentVoiceInputAdapter.ets.
 */
import webSocket from '@ohos.net.webSocket'
import util from '@ohos.util'
import {
  TENCENT_ASR_APP_ID,
  TENCENT_ASR_ENGINE_MODEL_TYPE,
  TENCENT_ASR_FILTER_DIRTY,
  TENCENT_ASR_FILTER_MODAL,
  TENCENT_ASR_FILTER_PUNC,
  TENCENT_ASR_NEED_VAD,
  TENCENT_ASR_REALTIME_RESULT_TIMEOUT_MS,
  TENCENT_ASR_SECRET_ID,
  TENCENT_ASR_SECRET_KEY,
  TENCENT_ASR_VOICE_FORMAT
} from '../../config/TencentAsrConfig'
import { TencentSignUtil } from './TencentSignUtil'

interface RealtimeResultItem {
  index?: number
  voice_text_str?: string
}

interface RealtimeResultPayload {
  code?: number
  message?: string
  final?: number
  result?: RealtimeResultItem
}

interface WsSession {
  socket: webSocket.WebSocket
  voiceId: string
  finalResolver: ((value: string) => void) | undefined
  finalRejecter: ((err: Error) => void) | undefined
  finalPromise: Promise<string>
  closed: boolean
  lastError: string
  lastCloseCode: number
  lastCloseReason: string
  lastServerMessage: string
}

export class TencentAsrRealtimeService {
  private readonly host: string = 'asr.cloud.tencent.com'
  private readonly signer: TencentSignUtil = new TencentSignUtil()
  private session: WsSession | undefined = undefined
  private readonly texts: Map<number, string> = new Map<number, string>()
  private latestText: string = ''
  private timeoutId: number = -1

  async startSession(): Promise<void> {
    if (this.session && !this.session.closed) return
    this.ensureCredentialsReady()
    this.texts.clear()
    this.latestText = ''

    const nowSec: number = Math.floor(Date.now() / 1000)
    const expiredSec: number = nowSec + 24 * 60 * 60
    const nonce: number = Math.floor(Math.random() * 2147483647)
    const voiceId: string = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`
    const queryMap: Record<string, string> = {
      secretid: TENCENT_ASR_SECRET_ID.trim(),
      engine_model_type: TENCENT_ASR_ENGINE_MODEL_TYPE.trim(),
      needvad: `${TENCENT_ASR_NEED_VAD}`,
      filter_dirty: `${TENCENT_ASR_FILTER_DIRTY}`,
      filter_modal: `${TENCENT_ASR_FILTER_MODAL}`,
      filter_punc: `${TENCENT_ASR_FILTER_PUNC}`,
      voice_id: voiceId,
      voice_format: `${TENCENT_ASR_VOICE_FORMAT}`,
      timestamp: `${nowSec}`,
      expired: `${expiredSec}`,
      nonce: `${nonce}`
    }
    const queryNoSig: string = this.toQuery(queryMap)
    const path: string = `/asr/v2/${TENCENT_ASR_APP_ID.trim()}`
    const signSource: string = `${this.host}${path}?${queryNoSig}`
    const signature: string = await this.buildSignUrlEncoded(signSource, TENCENT_ASR_SECRET_KEY.trim())
    const url: string = `wss://${this.host}${path}?${queryNoSig}&signature=${signature}`

    const socket: webSocket.WebSocket = webSocket.createWebSocket()
    const session = this.createSession(socket, voiceId)
    this.session = session
    this.bindSocket(session)
    await socket.connect(url)
  }

  async sendAudioChunk(chunk: ArrayBuffer): Promise<void> {
    const s: WsSession | undefined = this.session
    if (!s || s.closed) return
    if (chunk.byteLength <= 0) return
    await s.socket.send(chunk)
  }

  async stopSessionAndWaitResult(): Promise<string> {
    const s: WsSession | undefined = this.session
    if (!s) return this.buildCurrentText()
    try {
      await s.socket.send(JSON.stringify({ type: 'end' }))
    } catch (e) {}

    this.armTimeoutGuard()
    let out: string = ''
    try {
      out = await s.finalPromise
    } finally {
      this.clearTimeoutGuard()
      await this.safeCloseSocket(s.socket)
      this.session = undefined
    }
    const trimmed: string = out.trim()
    if (trimmed.length > 0) return trimmed
    const details: Array<string> = []
    if (s.lastError.length > 0) details.push(`ws_error=${s.lastError}`)
    if (s.lastCloseCode > 0) details.push(`ws_close_code=${s.lastCloseCode}`)
    if (s.lastCloseReason.length > 0) details.push(`ws_close_reason=${s.lastCloseReason}`)
    if (s.lastServerMessage.length > 0) details.push(`ws_last_msg=${s.lastServerMessage}`)
    if (details.length > 0) {
      throw new Error(details.join(', '))
    }
    return ''
  }

  async abortSession(): Promise<void> {
    const s: WsSession | undefined = this.session
    this.clearTimeoutGuard()
    this.session = undefined
    if (!s) return
    await this.safeCloseSocket(s.socket)
  }

  private createSession(socket: webSocket.WebSocket, voiceId: string): WsSession {
    let resolveFn: ((value: string) => void) | undefined = undefined
    let rejectFn: ((err: Error) => void) | undefined = undefined
    const p = new Promise<string>((resolve, reject): void => {
      resolveFn = resolve
      rejectFn = reject
    })
    return {
      socket: socket,
      voiceId: voiceId,
      finalResolver: resolveFn,
      finalRejecter: rejectFn,
      finalPromise: p,
      closed: false,
      lastError: '',
      lastCloseCode: 0,
      lastCloseReason: '',
      lastServerMessage: ''
    }
  }

  private bindSocket(s: WsSession): void {
    s.socket.on('message', (err, data): void => {
      if (err) return
      const msg: string = this.decodeWsMessage(data)
      s.lastServerMessage = msg
      this.onServerMessage(s, msg)
    })
    s.socket.on('error', (err): void => {
      const message: string = err ? String(err.message ?? err.code ?? 'websocket error') : 'websocket error'
      s.lastError = message
    })
    s.socket.on('close', (err, data): void => {
      void err
      if (data) {
        s.lastCloseCode = data.code ?? 0
        s.lastCloseReason = data.reason ?? ''
      }
      this.finishResolve(s, this.buildCurrentText())
    })
  }

  private onServerMessage(s: WsSession, message: string): void {
    if (!message || message.trim().length <= 0) return
    try {
      const payload: RealtimeResultPayload = JSON.parse(message) as RealtimeResultPayload
      if ((payload.code ?? 0) !== 0) {
        const msg: string = payload.message ?? `code=${payload.code}`
        this.finishReject(s, new Error(msg))
        return
      }
      if (payload.result) {
        const idx: number = payload.result.index ?? this.texts.size
        const txt: string = (payload.result.voice_text_str ?? '').trim()
        if (txt.length > 0) {
          this.texts.set(idx, txt)
          this.latestText = this.buildCurrentText()
        }
      }
      // 某些负载版本直接返回纯文本。
      const anyPayload: Record<string, string | number | Object> = payload as unknown as Record<string, string | number | Object>
      const rawTxt: string = String(anyPayload['text'] ?? anyPayload['voice_text_str'] ?? '').trim()
      if (rawTxt.length > 0) {
        this.latestText = rawTxt
      }
      if ((payload.final ?? 0) === 1) {
        this.finishResolve(s, this.buildCurrentText())
      }
    } catch (e) {
      // ignore non-json message
    }
  }

  private finishResolve(s: WsSession, text: string): void {
    if (s.closed) return
    s.closed = true
    const resolver = s.finalResolver
    s.finalResolver = undefined
    s.finalRejecter = undefined
    if (resolver) resolver(text.trim())
  }

  private finishReject(s: WsSession, err: Error): void {
    if (s.closed) return
    s.closed = true
    const rejecter = s.finalRejecter
    s.finalResolver = undefined
    s.finalRejecter = undefined
    if (rejecter) rejecter(err)
  }

  private buildCurrentText(): string {
    if (this.texts.size <= 0) return this.latestText.trim()
    const keys = Array.from(this.texts.keys()).sort((a, b): number => a - b)
    const arr: Array<string> = []
    for (let i: number = 0; i < keys.length; i++) {
      const t: string = (this.texts.get(keys[i]) ?? '').trim()
      if (t.length > 0) arr.push(t)
    }
    return arr.join('').trim()
  }

  private armTimeoutGuard(): void {
    this.clearTimeoutGuard()
    this.timeoutId = setTimeout((): void => {
      const s: WsSession | undefined = this.session
      if (!s) return
      this.finishResolve(s, this.buildCurrentText())
    }, TENCENT_ASR_REALTIME_RESULT_TIMEOUT_MS) as unknown as number
  }

  private clearTimeoutGuard(): void {
    if (this.timeoutId >= 0) {
      clearTimeout(this.timeoutId)
      this.timeoutId = -1
    }
  }

  private ensureCredentialsReady(): void {
    if (!TENCENT_ASR_APP_ID.trim() || !TENCENT_ASR_SECRET_ID.trim() || !TENCENT_ASR_SECRET_KEY.trim()) {
      throw new Error('请先在 config/TencentAsrConfig.ets 填写 APP_ID/SECRET_ID/SECRET_KEY')
    }
  }

  private toQuery(map: Record<string, string>): string {
    const keys: Array<string> = Object.keys(map).sort()
    const parts: Array<string> = []
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i]
      parts.push(`${k}=${encodeURIComponent(map[k])}`)
    }
    return parts.join('&')
  }

  private async buildSignUrlEncoded(signSource: string, secretKey: string): Promise<string> {
    const b64Text: string = this.signer.signBase64(signSource, secretKey)
    return encodeURIComponent(b64Text)
  }

  private decodeWsMessage(data: string | ArrayBuffer): string {
    if (typeof data === 'string') return data
    return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(new Uint8Array(data), { stream: false })
  }
  private async safeCloseSocket(socket: webSocket.WebSocket): Promise<void> {
    try {
      await socket.close({ code: 1000, reason: 'done' })
    } catch (e) {
      try { await socket.close() } catch (e2) {}
    }
  }
}
