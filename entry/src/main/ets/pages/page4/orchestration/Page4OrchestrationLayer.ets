import { Page1Action } from '../../page1/types/Page1Types'
import { Page4Keywords } from '../config/Page4Keywords'
import { Page4PlannedTask } from '../modules/Page4OpenClawPlanQaModule'

export interface Page4TaskParseDeps {
  extractDestNode: (text: string) => string
  isValidGridId: (id: string) => boolean
  resolveActionByText: (lower: string) => Page1Action | undefined
  looksLikeCaptureFrameIntent: (lower: string) => boolean
  containsAny: (text: string, keys: Array<string>) => boolean
}

export class Page4OrchestrationLayer {
  static actionName(action: Page1Action): string {
    if (action === Page1Action.GO) return '前进'
    if (action === Page1Action.BACK) return '后退'
    if (action === Page1Action.LEFT) return '左转'
    if (action === Page1Action.RIGHT) return '右转'
    if (action === Page1Action.UTURN) return '掉头'
    if (action === Page1Action.STOP) return '停止'
    if (action === Page1Action.SCRAM) return '紧急停止'
    if (action === Page1Action.TFTA) return 'TFTA'
    return '动作'
  }

  static resolveActionByText(
    textLower: string,
    lastAction: Page1Action | undefined,
    containsAny: (text: string, keys: Array<string>) => boolean
  ): Page1Action | undefined {
    if (containsAny(textLower, Page4Keywords.CONTROL_ACTION_REPEAT)) return lastAction
    if (containsAny(textLower, Page4Keywords.ACTION_SCRAM)) return Page1Action.SCRAM
    if (containsAny(textLower, Page4Keywords.ACTION_STOP)) return Page1Action.STOP
    if (containsAny(textLower, Page4Keywords.ACTION_GO)) return Page1Action.GO
    if (containsAny(textLower, Page4Keywords.ACTION_BACK)) return Page1Action.BACK
    if (containsAny(textLower, Page4Keywords.ACTION_LEFT)) return Page1Action.LEFT
    if (containsAny(textLower, Page4Keywords.ACTION_RIGHT)) return Page1Action.RIGHT
    if (containsAny(textLower, Page4Keywords.ACTION_UTURN)) return Page1Action.UTURN
    return undefined
  }

  static looksLikeCaptureFrameIntent(
    textLower: string,
    containsAny: (text: string, keys: Array<string>) => boolean
  ): boolean {
    return containsAny(textLower, Page4Keywords.CAPTURE_FRAME)
  }

  static splitPromptToClauses(text: string): Array<string> {
    const src: string = text
      .replace(Page4Keywords.buildMultiTaskConnectorRegex(), '|')
      .replace(Page4Keywords.buildMultiTaskSeparatorRegex(), '|')
    const raw: Array<string> = src.split('|')
    const out: Array<string> = []
    for (let i: number = 0; i < raw.length; i++) {
      const one: string = raw[i].trim()
      if (one.length > 0) out.push(one)
    }
    return out
  }

  static parseTaskFromClause(clause: string, deps: Page4TaskParseDeps): Page4PlannedTask | undefined {
    const lower: string = clause.toLowerCase()
    const dest: string = deps.extractDestNode(clause)
    if (dest.length > 0 && deps.isValidGridId(dest)) return { kind: 'route', destNodeId: dest }

    const action: Page1Action | undefined = deps.resolveActionByText(lower)
    if (action !== undefined) return { kind: 'action', action: action }

    if (deps.containsAny(lower, Page4Keywords.AUTO_FOLLOW_ON)) return { kind: 'auto_follow', enabled: true }
    if (deps.containsAny(lower, Page4Keywords.AUTO_FOLLOW_OFF)) return { kind: 'auto_follow', enabled: false }
    if (deps.containsAny(lower, Page4Keywords.SEND_MODE_REAL)) return { kind: 'send_mode', mode: 'REAL_SEND' }
    if (deps.containsAny(lower, Page4Keywords.SEND_MODE_DRY)) return { kind: 'send_mode', mode: 'DRY_RUN' }
    if (deps.looksLikeCaptureFrameIntent(lower)) return { kind: 'capture_frame' }
    if (deps.containsAny(lower, Page4Keywords.QUERY_STATUS)) return { kind: 'query_status' }
    if (deps.containsAny(lower, Page4Keywords.QUERY_VISION)) return { kind: 'query_vision' }
    if (deps.containsAny(lower, Page4Keywords.QUERY_COMM)) return { kind: 'query_comm' }
    if (deps.containsAny(lower, Page4Keywords.QUERY_VIDEO)) return { kind: 'query_video' }
    return undefined
  }

  static parseLocalPlannedTasks(text: string, deps: Page4TaskParseDeps): Array<Page4PlannedTask> {
    const clauses: Array<string> = this.splitPromptToClauses(text)
    const out: Array<Page4PlannedTask> = []
    for (let i: number = 0; i < clauses.length; i++) {
      const task: Page4PlannedTask | undefined = this.parseTaskFromClause(clauses[i], deps)
      if (!task) continue
      out.push(task)
    }
    return out
  }

  static looksLikeMultiTask(text: string, containsAny: (text: string, keys: Array<string>) => boolean): boolean {
    const x: string = text.trim()
    if (x.length <= 0) return false
    if (this.splitPromptToClauses(x).length >= 2) return true
    return containsAny(x, Page4Keywords.MULTI_TASK_MARKERS)
  }

  static looksLikeControlIntent(
    text: string,
    lower: string,
    extractDestNode: (text: string) => string,
    containsAny: (text: string, keys: Array<string>) => boolean
  ): boolean {
    if (text.trim().length <= 0) return false
    if (this.looksLikeMultiTask(text, containsAny)) return true
    if (extractDestNode(text).length > 0) return true
    return containsAny(lower, Page4Keywords.CONTROL_INTENT)
  }
}
