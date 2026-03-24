/**
 * 代码指南：
 * 文件：pages/page1/net/CarTelemetryParser.ets
 * 用途：0x55AA 协议的车辆帧模型/解析器/解码工具。
 * 何时修改：数据包格式变化、解析规则变化或遥测解码需要更新时。
 * 相关文件：app/Page1Coordinator.ets 和 services/control/CarTcpService.ets。
 */
// entry/src/main/ets/pages/page1/net/CarTelemetryParser.ets

import { CarRole, CarTelemetryFrame } from './CarTelemetryFrame'

export class CarTelemetryParser {
  // 你安卓示例里 mByte 用到 0..9，下标 10 通常是校验/尾部（你项目里可能是 11 字节）
  // 这里做“最小可用”：len >= 10 即可解析关键字段
  static tryParseFromRaw(raw: Uint8Array): CarTelemetryFrame | undefined {
    if (raw.length < 10) return undefined

    const head: number = raw[0] & 0xff
    if (head !== 0x55) return undefined

    const roleByte: number = raw[1] & 0xff
    const role: CarRole = CarTelemetryParser.parseRole(roleByte)

    const status: number = raw[2] & 0xff
    const psStatus: number = raw[3] & 0xff

    // Android 代码：Ultra = (b5<<8)+b4，说明是小端序
    const ultraMm: number = CarTelemetryParser.u16le(raw[4], raw[5])
    const lightLux: number = CarTelemetryParser.u16le(raw[6], raw[7])
    const codedDisk: number = CarTelemetryParser.u16le(raw[8], raw[9])

    const f: CarTelemetryFrame = {
      tsMs: Date.now(),
      role: role,
      status: status,
      psStatus: psStatus,
      ultraMm: ultraMm,
      lightLux: lightLux,
      codedDisk: codedDisk
    }
    return f
  }

  private static parseRole(b: number): CarRole {
    if (b === 0xAA) return CarRole.MASTER
    if (b === 0x02) return CarRole.SLAVE
    return CarRole.UNKNOWN
  }

  private static u16le(lo: number, hi: number): number {
    const l: number = lo & 0xff
    const h: number = hi & 0xff
    return (h << 8) + l
  }
}
