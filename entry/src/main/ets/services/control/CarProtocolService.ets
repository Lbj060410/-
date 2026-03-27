// @ts-nocheck
/**
 * 代码指南：
 * 文件： services/control/CarProtocolService.ets
 * 用途： 指令级协议发送器（编码并发送控制、语音、特殊指令）。
 * 何时修改： 新增车辆指令码或修改指令载荷格式时。
 * 相关文件： services/control/CarFrameCodec.ets & services/control/CarTcpService.ets & page1 协调器调用方。
 */
// entry/src/main/ets/services/control/CarProtocolService.ets

import { CarFrameCodec } from './CarFrameCodec'
import { CarTcpService } from './CarTcpService'
import { FrameLogService } from '../diagnostics/FrameLogService'
import { commStore } from '../../state/CommStore'
import hilog from '@ohos.hilog'
import * as libentry from 'libentry.so'

const TAGRUN = 'SendMasterRun';
const DOMAIN = 0xFF01   //小车运行日志
const TAGCONNECT="SendMaster"
const TAGTEXTONE1 = 'textone1'

export enum CarSendMode {
  DRY_RUN = 0,
  REAL_SEND = 1
}

/**
 * 小车协议发送服务（业务动作 -> 协议帧）。
 * 设计原则：
 * - 所有发送都收敛到 sendRaw，便于统一统计与日志；
 * - 通过 DRY_RUN/REAL_SEND 两种模式复用同一套上层逻辑。
 */
export class CarProtocolService {
  private tcp?: CarTcpService
  // mode 直接决定 sendRaw 是否真正发包：
  // - DRY_RUN: 只记日志，不触发真实车辆动作
  // - REAL_SEND: 真实写 socket
  private mode: CarSendMode = CarSendMode.REAL_SEND

  // 十进制字符串主要用于对照旧日志/教学日志
  private frameToDecimal(frame: Uint8Array): string {
    const parts: string[] = []
    for (let i: number = 0; i < frame.length; i++) {
      parts.push(`${frame[i] & 0xff}`)
    }
    return parts.join(',')
  }

  // 十六进制字符串用于协议排查，和抓包最接近
  private frameToHex(frame: Uint8Array): string {
    const parts: string[] = []
    for (let i: number = 0; i < frame.length; i++) {
      const hex: string = (frame[i] & 0xff).toString(16).toUpperCase().padStart(2, '0')
      parts.push(hex)
    }
    return parts.join(' ')
  }

  // 连接链路日志，方便定位“到底发了什么帧”
  private logConnectFrame(frame: Uint8Array): void {
    const msg: string = this.frameToHex(frame)
    hilog.info(DOMAIN, TAGCONNECT, '%{public}s', msg)
  }

  // 注入底层 TCP 发送器（由协调器在 bind 阶段调用）
  bindTcp(tcp: CarTcpService): void {
    this.tcp = tcp
  }

  // 运行时可切换：DRY_RUN 仅记日志不下发，REAL_SEND 才真正发包
  setMode(mode: CarSendMode): void {
    this.mode = mode
  }

  getMode(): CarSendMode {
    return this.mode
  }

  private getTcpOrLog(): CarTcpService | undefined {
    const t: CarTcpService | undefined = this.tcp
    if (!t) hilog.warn(DOMAIN, TAGCONNECT, '%{public}s', '[CAR][WARN] tcp not bound, drop send')
    return t
  }

  // ===== 唯一发送出口（支持 DRY/REAL）=====
  async sendRaw(frame: Uint8Array, tag: string): Promise<void> {
    const sendTimes: number = 2
    for (let i: number = 0; i < sendTimes; i++) {
      const sendTag: string = `${tag}#${i + 1}/${sendTimes}`
      // 统一在这里做 TX 统计 + 帧日志（即使 DRY_RUN 也记录“发送意图”）
      commStore.bumpTxPacket()
      FrameLogService.appendTx(frame, sendTag)
      this.logConnectFrame(frame)

      if (this.mode === CarSendMode.DRY_RUN) continue
      const t: CarTcpService | undefined = this.getTcpOrLog()
      if (!t) return
      await t.sendOrLog(frame, sendTag)
      if (i + 1 < sendTimes) {
        await this.sleepMs(10)
      }
    }
  }

