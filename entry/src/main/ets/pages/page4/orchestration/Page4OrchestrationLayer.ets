import { Page1Action } from '../../page1/types/Page1Types'
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
    if (containsAny(textLower, ['再来一次', '重复上一动作', '继续刚才动作', 'repeat'])) return lastAction
    if (containsAny(textLower, ['紧急停止', '急停', 'scram'])) return Page1Action.SCRAM
    if (containsAny(textLower, ['停止', '停车', 'stop'])) return Page1Action.STOP
    if (containsAny(textLower, ['前进', '向前', 'go'])) return Page1Action.GO
    if (containsAny(textLower, ['后退', '倒车', 'back'])) return Page1Action.BACK
    if (containsAny(textLower, ['左转'])) return Page1Action.LEFT
    if (containsAny(textLower, ['右转'])) return Page1Action.RIGHT
    if (containsAny(textLower, ['掉头'])) return Page1Action.UTURN
    return undefined
  }

  static looksLikeCaptureFrameIntent(
    textLower: string,
    containsAny: (text: string, keys: Array<string>) => boolean
  ): boolean {
    return containsAny(textLower, [
      '获取当前摄像头画面',
      '获取当前画面',
      '抓取当前画面',
      '读取当前画面',
      '保存当前画面',
      '给我当前画面',
      '看一下当前画面',
      'camera frame',
      'current frame',
      'capture frame'
    ])
  }

  static splitPromptToClauses(text: string): Array<string> {
    const src: string = text
      .replace(/然后|接着|随后|并且|并且再|同时|接下来|再去|再到/g, '|')
      .replace(/[，,；;。.!！?？\n]/g, '|')
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

    if (deps.containsAny(lower, ['开启自动跟随', '打开自动跟随', '自动跟随开启', '自动驾驶开启'])) return { kind: 'auto_follow', enabled: true }
    if (deps.containsAny(lower, ['关闭自动跟随', '停止自动跟随', '自动跟随关闭', '自动驾驶关闭'])) return { kind: 'auto_follow', enabled: false }
    if (deps.containsAny(lower, ['开启真车模式', '真车模式', 'real_send'])) return { kind: 'send_mode', mode: 'REAL_SEND' }
    if (deps.containsAny(lower, ['开启仿真模式', '仿真模式', 'dry_run', '关闭真车模式'])) return { kind: 'send_mode', mode: 'DRY_RUN' }
    if (deps.looksLikeCaptureFrameIntent(lower)) return { kind: 'capture_frame' }
    if (deps.containsAny(lower, ['查询状态', '状态', 'status'])) return { kind: 'query_status' }
    if (deps.containsAny(lower, ['识别状态', '视觉状态', '识别结果', 'vision'])) return { kind: 'query_vision' }
    if (deps.containsAny(lower, ['网络', '通信'])) return { kind: 'query_comm' }
    if (deps.containsAny(lower, ['视频', '相机'])) return { kind: 'query_video' }
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
    return containsAny(x, ['然后', '接着', '并且', '同时', '再', '随后', ';', '；', ',', '，'])
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
    const keywords: Array<string> = [
      '导航', '前往', '去', '到',
      '返仓', '回仓', '返航', '回基地', '回中心', '回物流中心', '回快递点', '回仓库', '返仓库',
      '前进', '后退', '左转', '右转', '掉头', '停止', '急停', '刹车',
      '自动跟随', '自动驾驶', '真车模式', '仿真模式', 'real_send', 'dry_run',
      '撤销', '回到安全点',
      '抓拍', '截图', '拍照', '相机', '视频',
      '查询状态', '状态', '识别', '视觉', '通信', '网络',
      '读取文件', '读文件', '文件内容', '进程列表', '查询进程', '执行命令', '命令行', 'process', 'read_file', 'exec_cmd'
    ]
    return containsAny(lower, keywords)
  }
}
