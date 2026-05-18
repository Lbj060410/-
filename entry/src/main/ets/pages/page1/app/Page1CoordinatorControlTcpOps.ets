import { Page1UiStore, CarConnState } from './Page1UiStore'
import { Page1Action } from '../types/Page1Types'
import { CarTcpCallbacks } from '../../../services/control/CarTcpService'
import { CarConnectionState } from '../../../services/control/CarConnectionState'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { CarProtoFrame, CarProtoStreamDecoder } from '../net/CarRx55StreamDecoder'
import { P1C, IPage1CoordinatorOps } from './Page1CoordinatorDefs'
import { commStore } from '../../../state/CommStore'
import { ensureRecognitionCenter } from '../../../services/recognition/RecognitionCenter'
import { RecognitionSubtype } from '../../../services/recognition/RecognitionTask'
import { videoStore } from '../../../state/VideoStore'
import { page2ReplayService } from '../../../services/replay/Page2ReplayService'
import hilog from '@ohos.hilog'

const PAGE1_TCP_LOG_DOMAIN = 0xFF03
const PAGE1_TCP_LOG_TAG = 'page1tcp'

export function bindTcpCallbacks(ctx: IPage1CoordinatorOps): void {
  const cb: CarTcpCallbacks = {
    onStateChange: (state: CarConnectionState, text: string): void => onTcpState(ctx, state, text),
    onData: (data: Uint8Array): void => onTcpData(ctx, data)
  }
  ctx.tcp.setCallbacks(cb)
}

export function onTcpState(ctx: IPage1CoordinatorOps, state: CarConnectionState, text: string): void {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return

  ctx.proto.setMode((s.realSendEnabled && state === CarConnectionState.CONNECTED) ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)

  if (state === CarConnectionState.CONNECTED) {
    ctx.rxDecoder.reset()
    s.setConnState(CarConnState.CONNECTED, `TCP:CONNECTED | ${text}`)
    s.heartbeatOk = true
    s.pushLog('TCP 已连接，进入新协议链路模式(CCF5)')
    commStore.setCommState(true, 'CONNECTED')
    commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
    commStore.setCommLastError('')
    return
  }
  if (state === CarConnectionState.CONNECTING) {
    ctx.rxDecoder.reset(); s.setConnState(CarConnState.CONNECTING, `TCP:CONNECTING | ${text}`)
    commStore.setCommState(false, 'CONNECTING'); commStore.setCommReconnectCount(ctx.tcp.getReconnectCount()); return
  }
  if (state === CarConnectionState.RECONNECTING) {
    ctx.rxDecoder.reset(); s.setConnState(CarConnState.RECONNECTING, `TCP:RECONNECTING | ${text}`)
    commStore.setCommState(false, 'RECONNECTING'); commStore.setCommReconnectCount(ctx.tcp.getReconnectCount()); return
  }
  if (state === CarConnectionState.FAILED) {
    ctx.rxDecoder.reset(); s.setConnState(CarConnState.FAILED, `TCP:FAILED | ${text}`)
    s.heartbeatOk = false
    commStore.setCommState(false, 'FAILED'); commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
    commStore.setCommLastError(ctx.tcp.getLastErrorText()); return
  }
  ctx.rxDecoder.reset(); s.setConnState(CarConnState.IDLE, `TCP:IDLE | ${text}`)
  s.heartbeatOk = false
  commStore.setCommState(false, 'DISCONNECTED')
  commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
}

