
import { CarTcpService } from './CarTcpService'
import { commStore } from '../../state/CommStore'
import hilog from '@ohos.hilog'

const PROTOCOL_LOG_DOMAIN = 0xFF01
const PROTOCOL_LOG_TAG = 'CarProtocol'

export enum CarSendMode {
  DRY_RUN = 0,
  REAL_SEND = 1
}

export enum CarMsgType {
  CONTROL = 0xC1,
  STATUS = 0xBC,
  ACK = 0xA0
}

export enum CarFlags {
  NO_ACK_NO_STORE = 0x00,
  STORE_ONLY = 0x01,
  ACK_ONLY = 0x02,
  NEED_ACK_AND_STORE = 0x03,
  ACK_FRAME = 0x80
}

export class CarProtocolService {
  private interfacePending?: never
  private tcp?: CarTcpService
  private mode: CarSendMode = CarSendMode.DRY_RUN
  private seq: number = 0
  private readonly ackTimeoutMs: number = 1000
  private readonly ackMaxRetries: number = 3
  private readonly pending: Map<number, {
    seq: number
    frame: Uint8Array
    retries: number
    timeoutId: number
    tag: string
  }> = new Map()
  private readonly ackMeaningBySeq: Map<number, string> = new Map()

  bindTcp(tcp: CarTcpService): void {
    this.tcp = tcp
  }

  setMode(mode: CarSendMode): void {
    this.mode = mode
    if (mode !== CarSendMode.REAL_SEND) {
      this.clearAllPending()
    }
  }

  getMode(): CarSendMode {
    return this.mode
  }

  private nextSeq(): number {
    this.seq = (this.seq + 1) & 0xFFFF
    if (this.seq === 0) this.seq = 1
    return this.seq
  }

  private crc8(frameNoCrcTail: Uint8Array, start: number, endExclusive: number): number {
    let crc: number = 0x00
    for (let i: number = start; i < endExclusive; i++) {
      crc ^= (frameNoCrcTail[i] & 0xFF)
      for (let b: number = 0; b < 8; b++) {
        if ((crc & 0x80) !== 0) crc = ((crc << 1) ^ 0x07) & 0xFF
        else crc = (crc << 1) & 0xFF
      }
    }
    return crc & 0xFF
  }

  private buildFrame(type: number, flags: number, seq: number, data?: Uint8Array): Uint8Array {
    const payload: Uint8Array = data ? data : new Uint8Array(0)
    const len: number = 4 + payload.length
    const rawNoCrcTail: Uint8Array = new Uint8Array(2 + 1 + len)
    rawNoCrcTail[0] = 0xCC
    rawNoCrcTail[1] = 0xF5
    rawNoCrcTail[2] = len & 0xFF
    rawNoCrcTail[3] = type & 0xFF
    rawNoCrcTail[4] = flags & 0xFF
    rawNoCrcTail[5] = (seq >> 8) & 0xFF
    rawNoCrcTail[6] = seq & 0xFF
    for (let i: number = 0; i < payload.length; i++) rawNoCrcTail[7 + i] = payload[i] & 0xFF

    const out: Uint8Array = new Uint8Array(rawNoCrcTail.length + 2)
    out.set(rawNoCrcTail, 0)
    // CRC range: from Byte1=0xF5 to payload end (exclude 0xCC, CRC, 0xBB).
    out[out.length - 2] = this.crc8(rawNoCrcTail, 1, rawNoCrcTail.length)
    out[out.length - 1] = 0xBB
    return out
  }

  private async writeFrame(frame: Uint8Array, tag: string): Promise<void> {
    if (this.mode !== CarSendMode.REAL_SEND) return
    if (!this.tcp) return
    await this.tcp.sendOrLog(frame, tag)
  }

  async sendRaw(frame: Uint8Array, tag: string): Promise<void> {
    await this.writeFrame(frame, tag)
  }

  async sendPacket(type: number, flags: number, data?: Uint8Array, fixedSeq?: number): Promise<number> {
    const seq: number = fixedSeq !== undefined ? (fixedSeq & 0xFFFF) : this.nextSeq()
    const frame: Uint8Array = this.buildFrame(type & 0xFF, flags & 0xFF, seq, data)
    const tag: string = `type=0x${(type & 0xFF).toString(16).toUpperCase()} seq=${seq}`
    this.appendDiagTxKeyFrame(type & 0xFF, flags & 0xFF, seq, data, frame)
    await this.writeFrame(frame, tag)
    if (this.mode === CarSendMode.REAL_SEND &&
      (flags === CarFlags.ACK_ONLY || flags === CarFlags.NEED_ACK_AND_STORE) &&
      type !== CarMsgType.ACK) {
      this.trackPending(seq, frame, tag)
    }
    return seq
  }

