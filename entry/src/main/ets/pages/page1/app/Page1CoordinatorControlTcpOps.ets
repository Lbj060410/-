/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1CoordinatorControlTcpOps.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1CoordinatorControlTcpOps.ets
 * 用途： 封装 Page1Coordinator 的 TCP 控制与协议收发相关操作。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import { Page1UiStore, CarConnState } from './Page1UiStore'
import { Page1Action, CarTelemetry } from '../types/Page1Types'
import { CarTcpCallbacks } from '../../../services/control/CarTcpService'
import { CarConnectionState } from '../../../services/control/CarConnectionState'
import { CarSendMode } from '../../../services/control/CarProtocolService'
import { CarFrame55 } from '../net/CarRx55StreamDecoder'
import { GridIdCodec } from './PathPlannerAStar'
import { P1C } from './Page1CoordinatorDefs'
import { commStore } from '../../../state/CommStore'
import { maybeBlockGoByTrafficGate } from './Page1CoordinatorTrafficGateOps'
import { replayArchiveService } from '../../../services/replay/ReplayArchiveService'
import { page2ReplayService } from '../../../services/replay/Page2ReplayService'
import hilog from '@ohos.hilog'

const PAGE1_TCP_LOG_DOMAIN = 0xFF03
const PAGE1_TCP_LOG_TAG = 'page1tcp'

function kickTcpConnectForRealSendIfNeeded(ctx: any, s: Page1UiStore): void {
  if (!s.realSendEnabled) return
  if (s.connState === CarConnState.CONNECTED || s.connState === CarConnState.CONNECTING || s.connState === CarConnState.RECONNECTING) return
  const nowMs: number = Date.now()
  const lastKickAtMs: number = Number(ctx.realSendConnectKickAtMs) || 0
  if (nowMs - lastKickAtMs < 2000) return
  ctx.realSendConnectKickAtMs = nowMs
  s.pushLog(`REAL_SEND: 链路未连接，自动重连 ${s.connIp}:${s.connPort}`)
  void ctx.connectTcp(s.connIp, s.connPort)
}

export function bindTcpCallbacks(ctx: any): void {
  const cb: CarTcpCallbacks = {
    onStateChange: (state: CarConnectionState, text: string): void => {
      onTcpState(ctx, state, text)
    },
    onData: (data: Uint8Array): void => {
      onTcpData(ctx, data)
    }
  }
  ctx.tcp.setCallbacks(cb)
}

function frameDedupKey(f: CarFrame55): string {
  return `${f.frameKind}|${f.cmd & 0xff}|${f.p1 & 0xff}|${f.p2 & 0xff}|${f.p3 & 0xff}|${bytesToHex(f.raw)}`
}

function isConsecutiveDuplicateFrame(ctx: any, f: CarFrame55): boolean {
  const key: string = frameDedupKey(f)
  const last: string = typeof ctx.lastRxFrameDedupKey === 'string' ? ctx.lastRxFrameDedupKey : ''
  if (key === last) return true
  ctx.lastRxFrameDedupKey = key
  return false
}

