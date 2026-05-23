/**
 * 浠ｇ爜鎸囧崡锛? * 鏂囦欢锛?services/assistant/OpenClawGatewayWsClient.ets
 * 鐢ㄩ€旓細 閫氳繃 OpenClaw Gateway WebSocket 鍗忚鍙戦€?chat.send 骞舵帴鏀舵祦寮?chat 浜嬩欢銆? * 浣曟椂淇敼锛?Gateway WS 鎻℃墜銆佷簨浠跺抚鎴?chat.send/chat.abort 鍙傛暟鍙樻洿鏃躲€? * 鐩稿叧鏂囦欢锛?services/assistant/OpenClawGatewayClient.ets銆乸ages/page4/gateway/Page4GatewayLayer.ets銆? */
import webSocket from '@ohos.net.webSocket'
import util from '@ohos.util'

export interface OpenClawGatewayWsClientOptions {
  url: string
  bearerToken: string
  connectTimeoutMs: number
  readTimeoutMs: number
}

export interface OpenClawGatewayWsChatOptions {
  sessionKey: string
  message: string
  timeoutMs?: number
  idempotencyKey?: string
  onStarted?: (runId: string) => void
  onDelta?: (text: string, runId: string) => void
}

export interface OpenClawGatewayWsChatResult {
  ok: boolean
  text: string
  errorText: string
  runId: string
}

interface GatewayResponseFrame {
  type?: string
  id?: string
  ok?: boolean
  payload?: Record<string, Object | string | number | boolean | undefined>
  error?: {
    code?: unknown
    message?: unknown
  }
}

interface GatewayEventFrame {
  type?: string
  event?: string
  payload?: unknown
}

interface PendingRequest {
  resolve: (value: Record<string, Object | string | number | boolean | undefined>) => void
  reject: (err: Error) => void
  timeoutId: number
}

interface ActiveChatWaiter {
  runId: string
  sessionKey: string
  buffer: string
  resolve: (value: OpenClawGatewayWsChatResult) => void
  reject: (err: Error) => void
  timeoutId: number
  onDelta?: (text: string, runId: string) => void
  finished: boolean
}

