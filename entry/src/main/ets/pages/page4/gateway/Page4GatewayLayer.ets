import {
  buildOpenClawChatCompletionsUrl,
  buildOpenClawGatewayWsUrl,
  buildPcToolGatewayUrl,
  buildTabletCompanionUrl,
  OPENCLAW_CHAT_MODEL,
  PC_TOOL_CONNECT_TIMEOUT_MS,
  PC_TOOL_READ_TIMEOUT_MS,
  TABLET_COMPANION_CONNECT_TIMEOUT_MS,
  TABLET_COMPANION_NODE_ID,
  TABLET_COMPANION_READ_TIMEOUT_MS
} from '../../../config/DeviceNetworkConfig'
import { OpenClawGatewayClient, OpenClawChatMessage } from '../../../services/assistant/OpenClawGatewayClient'
import { OpenClawGatewayWsClient } from '../../../services/assistant/OpenClawGatewayWsClient'
import { PcToolGatewayClient } from '../../../services/assistant/PcToolGatewayClient'
import { TabletCompanionClient } from '../../../services/assistant/TabletCompanionClient'

export interface Page4GatewayState {
  lastGoodOpenClawHost: string
  openClawHostCooldownUntilMs: Record<string, number>
  openClawHostCooldownMs: number
  openClawWsSessionKey?: string
}

export class Page4GatewayLayer {
  static summarizePcToolText(toolName: string, text: string): string {
    const one: string = text.trim()
    if (one.length <= 0) return `pc.${toolName}: (empty)`
    const short: string = one.length > 240 ? `${one.substring(0, 240)}...` : one
    return `pc.${toolName}: ${short}`
  }

  static summarizeTabletCompanionText(action: string, text: string): string {
    const one: string = text.trim()
    if (one.length <= 0) return `tablet.${action}: (empty)`
    const short: string = one.length > 240 ? `${one.substring(0, 240)}...` : one
    return `tablet.${action}: ${short}`
  }

  static normalizeGatewayErrorText(raw: string): string {
    const text: string = raw.trim()
    if (text.length <= 0) return 'unknown'
    if (text.indexOf('ECONNREFUSED') >= 0) return '连接被拒绝'
    if (text.indexOf('ETIMEDOUT') >= 0 || text.indexOf('timeout') >= 0) return '连接超时'
    if (text.indexOf('401') >= 0 || text.indexOf('Unauthorized') >= 0) return '鉴权失败'
    if (text.indexOf('403') >= 0 || text.indexOf('Forbidden') >= 0) return '权限不足'
    return text
  }

  static isOpenClawHostCooling(state: Page4GatewayState, host: string, nowMs: number): boolean {
    const untilMs: number | undefined = state.openClawHostCooldownUntilMs[host]
    return typeof untilMs === 'number' && untilMs > nowMs
  }

  static markOpenClawHostSuccess(state: Page4GatewayState, host: string): Page4GatewayState {
    state.lastGoodOpenClawHost = host
    state.openClawHostCooldownUntilMs[host] = 0
    return state
  }

  static markOpenClawHostFail(state: Page4GatewayState, host: string): Page4GatewayState {
    state.openClawHostCooldownUntilMs[host] = Date.now() + state.openClawHostCooldownMs
    return state
  }

