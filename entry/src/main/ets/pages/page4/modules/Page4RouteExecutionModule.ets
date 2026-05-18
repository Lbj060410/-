import { GridIdCodec } from '../../page1/app/PathPlannerAStar'

export interface Page4ExecutionReceipt {
  taskText: string
  sent: boolean
  ack: string
  done: string
}

export interface Page4RouteResult {
  ok: boolean
  receipt: Page4ExecutionReceipt
  appliedDest: string
  lastDestNodeId: string
  lastRouteFailureReason: string
  lastReplanSummary: string
}

export interface Page4RouteHooks {
  buildRouteFallbackCandidates: (dest: string) => Array<string>
  rememberSafePointFromStore: () => void
  startManualRoute: (goal: string) => Promise<void>
  buildReceipt: (taskText: string, sent: boolean, done: boolean) => Page4ExecutionReceipt
  waitUntilArriveNode: (destNodeId: string) => Promise<{ arrived: boolean, finalNode: string, reason: string }>
}

export class Page4RouteExecutionModule {
  static buildReceipt(taskText: string, sent: boolean, done: boolean, ackText: string): Page4ExecutionReceipt {
    return {
      taskText: taskText,
      sent: sent,
      ack: ackText,
      done: done ? '完成/已生效' : '未完成'
    }
  }

  static renderReceiptsSummary(receipts: Array<Page4ExecutionReceipt>): string {
    if (receipts.length <= 0) return '无执行项'
    const out: Array<string> = []
    for (let i: number = 0; i < receipts.length; i++) {
      const r: Page4ExecutionReceipt = receipts[i]
      out.push(`${i + 1}.${r.taskText}[sent=${r.sent ? 'Y' : 'N'},ack=${r.ack},done=${r.done}]`)
    }
    return out.join('；')
  }

  static async sleepMs(delayMs: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout((): void => resolve(), Math.max(0, Math.trunc(delayMs)))
    })
  }

  static async waitUntilArriveNode(
    destNodeId: string,
    routeArrivalTimeoutMs: number,
    routeArrivalPollMs: number,
    getCurrentNodeId: () => string
  ): Promise<{ arrived: boolean, finalNode: string, reason: string }> {
    const goal: string = destNodeId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(goal)) return { arrived: false, finalNode: '', reason: 'bad_goal' }
    const deadlineMs: number = Date.now() + Math.max(1000, Math.trunc(routeArrivalTimeoutMs))
    while (Date.now() <= deadlineMs) {
      const cur: string = getCurrentNodeId().trim().toUpperCase()
      if (cur === goal) return { arrived: true, finalNode: cur, reason: 'arrived' }
      await this.sleepMs(routeArrivalPollMs)
    }
    const finalNode: string = getCurrentNodeId().trim().toUpperCase()
    return { arrived: false, finalNode: finalNode, reason: 'timeout' }
  }

  static async routeWithReplan(
    dest: string,
    lastDestNodeId: string,
    lastRouteFailureReason: string,
    lastReplanSummary: string,
    hooks: Page4RouteHooks
  ): Promise<Page4RouteResult> {
    const candidates: Array<string> = hooks.buildRouteFallbackCandidates(dest)
    let firstErr: string = ''
    let nextLastDestNodeId: string = lastDestNodeId
    let nextLastRouteFailureReason: string = lastRouteFailureReason
    let nextLastReplanSummary: string = lastReplanSummary

    for (let i: number = 0; i < candidates.length; i++) {
      const goal: string = candidates[i]
      try {
        hooks.rememberSafePointFromStore()
        await hooks.startManualRoute(goal)
        nextLastDestNodeId = goal
        const taskText: string = i <= 0 ? `导航 ${goal}` : `重规划导航 ${goal}`
        if (i > 0) nextLastReplanSummary = `原目标${dest}失败，改为${goal}`
        return {
          ok: true,
          receipt: hooks.buildReceipt(taskText, true, true),
          appliedDest: goal,
          lastDestNodeId: nextLastDestNodeId,
          lastRouteFailureReason: nextLastRouteFailureReason,
          lastReplanSummary: nextLastReplanSummary
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'route failed'
        if (firstErr.length <= 0) firstErr = msg
        nextLastRouteFailureReason = msg
      }
    }

    const detail: string = firstErr.length > 0 ? firstErr : '规划失败'
    nextLastRouteFailureReason = detail
    nextLastReplanSummary = `原目标${dest}失败，未找到可替代方案`
    return {
      ok: false,
      receipt: hooks.buildReceipt(`导航失败(${dest}:${detail})`, false, false),
      appliedDest: '',
      lastDestNodeId: nextLastDestNodeId,
      lastRouteFailureReason: nextLastRouteFailureReason,
      lastReplanSummary: nextLastReplanSummary
    }
  }

  static async routeWithReplanAndWaitArrival(
    dest: string,
    lastDestNodeId: string,
    lastRouteFailureReason: string,
    lastReplanSummary: string,
    hooks: Page4RouteHooks
  ): Promise<{ receipts: Array<Page4ExecutionReceipt>, lastDestNodeId: string, lastRouteFailureReason: string, lastReplanSummary: string }> {
    const routed = await this.routeWithReplan(dest, lastDestNodeId, lastRouteFailureReason, lastReplanSummary, hooks)
    const receipts: Array<Page4ExecutionReceipt> = [routed.receipt]
    if (!routed.ok || !GridIdCodec.isValidId(routed.appliedDest)) {
      return {
        receipts,
        lastDestNodeId: routed.lastDestNodeId,
        lastRouteFailureReason: routed.lastRouteFailureReason,
        lastReplanSummary: routed.lastReplanSummary
      }
    }

    const wait = await hooks.waitUntilArriveNode(routed.appliedDest)
    if (wait.arrived) {
      receipts.push(hooks.buildReceipt(`到达 ${routed.appliedDest}`, true, true))
    } else {
      const curText: string = wait.finalNode.length > 0 ? wait.finalNode : '未知'
      receipts.push(hooks.buildReceipt(`等待到达超时(${routed.appliedDest}, 当前=${curText})`, true, false))
    }

    return {
      receipts,
      lastDestNodeId: routed.lastDestNodeId,
      lastRouteFailureReason: routed.lastRouteFailureReason,
      lastReplanSummary: routed.lastReplanSummary
    }
  }
}
