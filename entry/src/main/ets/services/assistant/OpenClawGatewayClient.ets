/**
 * 代码指南：
 * 文件： services/assistant/OpenClawGatewayClient.ets
 * 用途： Call OpenClaw gateway OpenAI-compatible HTTP endpoint for chat responses.
 * 何时修改： adjusting auth, request payload, timeout, or response parsing.
 * 相关文件： pages/page4/Page4View.ets, config/DeviceNetworkConfig.ets.
 */
import http from '@ohos.net.http'

export interface OpenClawChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string
}

export interface OpenClawCompletionResult {
  ok: boolean
  text: string
  errorText: string
  responseCode: number
}

export interface OpenClawGatewayClientOptions {
  endpoint: string
  bearerToken: string
  model: string
  connectTimeoutMs: number
  readTimeoutMs: number
}

interface OpenClawResponseChoice {
  message?: {
    role?: unknown
    content?: unknown
  }
}

interface OpenClawErrorShape {
  message?: unknown
  type?: unknown
  code?: unknown
}

interface OpenClawResponseShape {
  choices?: Array<OpenClawResponseChoice>
  error?: OpenClawErrorShape
}

interface HttpBusinessErrorLike {
  code?: number | string
  message?: string
}

export class OpenClawGatewayClient {
  private readonly endpoint: string
  private readonly bearerToken: string
  private readonly model: string
  private readonly connectTimeoutMs: number
  private readonly readTimeoutMs: number

  constructor(options: OpenClawGatewayClientOptions) {
    this.endpoint = options.endpoint
    this.bearerToken = options.bearerToken.trim()
    this.model = options.model.trim()
    this.connectTimeoutMs = Math.max(1000, options.connectTimeoutMs)
    this.readTimeoutMs = Math.max(1000, options.readTimeoutMs)
  }

  async complete(messages: Array<OpenClawChatMessage>): Promise<OpenClawCompletionResult> {
    if (messages.length <= 0) {
      return {
        ok: false,
        text: '',
        errorText: 'empty messages',
        responseCode: 0
      }
    }

    const client: http.HttpRequest = http.createHttp()
    try {
      const reqBody: string = JSON.stringify({
        model: this.model.length > 0 ? this.model : 'openclaw',
        stream: false,
        messages: messages
      })

      const resp: http.HttpResponse = await client.request(this.endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.bearerToken}`
        },
        extraData: reqBody,
        connectTimeout: this.connectTimeoutMs,
        readTimeout: this.readTimeoutMs,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        expectDataType: http.HttpDataType.STRING
      })

      const responseCode: number = resp.responseCode
      const bodyText: string = this.asText(resp.result)
      const parsed: OpenClawResponseShape = this.safeParse(bodyText)

      if (responseCode !== 200) {
        return {
          ok: false,
          text: '',
          errorText: this.resolveErrorText(parsed, bodyText, `http code=${responseCode}`),
          responseCode
        }
      }

      const assistantText: string = this.resolveAssistantText(parsed)
      if (assistantText.length <= 0) {
        return {
          ok: false,
          text: '',
          errorText: 'empty assistant response',
          responseCode
        }
      }

      return {
        ok: true,
        text: assistantText,
        errorText: '',
        responseCode
      }
    } catch (e) {
      let msg: string = 'openclaw request failed'
      if (e instanceof Error) {
        msg = e.message
      } else if (typeof e === 'object' && e !== null) {
        const be: HttpBusinessErrorLike = e as HttpBusinessErrorLike
        const codeText: string = typeof be.code !== 'undefined' ? `code=${be.code} ` : ''
        const msgText: string = typeof be.message === 'string' && be.message.length > 0 ? be.message : 'openclaw request failed'
        msg = `${codeText}msg=${msgText}`.trim()
      }
      return {
        ok: false,
        text: '',
        errorText: this.trim(msg, 180),
        responseCode: 0
      }
    } finally {
      try { client.destroy() } catch (e) {}
    }
  }

  private resolveAssistantText(parsed: OpenClawResponseShape): string {
    const choices: Array<OpenClawResponseChoice> = Array.isArray(parsed.choices) ? parsed.choices : []
    if (choices.length <= 0) return ''
    const first: OpenClawResponseChoice = choices[0]
    if (!first.message) return ''
    return this.normalizeContent(first.message.content)
  }

  private normalizeContent(content: unknown): string {
    if (typeof content === 'string') return content.trim()

    if (Array.isArray(content)) {
      let merged: string = ''
      for (let i: number = 0; i < content.length; i++) {
        const part: unknown = content[i]
        if (!part || typeof part !== 'object') continue
        const map: Record<string, unknown> = part as Record<string, unknown>
        const text: unknown = map['text']
        const inputText: unknown = map['input_text']
        const one: string =
          typeof text === 'string'
            ? text
            : (typeof inputText === 'string' ? inputText : '')
        if (one.length <= 0) continue
        merged = merged.length <= 0 ? one : `${merged}\n${one}`
      }
      return merged.trim()
    }

    return ''
  }

  private resolveErrorText(parsed: OpenClawResponseShape, bodyText: string, fallback: string): string {
    if (parsed.error) {
      const err: OpenClawErrorShape = parsed.error
      const msg: string = typeof err.message === 'string' ? err.message : ''
      const typeText: string = typeof err.type === 'string' ? err.type : ''
      const codeText: string = typeof err.code === 'string' || typeof err.code === 'number' ? String(err.code) : ''
      const pieces: Array<string> = []
      if (msg.length > 0) pieces.push(msg)
      if (typeText.length > 0) pieces.push(`type=${typeText}`)
      if (codeText.length > 0) pieces.push(`code=${codeText}`)
      if (pieces.length > 0) return this.trim(pieces.join(' | '), 180)
    }

    if (bodyText.length > 0) {
      const normalized: string = bodyText.split('\n').join(' ').split('\r').join(' ')
      return this.trim(normalized, 180)
    }
    return fallback
  }

  private safeParse(text: string): OpenClawResponseShape {
    try {
      const obj: object = JSON.parse(text) as object
      return obj as OpenClawResponseShape
    } catch (e) {
      return {}
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