export function onTcpState(ctx: any, state: CarConnectionState, text: string): void {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  ctx.lastRxFrameDedupKey = ''

  ctx.proto.setMode(
    (s.realSendEnabled && state === CarConnectionState.CONNECTED)
      ? CarSendMode.REAL_SEND
      : CarSendMode.DRY_RUN
  )

  if (state === CarConnectionState.CONNECTED) {
    ctx.rxDecoder.reset()
    ctx.resetPathAckState()
    s.setConnState(CarConnState.CONNECTED, `TCP:CONNECTED | ${text}`)
    s.heartbeatOk = true
    s.pushLog('TCP 已连接，进入实时链路模式')
    commStore.setCommState(true, 'CONNECTED')
    commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
    commStore.setCommLastError('')
    return
  }

  if (state === CarConnectionState.CONNECTING) {
    ctx.rxDecoder.reset()
    ctx.resetPathAckState()
    s.setConnState(CarConnState.CONNECTING, `TCP:CONNECTING | ${text}`)
    s.pushLog('TCP 连接中...')
    commStore.setCommState(false, 'CONNECTING')
    commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
    return
  }

  if (state === CarConnectionState.RECONNECTING) {
    ctx.rxDecoder.reset()
    ctx.resetPathAckState()
    s.setConnState(CarConnState.RECONNECTING, `TCP:RECONNECTING | ${text}`)
    s.reconnectCount += 1
    s.pushLog(`TCP 触发重连，count=${s.reconnectCount}`)
    commStore.setCommState(false, 'RECONNECTING')
    commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
    return
  }

  if (state === CarConnectionState.FAILED) {
    ctx.rxDecoder.reset()
    ctx.resetPathAckState()
    s.setConnState(CarConnState.FAILED, `TCP:FAILED | ${text}`)
    s.heartbeatOk = false
    s.pushLog(`TCP 失败：${text}`)
    commStore.setCommState(false, 'FAILED')
    commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
    commStore.setCommLastError(ctx.tcp.getLastErrorText())
    return
  }

  ctx.rxDecoder.reset()
  ctx.resetPathAckState()
  s.setConnState(CarConnState.IDLE, `TCP:IDLE | ${text}`)
  s.heartbeatOk = false
  commStore.setCommState(false, 'DISCONNECTED')
  commStore.setCommReconnectCount(ctx.tcp.getReconnectCount())
}

export function onTcpData(ctx: any, data: Uint8Array): void {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  s.bumpRx()
  s.heartbeatOk = true
  commStore.bumpRxPacket()

  const frames: Array<CarFrame55> = ctx.rxDecoder.feed(data)
  if (frames.length <= 0) {
    const isHeartbeatEcho: boolean = data.length === 1 && ((data[0] & 0xff) === 0x00)
    if (!isHeartbeatEcho) {
      const nowMs: number = Date.now()
      const lastLogAtMs: number = (ctx.rawNoFrameLastLogAtMs as number) || 0
      if (nowMs - lastLogAtMs >= 1200) {
        ctx.rawNoFrameLastLogAtMs = nowMs
        const bufSize: number = typeof ctx.rxDecoder.getBufferedSize === 'function' ? ctx.rxDecoder.getBufferedSize() : 0
        s.pushLog(`RX RAW(no55AA): ${bytesToHex(data)} | decoderBuf=${bufSize}`)
      }
    }
    return
  }

  for (let i: number = 0; i < frames.length; i++) {
    const f: CarFrame55 = frames[i]
    if (isConsecutiveDuplicateFrame(ctx, f)) continue

    const nextTelemetry: CarTelemetry | undefined = parseTelemetryFrom55(ctx, s.telemetry, f)
    if (nextTelemetry) {
      if (f.cmd === 0xBB) {
        const lux: number = decodeLuxFromBbFrame(f)
        appendDiagKeyRxFrame(ctx, f, `光照值=${lux}`)
      }
      s.setTelemetry(nextTelemetry)
      s.updateRisk()
      if (ctx.maybeTriggerRoutePointObstacle()) continue
      ctx.maybeReplanOnObstacle()
      continue
    }
    logFrame55(ctx, s, f)
  }
}

export function parseTelemetryFrom55(ctx: any, prev: CarTelemetry, f: CarFrame55): CarTelemetry | undefined {
  void ctx
  if (f.cmd === 0xBB) {
    const lux: number = decodeLuxFromBbFrame(f)
    if (typeof ctx.onLightLuxReceived === 'function') {
      ctx.onLightLuxReceived(lux)
    }
    return {
      tsMs: Date.now(),
      speed: prev.speed,
      headingDeg: prev.headingDeg,
      odomMm: prev.odomMm,
      ultraFrontCm: prev.ultraFrontCm,
      ultraBackCm: prev.ultraBackCm,
      irDistCm: prev.irDistCm,
      lightLux: lux,
      rfid: prev.rfid
    }
  }
  return undefined
}

export function clearPendingFrameDestApply(ctx: any): void {
  if (ctx.frameDestApplyTimerId !== -1) {
    clearTimeout(ctx.frameDestApplyTimerId)
    ctx.frameDestApplyTimerId = -1
  }
  ctx.pendingFrameDestNodeId = ''
}

