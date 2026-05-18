import { Page1Action } from '../../page1/types/Page1Types'

export type Page4PlannedTaskKind =
  'route' |
  'action' |
  'auto_follow' |
  'send_mode' |
  'capture_frame' |
  'undo' |
  'method' |
  'query_status' |
  'query_vision' |
  'query_comm' |
  'query_video'

export interface Page4PlannedTask {
  kind: Page4PlannedTaskKind
  destNodeId?: string
  action?: Page1Action
  enabled?: boolean
  mode?: 'REAL_SEND' | 'DRY_RUN'
  methodName?: string
  methodArgs?: Record<string, Object | string | number | boolean | undefined>
}

export class Page4OpenClawPlanQaModule {
  static mapActionToken(actionText: string): Page1Action | undefined {
    const t: string = actionText.trim().toUpperCase()
    if (t === 'GO' || t === 'FORWARD') return Page1Action.GO
    if (t === 'BACK' || t === 'BACKWARD') return Page1Action.BACK
    if (t === 'LEFT' || t === 'TURN_LEFT') return Page1Action.LEFT
    if (t === 'RIGHT' || t === 'TURN_RIGHT') return Page1Action.RIGHT
    if (t === 'UTURN' || t === 'U_TURN') return Page1Action.UTURN
    if (t === 'STOP') return Page1Action.STOP
    if (t === 'SCRAM' || t === 'ESTOP') return Page1Action.SCRAM
    return undefined
  }

  static normalizeMethodName(raw: string): string {
    const name: string = raw.trim().toLowerCase()
    if (name === 'undo_last_action') return 'undo_to_safe_point'
    if (name === 'capture_current_frame') return 'get_camera_frame'
    return name
  }

  static isAllowedMethodName(raw: string): boolean {
    const name: string = this.normalizeMethodName(raw)
    const allowed: Array<string> = [
      'start_manual_route','send_action','set_auto_follow','set_send_mode','speak_text','undo_to_safe_point',
      'get_camera_frame','query_status','query_vision','query_comm','query_video','read_file','process_list',
      'exec_cmd','set_recognition','set_auto_report','set_vision_mode','set_adaptive_strategy','tablet_set_alarm',
      'tablet_open_app','tablet_list_alarm','tablet_start_ability','tablet_open_url'
    ]
    for (let i: number = 0; i < allowed.length; i++) if (allowed[i] === name) return true
    return false
  }

  static extractJsonObject(text: string): string {
    const src: string = text.trim()
    if (src.length <= 0) return ''
    const codeBlock: RegExpMatchArray | null = src.match(/```(?:json)?\s*([\s\S]*?)```/i)
    const body: string = codeBlock && codeBlock.length > 1 ? codeBlock[1].trim() : src
    const start: number = body.indexOf('{')
    const end: number = body.lastIndexOf('}')
    if (start < 0 || end <= start) return ''
    return body.substring(start, end + 1)
  }

  static mapOpenClawPlan(text: string): Array<Page4PlannedTask> {
    const jsonText: string = this.extractJsonObject(text)
    if (jsonText.length <= 0) return []
    try {
      const root: Record<string, Object | string | number | boolean | Array<Object>> =
        JSON.parse(jsonText) as Record<string, Object | string | number | boolean | Array<Object>>
      const arr: Array<Record<string, Object | string | number | boolean>> = Array.isArray(root['tasks'])
        ? (root['tasks'] as Array<Record<string, Object | string | number | boolean>>)
        : []
      const out: Array<Page4PlannedTask> = []
      for (let i: number = 0; i < arr.length; i++) {
        const t: Record<string, Object | string | number | boolean> = arr[i]
        const typeText: string = String(t['type'] ?? '').trim().toLowerCase()
        if (typeText === 'route') { const dest: string = String(t['dest'] ?? '').trim().toUpperCase(); if (dest.length > 0) out.push({ kind: 'route', destNodeId: dest }); continue }
        if (typeText === 'action') { const action = this.mapActionToken(String(t['action'] ?? '')); if (action !== undefined) out.push({ kind: 'action', action }); continue }
        if (typeText === 'auto_follow') { const v: string = String(t['enabled'] ?? '').trim().toLowerCase(); if (v === 'true' || v === '1' || v === 'on') out.push({ kind: 'auto_follow', enabled: true }); else if (v === 'false' || v === '0' || v === 'off') out.push({ kind: 'auto_follow', enabled: false }); continue }
        if (typeText === 'send_mode') { const v: string = String(t['mode'] ?? '').trim().toUpperCase(); if (v === 'REAL_SEND' || v === 'DRY_RUN') out.push({ kind: 'send_mode', mode: v as 'REAL_SEND' | 'DRY_RUN' }); continue }
        if (typeText === 'capture_frame') { out.push({ kind: 'capture_frame' }); continue }
        if (typeText === 'undo') { out.push({ kind: 'undo' }); continue }
        if (typeText === 'query_status') { out.push({ kind: 'query_status' }); continue }
        if (typeText === 'query_vision') { out.push({ kind: 'query_vision' }); continue }
        if (typeText === 'query_comm') { out.push({ kind: 'query_comm' }); continue }
        if (typeText === 'query_video') { out.push({ kind: 'query_video' }); continue }
        if (typeText === 'method' || typeText === 'call') {
          const name: string = this.normalizeMethodName(String(typeText === 'method' ? (t['name'] ?? '') : (t['method'] ?? '')))
          const argsRaw: Object | string | number | boolean | undefined = typeText === 'method' ? t['args'] : t['params']
          const args: Record<string, Object | string | number | boolean | undefined> =
            typeof argsRaw === 'object' && argsRaw !== null
              ? (argsRaw as Record<string, Object | string | number | boolean | undefined>)
              : {}
          if (!this.isAllowedMethodName(name)) continue
          out.push({ kind: 'method', methodName: name, methodArgs: args })
          continue
        }
      }
      return out
    } catch (_) {
      return []
    }
  }
}
