// @ts-nocheck
/**
 * 代码指南：
 * 文件：services/control/CarTcpService.ets
 * 用途：TCP 连接/重连/读写服务和回调。
 * 何时修改：调整 socket 生命周期、重试策略或接收缓冲行为时。
 * 相关文件：app/Page1Coordinator.ets 和 CarProtocolService.ets。
 */
import socket from '@ohos.net.socket'

import { CarConnectionState } from './CarConnectionState'
import { CAR_TCP_PORT } from '../../config/DeviceNetworkConfig'
import hilog from '@ohos.hilog'

const DOMAIN = 0xFF01

const TAG_CONNECTSS = 'sendconnect'
const TAG_SENDAMSTER = 'sendmaster'


export interface CarTcpCallbacks {
  onStateChange: (state: CarConnectionState, text: string) => void
  onData: (data: Uint8Array) => void
}

interface SocketErrorLike {
  code?: number | string
  message?: string
}

interface TcpMessageLike {
  message?: ArrayBuffer | Uint8Array | Array<number>
  data?: ArrayBuffer | Uint8Array | Array<number>
  payload?: ArrayBuffer | Uint8Array | Array<number>
  buffer?: ArrayBuffer | Uint8Array | Array<number>
  msg?: ArrayBuffer | Uint8Array | Array<number>
}

export class CarTcpService {
  private tcp?: socket.TCPSocket
  private state: CarConnectionState = CarConnectionState.IDLE

  // 自动重连策略：最多重试 maxReconnect 次
  // - 调大：弱网下更容易自恢复，但等待时间更长、日志更多
  // - 调小：失败更快暴露给上层，但容错变差
  private readonly maxReconnect: number = 3
  private readonly reconnectBaseDelayMs: number = 700
  private readonly reconnectMaxDelayMs: number = 5000
  private readonly reconnectJitterMs: number = 250
  private reconnectCount: number = 0

  // 心跳用于维持链路活性，避免长时间静默后连接被动断开
  // - 调大：心跳包更少、开销更低，但断链发现更慢
  // - 调小：断链发现更快，但额外流量和日志更高
  private readonly heartbeatIntervalMs: number = 5000
  private heartbeatTimerId: number = -1
  private reconnectTimerId: number = -1
  // connectSeq 用于连接代次隔离：
  // 每新建一次 socket 就 +1，旧 socket 的迟到事件会被丢弃。
  private connectSeq: number = 0

  // 心跳内容，当前协议用单字节 0x00
  private readonly heartbeatData: Uint8Array = new Uint8Array([0x00])

  private currentIp: string = ''
  private currentPort: number = CAR_TCP_PORT

  private callbacks?: CarTcpCallbacks
  private lastErrorText: string = ''
  // true 表示“用户主动断开”，此时 close/error 事件不应触发重连
  private manualDisconnect: boolean = false

  private logInfo(tag: string, text: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', text)
  }

  private logWarn(tag: string, text: string): void {
    hilog.warn(DOMAIN, tag, '%{public}s', text)
  }

  private logError(tag: string, text: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', text)
  }

  private toDecimal(data: Uint8Array): string {
    let s: string = ''
    let i: number = 0
    while (i < data.length) {
      const v: number = data[i] & 0xff
      const part: string = `${v}`
      s = s.length === 0 ? part : (s + ',' + part)
      i += 1
    }
    return s
  }

  private toHexPrefixed(data: Uint8Array): string {
    let s: string = ''
    let i: number = 0
    while (i < data.length) {
      const v: number = data[i] & 0xff
      const part: string = `0x${v.toString(16).toUpperCase().padStart(2, '0')}`
      s = s.length === 0 ? part : (s + ' ' + part)
      i += 1
    }
    return s
  }

  private toHex(data: Uint8Array): string {
    let s: string = ''
    let i: number = 0
    while (i < data.length) {
      const v: number = data[i] & 0xff
      const part: string = v.toString(16).toUpperCase().padStart(2, '0')
      s = s.length === 0 ? part : (s + ' ' + part)
      i += 1
    }
    return s
  }

