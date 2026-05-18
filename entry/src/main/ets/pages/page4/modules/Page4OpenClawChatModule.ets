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
  logInfo: (name: string, message: string) => void
  logError: (name: string, message: string) => void
}

export class Page4OpenClawChatModule {
  static async answerByOpenClaw(deps: Page4OpenClawAnswerDeps): Promise<void> {
    const tokenCandidates: Array<string> = deps.resolveTokenCandidates()
    if (tokenCandidates.length <= 0) {
      deps.pushAssistant('OpenClaw token 为空，请在 DeviceNetworkConfig.ets 配置 OPENCLAW_GATEWAY_TOKEN。')
      return
    }
    const hosts: Array<string> = deps.resolveHosts()
    if (hosts.length <= 0) {
      deps.pushAssistant('未检测到 OpenClaw 主机地址。请在 DeviceNetworkConfig.ets 设置 OPENCLAW_GATEWAY_HOST。')
      return
    }
    const reqMessages: Array<OpenClawChatMessage> = deps.buildOpenClawMessages()
    deps.setAssistantBusy(true)
    const timeoutId: number = deps.setManagedTimeout((): void => {
      deps.setAssistantBusy(false)
      deps.pushAssistant('查询超时（45秒），请稍后重试。')
    }, 60000)
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
        deps.model
      )
      deps.applyGatewayState(rs.state)
      if (rs.ok) {
        deps.clearManagedTimer(timeoutId)
        deps.logInfo('sendOpenClawSuccess', `chars=${rs.text.length}`)
        deps.setAssistantBusy(false)
        deps.pushAssistant(rs.text, true)
        return
      }
      deps.logError('sendOpenClawAllFailed', rs.error.length > 0 ? rs.error : 'unknown')
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'unknown error'
      deps.logError('sendOpenClawException', msg)
    } finally {
      deps.clearManagedTimer(timeoutId)
      deps.setAssistantBusy(false)
    }
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
    const roleRaw: string = String(obj['role'] ?? '').trim().toLowerCase()
    let role: 'home' | 'company' | '' = ''
    if (roleRaw === 'home' || roleRaw === '物流中心') role = 'home'
    if (roleRaw === 'company' || roleRaw === '快递点' || roleRaw === '公司仓库') role = 'company'
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
