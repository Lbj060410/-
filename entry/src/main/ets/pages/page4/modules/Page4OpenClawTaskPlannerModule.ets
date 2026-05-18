import { OpenClawChatMessage } from '../../../services/assistant/OpenClawGatewayClient'
import { Page4GatewayLayer, Page4GatewayState } from '../gateway/Page4GatewayLayer'
import { Page4PlannedTask } from './Page4OpenClawPlanQaModule'

export interface Page4OpenClawTaskPlannerDeps {
  resolveTokenCandidates: () => Array<string>
  resolveHosts: () => Array<string>
  gatewayState: () => Page4GatewayState
  applyGatewayState: (state: Page4GatewayState) => void
  mapOpenClawPlan: (text: string) => Array<Page4PlannedTask>
  buildRuntimePrompt: () => string
  connectTimeoutMs: () => number
  readTimeoutMs: () => number
  model: string
}

export class Page4OpenClawTaskPlannerModule {
  static async planTasksByOpenClaw(input: string, deps: Page4OpenClawTaskPlannerDeps): Promise<Array<Page4PlannedTask>> {
    const tokenCandidates: Array<string> = deps.resolveTokenCandidates()
    if (tokenCandidates.length <= 0) return []
    const hosts: Array<string> = deps.resolveHosts()
    if (hosts.length <= 0) return []

    const messages: Array<OpenClawChatMessage> = [
      {
        role: 'system',
        content:
          '你是无人物流车任务解析器。把用户一句话解析为任务数组，输出严格 JSON：' +
          '{"tasks":[{"type":"route","dest":"B2"},{"type":"method","name":"set_auto_follow","args":{"enabled":true}}]}。' +
          'type 允许 route/action/auto_follow/send_mode/capture_frame/undo/query_status/query_vision/query_comm/query_video/method。' +
          'route.dest 必须是 A1-G7 这样的点位；action 仅 GO/BACK/LEFT/RIGHT/UTURN/STOP/SCRAM；' +
          'auto_follow 使用 enabled=true/false；send_mode 使用 mode=REAL_SEND/DRY_RUN。' +
          'method.name 仅允许 start_manual_route/send_action/set_auto_follow/set_send_mode/speak_text/undo_to_safe_point/get_camera_frame/query_status/query_vision/query_comm/query_video/read_file/process_list/exec_cmd/set_recognition/set_auto_report/set_vision_mode/set_adaptive_strategy/tablet_set_alarm/tablet_open_app/tablet_list_alarm/tablet_start_ability/tablet_open_url。' +
          'method.args: start_manual_route 传 dest; send_action 传 action; set_auto_follow 传 enabled; set_send_mode 传 mode; speak_text 传 text; read_file 传 path; exec_cmd 传 cmd; set_recognition 传 enabled; set_auto_report 传 enabled; set_vision_mode 传 mode=traffic|barrier; set_adaptive_strategy 传 mode=normal|weak; tablet_set_alarm 传 hour/minute/label; tablet_open_app 传 bundleName; tablet_start_ability 传 bundleName/abilityName/parameters; tablet_open_url 传 url。' +
          '请按物流场景理解用户意图（如去装货点、去卸货点、返仓、暂停、急停），但输出字段必须严格符合上述枚举与格式。' +
          '注意：对于 get_camera_frame 方法，系统会自动获取摄像头画面。你只需要返回标准的JSON任务数组即可。' +
          '不要输出任何解释文本。'
      },
      { role: 'system', content: deps.buildRuntimePrompt() },
      { role: 'user', content: input }
    ]

    const rs = await Page4GatewayLayer.completeOpenClaw(
      deps.gatewayState(),
      messages,
      hosts,
      tokenCandidates,
      deps.connectTimeoutMs(),
      deps.readTimeoutMs(),
      deps.model
    )
    deps.applyGatewayState(rs.state)
    if (rs.ok) {
      const planned: Array<Page4PlannedTask> = deps.mapOpenClawPlan(rs.text)
      if (planned.length > 0) return planned
    }
    return []
  }
}