  static rankOpenClawHosts(state: Page4GatewayState, inputHosts: Array<string>): Array<string> {
    const out: Array<string> = []
    const normal: Array<string> = []
    const cooling: Array<string> = []
    const nowMs: number = Date.now()
    const pushUnique = (arr: Array<string>, host: string): void => {
      for (let i: number = 0; i < arr.length; i++) {
        if (arr[i] === host) return
      }
      arr.push(host)
    }

    for (let i: number = 0; i < inputHosts.length; i++) {
      const host: string = inputHosts[i].trim()
      if (host.length <= 0) continue
      if (this.isOpenClawHostCooling(state, host, nowMs)) pushUnique(cooling, host)
      else pushUnique(normal, host)
    }

    const preferred: string = state.lastGoodOpenClawHost.trim()
    if (preferred.length > 0) {
      for (let i: number = 0; i < normal.length; i++) {
        if (normal[i] === preferred) {
          out.push(preferred)
          break
        }
      }
    }

    for (let i: number = 0; i < normal.length; i++) {
      const host: string = normal[i]
      let exists: boolean = false
      for (let j: number = 0; j < out.length; j++) {
        if (out[j] === host) {
          exists = true
          break
        }
      }
      if (!exists) out.push(host)
    }

    for (let i: number = 0; i < cooling.length; i++) out.push(cooling[i])
    return out
  }

  static async callPcToolGateway(
    state: Page4GatewayState,
    toolName: string,
    payload: Record<string, Object | string | number | boolean>,
    hosts: Array<string>,
    tokens: Array<string>
  ): Promise<{ ok: boolean, summary: string, state: Page4GatewayState }> {
    if (hosts.length <= 0) return { ok: false, summary: '未检测到 PC 工具网关主机地址。', state }
    const errs: Array<string> = []
    for (let i: number = 0; i < hosts.length; i++) {
      const host: string = hosts[i]
      for (let k: number = 0; k < tokens.length; k++) {
        const token: string = tokens[k]
        const client: PcToolGatewayClient = new PcToolGatewayClient({
          endpoint: buildPcToolGatewayUrl(host, toolName),
          bearerToken: token,
          connectTimeoutMs: PC_TOOL_CONNECT_TIMEOUT_MS,
          readTimeoutMs: PC_TOOL_READ_TIMEOUT_MS
        })
        const result = await client.call(payload)
        if (result.ok) {
          state = this.markOpenClawHostSuccess(state, host)
          return { ok: true, summary: this.summarizePcToolText(toolName, result.text), state }
        }
        errs.push(`${host}/${k + 1}:${this.normalizeGatewayErrorText(result.errorText)}`)
      }
      state = this.markOpenClawHostFail(state, host)
    }
    const merged: string = errs.length > 0 ? errs.join(' | ') : '请求失败'
    return { ok: false, summary: `pc.${toolName}: ${merged}`, state }
  }

  static async callTabletCompanion(
    state: Page4GatewayState,
    action: string,
    args: Record<string, Object | string | number | boolean>,
    hosts: Array<string>,
    tokens: Array<string>,
    nodeId: string = TABLET_COMPANION_NODE_ID
  ): Promise<{ ok: boolean, summary: string, state: Page4GatewayState }> {
    if (hosts.length <= 0) return { ok: false, summary: '未检测到平板伴侣主机地址。', state }
    const errs: Array<string> = []
    for (let i: number = 0; i < hosts.length; i++) {
      const host: string = hosts[i]
      for (let k: number = 0; k < tokens.length; k++) {
        const token: string = tokens[k]
        const client: TabletCompanionClient = new TabletCompanionClient({
          endpoint: buildTabletCompanionUrl(host, action),
          bearerToken: token,
          nodeId,
          connectTimeoutMs: TABLET_COMPANION_CONNECT_TIMEOUT_MS,
          readTimeoutMs: TABLET_COMPANION_READ_TIMEOUT_MS
        })
        const result = await client.invoke(args)
        if (result.ok) {
          state = this.markOpenClawHostSuccess(state, host)
          return { ok: true, summary: this.summarizeTabletCompanionText(action, result.text), state }
        }
        errs.push(`${host}/${k + 1}:${this.normalizeGatewayErrorText(result.errorText)}`)
      }
      state = this.markOpenClawHostFail(state, host)
    }
    const merged: string = errs.length > 0 ? errs.join(' | ') : '请求失败'
    return { ok: false, summary: `tablet.${action}: ${merged}`, state }
  }

