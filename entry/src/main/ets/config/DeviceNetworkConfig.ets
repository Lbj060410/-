/**
 * 代码指南：
 * 文件：config/DeviceNetworkConfig.ets
 * 用途：静态配置常量和配置辅助工具。
 * 何时修改：环境默认值或端点常量调整时。
 * 相关文件：services/network/* 和页面协调器。
 */
export const CAR_DEVICE_IP: string = '192.168.156.254'
export const CAR_CAMERA_IP: string = '192.168.156.90'
// RTSP 摄像头与 HTTP 摄像头为同一台设备，统一使用上方 IP
export const CAR_CAMERA_HTTP_PORT: number = 81
export const CAR_RTSP_PORT: number = 10554
export const CAR_TCP_PORT: number = 60000
export const CAR_CAMERA_USER: string = 'admin'
export const CAR_CAMERA_PASS: string = '888888'

// OpenClaw 网关默认配置，用于 page4 助手。
// 对于真实设备：
// 1) 将 OPENCLAW_GATEWAY_HOST 设置为你的 PC 局域网 IP，或保持空以自动尝试 Wi-Fi 网关 IP。
// 2) 将 token 写入公共目录 openclaw.env.json（由 page4 在运行时加载）— 不要在此处硬编码令牌。
export const OPENCLAW_GATEWAY_HOST: string = '192.168.156.101'
export const OPENCLAW_GATEWAY_FALLBACK_HOST: string = '10.184.142.215'
export const OPENCLAW_GATEWAY_PORT: number = 18789
export const OPENCLAW_GATEWAY_TOKEN: string = ''
export const OPENCLAW_GATEWAY_TOKEN_FALLBACK: string = ''
export const OPENCLAW_CHAT_MODEL: string = 'deepseek-v4-pro'
export const OPENCLAW_CONNECT_TIMEOUT_MS: number = 12000
export const OPENCLAW_READ_TIMEOUT_MS: number = 60000

// PC 工具网关配置（MVP）：
// 用于执行受控工具：read_file / process_list / exec_cmd(白名单)。
export const PC_TOOL_GATEWAY_HOST: string = '192.168.156.101'
export const PC_TOOL_GATEWAY_PORT: number = 18789
export const PC_TOOL_GATEWAY_TOKEN: string = ''
export const PC_TOOL_GATEWAY_TOKEN_FALLBACK: string = OPENCLAW_GATEWAY_TOKEN_FALLBACK
export const PC_TOOL_CONNECT_TIMEOUT_MS: number = 5000
export const PC_TOOL_READ_TIMEOUT_MS: number = 20000

// 鸿蒙平板伴侣代理配置（MVP）：
// 通过代理 App 执行受控跨应用能力（如设置闹钟、打开应用）。
export const TABLET_COMPANION_HOST: string = '192.168.156.101'
export const TABLET_COMPANION_PORT: number = 18789
export const TABLET_COMPANION_TOKEN: string = ''
export const TABLET_COMPANION_TOKEN_FALLBACK: string = OPENCLAW_GATEWAY_TOKEN_FALLBACK
export const TABLET_COMPANION_NODE_ID: string = 'tablet-main'
export const TABLET_COMPANION_CONNECT_TIMEOUT_MS: number = 5000
export const TABLET_COMPANION_READ_TIMEOUT_MS: number = 20000

// 仅作为后备。运行时应优先使用当前 Wi-Fi 网关/发现结果。
const runtimeSecretMap: Record<string, string> = {}

export function setRuntimeSecret(name: string, value: string): void {
  const key: string = name.trim()
  if (key.length <= 0) return
  const one: string = value.trim()
  if (one.length <= 0) {
    if (runtimeSecretMap[key] !== undefined) delete runtimeSecretMap[key]
    return
  }
  runtimeSecretMap[key] = one
}

function readEnvString(name: string): string {
  const key: string = name.trim()
  if (key.length <= 0) return ''
  const root: Record<string, Object | string | undefined> = globalThis as Record<string, Object | string | undefined>
  const processObj: Record<string, Object | string | undefined> | undefined =
    (root['process'] as Record<string, Object | string | undefined> | undefined)
  const envObj: Record<string, Object | string | undefined> | undefined =
    processObj ? (processObj['env'] as Record<string, Object | string | undefined> | undefined) : undefined
  const envVal: Object | string | undefined = envObj ? envObj[key] : undefined
  if (typeof envVal === 'string' && envVal.trim().length > 0) return envVal.trim()
  const runtimeVal: string | undefined = runtimeSecretMap[key]
  if (typeof runtimeVal === 'string' && runtimeVal.trim().length > 0) return runtimeVal.trim()

  // Optional fallback for runtimes that inject env-like values directly on globalThis.
  const globalVal: Object | string | undefined = root[key]
  if (typeof globalVal === 'string' && globalVal.trim().length > 0) return globalVal.trim()
  return ''
}

export function defaultCameraHost(): string {
  return `${CAR_CAMERA_IP}:${CAR_CAMERA_HTTP_PORT}`
}

export function defaultRtspUrl(): string {
  const user: string = CAR_CAMERA_USER.trim()
  const pass: string = CAR_CAMERA_PASS.trim()
  if (user.length > 0 && pass.length > 0) {
    return `rtsp://${user}:${pass}@${CAR_CAMERA_IP}:${CAR_RTSP_PORT}/tcp/av0_0`
  }
  return `rtsp://${CAR_CAMERA_IP}:${CAR_RTSP_PORT}/tcp/av0_0`
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
  const appendSubnetCandidates = (ip: string): void => {
    const one: string = ip.trim()
    const idx: number = one.lastIndexOf('.')
    if (idx <= 0) return
    const prefix: string = one.substring(0, idx)
    pushUnique(`${prefix}.100`)
    pushUnique(`${prefix}.101`)
  }

  if (configured.length > 0) {
    pushUnique(configured)
    pushUnique(gatewayIp)
    appendSubnetCandidates(configured)
    appendSubnetCandidates(gatewayIp)
    pushUnique(OPENCLAW_GATEWAY_FALLBACK_HOST)
    return out
  }

  pushUnique(gatewayIp)
  appendSubnetCandidates(gatewayIp)
  pushUnique(OPENCLAW_GATEWAY_FALLBACK_HOST)
  return out
}