  // ===== 8B =====
  // 8B 命令帧：用于紧凑型控制指令
  async sendCmd8WithType(type: number, major: number, p1: number, p2: number, p3: number): Promise<void> {
    const frame: Uint8Array = CarFrameCodec.build8(type, major, p1, p2, p3)
    await this.sendRaw(frame, `8B type=0x${type.toString(16)} major=0x${major.toString(16)}`)
  }

  async sendCmd8(major: number, p1: number, p2: number, p3: number): Promise<void> {
    await this.sendCmd8WithType(0xaa, major, p1, p2, p3)
  }

  // ===== 12B =====
  // 12B 数据帧：h 表示主命令，payload8 承载子命令/参数
  async sendData12(h: number, payload8: Uint8Array): Promise<void> {
    const frame: Uint8Array = CarFrameCodec.build12(h & 0xff, payload8)
    await this.sendRaw(frame, `12B h=0x${h.toString(16)}`)

  }

  // ===== 小车控制 0x0A =====
    // 0x0A: 车辆控制类命令（运动、灯光、超声波触发等）
  private async sendControl0A(code: number, text: string): Promise<void> {
    const payload8: Uint8Array = new Uint8Array(8)
    payload8[0] = code & 0xff
    const previewFrame: Uint8Array = CarFrameCodec.build12(0x0A, payload8)
    commStore.appendDiagKeyTxFrame({
      tsMs: Date.now(),
      cmdHex: `0x${(code & 0xff).toString(16).toUpperCase().padStart(2, '0')}`,
      actionText: text,
      modeText: this.mode === CarSendMode.REAL_SEND ? 'REAL_SEND' : 'DRY_RUN',
      hex: this.frameToHex(previewFrame)
    })
    await this.sendData12(0x0A, payload8)
    hilog.info(DOMAIN, TAGRUN, '%{public}s', text)
  }

  // 基础运动控制：前进/后退/转向/半转/掉头/停止
  async go(): Promise<void> {
    await this.sendControl0A(0x01, '前进')
  }

  async back(): Promise<void> {
    await this.sendControl0A(0x02, '后退')
  }

  async left(): Promise<void> {
    await this.sendControl0A(0x03, '左转')
  }

  async right(): Promise<void> {
    await this.sendControl0A(0x04, '右转')
  }

  async leftHalf(): Promise<void> {
    await this.sendControl0A(0x05, '左半转')
  }

  async rightHalf(): Promise<void> {
    await this.sendControl0A(0x06, '右半转')
  }

  async setAlarm(enabled: boolean): Promise<void> {
    await this.sendControl0A(enabled ? 0x07 : 0x08, enabled ? '警报开启' : '警报关闭')
  }

  async leftlight(): Promise<void> {
    await this.sendControl0A(0x09, '开启左灯')
  }

  async rightlight(): Promise<void> {
    await this.sendControl0A(0x0A, '开启右灯')
  }

  async offlight(): Promise<void> {
    await this.sendControl0A(0x0B, '关闭灯光')
  }

  async adjustLight(): Promise<void> {
    await this.sendControl0A(0x0C, '路灯调节')
  }

  async light(): Promise<void> {
    await this.sendControl0A(0x0D, '光照指发送')
  }

  async uturn(): Promise<void> {
    await this.sendControl0A(0x0E, '掉头')
  }

  async sendTFTA(): Promise<void> {
    await this.sendControl0A(0x0F, 'TFTA发送')
  }

  async sendTFTB(): Promise<void> {
    await this.sendControl0A(0x10, 'TFTB发送')
  }

  async strobe(): Promise<void> {
    await this.sendControl0A(0x11, '闸门发送')
  }

