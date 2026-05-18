import { Page1Action } from '../../page1/types/Page1Types'
import { Page4ExecutionReceipt } from './Page4RouteExecutionModule'
import { Page4PlannedTask } from './Page4OpenClawPlanQaModule'

export interface Page4RegistryMethodDeps {
  normalizeMethodName: (raw: string) => string
  isAllowedMethodName: (raw: string) => boolean
  extractDestNode: (text: string) => string
  isValidGridId: (id: string) => boolean
  routeWithReplanAndWaitArrival: (dest: string) => Promise<Array<Page4ExecutionReceipt>>
  mapActionToken: (actionText: string) => Page1Action | undefined
  rememberSafePointFromStore: () => void
  onAction: (action: Page1Action) => Promise<void>
  setLastAction: (action: Page1Action) => void
  actionName: (action: Page1Action) => string
  setAutoFollowEnabled: (enabled: boolean) => void
  setRealSendEnabled: (enabled: boolean) => void
  speakText: (text: string) => Promise<boolean>
  getUndoTarget: () => string
  buildCameraFrameSummaryText: () => string
  buildStatusSummaryText: () => string
  buildVisionSummaryText: () => string
  buildCommSummaryText: () => string
  buildVideoSummaryText: () => string
  setRecognitionEnabled: (enabled: boolean) => void
  setAutoReportEnabled: (enabled: boolean) => void
  setVisionMode: (mode: 'traffic' | 'barrier') => boolean
  setAdaptiveStrategy: (mode: 'normal' | 'weak' | 'night') => boolean
  callTabletCompanion: (
    action: string,
    args: Record<string, Object | string | number | boolean | undefined>
  ) => Promise<{ ok: boolean, summary: string }>
  callPcToolGateway: (
    toolName: string,
    args: Record<string, Object | string | number | boolean | undefined>
  ) => Promise<{ ok: boolean, summary: string }>
  isAllowedPcExecCmd: (cmd: string) => boolean
  buildReceipt: (taskText: string, sent: boolean, done: boolean) => Page4ExecutionReceipt
}

export class Page4RegistryMethodModule {
  static parseMethodBooleanArg(
    args: Record<string, Object | string | number | boolean | undefined>,
    key: string
  ): boolean | undefined {
    const v: Object | string | number | boolean | undefined = args[key]
    if (typeof v === 'boolean') return v
    const s: string = String(v ?? '').trim().toLowerCase()
    if (s === 'true' || s === '1' || s === 'on' || s === 'yes') return true
    if (s === 'false' || s === '0' || s === 'off' || s === 'no') return false
    return undefined
  }

