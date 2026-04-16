/**
 * 鸿蒙平板伴侣代理协议（MVP）
 * 用于 page4 -> 网关 -> 平板伴侣代理 的统一入参与回包定义。
 */

export type TabletCompanionAction =
  'set_alarm' |
  'open_app' |
  'list_alarm' |
  'start_ability' |
  'open_url'

export interface TabletSetAlarmArgs {
  hour: number
  minute: number
  label?: string
}

export interface TabletOpenAppArgs {
  bundleName: string
  abilityName?: string
}

export interface TabletStartAbilityArgs {
  bundleName: string
  abilityName?: string
  parameters?: Record<string, Object | string | number | boolean>
}

export interface TabletOpenUrlArgs {
  url: string
}

export interface TabletCompanionInvokeRequest {
  nodeId: string
  action: TabletCompanionAction
  args: Record<string, Object | string | number | boolean | undefined>
}

export interface TabletAlarmItem {
  id: string
  hour: number
  minute: number
  label: string
  enabled: boolean
}

export interface TabletCompanionInvokeResponse {
  ok: boolean
  message: string
  data?: Record<string, Object | string | number | boolean | Array<Object>>
}