  async yesline(): Promise<void> {
    await this.sendControl0A(0x12, '上下倒车')
  }

  async noline(): Promise<void> {
    await this.sendControl0A(0x13, '左右倒车')
  }

  async ultrasonic(): Promise<void> {
    await this.sendControl0A(0x14, '超声波')
  }

  async depart(): Promise<void>{
    await this.sendControl0A(0x15,"出库和入库")
  }

  async carport(plie: number): Promise<void> {
    // 协议约定：车库命令使用 0x18，楼层参数紧跟其后（payload 第2位，index=1）。
    const level: number = Math.max(1, Math.min(4, Math.trunc(plie)))
    const payload8: Uint8Array = new Uint8Array(8)
    payload8[0] = 0x18
    payload8[1] = level & 0xff

    const previewFrame: Uint8Array = CarFrameCodec.build12(0x0A, payload8)
    commStore.appendDiagKeyTxFrame({
      tsMs: Date.now(),
      cmdHex: '0x18',
      actionText: `车库到${level}层`,
      modeText: this.mode === CarSendMode.REAL_SEND ? 'REAL_SEND' : 'DRY_RUN',
      hex: this.frameToHex(previewFrame)
    })

    await this.sendData12(0x0A, payload8)
    hilog.info(DOMAIN, TAGRUN, '%{public}s', `车库层发送 level=${level} payload[1]`)
  }

  async lowcarport(): Promise<void>{
    const payloadText: string = 'textone1 lowcarport() -> send 0x19'
    hilog.info(DOMAIN, TAGTEXTONE1, 'send payload: %{public}s', payloadText)
    await this.sendControl0A(0x19,"车库调至一层并获取当前层数")
  }

  async billing(): Promise<void>{
    await this.sendControl0A(0x1A,"LED标志物开始计时")
  }

  async SrttleAccounts(): Promise<void>{
    await this.sendControl0A(0x1B,"LED标志物结束计时")
  }

  // 注意：
  // stopTask(0xBB) 只会终止小车端部分任务（如警报/播报等非运动任务），
  // 不能可靠停止小车行动任务（行驶/转向）。业务层应尽量不要用它做“停车”。
  async stopTask(): Promise<void> {
    await this.sendControl0A(0xBB, '终止非行动任务（不保证停止运动）')
  }

  //=====0x0B 特定语音发送=====
    // 0x0B: 预置语音码播放（由小车端固定语音表解释）
  private async sendControl0B(code: number, text: string): Promise<void> {
    const payload8: Uint8Array = new Uint8Array(8)
    payload8[0] = code & 0xff
    await this.sendData12(0x0B, payload8)
    hilog.info(DOMAIN, TAGRUN, '%{public}s', text)
  }
  async voiceone(): Promise<void> {
    await this.sendControl0B(0x2B, '发送已为您重新规划路线')
  }

  async voicetow(): Promise<void> {
    await this.sendControl0B(0x2C, '发送已找到停车位，正在为您停车')
  }

  async voicethree(): Promise<void> {
    await this.sendControl0B(0x2D, '发送达目的地，祝您旅途愉快')
  }
  async voicefour(): Promise<void> {
    await this.sendControl0B(0x2E, '发送以为你规划最优路径，小创')
  }
  async voicefive(): Promise<void> {
    await this.sendControl0B(0x2F, '发送紧急避险')
  }

  async voicesex(): Promise<void> {
    await this.sendControl0B(0x30, '当前车位已被占用，正在为您寻找其他车位')
  }



