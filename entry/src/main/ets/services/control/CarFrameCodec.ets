/**
 * 代码指南：
 * 文件：services/control/CarFrameCodec.ets
 * 用途：车辆命令数据包的底层帧编码/解码辅助工具。
 * 何时修改：帧格式定义变化时。
 * 相关文件：services/control/CarProtocolService.ets。
 */
// entry/src/main/ets/services/control/CarFrameCodec.ets

export class CarFrameCodec {
  //原安卓数据包真头
  static readonly HEADER_12: number = 0xCC
  //原安卓数据包帧尾
  static readonly FOOTER: number = 0xBB

  // ===== 12字节：0xCC h payload[8] chk 0xBB =====
  static build12(h: number, payload8: Uint8Array): Uint8Array {
    const out: Uint8Array = new Uint8Array(12)
    out[0] = CarFrameCodec.HEADER_12
    out[1] = CarFrameCodec.u8(h)

    // payload 必须 8 字节
    for (let i: number = 0; i < 8; i++) {
      out[2 + i] = (i < payload8.length) ? (payload8[i] & 0xff) : 0
    }

    let sum: number = 0
    for (let i: number = 0; i < 8; i++) {
      sum += (out[2 + i] & 0xff)
    }
    out[10] = CarFrameCodec.u8(sum % 256)
    out[11] = CarFrameCodec.FOOTER
    return out
  }

  // ===== 工具：字节裁剪 =====
  private static u8(v: number): number {
    return v & 0xff
  }
}
