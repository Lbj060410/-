import { Page1Action } from '../../page1/types/Page1Types'
import { Page4PlannedTask } from './Page4OpenClawPlanQaModule'
import { Page4ExecutionReceipt } from './Page4RouteExecutionModule'

export interface Page4TaskExecutionDeps {
  isValidGridId: (id: string) => boolean
  routeWithReplanAndWaitArrival: (dest: string) => Promise<Array<Page4ExecutionReceipt>>
  rememberSafePointFromStore: () => void
  onAction: (action: Page1Action) => Promise<void>
  setLastAction: (action: Page1Action) => void
  actionName: (action: Page1Action) => string
  setAutoFollowEnabled: (enabled: boolean) => void
  setRealSendEnabled: (enabled: boolean) => void
  executeRegistryMethod: (task: Page4PlannedTask) => Promise<Array<Page4ExecutionReceipt>>
  getUndoTarget: () => string
  buildCameraFrameSummaryText: () => string
  buildStatusSummaryText: () => string
  buildVisionSummaryText: () => string
  buildCommSummaryText: () => string
  buildVideoSummaryText: () => string
  buildReceipt: (taskText: string, sent: boolean, done: boolean) => Page4ExecutionReceipt
}

export class Page4TaskExecutionModule {
  static async executePlannedTasks(
    tasks: Array<Page4PlannedTask>,
    deps: Page4TaskExecutionDeps
  ): Promise<Array<Page4ExecutionReceipt>> {
    if (tasks.length <= 0) return []
    const receipts: Array<Page4ExecutionReceipt> = []
    for (let i: number = 0; i < tasks.length; i++) {
      const t: Page4PlannedTask = tasks[i]
      try {
        if (t.kind === 'route') {
          const dest: string = String(t.destNodeId ?? '').trim().toUpperCase()
          if (!deps.isValidGridId(dest)) {
            receipts.push(deps.buildReceipt(`跳过无效点位:${dest}`, false, false))
            continue
          }
          const routeReceipts: Array<Page4ExecutionReceipt> = await deps.routeWithReplanAndWaitArrival(dest)
          for (let j: number = 0; j < routeReceipts.length; j++) receipts.push(routeReceipts[j])
          continue
        }
        if (t.kind === 'action') {
          if (typeof t.action === 'undefined') continue
          deps.rememberSafePointFromStore()
          await deps.onAction(t.action)
          deps.setLastAction(t.action)
          receipts.push(deps.buildReceipt(deps.actionName(t.action), true, true))
          continue
        }
        if (t.kind === 'auto_follow') {
          const enabled: boolean = !!t.enabled
          deps.setAutoFollowEnabled(enabled)
          receipts.push(deps.buildReceipt(enabled ? '自动跟随开启' : '自动跟随关闭', true, true))
          continue
        }
        if (t.kind === 'send_mode') {
          const mode: string = String(t.mode ?? '')
          if (mode === 'REAL_SEND') {
            deps.setRealSendEnabled(true)
            receipts.push(deps.buildReceipt('真车模式', true, true))
          } else if (mode === 'DRY_RUN') {
            deps.setRealSendEnabled(false)
            receipts.push(deps.buildReceipt('仿真模式', true, true))
          }
          continue
        }
        if (t.kind === 'method') {
          const one: Array<Page4ExecutionReceipt> = await deps.executeRegistryMethod(t)
          for (let j: number = 0; j < one.length; j++) receipts.push(one[j])
          continue
        }
        if (t.kind === 'capture_frame') {
          receipts.push(deps.buildReceipt(deps.buildCameraFrameSummaryText(), true, true))
          continue
        }
        if (t.kind === 'undo') {
          let stopOk: boolean = false
          try {
            await deps.onAction(Page1Action.STOP)
            deps.setLastAction(Page1Action.STOP)
            receipts.push(deps.buildReceipt('撤销-停止', true, true))
            stopOk = true
          } catch (e) {
            const msg: string = e instanceof Error ? e.message : 'stop failed'
            receipts.push(deps.buildReceipt(`撤销-停止失败(${msg})`, false, false))
          }
          const target: string = deps.getUndoTarget()
          if (stopOk && deps.isValidGridId(target)) {
            const backReceipts: Array<Page4ExecutionReceipt> = await deps.routeWithReplanAndWaitArrival(target)
            for (let j: number = 0; j < backReceipts.length; j++) receipts.push(backReceipts[j])
          } else if (stopOk) {
            receipts.push(deps.buildReceipt('撤销-回安全点(未记录安全点)', false, false))
          }
          continue
        }
        if (t.kind === 'query_status') receipts.push(deps.buildReceipt(deps.buildStatusSummaryText(), true, true))
        if (t.kind === 'query_vision') receipts.push(deps.buildReceipt(deps.buildVisionSummaryText(), true, true))
        if (t.kind === 'query_comm') receipts.push(deps.buildReceipt(deps.buildCommSummaryText(), true, true))
        if (t.kind === 'query_video') receipts.push(deps.buildReceipt(deps.buildVideoSummaryText(), true, true))
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : '任务失败'
        receipts.push(deps.buildReceipt(`失败:${msg}`, false, false))
      }
    }
    return receipts
  }
}
