/**
 * 代码指南：
 * 文件：pages/page1/net/CarTelemetryFrame.ets
 * 用途：0x55AA 协议的车辆帧模型/解析器/解码工具。
 * 何时修改：数据包格式变化、解析规则变化或遥测解码需要更新时。
 * 相关文件：app/Page1Coordinator.ets 和 services/control/CarTcpService.ets。
 */
// entry/src/main/ets/pages/page1/net/CarTelemetryFrame.ets

export enum CarRole {
  MASTER = 1,
  SLAVE = 2,
  UNKNOWN = 9
}

export interface CarTelemetryFrame {
  tsMs: number
  role: CarRole
  status: number        // mByte[2]
  psStatus: number      // mByte[3]
  ultraMm: number       // mByte[4..5] 小端序
  lightLux: number      // mByte[6..7] 小端序
  codedDisk: number     // mByte[8..9] 小端序
}