export function scheduleFrameDestApply(ctx: any, destNodeId: string): void {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return

  clearPendingFrameDestApply(ctx)
  ctx.pendingFrameDestNodeId = destNodeId
  s.destDraft = destNodeId
  s.pushLog(`收到主车目的地，2秒后应用：${destNodeId}`)
  s.setAction(`收到目的地：${destNodeId}`)

  ctx.frameDestApplyTimerId = setTimeout(async (): Promise<void> => {
    const store: Page1UiStore | undefined = ctx.store
    const pendingDestNodeId: string = ctx.pendingFrameDestNodeId
    ctx.frameDestApplyTimerId = -1
    ctx.pendingFrameDestNodeId = ''
    if (!store || pendingDestNodeId.length <= 0) return

    store.destDraft = pendingDestNodeId
    store.applyDest()
    ctx.planPath(store.destApplied)
    ctx.destFromFrame = false
    store.pushLog(`主车目的地已应用并开始规划：${store.destApplied}`)
  }, P1C.FRAME_DEST_APPLY_DELAY_MS) as number
}

export function byteToHex(v: number): string {
  return (v & 0xff).toString(16).toUpperCase().padStart(2, '0')
}

export function bytesToHex(data: Uint8Array): string {
  let s: string = ''
  let i: number = 0
  while (i < data.length) {
    const v: number = data[i] & 0xff
    const part: string = v.toString(16).toUpperCase().padStart(2, '0')
    s = s.length === 0 ? part : `${s} ${part}`
    i += 1
  }
  return s
}

export function markParkingUltrasonicRequest(ctx: any, nowMs: number): void {
  ctx.parkingUltrasonicPending = true
  ctx.parkingUltrasonicRequestAtMs = nowMs
  ctx.parkingUltrasonicExpireAtMs = nowMs + P1C.ULTRASONIC_RESPONSE_CONTEXT_MS
}

export function clearParkingUltrasonicRequest(ctx: any): void {
  ctx.parkingUltrasonicPending = false
  ctx.parkingUltrasonicRequestAtMs = 0
  ctx.parkingUltrasonicExpireAtMs = 0
}

export function isParkingUltrasonicResponseContext(ctx: any, nowMs: number): boolean {
  if (!ctx.parkingUltrasonicPending) return false
  if (ctx.parkingUltrasonicRequestAtMs <= 0) return false
  if (nowMs < ctx.parkingUltrasonicRequestAtMs) return false
  if (nowMs > ctx.parkingUltrasonicExpireAtMs) return false
  return true
}

export function decodeLuxFromBbFrame(f: CarFrame55): number {
  const lo: number = f.p2 & 0xff
  const hi: number = f.p3 & 0xff
  return (hi << 8) + lo
}

export function appendDiagKeyRxFrame(ctx: any, f: CarFrame55, summary: string): void {
  commStore.appendDiagKeyRxFrame({
    tsMs: Date.now(),
    cmdHex: `0x${byteToHex(f.cmd)}`,
    summary: summary,
    frameKind: f.frameKind,
    hex: bytesToHex(f.raw)
  })
}