export function onTcpData(ctx: IPage1CoordinatorOps, data: Uint8Array): void {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  s.bumpRx(); s.heartbeatOk = true; commStore.bumpRxPacket()

  const frames: Array<CarProtoFrame> = (ctx.rxDecoder as CarProtoStreamDecoder).feedProto(data)
  if (frames.length <= 0) {
    const nowMs: number = Date.now()
    const lastLogAtMs: number = Number(ctx.rawNoFrameLastLogAtMs) || 0
    if (nowMs - lastLogAtMs >= 1200) {
      ctx.rawNoFrameLastLogAtMs = nowMs
      s.pushLog(`RX RAW(noCCF5): ${bytesToHex(data)} | decoderBuf=${ctx.rxDecoder.getBufferedSize()}`)
    }
    return
  }

  for (let i: number = 0; i < frames.length; i++) {
    const f: CarProtoFrame = frames[i]
    if (!f.ok) {
      s.pushLog(`RX CCF5 CRC错误 type=0x${byteToHex(f.type)} seq=${f.seq}`)
      appendDiagRxFrame(f, `CRC错误 type=0x${byteToHex(f.type)}`)
      continue
    }
    const t: number = f.type & 0xff
    const d: Uint8Array = f.data

    if (t === 0xA0) {
      const ok: boolean = typeof ctx.proto.onAckReceived === 'function' ? ctx.proto.onAckReceived(f.seq) : false
      s.pushLog(`RX CCF5 ACK seq=${f.seq} ${ok ? 'matched' : 'untracked'}`)
      let ackSummary: string = `ACK 未匹配 seq=${f.seq}`
      if (ok) {
        const meaning: string = (typeof ctx.proto.consumeAckMatchedMeaning === 'function')
          ? String(ctx.proto.consumeAckMatchedMeaning(f.seq) || '')
          : ''
        ackSummary = meaning.length > 0 ? `ACK ${meaning}` : `ACK 已匹配 seq=${f.seq}`
      }
      appendDiagRxFrame(f, ackSummary)
      continue
    }

    if (f.flags === 0x02 || f.flags === 0x03) {
      if (typeof ctx.proto.sendAck === 'function') {
        void ctx.proto.sendAck(f.seq)
      }
    }

    if (t === 0xBC) {
      appendDiagRxFrame(f, summarizeBcFrame(f))
      handleBCFrame(ctx, s, f)
      continue
    }

    appendDiagRxFrame(f, `收到类型0x${byteToHex(t)} flags=0x${byteToHex(f.flags)}`)
    s.pushLog(`RX CCF5 type=0x${byteToHex(t)} flags=0x${byteToHex(f.flags)} seq=${f.seq} data=${bytesToHex(d)}`)
  }
}

function handleBCFrame(ctx: IPage1CoordinatorOps, s: Page1UiStore, f: CarProtoFrame): void {
  const d: Uint8Array = f.data
  if (d.length <= 0) {
    s.pushLog(`RX CCF5 BC: empty seq=${f.seq}`)
    return
  }
  const data1: number = d[0] & 0xff
  if (data1 === 0x01) {
    // data1=0x01: 当前点位上报（节点两字节 ASCII，如 F6），可选第4字节为方向 ASCII
    if (d.length >= 3) {
      const nodeId: string = decodeNodeAscii(d[1], d[2])
      if (nodeId.length > 0) {
        const dirRaw: number = d.length >= 4 ? (d[3] & 0xff) : 0x4E
        const dirText: string = decodeDirByte(dirRaw)
        const headingDeg: number = headingDegFromDir(dirText)
        s.updateCurrentNodePose(nodeId, headingDeg)
        syncPathWithCarNode(s, nodeId)
        s.pushLog(`RX CCF5 BC: 当前点位 node=${nodeId} 方向为${dirToCn(dirText)}(0x${byteToHex(dirRaw)}) seq=${f.seq}`)
        return
      }
    }
    s.pushLog(`RX CCF5 BC: 当前点位(格式异常) data=${bytesToHex(d)} seq=${f.seq}`)
    return
  }
  if (data1 === 0x02) {
    // data1=0x02: 上报障碍物所在路段
    // 约定解析：02 <fromCol><fromRow><toCol><toRow>
    if (d.length >= 5) {
      videoStore.setRecognitionEnabled(true)
      videoStore.setPage2Yolov26BarrierEnabled(true)
      const fromId: string = decodeNodeAscii(d[1], d[2])
      const toId: string = decodeNodeAscii(d[3], d[4])
      if (fromId.length > 0 && toId.length > 0) {
        const edgeId: string = `${fromId}|${toId}`
        void page2ReplayService.onObstacleEdgeDetected(fromId, toId)
        if (!s.isBlockedEdgeById(edgeId)) {
          s.toggleBlockedEdge(edgeId)
        }
        s.addBlockedEdgeIfAbsent(edgeId, 'CAR_ASTAR_OBSTACLE')
        if (s.destApplied.length > 0 && typeof ctx.planPath === 'function') {
          ctx.planPath(s.destApplied)
          s.pushLog(`RX CCF5 BC: 重规划触发 goal=${s.destApplied}`)
        }
      }
      s.pushLog(`RX CCF5 BC: 路段障碍 edge=${fromId.length > 0 ? fromId : '??'}|${toId.length > 0 ? toId : '??'} seq=${f.seq}`)
      return
    }
    s.pushLog(`RX CCF5 BC: 路段障碍(格式异常) data=${bytesToHex(d)} seq=${f.seq}`)
    return
  }
  if (data1 === 0x06) {
    try {
      // 小车触发交通灯识别：走识别中心 -> 识别上报服务 -> SendTrafficGreen/SendTrafficRedOrYellow
      videoStore.setRecognitionEnabled(true)
      videoStore.setPage2TrafficEnabled(true)
      void page2ReplayService.onTrafficLightSignal(`RX CCF5 BC: data1=0x06 seq=${f.seq}`)
      const scheduler = ensureRecognitionCenter()
      scheduler.enqueueAutoSnapshotTriggered(RecognitionSubtype.TRAFFIC_LIGHT)
      s.pushLog(`RX CCF5 BC: 触发交通灯识别 seq=${f.seq}`)
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e)
      s.pushLog(`RX CCF5 BC: 交通灯识别触发失败 ${msg}`)
    }
    return
  }
  if (data1 === 0x03) {
    s.setAction('小车已通过道闸')
    s.pushLog(`RX CCF5 BC: 小车已通过道闸 seq=${f.seq}`)
    return
  }
  if (data1 === 0x04) {
    s.setAction('入库完成')
    s.pushLog(`RX CCF5 BC: 入库完成 seq=${f.seq}`)
    return
  }
  if (data1 === 0x05) {
    s.setAction('出库完成')
    s.pushLog(`RX CCF5 BC: 出库完成 seq=${f.seq}`)
    return
  }
  s.pushLog(`RX CCF5 BC: data1=0x${byteToHex(data1)} data=${bytesToHex(d)} seq=${f.seq}`)
}