  static async completeOpenClaw(
    state: Page4GatewayState,
    messages: Array<OpenClawChatMessage>,
    hosts: Array<string>,
    tokens: Array<string>,
    connectTimeoutMs: number,
    readTimeoutMs: number,
    model: string = OPENCLAW_CHAT_MODEL,
    streamCallbacks?: {
      onStarted?: (runId: string) => void
      onDelta?: (text: string, runId: string) => void
    }
  ): Promise<{ ok: boolean, text: string, error: string, state: Page4GatewayState }> {
    const errs: Array<string> = []
    const mergedPrompt: string = this.buildWsPromptFromMessages(messages)
    const wsTimeoutMs: number = Math.max(5000, Math.min(readTimeoutMs, 12000))
    for (let i: number = 0; i < hosts.length; i++) {
      const host: string = hosts[i]
      for (let k: number = 0; k < tokens.length; k++) {
        const token: string = tokens[k]
        const sessionKey: string = this.ensureOpenClawWsSessionKey(state)

        if (mergedPrompt.length > 0) {
          const wsClient: OpenClawGatewayWsClient = new OpenClawGatewayWsClient({
            url: buildOpenClawGatewayWsUrl(host),
            bearerToken: token,
            connectTimeoutMs,
            readTimeoutMs: wsTimeoutMs
          })
          const wsResult = await wsClient.chat({
            sessionKey,
            message: mergedPrompt,
            timeoutMs: wsTimeoutMs,
            onStarted: streamCallbacks?.onStarted,
            onDelta: streamCallbacks?.onDelta
          })
          if (wsResult.ok && wsResult.text.trim().length > 0) {
            state = this.markOpenClawHostSuccess(state, host)
            return { ok: true, text: wsResult.text, error: '', state }
          }
          if (wsResult.errorText.trim().length > 0) {
            errs.push(`${host}/${k + 1} WS ${this.normalizeGatewayErrorText(wsResult.errorText)}`)
          }
        }

        const client: OpenClawGatewayClient = new OpenClawGatewayClient({
          endpoint: buildOpenClawChatCompletionsUrl(host),
          bearerToken: token,
          model,
          connectTimeoutMs,
          readTimeoutMs
        })
        const result = await client.complete(messages)
        if (result.ok) {
          state = this.markOpenClawHostSuccess(state, host)
          return { ok: true, text: result.text, error: '', state }
        }
        const codeText: string = result.responseCode > 0 ? `HTTP ${result.responseCode}` : 'NETWORK'
        errs.push(`${host}/${k + 1} ${codeText} ${this.normalizeGatewayErrorText(result.errorText)}`)
      }
      state = this.markOpenClawHostFail(state, host)
    }
    return { ok: false, text: '', error: errs.join(' || '), state }
  }

  private static buildWsPromptFromMessages(messages: Array<OpenClawChatMessage>): string {
    if (messages.length <= 0) return ''
    const systemParts: Array<string> = []
    const convoParts: Array<string> = []
    for (let i: number = 0; i < messages.length; i++) {
      const one: OpenClawChatMessage = messages[i]
      const content: string = one.content.trim()
      if (content.length <= 0) continue
      if (one.role === 'system') {
        systemParts.push(content)
        continue
      }
      const who: string = one.role === 'assistant' ? '助手' : '用户'
      convoParts.push(`${who}：${content}`)
    }
    const blocks: Array<string> = []
    if (systemParts.length > 0) blocks.push(systemParts.join('\n\n'))
    if (convoParts.length > 0) blocks.push(convoParts.join('\n'))
    return blocks.join('\n\n').trim()
  }

  private static ensureOpenClawWsSessionKey(state: Page4GatewayState): string {
    const existing: string = String(state.openClawWsSessionKey ?? '').trim()
    if (existing.length > 0) return existing
    const key: string = `agent:main:direct:page4-${Date.now()}`
    state.openClawWsSessionKey = key
    return key
  }
}
