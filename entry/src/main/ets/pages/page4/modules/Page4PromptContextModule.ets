import { OpenClawChatMessage } from '../../../services/assistant/OpenClawGatewayClient'

export class Page4PromptContextModule {
  // 增大容量以容纳中文别名、时间戳等丰富的方法轨迹数据
  private static readonly OPENCLAW_TRACE_MAX_CHARS: number = 150

  static normalizePlaceInput(text: string): string {
    return text.trim().toUpperCase().replace(/[，。！？、；：,.!?\-_/\\()\[\]\s]/g, '')
  }

  // Keep trace context short so OpenClaw does not waste time on verbose internals.
  static compactMethodTraceText(text: string): string {
    const src: string = text.trim()
    if (src.length <= 0) return 'placeBinding.idle'
    if (src.length <= this.OPENCLAW_TRACE_MAX_CHARS) return src
    return `${src.slice(0, this.OPENCLAW_TRACE_MAX_CHARS - 3)}...`
  }

  static buildOpenClawRuntimeContextPrompt(
    mode: string,
    autoFollowEnabled: boolean,
    mappingText: string,
    placeBindingTraceText: string
  ): string {
    const traceText: string = this.compactMethodTraceText(placeBindingTraceText)
    return `系统上下文：默认地址=江西省；当前可用点位为A1-G7；当前模式=${mode}；自动跟随=${autoFollowEnabled ? 'ON' : 'OFF'}；业务类型=无人物流车。\n${mappingText}\n方法轨迹：${traceText}\n语义约定：固定业务点位包含物流中心与快递点。`
  }

  static buildOpenClawRuntimeContextPromptLite(
    mode: string,
    autoFollowEnabled: boolean,
    connStateText: string,
    batteryPct: number,
    homeBindingText: string,
    companyBindingText: string,
    placeBindingTraceText: string
  ): string {
    const traceText: string = this.compactMethodTraceText(placeBindingTraceText)
    return `系统上下文：默认地址=江西省；当前模式=${mode}；自动跟随=${autoFollowEnabled ? 'ON' : 'OFF'}；链路=${connStateText}；当前小车电量=${batteryPct}%；物流中心=${homeBindingText}；快递点=${companyBindingText}；方法轨迹=${traceText}。`
  }

  static buildOpenClawMessages(
    messages: Array<{ role: 'user' | 'assistant', text: string }>,
    systemPrompt: string,
    runtimePrompt: string,
    maxHistory: number = 8
  ): Array<OpenClawChatMessage> {
    const out: Array<OpenClawChatMessage> = []
    out.push({ role: 'system', content: systemPrompt })
    out.push({ role: 'system', content: runtimePrompt })

    const begin: number = messages.length > maxHistory ? messages.length - maxHistory : 0
    for (let i: number = begin; i < messages.length; i++) {
      const msg = messages[i]
      const text: string = msg.text.trim()
      if (text.length <= 0) continue
      out.push({ role: msg.role === 'assistant' ? 'assistant' : 'user', content: text })
    }
    return out
  }
}