  // 接收帧日志（HEX）用于定位协议层解析问题
  private logRxFrame(data: Uint8Array): void {
    const hex: string = this.toHex(data)
    this.logInfo(TAG_SENDAMSTER, `收到数据帧 HEX: ${hex}`)
    this.logInfo(TAG_SENDAMSTER, `读取到数据，长度：${data.length}字节`)
  }

  private extractRxBytes(msg: TcpMessageLike | ArrayBuffer | Uint8Array): Uint8Array {
    if (typeof (msg as Object) === 'string') {
      const fromText: Uint8Array = this.parseBytesFromText(msg as string)
      if (fromText.length > 0) return fromText
      return new Uint8Array(0)
    }

    const anyMsg = msg as Object
    if (msg instanceof Uint8Array) return msg
    if (msg instanceof ArrayBuffer) return new Uint8Array(msg)
    if (typeof anyMsg !== 'object' || anyMsg === null) return new Uint8Array(0)

    const typed: TcpMessageLike = msg as TcpMessageLike
    const raw: ArrayBuffer | Uint8Array | Array<number> | undefined =
      typed.message ?? typed.data ?? typed.payload ?? typed.buffer ?? typed.msg
    const direct: Uint8Array | undefined = this.toUint8(raw)
    if (direct) return direct

    const deep: Uint8Array | undefined = this.extractBytesDeep(msg as Object)
    if (deep) return deep

    return new Uint8Array(0)
  }

  private toUint8(raw: ArrayBuffer | Uint8Array | Array<number> | undefined): Uint8Array | undefined {
    if (!raw) return undefined
    if (raw instanceof Uint8Array) return raw
    if (raw instanceof ArrayBuffer) return new Uint8Array(raw)
    if (Array.isArray(raw)) return new Uint8Array(raw)
    return undefined
  }

  private extractBytesDeep(msg: Object): Uint8Array | undefined {
    const anyMsg: Record<string, Object> = msg as Record<string, Object>
    const keys: Array<string> = Object.keys(anyMsg)
    const probeKeys: Array<string> = ['message', 'data', 'payload', 'buffer', 'msg', 'raw', 'body', 'value']
    for (let i: number = 0; i < probeKeys.length; i++) {
      const key: string = probeKeys[i]
      if (keys.indexOf(key) < 0) continue
      const v: Object = anyMsg[key]
      const b: Uint8Array | undefined = this.toUint8(v as ArrayBuffer | Uint8Array | Array<number> | undefined)
      if (b && b.length > 0) return b
      if (typeof v === 'string') {
        const fromText: Uint8Array = this.parseBytesFromText(v)
        if (fromText.length > 0) return fromText
      }
    }
    return undefined
  }

  private parseBytesFromText(text: string): Uint8Array {
    const src: string = text.trim()
    if (src.length <= 0) return new Uint8Array(0)

    const chunks: Array<string> = src.split(/[\s,]+/)
    const out: Array<number> = []
    for (let i: number = 0; i < chunks.length; i++) {
      const token: string = chunks[i]
      if (token.length <= 0) continue
      let n: number = -1
      if (token.startsWith('0x') || token.startsWith('0X')) {
        n = Number.parseInt(token.substring(2), 16)
      } else if (/^[0-9A-Fa-f]{2}$/.test(token)) {
        n = Number.parseInt(token, 16)
      } else if (/^\d{1,3}$/.test(token)) {
        n = Number.parseInt(token, 10)
      } else {
        return new Uint8Array(0)
      }
      if (!Number.isFinite(n) || n < 0 || n > 255) return new Uint8Array(0)
      out.push(n & 0xff)
    }
    return new Uint8Array(out)
  }

  private describeMessageShape(msg: TcpMessageLike | ArrayBuffer | Uint8Array): string {
    if (msg instanceof Uint8Array) return `Uint8Array(len=${msg.length})`
    if (msg instanceof ArrayBuffer) return `ArrayBuffer(byteLength=${msg.byteLength})`
    if (typeof (msg as Object) === 'string') {
      const s: string = msg as string
      return `string(len=${s.length})`
    }
    if (typeof (msg as Object) !== 'object' || (msg as Object) === null) {
      return `${typeof (msg as Object)}`
    }
    const obj: Record<string, Object> = msg as Record<string, Object>
    const keys: Array<string> = Object.keys(obj)
    const keyText: string = keys.join(',')
    return `object(keys=${keyText})`
  }

