/**
 * 代码指南：
 * 文件：pages/page1/net/CarHex.ets
 * 用途：0x55AA 协议的车辆帧模型/解析器/解码工具。
 * 何时修改：数据包格式变化、解析规则变化或遥测解码需要更新时。
 * 相关文件：app/Page1Coordinator.ets 和 services/control/CarTcpService.ets。
 */
// entry/src/main/ets/pages/page1/net/CarHex.ets

export class CarHex {
  static toHex(bytes: Uint8Array): string {
    let out: string = ''
    for (let i: number = 0; i < bytes.length; i++) {
      const v: number = bytes[i] & 0xff
      const s: string = v.toString(16).toUpperCase().padStart(2, '0')
      out = (out.length === 0) ? s : (out + ' ' + s)
    }
    return out
  }
}