export function logFrame55(ctx: any, s: Page1UiStore, f: CarFrame55): void {
  let msg: string = `RX 55AA cmd=0x${byteToHex(f.cmd)} payload=${bytesToHex(f.payload)}`

  if (f.cmd === 0xBB) {
    const lux: number = decodeLuxFromBbFrame(f)
    msg = `RX 55AA cmd=0xBB 光照值=${lux}`
  } else if (f.cmd === 0xBC) {
    const ultrasonicP1: number = f.p1 & 0xff

    if (ultrasonicP1 === 0x04) {
      ctx.onGarageParkDone04()
      msg = `RX 55AA cmd=0xBC garage-park-done p1=0x${byteToHex(ultrasonicP1)}`
      appendDiagKeyRxFrame(ctx, f, `garage-park-done p1=0x${byteToHex(ultrasonicP1)}`)
      s.pushLog(msg)
      return
    }

    if (ultrasonicP1 === 0x03) {
      ctx.onGarageDepartReadyAck()
      msg = `RX 55AA cmd=0xBC garage-ready p1=0x${byteToHex(ultrasonicP1)}`
      appendDiagKeyRxFrame(ctx, f, `garage-ready p1=0x${byteToHex(ultrasonicP1)}`)
      s.pushLog(msg)
      return
    }

    if (ultrasonicP1 === 0x00 || ultrasonicP1 === 0x01 || ultrasonicP1 === 0x02) {
      const recvAtMs: number = Date.now()
      const parkingCtx: boolean =
        isParkingUltrasonicResponseContext(ctx, recvAtMs) || !!ctx.parkingAwaitingUltrasonicDecision
      ctx.lastUltrasonicP1 = ultrasonicP1
      ctx.lastUltrasonicAtMs = recvAtMs
      msg = `RX 55AA cmd=0xBC 超声波结果 p1=0x${byteToHex(ultrasonicP1)}`
      appendDiagKeyRxFrame(ctx, f, `超声波结果 p1=0x${byteToHex(ultrasonicP1)}`)

      if (parkingCtx) {
        s.pushLog(
          ultrasonicP1 === 0x01
            ? '超声波：停车位被占用(0x01)'
            : `超声波：停车位可用(p1=0x${byteToHex(ultrasonicP1)})`
        )
        if (typeof ctx.onParkingUltrasonicResult === 'function') {
          void ctx.onParkingUltrasonicResult(ultrasonicP1, recvAtMs)
        } else {
          clearParkingUltrasonicRequest(ctx)
        }
      } else {
        s.pushLog(
          ultrasonicP1 === 0x01
            ? '超声波：行驶前方有障碍物(0x01)'
            : `超声波：行驶态结果 p1=0x${byteToHex(ultrasonicP1)}`
        )
        if (ultrasonicP1 === 0x01) {
          replayArchiveService.onObstacleTriggered('ULTRASONIC', '超声波检测到障碍并触发避障')
          void page2ReplayService.onUltrasonicObstacleSignal('接收到小车 0x01 障碍物信号')
          ctx.queueDrivingUltrasonicObstacle(ctx.lastUltrasonicAtMs)
        }
      }

      s.pushLog(msg)
      return
    }

    const rawP1Hex: string = byteToHex(f.p1)
    const rawP2Hex: string = byteToHex(f.p2)
    const rawP3Hex: string = byteToHex(f.p3)
    const colChar: string = String.fromCharCode(f.p1 & 0xff)
    const rowChar: string = String.fromCharCode(f.p2 & 0xff)
    const destNodeId: string = `${colChar}${rowChar}`.toUpperCase()

    msg = `RX 55AA cmd=0xBC p1=0x${rawP1Hex} p2=0x${rawP2Hex} p3=0x${rawP3Hex} 目的地=${destNodeId}`
    appendDiagKeyRxFrame(ctx, f, `目的地=${destNodeId} p1=0x${rawP1Hex} p2=0x${rawP2Hex} p3=0x${rawP3Hex}`)

    if (GridIdCodec.isValidId(destNodeId)) {
      ctx.destFromFrame = true
      scheduleFrameDestApply(ctx, destNodeId)
    } else if (destNodeId.trim().length > 0) {
      s.pushLog(`收到非法目的地编码 ASCII=${destNodeId}`)
    }
  } else if (f.cmd === 0xBD) {
    const status: number = f.p1 & 0xff
    ctx.onPathAckFrame(f)

    if (status === 0x01) {
      msg = 'RX 55AA cmd=0xBD 状态=01(已接收)'
    } else if (status === 0x02) {
      msg = 'RX 55AA cmd=0xBD 状态=02(已完成)'
    } else {
      msg = `RX 55AA cmd=0xBD 状态=0x${byteToHex(status)}`
    }

    appendDiagKeyRxFrame(ctx, f, msg)
  }

  s.pushLog(msg)
}

export async function connectTcp(ctx: any, ip: string, port: number): Promise<void> {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return

  s.setConnState(CarConnState.CONNECTING, `TCP:CONNECTING | ${ip}:${port}`)
  s.pushLog(`尝试连接主车：${ip}:${port}`)

  try {
    await ctx.tcp.connect(ip, port)
  } catch {
    s.pushLog('connect() 抛异常：已交给 CarTcpService 重连处理')
  }
}