export class OpenClawGatewayWsClient {
  private readonly url: string
  private readonly bearerToken: string
  private readonly connectTimeoutMs: number
  private readonly readTimeoutMs: number
  private socket: webSocket.WebSocket | undefined = undefined
  private readonly decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true })
  private readonly pending: Record<string, PendingRequest> = {}
  private chatWaiter: ActiveChatWaiter | undefined = undefined
  private connectResolver: (() => void) | undefined = undefined
  private connectRejecter: ((err: Error) => void) | undefined = undefined
  private connectPromise: Promise<void> | undefined = undefined
  private connectDone: boolean = false
  private closed: boolean = false
  private reqSeq: number = 0

  constructor(options: OpenClawGatewayWsClientOptions) {
    this.url = options.url
    this.bearerToken = options.bearerToken.trim()
    this.connectTimeoutMs = Math.max(1000, options.connectTimeoutMs)
    this.readTimeoutMs = Math.max(1000, options.readTimeoutMs)
  }

  async chat(options: OpenClawGatewayWsChatOptions): Promise<OpenClawGatewayWsChatResult> {
    const message: string = options.message.trim()
    if (message.length <= 0) {
      return { ok: false, text: '', errorText: 'empty message', runId: '' }
    }

    const sessionKey: string = options.sessionKey.trim()
    const requestId: string = options.idempotencyKey?.trim() ?? this.nextId('run')
    try {
      await this.ensureConnected()
      const finalPromise: Promise<OpenClawGatewayWsChatResult> = this.waitForChatFinal(
        sessionKey,
        requestId,
        options.timeoutMs,
        options.onDelta
      )
      const payload = await this.request('chat.send', {
        sessionKey,
        message,
        idempotencyKey: requestId,
        deliver: false,
        timeoutMs: options.timeoutMs ?? this.readTimeoutMs
      }, this.connectTimeoutMs)
      const runId: string = String(payload['runId'] ?? requestId).trim()
      this.rebindActiveChatRunId(requestId, runId)
      if (options.onStarted) options.onStarted(runId)
      return await finalPromise
    } catch (e) {
      this.rejectActiveChat(e instanceof Error ? e : new Error(String(e)))
      const msg: string = e instanceof Error ? e.message : String(e)
      return { ok: false, text: '', errorText: msg, runId: '' }
    } finally {
      await this.safeCloseSocket()
    }
  }

  private async ensureConnected(): Promise<void> {
    if (this.connectDone) return
    if (this.connectPromise) {
      await this.connectPromise
      return
    }
    this.connectPromise = new Promise<void>((resolve, reject): void => {
      this.connectResolver = resolve
      this.connectRejecter = reject
    })
    const socket: webSocket.WebSocket = webSocket.createWebSocket()
    this.socket = socket
    this.bindSocket(socket)
    await socket.connect(this.url)
    await this.connectPromise
  }

  private bindSocket(socket: webSocket.WebSocket): void {
    socket.on('message', (err, data): void => {
      if (err) return
      const raw: string = this.decodeWsMessage(data)
      this.handleSocketMessage(raw)
    })
    socket.on('error', (err): void => {
      const msg: string = err ? String(err.message ?? err.code ?? 'websocket error') : 'websocket error'
      const one: Error = new Error(msg)
      if (!this.connectDone) this.rejectConnect(one)
      this.rejectActiveChat(one)
      this.rejectAllPending(one)
    })
    socket.on('close', (_err, data): void => {
      const code: number = data?.code ?? 0
      const reason: string = data?.reason ?? ''
      const msg: string = `gateway closed (${code}): ${reason}`
      const one: Error = new Error(msg)
      if (!this.connectDone && !this.closed) this.rejectConnect(one)
      if (!this.closed) {
        this.rejectActiveChat(one)
        this.rejectAllPending(one)
      }
    })
  }

  private handleSocketMessage(raw: string): void {
    if (!raw || raw.trim().length <= 0) return
    let parsed: Record<string, Object | string | number | boolean | undefined> = {}
    try {
      parsed = JSON.parse(raw) as Record<string, Object | string | number | boolean | undefined>
    } catch (_) {
      return
    }
    const frameType: string = String(parsed['type'] ?? '').trim()
    if (frameType === 'event') {
      this.handleEventFrame(parsed as unknown as GatewayEventFrame)
      return
    }
    if (frameType === 'res') {
      this.handleResponseFrame(parsed as unknown as GatewayResponseFrame)
    }
  }

  private handleEventFrame(frame: GatewayEventFrame): void {
    const eventName: string = String(frame.event ?? '').trim()
    if (eventName === 'connect.challenge') {
      void this.sendConnect()
      return
    }
    if (eventName !== 'chat') return
    this.handleChatPayload(frame.payload)
  }

  private async sendConnect(): Promise<void> {
    try {
      await this.request('connect', {
        minProtocol: 3,
        maxProtocol: 3,
        client: {
          id: 'gateway-client',
          displayName: 'Page4',
          version: '1.0',
          platform: 'HarmonyOS',
          mode: 'backend',
          instanceId: this.nextId('client')
        },
        caps: [],
        auth: {
          token: this.bearerToken
        },
        role: 'operator',
        scopes: ['operator.admin']
      }, this.connectTimeoutMs)
      this.connectDone = true
      const resolver = this.connectResolver
      this.connectResolver = undefined
      this.connectRejecter = undefined
      if (resolver) resolver()
    } catch (e) {
      this.rejectConnect(e instanceof Error ? e : new Error(String(e)))
      void this.safeCloseSocket()
    }
  }

  private handleResponseFrame(frame: GatewayResponseFrame): void {
    const reqId: string = String(frame.id ?? '').trim()
    if (reqId.length <= 0) return
    const pending: PendingRequest | undefined = this.pending[reqId]
    if (!pending) return
    this.pending[reqId] = undefined as unknown as PendingRequest
    delete this.pending[reqId]
    clearTimeout(pending.timeoutId)
    if (frame.ok === true) {
      pending.resolve(frame.payload ?? {})
      return
    }
    const msg: string = String(frame.error?.message ?? 'gateway request failed').trim()
    const codeText: string = String(frame.error?.code ?? '').trim()
    pending.reject(new Error(codeText.length > 0 ? `${codeText}: ${msg}` : msg))
  }

  private handleChatPayload(payload: unknown): void {
    const waiter: ActiveChatWaiter | undefined = this.chatWaiter
    if (!waiter || waiter.finished) return
    if (!payload || typeof payload !== 'object') return
    const map: Record<string, unknown> = payload as Record<string, unknown>
    const runId: string = String(map['runId'] ?? '').trim()
    const sessionKey: string = String(map['sessionKey'] ?? '').trim()
    if (runId !== waiter.runId || sessionKey !== waiter.sessionKey) return
    const state: string = String(map['state'] ?? '').trim()
    if (state === 'delta') {
      const text: string = this.extractAssistantText(map['message'])
      if (text.length <= 0) return
      waiter.buffer = text
      if (waiter.onDelta) waiter.onDelta(text, waiter.runId)
      return
    }
    if (state === 'final') {
      waiter.finished = true
      clearTimeout(waiter.timeoutId)
      const text: string = this.extractAssistantText(map['message'])
      const finalText: string = text.length > 0 ? text : waiter.buffer
      waiter.resolve({
        ok: true,
        text: finalText,
        errorText: '',
        runId: waiter.runId
      })
      this.chatWaiter = undefined
      return
    }
    if (state === 'error') {
      waiter.finished = true
      clearTimeout(waiter.timeoutId)
      const msg: string = String(map['errorMessage'] ?? 'chat failed').trim()
      waiter.reject(new Error(msg.length > 0 ? msg : 'chat failed'))
      this.chatWaiter = undefined
    }
  }

  private async waitForChatFinal(
    sessionKey: string,
    runId: string,
    timeoutMs: number | undefined,
    onDelta?: (text: string, runId: string) => void
  ): Promise<OpenClawGatewayWsChatResult> {
    const finalTimeoutMs: number = Math.max(1000, timeoutMs ?? this.readTimeoutMs)
    if (this.chatWaiter && !this.chatWaiter.finished) {
      this.rejectActiveChat(new Error('chat waiter replaced'))
    }
    return await new Promise<OpenClawGatewayWsChatResult>((resolve, reject): void => {
      const timerId: number = setTimeout((): void => {
        void this.abortRun(sessionKey, runId)
        if (this.chatWaiter && this.chatWaiter.runId === runId) {
          this.chatWaiter.finished = true
          this.chatWaiter = undefined
        }
        reject(new Error('gateway chat timeout'))
      }, finalTimeoutMs) as unknown as number
      this.chatWaiter = {
        runId,
        sessionKey,
        buffer: '',
        resolve,
        reject,
        timeoutId: timerId,
        onDelta,
        finished: false
      }
    })
  }

  private rebindActiveChatRunId(oldRunId: string, newRunId: string): void {
    if (!this.chatWaiter || this.chatWaiter.finished) return
    if (this.chatWaiter.runId !== oldRunId) return
    const one: string = newRunId.trim()
    if (one.length <= 0) return
    this.chatWaiter.runId = one
  }

  private async abortRun(sessionKey: string, runId: string): Promise<void> {
    try {
      await this.request('chat.abort', { sessionKey, runId }, Math.min(3000, this.connectTimeoutMs))
    } catch (_) {}
  }

  private async request(
    method: string,
    params: Record<string, Object | string | number | boolean | undefined>,
    timeoutMs: number
  ): Promise<Record<string, Object | string | number | boolean | undefined>> {
    const socket: webSocket.WebSocket | undefined = this.socket
    if (!socket) throw new Error('gateway not connected')
    const reqId: string = this.nextId('req')
    const frame: Record<string, Object | string> = {
      type: 'req',
      id: reqId,
      method,
      params: JSON.stringify(params)
    }
    return await new Promise<Record<string, Object | string | number | boolean | undefined>>((resolve, reject): void => {
      const timerId: number = setTimeout((): void => {
        const pending: PendingRequest | undefined = this.pending[reqId]
        if (!pending) return
        this.pending[reqId] = undefined as unknown as PendingRequest
        delete this.pending[reqId]
        reject(new Error(`gateway request timeout for ${method}`))
      }, Math.max(1000, timeoutMs)) as unknown as number
      this.pending[reqId] = {
        resolve,
        reject,
        timeoutId: timerId
      }
      void socket.send(JSON.stringify({
        type: 'req',
        id: reqId,
        method,
        params
      })).catch((e: Error): void => {
        clearTimeout(timerId)
        this.pending[reqId] = undefined as unknown as PendingRequest
        delete this.pending[reqId]
        reject(e)
      })
    })
  }

  private extractAssistantText(message: unknown): string {
    if (typeof message === 'string') return message.trim()
    if (!message || typeof message !== 'object') return ''
    const map: Record<string, unknown> = message as Record<string, unknown>
    const text: unknown = map['text']
    if (typeof text === 'string') return text.trim()
    const content: unknown = map['content']
    if (!Array.isArray(content)) return ''
    let merged: string = ''
    for (let i: number = 0; i < content.length; i++) {
      const part: unknown = content[i]
      if (!part || typeof part !== 'object') continue
      const one: Record<string, unknown> = part as Record<string, unknown>
      const rawText: unknown = one['text']
      if (typeof rawText !== 'string') continue
      const clean: string = rawText.trim()
      if (clean.length <= 0) continue
      merged = merged.length <= 0 ? clean : `${merged}\n${clean}`
    }
    return merged.trim()
  }

  private rejectConnect(err: Error): void {
    if (this.connectDone) return
    const rejecter = this.connectRejecter
    this.connectResolver = undefined
    this.connectRejecter = undefined
    if (rejecter) rejecter(err)
  }

  private rejectAllPending(err: Error): void {
    const keys: Array<string> = Object.keys(this.pending)
    for (let i: number = 0; i < keys.length; i++) {
      const key: string = keys[i]
      const one: PendingRequest | undefined = this.pending[key]
      if (!one) continue
      clearTimeout(one.timeoutId)
      one.reject(err)
      this.pending[key] = undefined as unknown as PendingRequest
      delete this.pending[key]
    }
  }

  private rejectActiveChat(err: Error): void {
    const waiter: ActiveChatWaiter | undefined = this.chatWaiter
    if (!waiter || waiter.finished) return
    waiter.finished = true
    clearTimeout(waiter.timeoutId)
    waiter.reject(err)
    this.chatWaiter = undefined
  }

  private decodeWsMessage(data: string | ArrayBuffer): string {
    if (typeof data === 'string') return data
    return this.decoder.decodeWithStream(new Uint8Array(data), { stream: false })
  }

  private async safeCloseSocket(): Promise<void> {
    this.closed = true
    const socket: webSocket.WebSocket | undefined = this.socket
    this.socket = undefined
    if (!socket) return
    try {
      await socket.close({ code: 1000, reason: 'done' })
    } catch (_) {
      try { await socket.close() } catch (_) {}
    }
  }

  private nextId(prefix: string): string {
    this.reqSeq += 1
    return `${prefix}_${Date.now()}_${this.reqSeq}`
  }
}

