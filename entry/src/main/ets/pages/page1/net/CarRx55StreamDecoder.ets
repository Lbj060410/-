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
// 当前仅兼容：
// 1) 55 AA 固定 8B，尾字节 BB
//
// 处理 TCP 粘包 / 半包 / 脏数据
// 仅接收 0x55 开头并且第二字节为 0xAA 的帧
//
// 示例：
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
//接收解析的数据帧头
  private readonly header0: number = 0x55
  //接收解析的数据帧尾
  private readonly header1: number = 0xAA

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