export async function disconnectTcp(ctx: any): Promise<void> {
  try {
    await ctx.tcp.disconnect()
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : 'disconnect error'
    hilog.warn(PAGE1_TCP_LOG_DOMAIN, PAGE1_TCP_LOG_TAG, '%{public}s', `[Page1] disconnectTcp: ${msg}`)
  }
}

export function canRealSend(ctx: any): boolean {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return false
  if (!s.realSendEnabled) return false
  return s.connState === CarConnState.CONNECTED
}

function isMotionAction(a: Page1Action): boolean {
  return a === Page1Action.GO ||
    a === Page1Action.BACK ||
    a === Page1Action.LEFT ||
    a === Page1Action.RIGHT ||
    a === Page1Action.LEFT_HALF ||
    a === Page1Action.RIGHT_HALF ||
    a === Page1Action.UTURN
}

function isStaleByEmergencySeq(ctx: any, seq: number): boolean {
  return (Number(ctx.emergencyCommandSeq) || 0) !== seq
}

async function triggerLightBaselineBeforeMotion(ctx: any, s: Page1UiStore): Promise<void> {
  if (!!ctx.lightMetricReady) return
  const nowMs: number = Date.now()
  const lastQueryAtMs: number = Number(ctx.lightMetricLastQueryAtMs) || 0
  const shouldQuery: boolean =
    !ctx.lightMetricQueryEnabled ||
    (nowMs - lastQueryAtMs >= P1C.LIGHT_QUERY_MIN_INTERVAL_MS)
  if (!shouldQuery) return

  if (typeof ctx.armLightMetricQuery === 'function') {
    ctx.armLightMetricQuery()
  }
  ctx.lightMetricLastQueryAtMs = nowMs
  s.bumpTx()
  void ctx.proto.light()
    .then((): void => {
      s.pushLog('LIGHT: 出发前自动查询光照基准(异步)')
    })
    .catch((): void => {
      s.pushLog('LIGHT: 出发前自动查询失败，继续发送运动指令')
    })
}

async function waitLightBaselineReadyForManualGo(ctx: any, s: Page1UiStore, timeoutMs: number): Promise<boolean> {
  const nowMs: number = Date.now()
  const lastQueryAtMs: number = Number(ctx.lightMetricLastQueryAtMs) || 0
  const shouldQueryNow: boolean =
    !ctx.lightMetricQueryEnabled ||
    (nowMs - lastQueryAtMs >= P1C.LIGHT_QUERY_MIN_INTERVAL_MS)
  let gateAtMs: number = lastQueryAtMs > 0 ? lastQueryAtMs : nowMs

  if (shouldQueryNow) {
    try {
      if (typeof ctx.armLightMetricQuery === 'function') {
        ctx.armLightMetricQuery()
      }
      gateAtMs = Date.now()
      ctx.lightMetricLastQueryAtMs = gateAtMs
      s.bumpTx()
      await ctx.proto.light()
      s.pushLog('LIGHT: 手动起步前已发送光照查询，等待BD=02后再发前进')
    } catch (_) {
      s.pushLog('LIGHT: 手动起步前光照查询发送失败，本轮前进取消')
      return false
    }
  } else {
    s.pushLog('LIGHT: 手动起步前等待最近一次光照查询的BD=02')
  }

  const waitMs: number = Math.max(300, timeoutMs)
  const deadlineMs: number = Date.now() + waitMs
  while (Date.now() <= deadlineMs) {
    const statusCode: number = Number(ctx.pathAckLastStatusCode) || 0
    const statusAtMs: number = Number(ctx.pathAckLastStatusAtMs) || 0
    if (statusCode === 0x02 && statusAtMs >= gateAtMs) return true
    await ctx.sleep(120)
  }

  s.pushLog(`LIGHT: 手动起步等待BD=02超时(${waitMs}ms)，本轮前进取消`)
  return false
}

export async function sendManualGoCommand(ctx: any, actionText: string, commandSeq: number): Promise<void> {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  if (isStaleByEmergencySeq(ctx, commandSeq)) return
  if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('GO', 'MANUAL_GO_SEND')) return
  s.setAction('前进')
  s.bumpTx()
  await ctx.proto.go()
  ctx.manualGoLastSentAtMs = Date.now()
  void actionText
}

