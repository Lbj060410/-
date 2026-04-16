import http from '@ohos.net.http'

export interface TabletCompanionClientOptions {
  endpoint: string
  bearerToken: string
  nodeId: string
  connectTimeoutMs: number
  readTimeoutMs: number
}

export interface TabletCompanionResult {
  ok: boolean
  text: string
  errorText: string
  responseCode: number
}

interface HttpBusinessErrorLike {
  code?: number | string
  message?: string
}

export class TabletCompanionClient {
  private readonly endpoint: string
  private readonly bearerToken: string
  private readonly nodeId: string
  private readonly connectTimeoutMs: number
  private readonly readTimeoutMs: number

  constructor(options: TabletCompanionClientOptions) {
    this.endpoint = options.endpoint
    this.bearerToken = options.bearerToken.trim()
    this.nodeId = options.nodeId.trim()
    this.connectTimeoutMs = Math.max(1000, options.connectTimeoutMs)
    this.readTimeoutMs = Math.max(1000, options.readTimeoutMs)
  }

  async invoke(args: Record<string, Object | string | number | boolean | undefined>): Promise<TabletCompanionResult> {
    const client: http.HttpRequest = http.createHttp()
    try {
      const reqBody: string = JSON.stringify({ nodeId: this.nodeId, args })
      const headers: Record<string, string> = { 'Content-Type': 'application/json' }
      if (this.bearerToken.length > 0) headers['Authorization'] = `Bearer ${this.bearerToken}`
      const resp: http.HttpResponse = await client.request(this.endpoint, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: reqBody,
        connectTimeout: this.connectTimeoutMs,
        readTimeout: this.readTimeoutMs,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        expectDataType: http.HttpDataType.STRING
      })
      const responseCode: number = resp.responseCode
      const bodyText: string = this.asText(resp.result).trim()
      if (responseCode !== 200) {
        return { ok: false, text: '', errorText: bodyText.length > 0 ? bodyText : `http code=${responseCode}`, responseCode }
      }
      return { ok: true, text: bodyText, errorText: '', responseCode }
    } catch (e) {
      let msg: string = 'tablet companion request failed'
      if (e instanceof Error) msg = e.message
      else if (typeof e === 'object' && e !== null) {
        const be: HttpBusinessErrorLike = e as HttpBusinessErrorLike
        const codeText: string = typeof be.code !== 'undefined' ? `code=${be.code} ` : ''
        const msgText: string = typeof be.message === 'string' && be.message.length > 0 ? be.message : 'tablet companion request failed'
        msg = `${codeText}msg=${msgText}`.trim()
      }
      return { ok: false, text: '', errorText: this.trim(msg, 180), responseCode: 0 }
    } finally {
      try { client.destroy() } catch (_) {}
    }
  }

  private asText(input: unknown): string {
    if (typeof input === 'string') return input
    return String(input ?? '')
  }

  private trim(s: string, maxLen: number): string {
    if (s.length <= maxLen) return s
    return s.substring(0, maxLen)
  }
}