  setCallbacks(cb: CarTcpCallbacks): void {
    this.callbacks = cb
    this.logInfo(TAG_CONNECTSS, 'setCallbacks 已绑定')
  }

  /**
   * 对外连接入口：
   * - 只接收“空闲态”发起连接；
   * - 重置重连计数；
   * - 进入 connectInternal 真正建链。
   */
  async connect(ip: string, port: number): Promise<void> {
    this.manualDisconnect = false

    if (this.state === CarConnectionState.CONNECTED ||
      this.state === CarConnectionState.CONNECTING ||
      this.state === CarConnectionState.RECONNECTING) {
      this.logError(TAG_CONNECTSS, '已连接或连接中，无需重复调用')
      return
    }

    this.currentIp = ip
    this.currentPort = port
    this.reconnectCount = 0
    this.lastErrorText = ''

    this.logError(TAG_CONNECTSS, `连接`)
    await this.connectInternal()
  }

  /**
   * 建链核心流程：
   * 1) 清理旧 socket；
   * 2) 创建新 socket 并绑定事件；
   * 3) 预设置网络参数；
   * 4) 发起 connect。
   */
  private async connectInternal(): Promise<void> {
    this.manualDisconnect = false
    this.stopHeartbeat()
    this.updateState(CarConnectionState.CONNECTING, `连接中... ${this.currentIp}:${this.currentPort}`)
    this.logError(TAG_CONNECTSS, `开始连接，目标IP：${this.currentIp}:${this.currentPort}`)

    await this.disposeSocket()

    const seq: number = ++this.connectSeq
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance()
    this.tcp = tcp

    // 每次连接尝试都有自己的 seq，事件回调里必须校验 seq，
    // 否则旧 socket 的迟到事件会污染当前连接状态。
    tcp.on('connect', () => {
      if (!this.isCurrentSocket(seq, tcp)) {
        this.logWarn(TAG_CONNECTSS, '收到 connect 事件，但不是当前 socket，忽略')
        return
      }

      // 连接成功后立即启动心跳与可选参数应用
      this.reconnectCount = 0
      this.updateState(CarConnectionState.CONNECTED, `连接成功 ${this.currentIp}:${this.currentPort}`)
      this.logError(TAG_CONNECTSS, '连接成功')
      void this.applyExtraOptions(tcp)
      this.startHeartbeat()
    })

    tcp.on('close', () => {
      if (!this.isCurrentSocket(seq, tcp)) {
        this.logWarn(TAG_CONNECTSS, '收到 close 事件，但不是当前 socket，忽略')
        return
      }

      this.logError(TAG_CONNECTSS, '连接关闭事件触发')
      this.stopHeartbeat()
      void this.disposeSocket(tcp)

      // 被动断开：触发重连；主动断开：只回到 IDLE
      if (this.manualDisconnect) {
        this.updateState(CarConnectionState.IDLE, '已断开')
        this.logError(TAG_CONNECTSS, '主动断开连接')
        return
      }

      this.updateState(CarConnectionState.IDLE, '连接关闭')
      this.logError(TAG_CONNECTSS, '服务器关闭连接或连接已断开，准备重连')
      this.tryReconnect()
    })

    tcp.on('error', (err: SocketErrorLike) => {
      if (!this.isCurrentSocket(seq, tcp)) {
        this.logWarn(TAG_CONNECTSS, '收到 error 事件，但不是当前 socket，忽略')
        return
      }

      this.stopHeartbeat()

      if (this.manualDisconnect) {
        this.updateState(CarConnectionState.IDLE, '已断开')
        this.logError(TAG_CONNECTSS, '主动断开后的 error 事件，忽略重连')
        return
      }

      // 连接异常统一走 FAILED -> dispose -> tryReconnect
      this.lastErrorText = this.formatSocketError(err, '连接异常')
      this.updateState(CarConnectionState.FAILED, this.lastErrorText)
      this.logError(TAG_CONNECTSS, this.lastErrorText)
      void this.disposeSocket(tcp)
      this.tryReconnect()
    })

    tcp.on('message', (msg: TcpMessageLike | ArrayBuffer | Uint8Array) => {
      if (!this.isCurrentSocket(seq, tcp)) {
        this.logWarn(TAG_CONNECTSS, '收到 message 事件，但不是当前 socket，忽略')
        return
      }

      const data: Uint8Array = this.extractRxBytes(msg)
      if (data.length <= 0) {
        const shape: string = this.describeMessageShape(msg)
        this.logWarn(TAG_SENDAMSTER, `message 事件收到空数据或未知字段 | shape=${shape}`)
        return
      }

      this.logError(TAG_CONNECTSS, '进入 message 回调，开始持续读取数据')
      this.logRxFrame(data)

      // 仅负责把原始字节上抛，不在 TCP 层做协议解析
      const cb: CarTcpCallbacks | undefined = this.callbacks
      if (cb) {
        cb.onData(data)
      } else {
        this.logWarn(TAG_CONNECTSS, 'callbacks 未绑定，数据未上抛')
      }
    })

    try {
      await this.prepareSocketForConnect(tcp)
      this.logInfo(TAG_CONNECTSS, 'Socket bind/defaultNet/bindSocket 完成')
    } catch (e) {
      if (!this.isCurrentSocket(seq, tcp)) return

      this.lastErrorText = this.formatSocketError(e, `连接准备失败 ${this.currentIp}:${this.currentPort}`)
      this.updateState(CarConnectionState.FAILED, this.lastErrorText)
      this.logError(TAG_CONNECTSS, this.lastErrorText)
      await this.disposeSocket(tcp)
      this.tryReconnect()
      return
    }

    const options: socket.TCPConnectOptions = {
      address: { address: this.currentIp, port: this.currentPort, family: 1 },
      timeout: 6000
    }

    tcp.connect(options, (err?: SocketErrorLike) => {
      if (!this.isCurrentSocket(seq, tcp)) return

      if (!err) {
        this.logInfo(TAG_CONNECTSS, `connect 回调返回成功 ${this.currentIp}:${this.currentPort}`)
        return
      }

      const codeText: string = typeof err.code === 'undefined' ? '' : `${err.code}`
      if (codeText === '2301114' || codeText === '2301115') {
        // 2301114/2301115: 平台返回的 pending 状态，不视为失败
        this.logInfo(TAG_CONNECTSS, `connect pending ${this.currentIp}:${this.currentPort} code=${codeText}`)
        return
      }

      this.lastErrorText = this.formatSocketError(err, `连接失败 ${this.currentIp}:${this.currentPort}`)
      this.updateState(CarConnectionState.FAILED, this.lastErrorText)
      this.logError(TAG_CONNECTSS, this.lastErrorText)
      void this.disposeSocket(tcp)
      this.tryReconnect()
    })
  }