export async function onAction(ctx: any, a: Page1Action): Promise<void> {
  const s: Page1UiStore | undefined = ctx.store
  if (!s) return
  const commandSeq: number = Number(ctx.emergencyCommandSeq) || 0

  // 急停优先级最高：立即中断自动运行并执行统一急停流程。
  if (a === Page1Action.SCRAM) {
    if (typeof ctx.emergencyStopAndHold === 'function') {
      await ctx.emergencyStopAndHold()
      return
    }
  }

  if (a !== Page1Action.GO) {
    ctx.manualGoGateToken += 1
    ctx.manualGoGateActive = false
  }

  if (isMotionAction(a)) {
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand(Page1Action[a], 'MANUAL')) {
      return
    }
  }

  ctx.proto.setMode(canRealSend(ctx) ? CarSendMode.REAL_SEND : CarSendMode.DRY_RUN)

  let actionText: string = ''
  if (a === Page1Action.GO) actionText = '前进'
  else if (a === Page1Action.BACK) actionText = '后退'
  else if (a === Page1Action.LEFT) actionText = '左转'
  else if (a === Page1Action.RIGHT) actionText = '右转'
  else if (a === Page1Action.LEFT_HALF) actionText = '左半转'
  else if (a === Page1Action.RIGHT_HALF) actionText = '右半转'
  else if (a === Page1Action.UTURN) actionText = '掉头'
  else if (a === Page1Action.ALARM) actionText = s.alarmEnabled ? '警报关闭' : '警报开启'
  else if (a === Page1Action.STOP) actionText = '停止'
  else if (a === Page1Action.LAMP) actionText = '路灯调节'
  else if (a === Page1Action.LANGUAGE) actionText = '站台播报'
  else if (a === Page1Action.SCRAM) actionText = '紧急停止'
  else if (a === Page1Action.TFTA) actionText = 'TFTA发送'
  else if (a === Page1Action.LIGHT) actionText = '光照查询'
  else if (a === Page1Action.TFTB) actionText = 'TFTB发送'
  else if (a === Page1Action.STROBE) actionText = '道闸发送'
  if (actionText.length > 0) {
    replayArchiveService.onAction(actionText, 'MANUAL')
  }

  if (!canRealSend(ctx)) {
    kickTcpConnectForRealSendIfNeeded(ctx, s)
    const mode: string = s.realSendEnabled ? 'REAL_SEND(未连接)' : 'DRY_RUN'
    s.bumpTx()
    if (a === Page1Action.ALARM) s.alarmEnabled = !s.alarmEnabled
    s.setAction(`动作=${actionText} | ${mode}`)
    ctx.previewManualActionOnMap(a)
    return
  }

  if (a === Page1Action.GO) {
    ctx.pathAckLastCommandText = actionText
    if (await ctx.maybeHandleGarageDepartBeforeDrive(Date.now())) {
      return
    }
    if (maybeBlockGoByTrafficGate(ctx, Date.now(), true)) {
      return
    }

    const nowGoMs: number = Date.now()
    if (nowGoMs - ctx.manualGoLastSentAtMs < P1C.MANUAL_GO_DEDUP_MS) {
      s.pushLog('MANUAL_GO_DEDUP: 连续前进已跳过')
      return
    }

    const lightReadyForGo: boolean = await waitLightBaselineReadyForManualGo(ctx, s, P1C.LIGHT_QUERY_WAIT_TIMEOUT_MS)
    if (!lightReadyForGo) return
    await sendManualGoCommand(ctx, actionText, commandSeq)
    ctx.previewManualActionOnMap(Page1Action.GO)
    return
  }

  if (a === Page1Action.BACK) {
    ctx.pathAckLastCommandText = actionText
    await triggerLightBaselineBeforeMotion(ctx, s)
    if (isStaleByEmergencySeq(ctx, commandSeq)) return
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('BACK', 'MANUAL_SEND')) return
    s.setAction('后退')
    s.bumpTx()
    await ctx.proto.back()
    ctx.previewManualActionOnMap(Page1Action.BACK)
    return
  }

  if (a === Page1Action.LEFT) {
    ctx.pathAckLastCommandText = actionText
    await triggerLightBaselineBeforeMotion(ctx, s)
    if (isStaleByEmergencySeq(ctx, commandSeq)) return
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('LEFT', 'MANUAL_SEND')) return
    s.setAction('左转')
    s.bumpTx()
    await ctx.proto.left()
    ctx.previewManualActionOnMap(Page1Action.LEFT)
    return
  }

  if (a === Page1Action.RIGHT) {
    ctx.pathAckLastCommandText = actionText
    await triggerLightBaselineBeforeMotion(ctx, s)
    if (isStaleByEmergencySeq(ctx, commandSeq)) return
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('RIGHT', 'MANUAL_SEND')) return
    s.setAction('右转')
    s.bumpTx()
    await ctx.proto.right()
    ctx.previewManualActionOnMap(Page1Action.RIGHT)
    return
  }

  if (a === Page1Action.LEFT_HALF) {
    ctx.pathAckLastCommandText = actionText
    await triggerLightBaselineBeforeMotion(ctx, s)
    if (isStaleByEmergencySeq(ctx, commandSeq)) return
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('LEFT_HALF', 'MANUAL_SEND')) return
    s.setAction('左半转')
    s.bumpTx()
    await ctx.proto.leftHalf()
    ctx.previewManualActionOnMap(Page1Action.LEFT_HALF)
    return
  }

  if (a === Page1Action.RIGHT_HALF) {
    ctx.pathAckLastCommandText = actionText
    await triggerLightBaselineBeforeMotion(ctx, s)
    if (isStaleByEmergencySeq(ctx, commandSeq)) return
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('RIGHT_HALF', 'MANUAL_SEND')) return
    s.setAction('右半转')
    s.bumpTx()
    await ctx.proto.rightHalf()
    ctx.previewManualActionOnMap(Page1Action.RIGHT_HALF)
    return
  }

  if (a === Page1Action.UTURN) {
    ctx.pathAckLastCommandText = actionText
    await triggerLightBaselineBeforeMotion(ctx, s)
    if (isStaleByEmergencySeq(ctx, commandSeq)) return
    if (typeof ctx.canSendMotionCommand === 'function' && !ctx.canSendMotionCommand('UTURN', 'MANUAL_SEND')) return
    s.setAction('掉头')
    s.bumpTx()
    await ctx.proto.uturn()
    ctx.previewManualActionOnMap(Page1Action.UTURN)
    return
  }

  if (a === Page1Action.ALARM) {
    const nextEnabled: boolean = !s.alarmEnabled
    const alarmText: string = nextEnabled ? '警报开启' : '警报关闭'
    s.alarmEnabled = nextEnabled
    s.setAction(alarmText)
    s.bumpTx()
    await ctx.proto.setAlarm(nextEnabled)
    return
  }

  if (a === Page1Action.STOP) {
    s.setAction('停止')
    s.pushLog('STOP: 已忽略 stopTask 下发（该指令无法停止行动任务）')
    return
  }

  if (a === Page1Action.LAMP) {
    s.setAction('路灯调节')
    s.bumpTx()
    s.pushLog('LIGHT: 路灯调节发送已关闭')
    return
  }

  if (a === Page1Action.LANGUAGE) {
    s.setAction('站台播报')
    s.bumpTx()
    s.pushLog('VOICE: 站台播报发送已关闭')
    return
  }

  if (a === Page1Action.SCRAM) {
    s.setAction('紧急停止')
    s.bumpTx()
    s.pushLog('VOICE: 紧急语音发送已关闭')
    return
  }

  if (a === Page1Action.TFTA) {
    s.setAction('TFTA发送')
    s.bumpTx()
    await ctx.proto.sendTFTA()
    return
  }

  if (a === Page1Action.LIGHT) {
    s.setAction('光照查询')
    s.bumpTx()
    if (typeof ctx.armLightMetricQuery === 'function') {
      ctx.armLightMetricQuery()
    }
    await ctx.proto.light()
    s.pushLog('LIGHT: 已发送光照查询，等待设备返回基准值')
    return
  }

  if (a === Page1Action.STROBE) {
    s.setAction('道闸发送')
    s.bumpTx()
    await ctx.proto.strobe()
    return
  }

  if (a === Page1Action.TFTB) {
    s.setAction('TFTB发送')
    s.bumpTx()
    await ctx.proto.sendTFTB()
    return
  }
}
