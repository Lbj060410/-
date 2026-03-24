/**
 * 代码指南：
 * 文件： pages/page1/net/CarTelemetryFrom8B.ets
 * 用途： 0x55AA 协议的车辆数据帧模型、解析器与解码工具
 * 何时修改： 数据包格式、解析规则发生变更，或遥测数据解码需要更新时
 * 相关文件： app/Page1Coordinator.ets 和 services/control/CarTcpService.ets.
 */
// entry/src/main/ets/pages/page1/net/CarTelemetryFrom8B.ets

import { CarFrame8 } from './CarFrameModels'
import { CarTelemetry } from '../types/Page1Types'

export class CarTelemetryFrom8B {
  // ✅ 先占一个“遥测主指令”，后续确定协议只改这个值
  static readonly TELEMETRY_MAJOR: number = 0xE1

  static isTelemetryFrame(f: CarFrame8): boolean {
    // 主车→鸿蒙：0x55 0xAA ...
    if (f.type !== 0xAA) return false
    if (f.major !== CarTelemetryFrom8B.TELEMETRY_MAJOR) return false
    return f.ok
  }

  static toTelemetry(prev: CarTelemetry, f: CarFrame8): CarTelemetry {
    const now: number = Date.now()

    // 占位映射（后续你按真实协议替换）
    const ultraFrontCm: number = f.first & 0xff
    const lightLux: number = (f.second & 0xff) * 10
    const odomIncMm: number = (f.third & 0xff) * 10

    const next: CarTelemetry = {
      tsMs: now,
      speed: prev.speed,                       // 暂不从遥测帧推
      headingDeg: prev.headingDeg,             // 暂不从遥测帧推
      odomMm: prev.odomMm + odomIncMm,         // 用增量累加（演示最稳）
      ultraFrontCm: ultraFrontCm,
      ultraBackCm: prev.ultraBackCm,
      irDistCm: prev.irDistCm,
      lightLux: lightLux,
      rfid: prev.rfid
    }
    return next
  }
}