  async disconnect(): Promise<void> {
    // 标记为主动断连，防止 close/error 触发自动重连
    this.manualDisconnect = true
    this.logError(TAG_CONNECTSS, 'disconnect 主动断开开始')
    this.stopHeartbeat()
    this.cancelReconnect()
    await this.disposeSocket()
    this.updateState(CarConnectionState.IDLE, '已断开')
    this.logError(TAG_CONNECTSS, 'disconnect 主动断开完成')
  }

  /**
   * 真实发送入口：
   * - 仅在 CONNECTED 且 socket 存在时允许发送；
   * - 任何发送失败都转为 FAILED，并触发重连流程。
   */
  async send(data: Uint8Array): Promise<void> {
    if (!this.tcp || this.state !== CarConnectionState.CONNECTED) {
      this.logError(TAG_CONNECTSS, '发送失败：未连接或 socket 为空')
      return
    }

    const opt: socket.TCPSendOptions = {
      data: this.toArrayBuffer(data)
    }

    try {
      this.logInfo(TAG_SENDAMSTER, `发送16进制：${this.toHex(data)}`)
      this.logInfo(TAG_SENDAMSTER, `发送数据长度：${data.length}字节`)
      await this.tcp.send(opt)
    } catch (e) {
      this.lastErrorText = this.formatSocketError(e, '发送失败')
      this.logError(TAG_CONNECTSS, this.lastErrorText)
      await this.disposeSocket()
      this.tryReconnect()
    }
  }

