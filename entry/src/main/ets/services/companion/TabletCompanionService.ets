import hilog from '@ohos.hilog'
import type common from '@ohos.app.ability.common'
import Want from '@ohos.app.ability.Want'
import {
  TabletAlarmItem,
  TabletCompanionAction,
  TabletCompanionInvokeRequest,
  TabletCompanionInvokeResponse
} from './TabletCompanionContract'

const COMPANION_DOMAIN = 0xFF45
const COMPANION_TAG = 'TabletCompanionService'
const DEFAULT_CLOCK_BUNDLE = 'com.huawei.clock'
const DEFAULT_CLOCK_ABILITY = 'EntryAbility'

export class TabletCompanionService {
  private alarms: Array<TabletAlarmItem> = []

  async invoke(req: TabletCompanionInvokeRequest): Promise<TabletCompanionInvokeResponse> {
    const action: TabletCompanionAction = req.action
    if (action === 'set_alarm') return this.onSetAlarm(req)
    if (action === 'open_app') return this.onOpenApp(req)
    if (action === 'list_alarm') return this.onListAlarm()
    if (action === 'start_ability') return this.onStartAbility(req)
    if (action === 'open_url') return this.onOpenUrl(req)
    return { ok: false, message: `unsupported action=${action}` }
  }

  private async onSetAlarm(req: TabletCompanionInvokeRequest): Promise<TabletCompanionInvokeResponse> {
    const hour: number = Math.trunc(Number(req.args['hour']))
    const minute: number = Math.trunc(Number(req.args['minute']))
    const label: string = String(req.args['label'] ?? '物流任务提醒').trim()
    if (!Number.isFinite(hour) || !Number.isFinite(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return { ok: false, message: 'bad args: hour/minute' }
    }

    const id: string = `${Date.now()}-${hour}-${minute}`
    this.alarms.unshift({
      id,
      hour,
      minute,
      label: label.length > 0 ? label : '物流任务提醒',
      enabled: true
    })
    if (this.alarms.length > 100) this.alarms = this.alarms.slice(0, 100)

    const openResult = await this.openClockForAlarm(hour, minute, label)
    if (!openResult.ok) {
      return {
        ok: false,
        message: `set_alarm failed: ${openResult.message}`,
        data: { id, hour, minute, label }
      }
    }
    hilog.info(COMPANION_DOMAIN, COMPANION_TAG, `set_alarm ok id=${id} time=${hour}:${minute} label=${label}`)
    return {
      ok: true,
      message: `alarm set ${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`,
      data: { id, hour, minute, label, enabled: true }
    }
  }

  private async onOpenApp(req: TabletCompanionInvokeRequest): Promise<TabletCompanionInvokeResponse> {
    const bundleName: string = String(req.args['bundleName'] ?? '').trim()
    const abilityName: string = String(req.args['abilityName'] ?? '').trim()
    if (bundleName.length <= 0) return { ok: false, message: 'bad args: bundleName empty' }

    const openResult = await this.openApp(bundleName, abilityName)
    if (!openResult.ok) {
      return { ok: false, message: `open_app failed: ${openResult.message}` }
    }
    hilog.info(COMPANION_DOMAIN, COMPANION_TAG, `open_app ok bundle=${bundleName} ability=${abilityName}`)
    return {
      ok: true,
      message: `open_app done`,
      data: { bundleName, abilityName }
    }
  }

  private async onListAlarm(): Promise<TabletCompanionInvokeResponse> {
    const items: Array<Object> = []
    for (let i: number = 0; i < this.alarms.length; i++) items.push(this.alarms[i] as unknown as Object)
    return {
      ok: true,
      message: `alarms=${this.alarms.length}`,
      data: { alarms: items }
    }
  }

  private async onStartAbility(req: TabletCompanionInvokeRequest): Promise<TabletCompanionInvokeResponse> {
    const bundleName: string = String(req.args['bundleName'] ?? '').trim()
    const abilityName: string = String(req.args['abilityName'] ?? '').trim()
    if (bundleName.length <= 0) return { ok: false, message: 'bad args: bundleName empty' }

    const paramsRaw: Object | string | number | boolean | undefined = req.args['parameters']
    const parameters: Record<string, Object | string | number | boolean> =
      typeof paramsRaw === 'object' && paramsRaw !== null
        ? (paramsRaw as Record<string, Object | string | number | boolean>)
        : {}

    const openResult = await this.startAbilityByWant(bundleName, abilityName, parameters)
    if (!openResult.ok) return { ok: false, message: `start_ability failed: ${openResult.message}` }
    return {
      ok: true,
      message: 'start_ability done',
      data: { bundleName, abilityName }
    }
  }

  private async onOpenUrl(req: TabletCompanionInvokeRequest): Promise<TabletCompanionInvokeResponse> {
    const url: string = String(req.args['url'] ?? '').trim()
    if (url.length <= 0) return { ok: false, message: 'bad args: url empty' }
    if (!this.isAllowedUrl(url)) return { ok: false, message: 'url not allowed' }

    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) return { ok: false, message: 'abilityContext unavailable' }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url
    } as Want
    try {
      await ctx.startAbility(want)
      return { ok: true, message: 'open_url done', data: { url } }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'open_url failed'
      return { ok: false, message: msg }
    }
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const root: Record<string, Object | undefined> = globalThis as Record<string, Object | undefined>
    const ctx: common.UIAbilityContext | undefined = root['abilityContext'] as common.UIAbilityContext | undefined
    return ctx
  }

  private async openApp(bundleName: string, abilityName: string): Promise<{ ok: boolean, message: string }> {
    return this.startAbilityByWant(bundleName, abilityName, {})
  }

  private async openClockForAlarm(hour: number, minute: number, label: string): Promise<{ ok: boolean, message: string }> {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) return { ok: false, message: 'abilityContext unavailable' }

    const alarmBundle: string = DEFAULT_CLOCK_BUNDLE
    const alarmAbility: string = DEFAULT_CLOCK_ABILITY
    const want: Want = {
      bundleName: alarmBundle,
      abilityName: alarmAbility,
      parameters: {
        action: 'set_alarm',
        hour,
        minute,
        label
      } as Record<string, Object | string | number | boolean>
    } as Want

    try {
      await ctx.startAbility(want)
      return { ok: true, message: 'clock opened' }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'open clock failed'
      hilog.error(COMPANION_DOMAIN, COMPANION_TAG, `set_alarm fail: ${msg}`)
      return { ok: false, message: msg }
    }
  }

  private async startAbilityByWant(
    bundleName: string,
    abilityName: string,
    parameters: Record<string, Object | string | number | boolean>
  ): Promise<{ ok: boolean, message: string }> {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) return { ok: false, message: 'abilityContext unavailable' }
    const want: Want = {
      bundleName,
      abilityName: abilityName.length > 0 ? abilityName : 'EntryAbility',
      parameters
    } as Want
    try {
      await ctx.startAbility(want)
      return { ok: true, message: 'startAbility ok' }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'startAbility failed'
      hilog.error(COMPANION_DOMAIN, COMPANION_TAG, `startAbility fail: ${msg}`)
      return { ok: false, message: msg }
    }
  }

  private isAllowedUrl(url: string): boolean {
    const lower: string = url.trim().toLowerCase()
    if (lower.startsWith('http://') || lower.startsWith('https://')) return true
    if (lower.startsWith('tel:') || lower.startsWith('sms:')) return true
    return false
  }
}

export const tabletCompanionService: TabletCompanionService = new TabletCompanionService()
