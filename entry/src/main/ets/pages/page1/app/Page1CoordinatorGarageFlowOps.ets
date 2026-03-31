/**
 * 代码指南：
 * 文件：pages/page1/app/Page1CoordinatorGarageFlowOps.ets
 * 用途：Page1 车库主流程控制（出库前拦截、BC/03、BC/04、最终 carport）拆分模块。
 * 何时修改：车库流程的业务判定与动作编排调整时。
 * 相关文件：app/Page1CoordinatorCore.ets
 */
import { Page1UiStore } from './Page1UiStore'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import hilog from '@ohos.hilog'

const TEXTONE1_DOMAIN = 0xFF02
const TEXTONE1_TAG = 'textone1'

type C = Record<string, any>

export async function onGateEnterAckCompleted(c0: object, fromId: string, toId: string): Promise<void> {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  if (!s) return
  const from: string = fromId.trim().toUpperCase()
  const to: string = toId.trim().toUpperCase()
  if (from !== 'B4' || to !== 'B2') return

  // billing 已废弃：道闸计时改为在 B2->B4 depart 发送时开始，B4->B2 depart 发送时结束。
  s.pushLog('GATE_BILLING: 忽略旧的 GO-ACK billing 流程，当前使用 depart 起止计时')
}

export function isGarageTerminalNode(c0: object, nodeId: string): boolean {
  return isSmartParkingGoal(c0, nodeId)
}

export function smartParkingGoalId(c0: object): string {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  if (!s) return 'F7'
  return s.smartParkingGoalId()
}

export function isSmartParkingGoal(c0: object, goalId: string): boolean {
  const x: string = goalId.trim().toUpperCase()
  return x.length > 0 && x === smartParkingGoalId(c0)
}

export async function maybeHandleGarageDepartBeforeDrive(c0: object, _nowMs: number): Promise<boolean> {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  if (!s) return false
  {
    const payloadText: string =
      `textone1 GARAGE_DEPART enter realSend=${s.realSendEnabled ? 1 : 0} conn=${s.connText} ` +
      `startSent=${c.garageDepartStopSent ? 1 : 0} ready03=${c.garageDepartReady03 ? 1 : 0}`
    hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
  }
  if (s.pathNodes.length <= 1) return false

  const startId: string = s.pathNodes[0].trim().toUpperCase()
  if (!isGarageTerminalNode(c0, startId)) return false
  if (s.pathIndex !== 0) return false

  const curId: string = s.currentSnapNodeId.trim().toUpperCase()
  if (curId.length > 0 && curId !== startId) return false

  if (c.garageDepartReady03) return false

  if (!c.garageDepartStopSent) {
    c.garageDepartStopSent = true
    s.setAction(`garage depart wait(BC/03) from ${startId}`)
    {
      const payloadText: string = `textone1 GARAGE_DEPART try_send_0x19 start=${startId}`
      hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
    }
    if (c.canRealSend()) {
      s.bumpTx()
      if (!c.canSendMotionCommand('LOWCARPORT', 'GARAGE_DEPART')) {
        const payloadText: string = 'textone1 GARAGE_DEPART blocked LOWCARPORT by motion guard'
        hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
        return true
      }
      await c.proto.lowcarport()
      {
        const payloadText: string = 'textone1 GARAGE_DEPART sent_0x19 lowcarport'
        hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
      }
      c.armGarageDepartAckRetry(startId)
      s.pushLog(`GARAGE_DEPART: lowcarport sent at ${startId}, wait BC/03`)
    } else {
      if (s.realSendEnabled) {
        // 用户已切到真车模式但链路尚未连接：不能直接 bypass，否则后续不会再发 0x19。
        c.garageDepartStopSent = false
        {
          const payloadText: string = 'textone1 GARAGE_DEPART waiting_tcp_connected_for_0x19'
          hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
        }
        s.pushLog(`GARAGE_DEPART: wait TCP connected before lowcarport at ${startId}`)
        return true
      }
      // 纯 DRY_RUN 才允许直接放行。
      c.garageDepartReady03 = true
      {
        const payloadText: string = 'textone1 GARAGE_DEPART dry_run_bypass'
        hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
      }
      s.pushLog(`GARAGE_DEPART: DRY_RUN bypass at ${startId}`)
      return false
    }
  }
  return true
}

export function onGarageDepartReadyAck(c0: object): void {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  c.clearGarageDepartAckWatch()
  c.garageDepartReady03 = true
  if (s) {
    const payloadText: string = 'textone1 GARAGE_DEPART recv_BC_03'
    hilog.info(TEXTONE1_DOMAIN, TEXTONE1_TAG, 'send payload: %{public}s', payloadText)
    s.pushLog('GARAGE_DEPART: recv BC/03, drive enabled')
    s.setAction('车库出库就绪')
  }
}

export function beginGarageWaitParkDone04(c0: object, _level: number): void {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  c.garageWaitingParkDone04 = true
  c.garagePendingCarportLevel = 2
  if (s) {
    s.pushLog(`GARAGE_PARKING: wait BC/04 then carport(${c.garagePendingCarportLevel})`)
    s.setAction('车库停车等待 BC/04')
  }
}

export function onGarageParkDone04(c0: object): void {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  if (c.garageFinalCarportSent) {
    if (s) s.pushLog('GARAGE_PARK_DONE: BC/04 ignored (already sent)')
    return
  }

  if (!c.garageWaitingParkDone04) {
    const smartGoalId: string = smartParkingGoalId(c0)
    const curId: string = s ? s.currentSnapNodeId.trim().toUpperCase() : ''
    const destId: string = s ? s.destApplied.trim().toUpperCase() : ''
    const atSmartGoal: boolean = curId === smartGoalId || destId === smartGoalId
    if (!atSmartGoal) {
      if (s) s.pushLog('GARAGE_PARK_DONE: BC/04 ignored (not waiting)')
      return
    }
    if (s) s.pushLog(`GARAGE_PARK_DONE: BC/04 fallback trigger at ${smartGoalId}`)
  } else {
    c.garageWaitingParkDone04 = false
  }

  const level: number = c.garagePendingCarportLevel > 0 ? c.garagePendingCarportLevel : 2
  c.garagePendingCarportLevel = 0
  c.garageFinalCarportSent = true
  void c.sendGarageCarportAfterParkDone(level)
}

export async function sendGarageCarportAfterParkDone(c0: object, _level: number): Promise<void> {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  const targetLevel: number = 2
  c.proto.setMode(c.canRealSend() ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)
  if (s) {
    s.pushLog(`GARAGE_PARK_DONE: BC/04 -> carport(${targetLevel})`)
    s.setAction(`garage carport level=${targetLevel}`)
    s.bumpTx()
  }
  if (!c.canSendMotionCommand(`CARPORT_${targetLevel}`, 'GARAGE_PARK_DONE')) {
    return
  }
  await c.proto.carport(targetLevel)
  if (c.canRealSend()) c.armGarageCarportAckRetry(targetLevel)
}

export async function maybeHandleGarageFinalArrive(c0: object, toId: string): Promise<void> {
  const c: C = c0 as C
  const s: Page1UiStore | undefined = c.store as Page1UiStore | undefined
  if (!s) return
  const id: string = toId.trim().toUpperCase()
  if (!isGarageTerminalNode(c0, id)) return
  // 车库流程现在由到达前超声波 + BC/04 握手驱动。
  s.pushLog(`GARAGE_ARRIVE: ${id} waiting BC/04 to carport`)
}

