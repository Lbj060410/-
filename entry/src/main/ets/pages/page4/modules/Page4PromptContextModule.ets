import { OpenClawChatMessage } from '../../../services/assistant/OpenClawGatewayClient'

export class Page4PromptContextModule {
  static normalizePlaceInput(text: string): string {
    return text.trim().toUpperCase().replace(/[，。！？、；：,.!?\-_/\\()\[\]\s]/g, '')
  }

  static buildOpenClawRuntimeContextPrompt(
    mode: string,
    autoFollowEnabled: boolean,
    mappingText: string,
    placeBindingTraceText: string
  ): string {
    return `系统上下文：默认地址=江西省南昌市；当前可用点位为A1-G7；当前模式=${mode}；自动跟随=${autoFollowEnabled ? 'ON' : 'OFF'}；业务类型=无人物流车。\n${mappingText}\n方法轨迹：${placeBindingTraceText}\n语义约定：home=物流中心，company=快递点。`
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
    return `系统上下文：默认地址=江西省南昌市；当前模式=${mode}；自动跟随=${autoFollowEnabled ? 'ON' : 'OFF'}；链路=${connStateText}；当前小车电量=${batteryPct}%；物流中心=${homeBindingText}；快递点=${companyBindingText}；方法轨迹=${placeBindingTraceText}。`
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