  static async executeRegistryMethod(
    task: Page4PlannedTask,
    deps: Page4RegistryMethodDeps
  ): Promise<Array<Page4ExecutionReceipt>> {
    const name: string = deps.normalizeMethodName(String(task.methodName ?? ''))
    const args: Record<string, Object | string | number | boolean | undefined> = task.methodArgs ?? {}
    const out: Array<Page4ExecutionReceipt> = []
    if (!deps.isAllowedMethodName(name)) {
      out.push(deps.buildReceipt(`未注册方法:${name}`, false, false))
      return out
    }
    if (name === 'start_manual_route') {
      const destRaw: string = String(args['dest'] ?? args['destNodeId'] ?? '').trim().toUpperCase()
      const dest: string = destRaw.length > 0 ? destRaw : deps.extractDestNode(String(args['text'] ?? ''))
      if (!deps.isValidGridId(dest)) return [deps.buildReceipt(`start_manual_route 参数错误 dest=${destRaw}`, false, false)]
      return await deps.routeWithReplanAndWaitArrival(dest)
    }
    if (name === 'send_action') {
      const actionToken: string = String(args['action'] ?? '').trim()
      const action: Page1Action | undefined = deps.mapActionToken(actionToken)
      if (typeof action === 'undefined') return [deps.buildReceipt(`send_action 参数错误 action=${actionToken}`, false, false)]
      deps.rememberSafePointFromStore()
      await deps.onAction(action)
      deps.setLastAction(action)
      return [deps.buildReceipt(deps.actionName(action), true, true)]
    }
    if (name === 'set_auto_follow') {
      const enabled: boolean | undefined = this.parseMethodBooleanArg(args, 'enabled')
      if (typeof enabled === 'undefined') return [deps.buildReceipt('set_auto_follow 参数错误 enabled', false, false)]
      deps.setAutoFollowEnabled(enabled)
      return [deps.buildReceipt(enabled ? '自动跟随开启' : '自动跟随关闭', true, true)]
    }
    if (name === 'set_send_mode') {
      const mode: string = String(args['mode'] ?? '').trim().toUpperCase()
      if (mode !== 'REAL_SEND' && mode !== 'DRY_RUN') return [deps.buildReceipt(`set_send_mode 参数错误 mode=${mode}`, false, false)]
      deps.setRealSendEnabled(mode === 'REAL_SEND')
      return [deps.buildReceipt(mode === 'REAL_SEND' ? '真车模式' : '仿真模式', true, true)]
    }
    if (name === 'speak_text') {
      const text: string = String(args['text'] ?? '').trim()
      if (text.length <= 0) return [deps.buildReceipt('speak_text 参数错误 text为空', false, false)]
      const content: string = text.length > 80 ? text.substring(0, 80) : text
      const ok: boolean = await deps.speakText(content)
      return [deps.buildReceipt(`语音播报:${content}`, ok, ok)]
    }
    if (name === 'undo_to_safe_point') {
      let stopOk: boolean = false
      try {
        await deps.onAction(Page1Action.STOP)
        deps.setLastAction(Page1Action.STOP)
        out.push(deps.buildReceipt('撤销-停止', true, true))
        stopOk = true
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'stop failed'
        out.push(deps.buildReceipt(`撤销-停止失败(${msg})`, false, false))
      }
      const target: string = deps.getUndoTarget()
      if (stopOk && deps.isValidGridId(target)) {
        const backReceipts: Array<Page4ExecutionReceipt> = await deps.routeWithReplanAndWaitArrival(target)
        for (let i: number = 0; i < backReceipts.length; i++) out.push(backReceipts[i])
      } else if (stopOk) out.push(deps.buildReceipt('撤销-回安全点(未记录安全点)', false, false))
      return out
    }
    if (name === 'get_camera_frame') return [deps.buildReceipt(deps.buildCameraFrameSummaryText(), true, true)]
    if (name === 'query_status') return [deps.buildReceipt(deps.buildStatusSummaryText(), true, true)]
    if (name === 'query_vision') return [deps.buildReceipt(deps.buildVisionSummaryText(), true, true)]
    if (name === 'query_comm') return [deps.buildReceipt(deps.buildCommSummaryText(), true, true)]
    if (name === 'query_video') return [deps.buildReceipt(deps.buildVideoSummaryText(), true, true)]
    if (name === 'set_recognition') {
      const enabled: boolean | undefined = this.parseMethodBooleanArg(args, 'enabled')
      if (typeof enabled === 'undefined') return [deps.buildReceipt('set_recognition 参数错误 enabled', false, false)]
      deps.setRecognitionEnabled(enabled)
      return [deps.buildReceipt(enabled ? '识别已开启' : '识别已关闭', true, true)]
    }
    if (name === 'set_auto_report') {
      const enabled: boolean | undefined = this.parseMethodBooleanArg(args, 'enabled')
      if (typeof enabled === 'undefined') return [deps.buildReceipt('set_auto_report 参数错误 enabled', false, false)]
      deps.setAutoReportEnabled(enabled)
      return [deps.buildReceipt(enabled ? '自动回传已开启' : '自动回传已关闭', true, true)]
    }
    if (name === 'set_vision_mode') {
      const mode: string = String(args['mode'] ?? '').trim().toLowerCase()
      if (mode === 'traffic' && deps.setVisionMode('traffic')) return [deps.buildReceipt('视觉模型已切换为 traffic', true, true)]
      if ((mode === 'barrier' || mode === 'yolov26barrier') && deps.setVisionMode('barrier')) return [deps.buildReceipt('视觉模型已切换为 yolov26barrier', true, true)]
      return [deps.buildReceipt(`set_vision_mode 参数错误 mode=${mode}`, false, false)]
    }
    if (name === 'set_adaptive_strategy') {
      const mode: string = String(args['mode'] ?? '').trim().toLowerCase()
      if (!deps.setAdaptiveStrategy(mode as 'normal' | 'weak' | 'night')) return [deps.buildReceipt(`set_adaptive_strategy 参数错误 mode=${mode}`, false, false)]
      return [deps.buildReceipt(mode === 'normal' ? '策略已切换为常规' : '策略已切换为弱网/夜间', true, true)]
    }
    if (name === 'tablet_set_alarm') {
      const hour: number = Math.trunc(Number(String(args['hour'] ?? '').trim()))
      const minute: number = Math.trunc(Number(String(args['minute'] ?? '').trim()))
      const label: string = String(args['label'] ?? '').trim()
      if (!Number.isFinite(hour) || !Number.isFinite(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return [deps.buildReceipt('tablet_set_alarm 参数错误 hour/minute', false, false)]
      }
      const r = await deps.callTabletCompanion('set_alarm', { hour, minute, label })
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'tablet_open_app') {
      const bundleName: string = String(args['bundleName'] ?? args['bundle'] ?? '').trim()
      if (bundleName.length <= 0) return [deps.buildReceipt('tablet_open_app 参数错误 bundleName为空', false, false)]
      const r = await deps.callTabletCompanion('open_app', { bundleName })
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'tablet_list_alarm') {
      const r = await deps.callTabletCompanion('list_alarm', {})
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'tablet_start_ability') {
      const bundleName: string = String(args['bundleName'] ?? args['bundle'] ?? '').trim()
      const abilityName: string = String(args['abilityName'] ?? '').trim()
      const paramsRaw: Object | string | number | boolean | undefined = args['parameters']
      const parameters: Record<string, Object | string | number | boolean | undefined> =
        typeof paramsRaw === 'object' && paramsRaw !== null ? (paramsRaw as Record<string, Object | string | number | boolean | undefined>) : {}
      if (bundleName.length <= 0) return [deps.buildReceipt('tablet_start_ability 参数错误 bundleName为空', false, false)]
      const r = await deps.callTabletCompanion('start_ability', { bundleName, abilityName, parameters })
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'tablet_open_url') {
      const url: string = String(args['url'] ?? '').trim()
      if (url.length <= 0) return [deps.buildReceipt('tablet_open_url 参数错误 url为空', false, false)]
      const r = await deps.callTabletCompanion('open_url', { url })
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'read_file') {
      const path: string = String(args['path'] ?? '').trim()
      if (path.length <= 0) return [deps.buildReceipt('read_file 参数错误 path为空', false, false)]
      if (path.endsWith('/') || path.endsWith('\\')) return [deps.buildReceipt(`read_file 参数错误 path疑似目录:${path}`, false, false)]
      const r = await deps.callPcToolGateway('read_file', { path })
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'process_list') {
      const r = await deps.callPcToolGateway('process_list', {})
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    if (name === 'exec_cmd') {
      const cmd: string = String(args['cmd'] ?? args['command'] ?? '').trim()
      if (cmd.length <= 0) return [deps.buildReceipt('exec_cmd 参数错误 cmd为空', false, false)]
      if (!deps.isAllowedPcExecCmd(cmd)) return [deps.buildReceipt(`exec_cmd 被策略拒绝:${cmd}`, false, false)]
      const r = await deps.callPcToolGateway('exec_cmd', { cmd })
      return [deps.buildReceipt(r.summary, r.ok, r.ok)]
    }
    return [deps.buildReceipt(`未实现方法:${name}`, false, false)]
  }
}
