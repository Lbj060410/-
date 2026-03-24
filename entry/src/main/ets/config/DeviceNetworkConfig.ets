/**
 * 代码指南：
 * 文件：config/DeviceNetworkConfig.ets
 * 用途：静态配置常量和配置辅助工具。
 * 何时修改：环境默认值或端点常量调整时。
 * 相关文件：services/network/* 和页面协调器。
 */
export const CAR_DEVICE_IP: string = '192.168.156.254'
export const CAR_CAMERA_IP: string = '192.168.156.90'
export const CAR_CAMERA_HTTP_PORT: number = 81
export const CAR_RTSP_PORT: number = 554
export const CAR_TCP_PORT: number = 60000
export const CAR_CAMERA_USER: string = 'admin'
export const CAR_CAMERA_PASS: string = '888888'

// OpenClaw 网关默认配置，用于 page4 助手。
// 对于真实设备：
// 1) 将 OPENCLAW_GATEWAY_HOST 设置为你的 PC 局域网 IP，或保持空以自动尝试 Wi-Fi 网关 IP。
// 2) 通过应用设置 UI 设置 OPENCLAW_GATEWAY_TOKEN — 不要在此处硬编码令牌。
export const OPENCLAW_GATEWAY_HOST: string = '192.168.156.104'
export const OPENCLAW_GATEWAY_FALLBACK_HOST: string = '192.168.3.8'
export const OPENCLAW_GATEWAY_PORT: number = 18789
export const OPENCLAW_GATEWAY_TOKEN: string = 'car-openclaw-2026'  // 与运行中的网关令牌保持同步
export const OPENCLAW_CHAT_MODEL: string = 'deepseek/deepseek-chat'
export const OPENCLAW_CONNECT_TIMEOUT_MS: number = 8000
export const OPENCLAW_READ_TIMEOUT_MS: number = 90000

// 仅作为后备。运行时应优先使用当前 Wi-Fi 网关/发现结果。

export function defaultCameraHost(): string {
  return `${CAR_CAMERA_IP}:${CAR_CAMERA_HTTP_PORT}`
}

export function defaultRtspUrl(): string {
  return `rtsp://${CAR_CAMERA_IP}:${CAR_RTSP_PORT}/stream`
}

export function buildCameraSnapshotUrl(cameraHost: string, user: string = 'admin', pass: string = ''): string {
  const parts: Array<string> = []
  const u: string = user.trim()
  const p: string = pass.trim()
  if (u.length > 0) parts.push(`loginuse=${encodeURIComponent(u)}`)
  if (p.length > 0) parts.push(`loginpas=${encodeURIComponent(p)}`)
  parts.push('res=0')
  return `http://${cameraHost}/snapshot.cgi?${parts.join('&')}`
}

export function resolveOpenClawHost(gatewayIp: string): string {
  const configured: string = OPENCLAW_GATEWAY_HOST.trim()
  if (configured.length > 0) return configured
  return gatewayIp.trim()
}

export function resolveOpenClawHostCandidates(gatewayIp: string): Array<string> {
  const out: Array<string> = []
  const pushUnique = (ip: string): void => {
    const one: string = ip.trim()
    if (one.length <= 0) return
    for (let i: number = 0; i < out.length; i++) {
      if (out[i] === one) return
    }
    out.push(one)
  }

  const configured: string = OPENCLAW_GATEWAY_HOST.trim()
  if (configured.length > 0) {
    pushUnique(configured)
    pushUnique(OPENCLAW_GATEWAY_FALLBACK_HOST)
    return out
  }

  pushUnique(gatewayIp)
  pushUnique(OPENCLAW_GATEWAY_FALLBACK_HOST)
  return out
}

export function buildOpenClawChatCompletionsUrl(host: string): string {
  return `http://${host}:${OPENCLAW_GATEWAY_PORT}/v1/chat/completions`
}