export function buildOpenClawChatCompletionsUrl(host: string): string {
  return `http://${host}:${OPENCLAW_GATEWAY_PORT}/v1/chat/completions`
}

export function buildOpenClawGatewayWsUrl(host: string): string {
  return `ws://${host}:${OPENCLAW_GATEWAY_PORT}`
}

export function resolvePcToolGatewayHost(gatewayIp: string): string {
  const configured: string = PC_TOOL_GATEWAY_HOST.trim()
  if (configured.length > 0) return configured
  return resolveOpenClawHost(gatewayIp)
}

export function resolvePcToolGatewayHostCandidates(gatewayIp: string): Array<string> {
  const configured: string = PC_TOOL_GATEWAY_HOST.trim()
  if (configured.length > 0) {
    const out: Array<string> = []
    const pushUnique = (ip: string): void => {
      const one: string = ip.trim()
      if (one.length <= 0) return
      for (let i: number = 0; i < out.length; i++) {
        if (out[i] === one) return
      }
      out.push(one)
    }
    pushUnique(configured)
    const fallback: Array<string> = resolveOpenClawHostCandidates(gatewayIp)
    for (let i: number = 0; i < fallback.length; i++) pushUnique(fallback[i])
    return out
  }
  return resolveOpenClawHostCandidates(gatewayIp)
}

export function buildPcToolGatewayUrl(host: string, toolName: string): string {
  const clean: string = toolName.trim().replace(/^\/+/, '')
  return `http://${host}:${PC_TOOL_GATEWAY_PORT}/v1/tools/${clean}`
}

export function resolveTabletCompanionHostCandidates(gatewayIp: string): Array<string> {
  const configured: string = TABLET_COMPANION_HOST.trim()
  if (configured.length > 0) {
    const out: Array<string> = []
    const pushUnique = (ip: string): void => {
      const one: string = ip.trim()
      if (one.length <= 0) return
      for (let i: number = 0; i < out.length; i++) {
        if (out[i] === one) return
      }
      out.push(one)
    }
    pushUnique(configured)
    const fallback: Array<string> = resolveOpenClawHostCandidates(gatewayIp)
    for (let i: number = 0; i < fallback.length; i++) pushUnique(fallback[i])
    return out
  }
  return resolveOpenClawHostCandidates(gatewayIp)
}

export function buildTabletCompanionUrl(host: string, action: string): string {
  const clean: string = action.trim().replace(/^\/+/, '')
  return `http://${host}:${TABLET_COMPANION_PORT}/v1/tablet/${clean}`
}

function pushUniqueToken(out: Array<string>, token: string): void {
  const one: string = token.trim()
  if (one.length <= 0) return
  for (let i: number = 0; i < out.length; i++) {
    if (out[i] === one) return
  }
  out.push(one)
}

export function resolveOpenClawTokenCandidates(): Array<string> {
  const out: Array<string> = []
  pushUniqueToken(out, readEnvString('OPENCLAW_GATEWAY_TOKEN'))
  pushUniqueToken(out, readEnvString('OPENCLAW_GATEWAY_TOKEN_FALLBACK'))
  pushUniqueToken(out, OPENCLAW_GATEWAY_TOKEN)
  pushUniqueToken(out, OPENCLAW_GATEWAY_TOKEN_FALLBACK)
  return out
}

export function resolvePcToolTokenCandidates(): Array<string> {
  const out: Array<string> = []
  pushUniqueToken(out, readEnvString('PC_TOOL_GATEWAY_TOKEN'))
  pushUniqueToken(out, readEnvString('PC_TOOL_GATEWAY_TOKEN_FALLBACK'))
  pushUniqueToken(out, readEnvString('OPENCLAW_GATEWAY_TOKEN'))
  pushUniqueToken(out, readEnvString('OPENCLAW_GATEWAY_TOKEN_FALLBACK'))
  pushUniqueToken(out, PC_TOOL_GATEWAY_TOKEN)
  pushUniqueToken(out, PC_TOOL_GATEWAY_TOKEN_FALLBACK)
  pushUniqueToken(out, OPENCLAW_GATEWAY_TOKEN)
  pushUniqueToken(out, OPENCLAW_GATEWAY_TOKEN_FALLBACK)
  return out
}

export function resolveTabletCompanionTokenCandidates(): Array<string> {
  const out: Array<string> = []
  pushUniqueToken(out, readEnvString('TABLET_COMPANION_TOKEN'))
  pushUniqueToken(out, readEnvString('TABLET_COMPANION_TOKEN_FALLBACK'))
  pushUniqueToken(out, readEnvString('OPENCLAW_GATEWAY_TOKEN'))
  pushUniqueToken(out, readEnvString('OPENCLAW_GATEWAY_TOKEN_FALLBACK'))
  pushUniqueToken(out, TABLET_COMPANION_TOKEN)
  pushUniqueToken(out, TABLET_COMPANION_TOKEN_FALLBACK)
  pushUniqueToken(out, OPENCLAW_GATEWAY_TOKEN)
  pushUniqueToken(out, OPENCLAW_GATEWAY_TOKEN_FALLBACK)
  return out
}