  //===== 0x0C =====
  // 文本语音播报（文本会被切分为 8 字节帧发送）
  async yuying(shu: string): Promise<void> {
    const payloads: Uint8Array[] = this.packBroadcastPayloads(shu)
    if (payloads.length <= 0) {
      hilog.warn(DOMAIN, TAGRUN, '%{public}s', '站台播报内容为空，未发送')
      return
    }
    for (let i: number = 0; i < payloads.length; i++) {
      const payload8: Uint8Array = new Uint8Array(8)
      payload8.set(payloads[i], 0)
      await this.sendData12(0x07, payload8)
    }
    hilog.info(DOMAIN, TAGRUN, '%{public}s', `语音发送完成 frames=${payloads.length} text=${shu}`)
  }
  // 公交站台播报（与 yuying 类似，但使用不同业务 h 码）
  async zhaantai(shu: string): Promise<void> {
    const payloads: Uint8Array[] = this.packBroadcastPayloads(shu)
    if (payloads.length <= 0) {
      hilog.warn(DOMAIN, TAGRUN, '%{public}s', '站台播报内容为空，未发送')
      return
    }
    for (let i: number = 0; i < payloads.length; i++) {
      const payload8: Uint8Array = new Uint8Array(8)
      payload8.set(payloads[i], 0)
      await this.sendData12(0x08, payload8)
    }
    hilog.info(DOMAIN, TAGRUN, '%{public}s', `站台播报完成 frames=${payloads.length} text=${shu}`)
  }

  // 按 Unicode 符号切分，避免代理对（如 emoji）被截断
  private nextSymbol(text: string, start: number): { value: string, next: number } {
    if (start >= text.length) {
      return { value: '', next: start }
    }
    const first: number = text.charCodeAt(start)
    if (first >= 0xD800 && first <= 0xDBFF && start + 1 < text.length) {
      const second: number = text.charCodeAt(start + 1)
      if (second >= 0xDC00 && second <= 0xDFFF) {
        return { value: text.substring(start, start + 2), next: start + 2 }
      }
    }
    return { value: text.substring(start, start + 1), next: start + 1 }
  }

  // libentry 编码失败时的兜底：非 ASCII 字符替换为 '?'
  private asciiFallbackBytes(text: string): Uint8Array {
    const out: number[] = []
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i)
      out.push(code <= 0x7F ? code : 0x3F)
    }
    return this.toByteArray(out)
  }

  // 通过 native 层做 GBK 编码，兼容小车端文本协议
  private encodeGbkBytes(text: string): Uint8Array {
    try {
      const buffer: ArrayBuffer = libentry.encodeGbk(text)
      return new Uint8Array(buffer)
    } catch (_) {
      return this.asciiFallbackBytes(text)
    }
  }

  // number[] -> Uint8Array 的统一封装
  private toByteArray(bytes: number[]): Uint8Array {
    const out: Uint8Array = new Uint8Array(bytes.length)
    for (let i: number = 0; i < bytes.length; i++) {
      out[i] = bytes[i] & 0xFF
    }
    return out
  }

  /**
   * 文本打包为 8 字节 payload 序列：
   * - 按符号取字节；
   * - 不能超 8 字节就新开一帧；
   * - 返回的每个 Uint8Array 都可直接塞入 12B payload。
   */
  private packBroadcastPayloads(text: string): Uint8Array[] {
    const payloads: Uint8Array[] = []
    let cursor: number = 0
    let current: number[] = []
    // 这里按 8 字节切片：
    // - 改小：帧数更多，稳定但更慢
    // - 改大：会破坏当前 12B 协议 payload 约束（不建议改）
    while (cursor < text.length) {
      const symbol = this.nextSymbol(text, cursor)
      cursor = symbol.next
      const bytes: Uint8Array = this.encodeGbkBytes(symbol.value)
      if (bytes.length <= 0) {
        continue
      }
      if (current.length > 0 && current.length + bytes.length > 8) {
        payloads.push(this.toByteArray(current))
        current = []
      }
      for (let i: number = 0; i < bytes.length; i++) {
        current.push(bytes[i] & 0xFF)
      }
    }
    if (current.length > 0) {
      payloads.push(this.toByteArray(current))
    }
    return payloads
  }

  private async sleepMs(ms: number): Promise<void> {
    const waitMs: number = Math.max(0, Math.trunc(ms))
    await new Promise<void>((resolve): void => {
      setTimeout((): void => resolve(), waitMs)
    })
  }
}

