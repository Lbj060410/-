/**
 * 代码指南：
 * 文件：pages/page1/net/CarFrameParser.ets
 * 用途：0x55AA 协议的车辆帧模型/解析器/解码工具。
 * 何时修改：数据包格式变化、解析规则变化或遥测解码需要更新时。
 * 相关文件：app/Page1Coordinator.ets 和 services/control/CarTcpService.ets。
 */
// entry/src/main/ets/pages/page1/net/CarFrameParser.ets

import { CarFrame8, CarFrame12, CarFrameUnknown } from './CarFrameModels'

export class CarFrameParser {
  static splitAndParse(data: Uint8Array): Array<CarFrame8 | CarFrame12 | CarFrameUnknown> {
    const out: Array<CarFrame8 | CarFrame12 | CarFrameUnknown> = []

    let i: number = 0
    while (i < data.length) {
      const remain: number = data.length - i

      // 8字节帧：0x55 ...... 0xBB
      if (remain >= 8 && ((data[i] & 0xff) === 0x55)) {
        const chunk8: Uint8Array = data.slice(i, i + 8)
        out.push(CarFrameParser.parse8(chunk8))
        i += 8
        continue
      }

      // 12字节帧：0xCC ...... 0xBB
      if (remain >= 12 && ((data[i] & 0xff) === 0xCC)) {
        const chunk12: Uint8Array = data.slice(i, i + 12)
        out.push(CarFrameParser.parse12(chunk12))
        i += 12
        continue
      }

      // 无法对齐：剩余全部 unknown，避免死循环
      const rest: Uint8Array = data.slice(i)
      out.push(new CarFrameUnknown(rest))
      break
    }

    return out
  }

  static parse8(frame: Uint8Array): CarFrame8 {
    const f: CarFrame8 = new CarFrame8()

    if (frame.length !== 8) {
      f.ok = false
      f.reason = `len=${frame.length}`
      return f
    }

    f.header = frame[0] & 0xff
    f.type = frame[1] & 0xff
    f.major = frame[2] & 0xff
    f.first = frame[3] & 0xff
    f.second = frame[4] & 0xff
    f.third = frame[5] & 0xff
    f.checksum = frame[6] & 0xff
    f.footer = frame[7] & 0xff

    if (f.header !== 0x55 || f.footer !== 0xBB) {
      f.ok = false
      f.reason = 'bad header/footer'
      return f
    }

    const expect: number = (f.major + f.first + f.second + f.third) % 256
    if (expect !== f.checksum) {
      f.ok = false
      f.reason = `bad checksum expect=${expect} got=${f.checksum}`
      return f
    }

    f.ok = true
    f.reason = 'ok'
    return f
  }

  static parse12(frame: Uint8Array): CarFrame12 {
    const f: CarFrame12 = new CarFrame12()

    if (frame.length !== 12) {
      f.ok = false
      f.reason = `len=${frame.length}`
      return f
    }

    f.header = frame[0] & 0xff
    f.h = frame[1] & 0xff
    f.payload = frame.slice(2, 10)
    f.checksum = frame[10] & 0xff
    f.footer = frame[11] & 0xff

    if (f.header !== 0xCC || f.footer !== 0xBB) {
      f.ok = false
      f.reason = 'bad header/footer'
      return f
    }

    let sum: number = 0
    for (let i: number = 0; i < f.payload.length; i++) {
      sum += (f.payload[i] & 0xff)
    }
    const expect: number = sum % 256
    if (expect !== f.checksum) {
      f.ok = false
      f.reason = `bad checksum expect=${expect} got=${f.checksum}`
      return f
    }

    f.ok = true
    f.reason = 'ok'
    return f
  }
}
