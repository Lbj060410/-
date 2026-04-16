import {
  TabletCompanionAction,
  TabletCompanionInvokeRequest,
  TabletCompanionInvokeResponse
} from './TabletCompanionContract'
import { tabletCompanionService } from './TabletCompanionService'

/**
 * 这是“伴侣代理 HTTP 路由”示例，不是自动生效的服务器。
 * 你可以把 handleTabletCompanionRoute 挂到现有网关的 /v1/tablet/{action}。
 */

export async function handleTabletCompanionRoute(
  actionText: string,
  body: Record<string, Object | string | number | boolean | undefined>
): Promise<TabletCompanionInvokeResponse> {
  const action = normalizeAction(actionText)
  if (action.length <= 0) {
    return { ok: false, message: `bad action=${actionText}` }
  }
  const nodeId: string = String(body['nodeId'] ?? '').trim()
  if (nodeId.length <= 0) {
    return { ok: false, message: 'missing nodeId' }
  }

  const argsRaw: Object | string | number | boolean | undefined = body['args']
  const args: Record<string, Object | string | number | boolean | undefined> =
    typeof argsRaw === 'object' && argsRaw !== null
      ? (argsRaw as Record<string, Object | string | number | boolean | undefined>)
      : {}

  const req: TabletCompanionInvokeRequest = {
    nodeId,
    action,
    args
  }
  return tabletCompanionService.invoke(req)
}

function normalizeAction(raw: string): '' | TabletCompanionAction {
  const s: string = raw.trim().toLowerCase()
  if (s === 'set_alarm') return 'set_alarm'
  if (s === 'open_app') return 'open_app'
  if (s === 'list_alarm') return 'list_alarm'
  if (s === 'start_ability') return 'start_ability'
  if (s === 'open_url') return 'open_url'
  return ''
}
