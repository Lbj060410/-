/**
 * 代码指南：
 * 文件： pages/page1/net/CarRx55StreamDecoder.ets
 * 用途： 用于 0x55AA 协议的车辆数据帧模型、解析器、解码工具
 * 何时修改： 数据包格式变更、解析规则修改、遥测解码需要更新时
 * 相关文件： app/Page1Coordinator.ets 以及 services/control/CarTcpService.ets.
 */
// entry/src/main/ets/pages/page1/net/CarRx55StreamDecoder.ets
//
// 工业级 RX 解码器
// 当前兼容两类协议：
// 1) 55 AA 固定 13B
// 2) 55 AA 固定 8B，尾字节 BB
//
// 处理 TCP 粘包 / 半包 / 脏数据
// 仅接收 0x55 开头并且第二字节为 0xAA 的帧
//
// 示例：
// 13B: 55 AA 00 01 5C 01 87 00 ED 8F 00 00 00
//  8B: 55 AA BC B2 00 00 6E BB

import { FrameLogService } from '../../../services/diagnostics/FrameLogService'

export interface CarFrame55 {
  ok: boolean
  raw: Uint8Array

  frameLen: number
  frameKind: string

  header0: number
  header1: number

  cmd: number
  payload: Uint8Array

  p1: number
  p2: number
  p3: number
  p4: number
  p5: number
  p6: number
  p7: number
  p8: number
  p9: number
  p10: number

  tail: number
}

export class CarRx55StreamDecoder {
  private readonly buf: Array<number> = []

  private readonly header0: number = 0x55
  private readonly header1: number = 0xAA

  private readonly frameLen13: number = 13
  private readonly frameLen8: number = 8
  private readonly frame8Tail: number = 0xBB

  feed(chunk: Uint8Array): Array<CarFrame55> {
    const out: Array<CarFrame55> = []

    let i: number = 0
    while (i < chunk.length) {
      this.buf.push(chunk[i] & 0xff)
      i += 1
    }

    const maxIter: number = this.buf.length + 24
    let iter: number = 0

    while (iter < maxIter) {
      iter += 1

      const headIdx: number = this.findHeader55()
      if (headIdx < 0) {
        this.buf.length = 0
        break
      }

      if (headIdx > 0) {
        this.buf.splice(0, headIdx)
      }

      if (this.buf.length < 2) {
        break
      }

      if ((this.buf[0] & 0xff) !== this.header0) {
        this.buf.shift()
        continue
      }

      if ((this.buf[1] & 0xff) !== this.header1) {
        this.buf.shift()
        continue
      }

      const canDecode8: boolean = this.buf.length >= this.frameLen8
      const canDecode13: boolean = this.buf.length >= this.frameLen13

      // 关键策略：
      // 只要当前头满足 8B 的尾字节 BB，就优先按 8B 出帧。
      // 这样可避免“实际8B被13B分支误吞”导致大面积丢帧。
      if (canDecode8) {
        const tail8: number = this.buf[7] & 0xff
        if (tail8 === this.frame8Tail) {
          const cand8: Array<number> = this.buf.slice(0, this.frameLen8)
          const raw8: Uint8Array = new Uint8Array(cand8)
          const parsed8: CarFrame55 = this.parse8(raw8)
          if (parsed8.ok) {
            out.push(parsed8)
            FrameLogService.appendRx(
              raw8,
              '0x55AA:8B',
              `cmd=0x${this.byteToHex(parsed8.cmd)} payload=${this.toHex(parsed8.payload)} tail=0x${this.byteToHex(parsed8.tail)}`
            )
            this.buf.splice(0, this.frameLen8)
            continue
          }
          this.buf.shift()
          continue
        }
      }

      // 固定 13B 帧（仅在未命中 8B 尾时尝试）。
      if (canDecode13) {
        const raw13: Uint8Array = new Uint8Array(this.buf.slice(0, this.frameLen13))
        const parsed13: CarFrame55 = this.parse13(raw13)
        if (parsed13.ok) {
          out.push(parsed13)
          FrameLogService.appendRx(
            raw13,
            '0x55AA:13B',
            `cmd=0x${this.byteToHex(parsed13.cmd)} payload=${this.toHex(parsed13.payload)}`
          )
          this.buf.splice(0, this.frameLen13)
          continue
        }

        this.buf.shift()
        continue
      }

      break
    }

    return out
  }

  reset(): void {
    this.buf.length = 0
  }

  getBufferedSize(): number {
    return this.buf.length
  }

  private parse13(raw: Uint8Array): CarFrame55 {
    return {
      ok: true,
      raw: raw,

      frameLen: 13,
      frameKind: '55AA_13B',

      header0: raw[0] & 0xff,
      header1: raw[1] & 0xff,

      cmd: raw[2] & 0xff,
      payload: raw.slice(3, 13),

      p1: raw[3] & 0xff,
      p2: raw[4] & 0xff,
      p3: raw[5] & 0xff,
      p4: raw[6] & 0xff,
      p5: raw[7] & 0xff,
      p6: raw[8] & 0xff,
      p7: raw[9] & 0xff,
      p8: raw[10] & 0xff,
      p9: raw[11] & 0xff,
      p10: raw[12] & 0xff,

      tail: raw[12] & 0xff
    }
  }

  private parse8(raw: Uint8Array): CarFrame55 {
    return {
      ok: true,
      raw: raw,

      frameLen: 8,
      frameKind: '55AA_8B_BB',

      header0: raw[0] & 0xff,
      header1: raw[1] & 0xff,

      cmd: raw[2] & 0xff,
      payload: raw.slice(3, 8),

      p1: raw[3] & 0xff,
      p2: raw[4] & 0xff,
      p3: raw[5] & 0xff,
      p4: raw[6] & 0xff,
      p5: raw[7] & 0xff,
      p6: 0,
      p7: 0,
      p8: 0,
      p9: 0,
      p10: 0,

      tail: raw[7] & 0xff
    }
  }

  private isLikely8BoundaryAtCurrentHead(): boolean {
    if (this.buf.length < this.frameLen13) return false
    if ((this.buf[7] & 0xff) !== this.frame8Tail) return false
    return (this.buf[8] & 0xff) === this.header0 && (this.buf[9] & 0xff) === this.header1
  }

  private findHeader55(): number {
    let i: number = 0
    while (i < this.buf.length) {
      if ((this.buf[i] & 0xff) === this.header0) return i
      i += 1
    }
    return -1
  }

  private toHex(data: Uint8Array): string {
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

  private byteToHex(v: number): string {
    return (v & 0xff).toString(16).toUpperCase().padStart(2, '0')
  }
}