function decodeNodeAscii(b0: number, b1: number): string {
  const c0: string = String.fromCharCode(b0 & 0xff).toUpperCase()
  const c1: string = String.fromCharCode(b1 & 0xff).toUpperCase()
  const id: string = `${c0}${c1}`
  const ok0: boolean = c0 >= 'A' && c0 <= 'Z'
  const ok1: boolean = c1 >= '0' && c1 <= '9'
  return (ok0 && ok1) ? id : ''
}

function decodeDirByte(b: number): string {
  const v: number = b & 0xff
  // 兼容数字方向编码：1=N, 2=E, 3=S, 4=W
  if (v === 0x01) return 'N'
  if (v === 0x02) return 'E'
  if (v === 0x03) return 'S'
  if (v === 0x04) return 'W'

  // 兼容 ASCII 方向编码：'N'/'E'/'S'/'W'
  const c: string = String.fromCharCode(v).toUpperCase()
  if (c === 'N' || c === 'E' || c === 'S' || c === 'W') return c
  return 'N'
}

function headingDegFromDir(dir: string): number {
  if (dir === 'E') return 0
  if (dir === 'S') return 90
  if (dir === 'W') return 180
  return 270
}

function dirToCn(dir: string): string {
  const d: string = (dir || 'N').trim().toUpperCase()
  if (d === 'E') return '东'
  if (d === 'S') return '南'
  if (d === 'W') return '西'
  return '北'
}

function summarizeBcFrame(f: CarProtoFrame): string {
  const d: Uint8Array = f.data
  if (d.length <= 0) return '状态上报'
  const data1: number = d[0] & 0xFF
  if (data1 === 0x01) {
    if (d.length >= 3) {
      const nodeId: string = decodeNodeAscii(d[1], d[2])
      const dirRaw: number = d.length >= 4 ? (d[3] & 0xff) : 0x4E
      const dirText: string = decodeDirByte(dirRaw)
      return `上报当前点位 node=${nodeId.length > 0 ? nodeId : '??'} 方向为${dirToCn(dirText)}(0x${byteToHex(dirRaw)})`
    }
    return '上报当前点位(格式异常)'
  }
  if (data1 === 0x02) {
    if (d.length >= 5) {
      const fromId: string = decodeNodeAscii(d[1], d[2])
      const toId: string = decodeNodeAscii(d[3], d[4])

      return `上报障碍路段 edge=${fromId.length > 0 ? fromId : '??'}|${toId.length > 0 ? toId : '??'}`
    }
    return '上报障碍路段(格式异常)'
  }
  if (data1 === 0x03) return '小车已通过道闸'
  if (data1 === 0x04) return '上报入库完成'
  if (data1 === 0x05) return '上报出库完成'
  if (data1 === 0x06) return '触发交通灯识别'
  return `状态上报 data1=0x${byteToHex(data1)}`
}