  // send 的容错包装：失败仅打日志，不把异常抛给上层流程
  async sendOrLog(data: Uint8Array, tag: string): Promise<void> {
    if (!this.tcp || this.state !== CarConnectionState.CONNECTED) {
      const hex: string = this.toHex(data)
      this.logInfo(TAG_SENDAMSTER, `[DRYRUN][${tag}] ${hex}`)
      return
    }
    await this.send(data)
  }

  // 心跳包定时发送 0x00，异常时触发 failed -> reconnect
  private startHeartbeat(): void {
    if (this.heartbeatTimerId !== -1) {
      this.logWarn(TAG_CONNECTSS, '心跳已启动，跳过重复启动')
      return
    }

    if (!this.tcp || this.state !== CarConnectionState.CONNECTED) {
      this.logWarn(TAG_CONNECTSS, '当前未连接，心跳未启动')
      return
    }

    this.logInfo(TAG_CONNECTSS, '启动心跳保活')

    this.heartbeatTimerId = setInterval(() => {
      if (!this.tcp || this.state !== CarConnectionState.CONNECTED) {
        this.logWarn(TAG_CONNECTSS, '心跳检测到未连接，跳过本次发送')
        return
      }

      this.logInfo(TAG_CONNECTSS, '发送心跳包')
      void this.send(this.heartbeatData)
    }, this.heartbeatIntervalMs) as number
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimerId !== -1) {
      clearInterval(this.heartbeatTimerId)
      this.heartbeatTimerId = -1
      this.logInfo(TAG_CONNECTSS, '心跳已停止')
    }
  }

  /**
   * 重连调度器：
   * - 达到上限后转 FAILED；
   * - 否则延时重连，避免瞬时抖动连续打满重试。
   */
  private tryReconnect(): void {
    if (this.manualDisconnect) {
      this.logWarn(TAG_CONNECTSS, '主动断开状态下不重连')
      return
    }

    if (this.reconnectTimerId !== -1) {
      this.logWarn(TAG_CONNECTSS, '已有重连任务，跳过重复创建')
      return
    }

    if (this.reconnectCount >= this.maxReconnect) {
      const reason: string = this.lastErrorText.length > 0 ? `连接超时，已达最大重连次数 | ${this.lastErrorText}` : '连接超时，已达最大重连次数'
      this.updateState(CarConnectionState.FAILED, reason)
      this.logError(TAG_CONNECTSS, `已达最大重连次数（${this.maxReconnect}次），停止重连`)
      return
    }

    this.reconnectCount += 1
    const delay: number = this.computeReconnectDelayMs(this.reconnectCount)

    this.updateState(CarConnectionState.RECONNECTING, `重连中(${this.reconnectCount})`)
    this.logError(TAG_CONNECTSS, `第${this.reconnectCount}次重连（指数退避，延迟${delay}ms），目标IP：${this.currentIp}`)

    this.reconnectTimerId = setTimeout(() => {
      this.reconnectTimerId = -1
      if (!this.manualDisconnect) {
        void this.connectInternal()
      }
    }, delay) as number
  }

  private computeReconnectDelayMs(attempt: number): number {
    const expLevel: number = Math.max(0, attempt - 1)
    const expDelay: number = this.reconnectBaseDelayMs * (2 ** expLevel)
    const bounded: number = Math.min(this.reconnectMaxDelayMs, expDelay)
    const jitter: number = Math.floor(Math.random() * this.reconnectJitterMs)
    return bounded + jitter
  }

  private cancelReconnect(): void {
    if (this.reconnectTimerId !== -1) {
      clearTimeout(this.reconnectTimerId)
      this.reconnectTimerId = -1
      this.logInfo(TAG_CONNECTSS, '已取消重连任务')
    }
  }

  // 对外统一派发状态变更（同时通知页面回调）
  private updateState(state: CarConnectionState, text: string): void {
    this.state = state
    this.logInfo(TAG_CONNECTSS, `状态变更：${text}`)
    const cb: CarTcpCallbacks | undefined = this.callbacks
    if (cb) {
      cb.onStateChange(state, text)
    }
  }

  getState(): CarConnectionState {
    return this.state
  }

  getReconnectCount(): number {
    return this.reconnectCount
  }

  getLastErrorText(): string {
    return this.lastErrorText
  }

  // 连接前准备：bind + defaultNet + bindSocket，降低系统路由不确定性
  private async prepareSocketForConnect(tcp: socket.TCPSocket): Promise<void> {
    await tcp.bind({ address: '0.0.0.0', port: 0, family: 1 })

  }

  // 额外 socket 参数（无损功能，失败不影响主流程）
  private async applyExtraOptions(tcp: socket.TCPSocket): Promise<void> {
    try {
      await tcp.setExtraOptions({
        keepAlive: true,
        OOBInline: true,
        TCPNoDelay: true,
        socketLinger: { on: true, linger: 10 },
        receiveBufferSize: 1000,
        sendBufferSize: 1000,
        reuseAddress: true,
        // socketTimeout:
        // - 调大：弱网容忍更强，但失败感知更慢
        // - 调小：失败暴露更快，但误判超时概率更高
        socketTimeout: 10000
      })
      this.logInfo(TAG_CONNECTSS, 'setExtraOptions 成功')
    } catch (e) {
      const warn: string = this.formatSocketError(e, 'setExtraOptions failed')
      this.logWarn(TAG_CONNECTSS, warn)
    }
  }

  // 安全释放 socket；带 specific 时只释放指定实例，避免误删新连接
  private async disposeSocket(specific?: socket.TCPSocket): Promise<void> {
    const target: socket.TCPSocket | undefined = specific ?? this.tcp
    if (!target) {
      this.logInfo(TAG_SENDAMSTER, '没有可释放的连接资源')
      return
    }

    if (this.tcp === target) {
      this.tcp = undefined
    }

    try {
      await target.close()
      this.logError(TAG_SENDAMSTER, '连接资源已彻底释放')
    } catch (e) {
      const errText: string = this.formatSocketError(e, '关闭资源失败')
      this.logError(TAG_SENDAMSTER, errText)
    }
  }

  private isCurrentSocket(seq: number, tcp: socket.TCPSocket): boolean {
    return this.connectSeq === seq && this.tcp === tcp
  }

  private formatSocketError(e: Object, fallback: string): string {
    if (e instanceof Error && e.message.length > 0) {
      return `${fallback} | ${this.classifySocketError(e.message, undefined)} | ${e.message}`
    }
    if (typeof e === 'object' && e !== null) {
      const err: SocketErrorLike = e as SocketErrorLike
      const parts: Array<string> = [fallback]
      const codeText: string | undefined = (typeof err.code === 'undefined') ? undefined : `${err.code}`
      const category: string = this.classifySocketError(err.message, codeText)
      parts.push(category)
      if (typeof err.code !== 'undefined') parts.push(`code=${err.code}`)
      if (typeof err.message === 'string' && err.message.length > 0) parts.push(err.message)
      return parts.join(' | ')
    }
    return fallback
  }

  private classifySocketError(message?: string, codeText?: string): string {
    const m: string = (typeof message === 'string') ? message.toLowerCase() : ''
    const c: string = (typeof codeText === 'string') ? codeText : ''
    if (m.indexOf('timeout') >= 0 || c === '2301021') return 'TIMEOUT'
    if (m.indexOf('refused') >= 0 || c === '111') return 'CONNECTION_REFUSED'
    if (m.indexOf('unreachable') >= 0 || m.indexOf('network') >= 0) return 'NETWORK_UNREACHABLE'
    if (m.indexOf('reset') >= 0 || m.indexOf('broken pipe') >= 0) return 'CONNECTION_RESET'
    return 'NETWORK_ERROR'
  }

  private toArrayBuffer(data: Uint8Array): ArrayBuffer {
    return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)
  }
}
