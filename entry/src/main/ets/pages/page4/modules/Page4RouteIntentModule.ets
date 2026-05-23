import { Page4ExecutionReceipt } from './Page4RouteExecutionModule'
import { Page4ReplyText } from '../config/Page4ReplyText'

export class Page4RouteIntentModule {
  static async routeByDest(
    dest: string,
    inputText: string,
    deps: {
      isValidGridId: (id: string) => boolean
      logInfo: (name: string, message: string) => void
      logError: (name: string, message: string) => void
      routeWithReplanAndWaitArrival: (dest: string) => Promise<Array<Page4ExecutionReceipt>>
      routeTargetDisplayText: (destNodeId: string, inputText: string) => string
      renderReceiptsSummary: (receipts: Array<Page4ExecutionReceipt>) => string
      pushAssistant: (text: string) => void
      getLastRouteFailureReason: () => string
    }
  ): Promise<boolean> {
    if (dest.length <= 0) return false
    if (!deps.isValidGridId(dest)) {
      deps.pushAssistant(`"${dest}" 不是合法的路网节点，请说如 "导航到D4" 等有效节点。`)
      return true
    }
    deps.logInfo('sendRoutePlanRequest', `dest=${dest}`)
    const routeReceipts: Array<Page4ExecutionReceipt> = await deps.routeWithReplanAndWaitArrival(dest)
    const routedOk: boolean = routeReceipts.length > 0 && routeReceipts[0].sent
    if (routedOk) deps.logInfo('sendRoutePlanSuccess', `dest=${dest}`)
    else deps.logError('sendRoutePlanFail', `dest=${dest}, reason=${deps.getLastRouteFailureReason()}`)
    const targetText: string = deps.routeTargetDisplayText(dest, inputText)
    if (routedOk) deps.pushAssistant(Page4ReplyText.routeSuccess(targetText, deps.renderReceiptsSummary(routeReceipts)))
    else deps.pushAssistant(Page4ReplyText.routeFail(deps.renderReceiptsSummary(routeReceipts)))
    return true
  }

  static async quickRouteToPlaceShortcut(
    text: string,
    deps: {
      resolveFastDestShortcut: (text: string) => string
      isValidGridId: (id: string) => boolean
      logInfo: (name: string, message: string) => void
      routeWithReplan: (dest: string) => Promise<{ ok: boolean, receipt: Page4ExecutionReceipt }>
      routeTargetDisplayText: (destNodeId: string, inputText: string) => string
      renderReceiptsSummary: (receipts: Array<Page4ExecutionReceipt>) => string
      pushAssistant: (text: string) => void
    }
  ): Promise<boolean> {
    const quickDest: string = deps.resolveFastDestShortcut(text)
    if (!deps.isValidGridId(quickDest)) return false
    deps.logInfo('quickRouteShortcut', `dest=${quickDest}`)
    const routed = await deps.routeWithReplan(quickDest)
    const targetText: string = deps.routeTargetDisplayText(quickDest, text)
    if (routed.ok) deps.pushAssistant(Page4ReplyText.routeSuccess(targetText, deps.renderReceiptsSummary([routed.receipt])))
    else deps.pushAssistant(Page4ReplyText.routeFail(deps.renderReceiptsSummary([routed.receipt])))
    return true
  }
}