function appendDiagRxFrame(f: CarProtoFrame, summary: string): void {
  try {
    let cmdHex: string = `0x${byteToHex(f.type)}`
    if ((f.type & 0xFF) === 0xBC && f.data.length > 0) {
      cmdHex = `0x${byteToHex(f.data[0] & 0xFF)}`
    } else if ((f.type & 0xFF) === 0xA0) {
      cmdHex = 'ACK'
    }
    commStore.appendDiagKeyRxFrame({
      tsMs: Date.now(),
      cmdHex: cmdHex,
      summary: summary,
      frameKind: 'CCF5',
      hex: bytesToHex(f.raw)
    })
  } catch (_) {}
}


export function clearPendingFrameDestApply(ctx: IPage1CoordinatorOps): void {
  if (ctx.frameDestApplyTimerId !== -1) { clearTimeout(ctx.frameDestApplyTimerId); ctx.frameDestApplyTimerId = -1 }
  ctx.pendingFrameDestNodeId = ''
}

export function scheduleFrameDestApply(ctx: IPage1CoordinatorOps, destNodeId: string): void {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  clearPendingFrameDestApply(ctx)
  ctx.pendingFrameDestNodeId = destNodeId
  s.destDraft = destNodeId
  s.pushLog(`收到目的地，2秒后应用：${destNodeId}`)
  s.setAction(`收到目的地：${destNodeId}`)
  ctx.frameDestApplyTimerId = setTimeout((): void => {
    const store: Page1UiStore | undefined = ctx.store
    const pendingDestNodeId: string = ctx.pendingFrameDestNodeId
    ctx.frameDestApplyTimerId = -1
    ctx.pendingFrameDestNodeId = ''
    if (!store || pendingDestNodeId.length <= 0) return
    store.destDraft = pendingDestNodeId
    store.applyDest()
    ctx.planPath(store.destApplied)
    ctx.destFromFrame = false
  }, P1C.FRAME_DEST_APPLY_DELAY_MS) as number
}

export function byteToHex(v: number): string { return (v & 0xff).toString(16).toUpperCase().padStart(2, '0') }

export function bytesToHex(data: Uint8Array): string {
  let s: string = ''
  for (let i: number = 0; i < data.length; i++) {
    const part: string = (data[i] & 0xff).toString(16).toUpperCase().padStart(2, '0')
    s = s.length === 0 ? part : `${s} ${part}`
  }
  return s
}

export function markParkingUltrasonicRequest(ctx: IPage1CoordinatorOps, nowMs: number): void {
  ctx.parkingUltrasonicPending = true
  ctx.parkingUltrasonicRequestAtMs = nowMs
  ctx.parkingUltrasonicExpireAtMs = nowMs + P1C.ULTRASONIC_RESPONSE_CONTEXT_MS
}

export function clearParkingUltrasonicRequest(ctx: IPage1CoordinatorOps): void {
  ctx.parkingUltrasonicPending = false
  ctx.parkingUltrasonicRequestAtMs = 0
  ctx.parkingUltrasonicExpireAtMs = 0
}

export function isParkingUltrasonicResponseContext(ctx: IPage1CoordinatorOps, nowMs: number): boolean {
  return !!ctx.parkingUltrasonicPending && ctx.parkingUltrasonicRequestAtMs > 0 && nowMs >= ctx.parkingUltrasonicRequestAtMs && nowMs <= ctx.parkingUltrasonicExpireAtMs
}

export async function connectTcp(ctx: IPage1CoordinatorOps, ip: string, port: number): Promise<void> {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  s.setConnState(CarConnState.CONNECTING, `TCP:CONNECTING | ${ip}:${port}`)
  s.pushLog(`尝试连接主车：${ip}:${port}`)
  try { await ctx.tcp.connect(ip, port) } catch { s.pushLog('connect() 抛异常：已交给 CarTcpService 重连处理') }
}

export async function disconnectTcp(ctx: IPage1CoordinatorOps): Promise<void> {
  try { await ctx.tcp.disconnect() } catch (e) {
    const msg: string = e instanceof Error ? e.message : 'disconnect error'
    hilog.warn(PAGE1_TCP_LOG_DOMAIN, PAGE1_TCP_LOG_TAG, '%{public}s', `[Page1] disconnectTcp: ${msg}`)
  }
}

