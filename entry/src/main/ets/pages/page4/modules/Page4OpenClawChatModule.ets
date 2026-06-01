import { OpenClawChatMessage } from '../../../services/assistant/OpenClawGatewayClient'
import { Page4GatewayLayer, Page4GatewayState } from '../gateway/Page4GatewayLayer'
import { Page4PlaceBindingPlan } from './Page4PoiBindingModule'

export interface Page4OpenClawAnswerDeps {
  resolveTokenCandidates: () => Array<string>
  resolveHosts: () => Array<string>
  buildOpenClawMessages: () => Array<OpenClawChatMessage>
  gatewayState: () => Page4GatewayState
  applyGatewayState: (state: Page4GatewayState) => void
  setAssistantBusy: (busy: boolean) => void
  setManagedTimeout: (cb: () => void, delayMs: number) => number
  clearManagedTimer: (id: number) => number
  connectTimeoutMs: () => number
  readTimeoutMs: () => number
  model: string
  pushAssistant: (text: string, typed?: boolean) => void
  beginStreamingAssistant?: () => string
  updateStreamingAssistant?: (msgId: string, text: string) => void
  finishStreamingAssistant?: (msgId: string, text: string) => void
  cancelStreamingAssistant?: (msgId: string) => void
  logInfo: (name: string, message: string) => void
  logError: (name: string, message: string) => void
}

export class Page4OpenClawChatModule {
  private static readonly TOKEN_SETUP_HINT_PATH: string =
    '/sdcard/Download/openclaw.env.json'

  private static normalizeOpenClawErrorText(raw: string): string {
    const text: string = raw.trim()
    if (text.length <= 0) return '请求失败'
    const low: string = text.toLowerCase()
    if (low.indexOf('401') >= 0 || low.indexOf('unauthorized') >= 0 || low.indexOf('forbidden') >= 0) {
      return `鉴权失败（token 无效或与网关不一致）：${text}`
    }
    if (low.indexOf('timeout') >= 0 || low.indexOf('timed out') >= 0) {
      return `网关超时：${text}`
    }
    if (low.indexOf('couldn\'t connect to server') >= 0 || low.indexOf('connect') >= 0) {
      return `网关连接失败：${text}`
    }
    return text
  }