  async sendAck(seq: number): Promise<void> {
    await this.sendPacket(CarMsgType.ACK, CarFlags.ACK_FRAME, new Uint8Array(0), seq)
  }

  // 通用命令组发送：
  // Send0A: data = 0x0A <subCode> [ext...]
  // Send0B: data = 0x0B <subCode> [ext...]
  // Send0C: data = 0x0C <subCode> [ext...]
  async Send0A(subCode: number, ext?: Uint8Array, needStore: boolean = false, needAck: boolean = true): Promise<number> {
    return await this.sendCmdGroup(0x0A, subCode, ext, needStore, needAck)
  }

  async Send0B(subCode: number, ext?: Uint8Array, needStore: boolean = false, needAck: boolean = true): Promise<number> {
    return await this.sendCmdGroup(0x0B, subCode, ext, needStore, needAck)
  }

  async Send0C(subCode: number, ext?: Uint8Array, needStore: boolean = true, needAck: boolean = true): Promise<number> {
    return await this.sendCmdGroup(0x0C, subCode, ext, needStore, needAck)
  }

  // 运动基础命令（基于 0x0A 组）
  // 前进
  async Forward(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x01, undefined, needStore)
  }

  // 后退
  async Backward(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x02, undefined, needStore)
  }

  // 左转
  async TurnLeft(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x03, undefined, needStore)
  }

  // 右转
  async TurnRight(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x04, undefined, needStore)
  }

  // 左半转
  async TurnLeftHalf(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x05, undefined, needStore)
  }

  // 右半转
  async TurnRightHalf(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x06, undefined, needStore)
  }

  // 掉头
  async TurnRound(needStore: boolean = false): Promise<number> {
    return await this.Send0A(0x0E, undefined, needStore)
  }

  // 0x0C 全量语义命令补充
  // 设置小车目的地
  async sendGoalNode(nodeId: string, needStore: boolean = true): Promise<number> {
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return 0
    const ext: Uint8Array = new Uint8Array([
      id.charCodeAt(0) & 0xFF,
      id.charCodeAt(1) & 0xFF])
    return await this.Send0C(0x01, ext, needStore)
  }
  // 设置当前位置和方向
  async sendCurrentNode(nodeId: string, dir: string | number = 'N'): Promise<number> {
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return 0
    const dirAscii: number = this.toDirAscii(dir)
    const ext: Uint8Array = new Uint8Array([
      id.charCodeAt(0) & 0xFF,
      id.charCodeAt(1) & 0xFF,
      dirAscii & 0xFF])
    return await this.Send0C(0x02, ext, false)
  }
  //设置道闸位置
  async  setBarrierPosition(fromNodeId: string, toNodeId: string, needStore: boolean = true): Promise<number> {
    const a: string = (fromNodeId || '').trim().toUpperCase()
    const b: string = (toNodeId || '').trim().toUpperCase()
    if (a.length !== 2 || b.length !== 2) return 0
    return await this.Send0C(
      0x03,
      new Uint8Array([
        a.charCodeAt(0) & 0xFF, a.charCodeAt(1) & 0xFF,
        b.charCodeAt(0) & 0xFF, b.charCodeAt(1) & 0xFF
      ]),
      needStore
    )
  }
  //清除道闸
  async clearBarrier(): Promise<number> {
    return await this.Send0C(0x04, undefined, false)
  }
  // 设置障碍路段：主指令0x05，4字节数据=两端点位（各2字节ASCII）
  async setObstacleEdge(fromNodeId: string, toNodeId: string, needStore: boolean = true): Promise<number> {
    const a: string = (fromNodeId || '').trim().toUpperCase()
    const b: string = (toNodeId || '').trim().toUpperCase()
    if (a.length !== 2 || b.length !== 2) return 0
    return await this.Send0C(
      0x05,
      new Uint8Array([
        a.charCodeAt(0) & 0xFF, a.charCodeAt(1) & 0xFF,
        b.charCodeAt(0) & 0xFF, b.charCodeAt(1) & 0xFF
      ]),
      needStore
    )
  }

  // 设置障碍点位
  async sendObstaclePoint(nodeId: string): Promise<number> {
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return 0
    const ext: Uint8Array = new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF])
    return await this.Send0C(0x06, ext, true)
  }

  // 清除所有清除阻塞点位
  async clearAllObstacles(): Promise<number> {
    return await this.Send0C(0x07, undefined, false)
  }
  //设置车库点位
  async setGaragePosition(nodeId: string): Promise<number> {
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return 0
    const ext: Uint8Array = new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF])
    return await this.Send0C(0x08, ext, true)
  }
  //清除车库点位
  async clearGarageNode(): Promise<number> {
    return await this.Send0C(0x09, undefined, false)
  }
  //停止任务
  async stopTask(): Promise<number> {
    return await this.Send0C(0x0A, undefined, false)
  }
  //继续任务
  async resumeTask(): Promise<number> {
    return await this.Send0C(0x0B, undefined, false)
  }

  //设置特殊路段
  async setSpecialSegment(fromNodeId: string, toNodeId: string, needStore: boolean = true): Promise<number> {
    const a: string = (fromNodeId || '').trim().toUpperCase()
    const b: string = (toNodeId || '').trim().toUpperCase()
    if (a.length !== 2 || b.length !== 2) return 0
    return await this.Send0C(
      0x0C,
      new Uint8Array([
        a.charCodeAt(0) & 0xFF, a.charCodeAt(1) & 0xFF,
        b.charCodeAt(0) & 0xFF, b.charCodeAt(1) & 0xFF
      ]),
      needStore
    )
  }
  //清除特殊路段
  async clearSpecialSegment(): Promise<number> {
    return await this.Send0C(0x0D, undefined, false)
  }

  // 设置红绿灯位置（路段两端点位 + 方向）
  async setTrafficLightNode(
    fromNodeId: string,
    toNodeId: string,
    dir: string | number = 'N',
    needStore: boolean = true
  ): Promise<number> {
    const a: string = (fromNodeId || '').trim().toUpperCase()
    const b: string = (toNodeId || '').trim().toUpperCase()
    if (a.length !== 2 || b.length !== 2) return 0
    const dirAscii: number = this.toDirAscii(dir)
    return await this.Send0C(
      0x0E,
      new Uint8Array([
        a.charCodeAt(0) & 0xFF, a.charCodeAt(1) & 0xFF,
        b.charCodeAt(0) & 0xFF, b.charCodeAt(1) & 0xFF,
        dirAscii & 0xFF
      ]),
      needStore
    )
  }
  // 红/黄： 0x0E 0x01
  // 绿：   0x0E 0x02
  //红灯
  async SendTrafficRedOrYellow(needStore: boolean = false): Promise<number> {
    return await this.Send0C(0x0E, new Uint8Array([0x01]), needStore)
  }
  //绿灯
  async SendTrafficGreen(needStore: boolean = false): Promise<number> {
    return await this.Send0C(0x0E, new Uint8Array([0x02]), needStore)
  }
  //清除交通灯
  async clearTrafficLightNode(): Promise<number> {
    return await this.Send0C(0x0F, undefined, false)
  }
  //设置仓库点位
  async setWarehouseNode(nodeId: string): Promise<number> {
    const id: string = (nodeId || '').trim().toUpperCase()
    if (id.length !== 2) return 0
    const ext: Uint8Array = new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF])
    return await this.Send0C(0x10, ext, true)
  }
  //清除仓库点位
  async clearWarehouseNode(): Promise<number> {
    return await this.Send0C(0x11, undefined, false)
  }
  //地图预设1
  async PresetOne(): Promise<number> {
    return await this.Send0C(0x12, undefined, false)
  }
  //地图预设2
  async PresetTow(): Promise<number> {
    return await this.Send0C(0x13, undefined, false)
  }

  //地图预设3
  async PresetThree(): Promise<number> {
    return await this.Send0C(0x14, undefined, false)
  }
  //地图预设4
  async PresetFour(): Promise<number> {
    return await this.Send0C(0x15, undefined, false)
  }

  // 一键清图
  async  resetNetworkMap(): Promise<number> {
    return await this.Send0C(0xF0, undefined, false)
  }



  // // 设置 TFTA 位置
  // async setTftaNode(nodeId: string, needStore: boolean = true): Promise<number> {
  //   const id: string = (nodeId || '').trim().toUpperCase()
  //   if (id.length !== 2) return 0
  //   return await this.Send0C(0x07, new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF]), needStore)
  // }

  // // 设置 TFTB 位置
  // async setTftbNode(nodeId: string, needStore: boolean = true): Promise<number> {
  //   const id: string = (nodeId || '').trim().toUpperCase()
  //   if (id.length !== 2) return 0
  //   return await this.Send0C(0x08, new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF]), needStore)
  // }

  // // 设置车库位置
  // async setGarageNode(nodeId: string, needStore: boolean = true): Promise<number> {
  //   const id: string = (nodeId || '').trim().toUpperCase()
  //   if (id.length !== 2) return 0
  //   return await this.Send0C(0x09, new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF]), needStore)
  // }

  // // 清除红绿灯
  // async clearTrafficLightNode(nodeId: string, needStore: boolean = false): Promise<number> {
  //   const id: string = (nodeId || '').trim().toUpperCase()
  //   if (id.length !== 2) return 0
  //   return await this.Send0C(0x0A, new Uint8Array([id.charCodeAt(0) & 0xFF, id.charCodeAt(1) & 0xFF]), needStore)
  // }


  onAckReceived(seq: number): boolean {
    const key: number = seq & 0xFFFF
    return this.clearPendingBySeq(key)
  }

  consumeAckMatchedMeaning(seq: number): string {
    const key: number = seq & 0xFFFF
    const text: string | undefined = this.ackMeaningBySeq.get(key)
    if (text !== undefined) {
      this.ackMeaningBySeq.delete(key)
      return text
    }
    return ''
  }

  private async sendCmdGroup(
    groupCode: number,
    subCode: number,
    ext?: Uint8Array,
    needStore: boolean = false,
    needAck: boolean = true
  ): Promise<number> {
    const tail: Uint8Array = ext ? ext : new Uint8Array(0)
    const data: Uint8Array = new Uint8Array(2 + tail.length)
    data[0] = groupCode & 0xFF
    data[1] = subCode & 0xFF
    for (let i: number = 0; i < tail.length; i++) data[2 + i] = tail[i] & 0xFF
    const flags: number = needAck
      ? (needStore ? CarFlags.NEED_ACK_AND_STORE : CarFlags.ACK_ONLY)
      : (needStore ? CarFlags.STORE_ONLY : CarFlags.NO_ACK_NO_STORE)
    return await this.sendPacket(
      CarMsgType.CONTROL,
      flags,
      data
    )
  }

  private trackPending(seq: number, frame: Uint8Array, tag: string): void {
    const key: number = seq & 0xFFFF
    this.clearPendingBySeq(key)
    const timeoutId: number = setTimeout((): void => {
      void this.retryPending(key)
    }, this.ackTimeoutMs) as number
    this.pending.set(key, {
      seq: key,
      frame: frame,
      retries: 0,
      timeoutId: timeoutId,
      tag: tag
    })
  }

  private async retryPending(seq: number): Promise<void> {
    const p = this.pending.get(seq)
    if (!p) return
    if (p.retries >= this.ackMaxRetries) {
      const warnText: string = `[WARN][CarProtocol] ACK超时丢帧 seq=${seq} tag=${p.tag} retries=${p.retries} reason=达到最大重试次数(${this.ackMaxRetries})`
      hilog.warn(PROTOCOL_LOG_DOMAIN, PROTOCOL_LOG_TAG, '%{public}s', warnText)
      commStore.bumpAckDrop()
      this.clearPendingBySeq(seq)
      return
    }
    p.retries += 1
    await this.writeFrame(p.frame, `${p.tag} retry=${p.retries}`)
    p.timeoutId = setTimeout((): void => {
      void this.retryPending(seq)
    }, this.ackTimeoutMs) as number
    this.pending.set(seq, p)
  }

  private clearPendingBySeq(seq: number): boolean {
    const p = this.pending.get(seq)
    if (!p) return false
    clearTimeout(p.timeoutId)
    this.pending.delete(seq)
    return true
  }

  private clearAllPending(): void {
    const keys: Array<number> = Array.from(this.pending.keys())
    for (let i: number = 0; i < keys.length; i++) {
      this.clearPendingBySeq(keys[i])
    }
  }

  private toDirAscii(dir: string | number): number {
    if (typeof dir === 'number') {
      const v: number = dir & 0xFF
      if (v === 0x4E || v === 0x45 || v === 0x53 || v === 0x57) return v // N/E/S/W
      if (v === 0x01) return 0x4E
      if (v === 0x02) return 0x45
      if (v === 0x03) return 0x53
      if (v === 0x04) return 0x57
      return 0x4E
    }
    const x: string = (dir || '').trim().toUpperCase()
    if (x === 'N') return 0x4E
    if (x === 'E') return 0x45
    if (x === 'S') return 0x53
    if (x === 'W') return 0x57
    return 0x4E
  }

  private appendDiagTxKeyFrame(type: number, flags: number, seq: number, data: Uint8Array | undefined, frame: Uint8Array): void {
    try {
      let cmdHex: string = `0x${(type & 0xFF).toString(16).toUpperCase().padStart(2, '0')}`
      let actionText: string = '发送数据'
      if (type === CarMsgType.CONTROL && data && data.length >= 2) {
        const group: number = data[0] & 0xFF
        const sub: number = data[1] & 0xFF
        cmdHex = `0x${sub.toString(16).toUpperCase().padStart(2, '0')}`
        actionText = this.txMeaning(group, sub, data)
      } else if (type === CarMsgType.ACK) {
        cmdHex = 'ACK'
        actionText = '确认应答'
      }
      this.ackMeaningBySeq.set(seq & 0xFFFF, actionText)
      if (this.ackMeaningBySeq.size > 200) {
        const keys: Array<number> = Array.from(this.ackMeaningBySeq.keys())
        for (let i: number = 0; i < keys.length - 150; i++) this.ackMeaningBySeq.delete(keys[i])
      }
      commStore.appendDiagKeyTxFrame({
        tsMs: Date.now(),
        cmdHex: cmdHex,
        actionText: actionText,
        modeText: this.mode === CarSendMode.REAL_SEND ? 'REAL_SEND' : 'DRY_RUN',
        hex: this.bytesToHex(frame)
      })
    } catch (_) {}
  }

  private txMeaning(group: number, sub: number, data: Uint8Array): string {
    const g: number = group & 0xFF
    const s: number = sub & 0xFF
    const asciiPair = (offset: number): string => {
      if (data.length < offset + 2) return '??'
      return `${String.fromCharCode(data[offset] & 0xFF)}${String.fromCharCode(data[offset + 1] & 0xFF)}`.toUpperCase()
    }
    const asciiDir = (offset: number): string => {
      if (data.length < offset + 1) return 'N'
      const c: string = String.fromCharCode(data[offset] & 0xFF).toUpperCase()
      return (c === 'N' || c === 'E' || c === 'S' || c === 'W') ? c : 'N'
    }
    if (g === 0x0A) {
      if (s === 0x01) return '前进'
      if (s === 0x02) return '后退'
      if (s === 0x03) return '左转'
      if (s === 0x04) return '右转'
      if (s === 0x05) return '左半转'
      if (s === 0x06) return '右半转'
      if (s === 0x0E) return '掉头'
      if (s === 0x00) return '停止'
    }
    if (g === 0x0B) {
      if (s === 0x01) return '识别红黄灯'
      if (s === 0x02) return '识别绿灯'
    }
    if (g === 0x0C) {
      if (s === 0x01) return `设置目的地 ${asciiPair(2)}`
      if (s === 0x02) return `设置当前位置 ${asciiPair(2)} dir=${asciiDir(4)}`
      if (s === 0x03) return `设置道闸 ${asciiPair(2)}|${asciiPair(4)}`
      if (s === 0x04) return '清除道闸'
      if (s === 0x05) return `设置障碍路段 ${asciiPair(2)}|${asciiPair(4)}`
      if (s === 0x06) return `设置障碍点位 ${asciiPair(2)}`
      if (s === 0x07) return '清除障碍'
      if (s === 0x08) return `设置车库 ${asciiPair(2)}`
      if (s === 0x09) return '清除车库'
      if (s === 0x0A) return '停止任务'
      if (s === 0x0B) return '继续任务'
      if (s === 0x0C) return `设置特殊路段 ${asciiPair(2)}|${asciiPair(4)}`
      if (s === 0x0D) return '清除特殊路段'
      if (s === 0x0E) {
        if (data.length >= 3 && (data[2] & 0xFF) === 0x01) return '交通灯控制 红/黄'
        if (data.length >= 3 && (data[2] & 0xFF) === 0x02) return '交通灯控制 绿灯'
        if (data.length >= 7) return `设置交通灯 ${asciiPair(2)}|${asciiPair(4)} dir=${asciiDir(6)}`
        return '交通灯控制/设置'
      }
      if (s === 0x0F) return '清除交通灯'
      if (s === 0xF0) return '清图'
    }
    return '控制指令'
  }

  private bytesToHex(data: Uint8Array): string {
    let s: string = ''
    for (let i: number = 0; i < data.length; i++) {
      const part: string = (data[i] & 0xFF).toString(16).toUpperCase().padStart(2, '0')
      s = s.length === 0 ? part : `${s} ${part}`
    }
    return s
  }
}