export function canRealSend(ctx: IPage1CoordinatorOps): boolean {
  const s: Page1UiStore | undefined = ctx.store
  return !!s && !!s.realSendEnabled && s.connState === CarConnState.CONNECTED
}

export async function sendManualGoCommand(ctx: IPage1CoordinatorOps, _actionText: string, _commandSeq: number): Promise<void> {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  s.setAction('前进'); s.bumpTx(); s.pushLog('旧发送协议已删除：忽略前进下发')
  ctx.manualGoLastSentAtMs = Date.now()
}

export async function onAction(ctx: IPage1CoordinatorOps, a: Page1Action): Promise<void> {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  const name: string = Page1Action[a]
  if (a === Page1Action.SCRAM) {
    s.pushLog('SCRAM: 按钮留空（未绑定发送）')
    return
  }

  // 门控已下线：不再拦截 GO。

  if (!ctx.canRealSend()) {
    s.bumpTx()
    s.setAction(`动作=${name} | DRY`)
    s.pushLog(`动作发送(DRY_RUN)：${name}`)
  } else {
    ctx.proto.setMode(CarSendMode.REAL_SEND)
    s.bumpTx()
    s.setAction(`动作=${name} | REAL`)
    let seq: number = 0
    if (a === Page1Action.GO) seq = await ctx.proto.Forward(false)
    else if (a === Page1Action.BACK) seq = await ctx.proto.Backward(false)
    else if (a === Page1Action.LEFT) seq = await ctx.proto.TurnLeft(false)
    else if (a === Page1Action.RIGHT) seq = await ctx.proto.TurnRight(false)
    else if (a === Page1Action.LEFT_HALF) seq = await ctx.proto.TurnLeftHalf(false)
    else if (a === Page1Action.RIGHT_HALF) seq = await ctx.proto.TurnRightHalf(false)
    else if (a === Page1Action.UTURN) seq = await ctx.proto.TurnRound(false)
    else if (a === Page1Action.STOP) seq = await ctx.proto.Send0A(0x00, undefined, false, true)
    s.pushLog(`动作发送(CCF5)：${name} seq=${seq}`)
  }

  if (a === Page1Action.GO) ctx.previewManualActionOnMap(Page1Action.GO)
  if (a === Page1Action.BACK) ctx.previewManualActionOnMap(Page1Action.BACK)
  if (a === Page1Action.LEFT) ctx.previewManualActionOnMap(Page1Action.LEFT)
  if (a === Page1Action.RIGHT) ctx.previewManualActionOnMap(Page1Action.RIGHT)
  if (a === Page1Action.LEFT_HALF) ctx.previewManualActionOnMap(Page1Action.LEFT_HALF)
  if (a === Page1Action.RIGHT_HALF) ctx.previewManualActionOnMap(Page1Action.RIGHT_HALF)
  if (a === Page1Action.UTURN) ctx.previewManualActionOnMap(Page1Action.UTURN)
}

// 小车上报节点时，用实际经过的节点同步路线预览。
// 逻辑：
// 1. 节点在路径前方 → 推进 pathIndex 到该节点（跳过中间漏报）
// 2. 节点不在路径里（小车重规划）→ 截断当前路径到当前位置，追加新节点
// 3. 无规划路径 → 不动
function syncPathWithCarNode(s: Page1UiStore, nodeId: string): void {
  const nodes: Array<string> = s.pathNodes
  if (nodes.length <= 1) return

  const id: string = nodeId.trim().toUpperCase()

  // 从当前 pathIndex 往后找，看节点是否在预览路径里
  const cur: number = s.pathIndex
  for (let i: number = cur; i < nodes.length; i++) {
    if (nodes[i].trim().toUpperCase() === id) {
      // 找到了：把 pathIndex 推进到该位置
      if (i > cur) {
        s.pathIndex = i
      }
      return
    }
  }

  // 节点不在预览路径里：小车走了不同路线（重规划/绕行）
  // 截断路径到 pathIndex（保留已走部分），然后把新节点追加进去
  const walked: Array<string> = nodes.slice(0, cur + 1)
  walked.push(id)
  s.setPath(walked, 'CAR_ASTAR_REROUTE')
  // setPath 会把 pathIndex 重置为 0，手动推到已走完的最后一个节点
  s.pathIndex = walked.length - 1
}