  static async answerByOpenClaw(deps: Page4OpenClawAnswerDeps): Promise<boolean> {
    const tokenCandidates: Array<string> = deps.resolveTokenCandidates()
    if (tokenCandidates.length <= 0) {
      deps.pushAssistant(
        `OpenClaw token 为空，请在 ${this.TOKEN_SETUP_HINT_PATH} 配置 token 文件。`
      )
      return false
    }
    const hosts: Array<string> = deps.resolveHosts()
    if (hosts.length <= 0) {
      deps.pushAssistant('未检测到 OpenClaw 主机地址。请在 DeviceNetworkConfig.ets 设置 OPENCLAW_GATEWAY_HOST。')
      return false
    }
    const reqMessages: Array<OpenClawChatMessage> = deps.buildOpenClawMessages()
    deps.setAssistantBusy(true)
    const timeoutId: number = deps.setManagedTimeout((): void => {
      deps.setAssistantBusy(false)
      deps.pushAssistant('查询超时（45秒），请稍后重试。')
    }, 60000)
    let streamMsgId: string = ''
    let streamUpdated: boolean = false
    try {
      const connectTimeoutMs: number = deps.connectTimeoutMs()
      const readTimeoutMs: number = deps.readTimeoutMs()
      deps.logInfo('sendOpenClawRequest', `hosts=${hosts.length}, model=${deps.model}, messages=${reqMessages.length}, ct=${connectTimeoutMs}, rt=${readTimeoutMs}, tk=${tokenCandidates.length}`)
      const rs = await Page4GatewayLayer.completeOpenClaw(
        deps.gatewayState(),
        reqMessages,
        hosts,
        tokenCandidates,
        connectTimeoutMs,
        readTimeoutMs,
        deps.model,
        {
          onStarted: (_runId: string): void => {
            if (!deps.beginStreamingAssistant) return
            if (streamMsgId.length > 0) return
            streamMsgId = deps.beginStreamingAssistant()
          },
          onDelta: (text: string, _runId: string): void => {
            if (!deps.beginStreamingAssistant || !deps.updateStreamingAssistant) return
            if (streamMsgId.length <= 0) streamMsgId = deps.beginStreamingAssistant()
            streamUpdated = true
            deps.updateStreamingAssistant(streamMsgId, text)
          }
        }
      )
      deps.applyGatewayState(rs.state)
      if (rs.ok) {
        deps.clearManagedTimer(timeoutId)
        const answerText: string = this.ensureVisibleReasoningText(rs.text)
        deps.logInfo('sendOpenClawSuccess', `chars=${answerText.length}`)
        deps.setAssistantBusy(false)
        if (streamMsgId.length > 0 && streamUpdated && deps.finishStreamingAssistant) {
          deps.finishStreamingAssistant(streamMsgId, answerText)
        } else {
          if (streamMsgId.length > 0 && deps.cancelStreamingAssistant) deps.cancelStreamingAssistant(streamMsgId)
          deps.pushAssistant(answerText, false)
        }
        return true
      }
      if (streamMsgId.length > 0 && deps.cancelStreamingAssistant) deps.cancelStreamingAssistant(streamMsgId)
      const errText: string = rs.error.length > 0
        ? this.normalizeOpenClawErrorText(rs.error)
        : 'OpenClaw 请求失败（未知错误）'
      deps.logError('sendOpenClawAllFailed', errText)
      deps.pushAssistant(`OpenClaw 调用失败：${errText}`)
    } catch (e) {
      if (streamMsgId.length > 0 && deps.cancelStreamingAssistant) deps.cancelStreamingAssistant(streamMsgId)
      const msg: string = e instanceof Error ? e.message : 'unknown error'
      deps.logError('sendOpenClawException', msg)
    } finally {
      deps.clearManagedTimer(timeoutId)
      deps.setAssistantBusy(false)
    }
    return false
  }

  static ensureVisibleReasoningText(text: string): string {
    const body: string = text.trim()
    if (body.length <= 0) return body
    if (body.indexOf('思考过程') >= 0 || body.indexOf('最终回答') >= 0 || body.indexOf('结论') >= 0) {
      return body
    }
    return `思考过程：我正在结合当前地图、链路状态和你的指令做判断。\n最终回答：${body}`
  }

  static parsePlaceBindingPlanText(text: string): Page4PlaceBindingPlan | undefined {
    const body: string = text.trim()
    if (body.length <= 0) return undefined
    const normalized: string = this.stripJsonCodeFence(body)
    let obj: Record<string, Object | string | number | boolean | undefined> | undefined = undefined
    try {
      obj = JSON.parse(normalized) as Record<string, Object | string | number | boolean | undefined>
    } catch (_) {
      return undefined
    }
    if (!obj) return undefined
    const roleRaw: string = String(obj['role'] ?? '').trim()
    let role: 'home' | 'company' | '' = ''
    if (roleRaw === '物流中心') role = 'home'
    if (roleRaw === '快递点' || roleRaw === '快递网点') role = 'company'
    if (role.length <= 0) return undefined
    const placeText: string = String(obj['place'] ?? obj['target'] ?? obj['location'] ?? '').trim()
    if (placeText.length <= 0) return undefined
    if (role === 'home') return { role: 'home', placeText }
    if (role === 'company') return { role: 'company', placeText }
    return undefined
  }

  static stripJsonCodeFence(text: string): string {
    let s: string = text.trim()
    if (!s.startsWith('```')) return s
    const firstLf: number = s.indexOf('\n')
    if (firstLf < 0) return s
    s = s.substring(firstLf + 1)
    const endFence: number = s.lastIndexOf('```')
    if (endFence >= 0) s = s.substring(0, endFence)
    return s.trim()
  }
}
