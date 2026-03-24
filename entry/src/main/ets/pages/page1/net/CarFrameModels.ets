/**
 * 代码指南：
 * 文件：pages/page1/net/CarFrameModels.ets
 * 用途：0x55AA 协议的车辆帧模型/解析器/解码工具。
 * 何时修改：数据包格式变化、解析规则变化或遥测解码需要更新时。
 * 相关文件：app/Page1Coordinator.ets 和 services/control/CarTcpService.ets。
 */
// entry/src/main/ets/pages/page1/net/CarFrameModels.ets

export enum CarFrameKind {
  FRAME8 = 1,
  FRAME12 = 2,
  UNKNOWN = 9
}

export class CarFrame8 {
  kind: CarFrameKind = CarFrameKind.FRAME8

  header: number = 0x55
  type: number = 0
  major: number = 0
  first: number = 0
  second: number = 0
  third: number = 0
  checksum: number = 0
  footer: number = 0xBB

  ok: boolean = false
  reason: string = ''

  constructor() {}
}

export class CarFrame12 {
  kind: CarFrameKind = CarFrameKind.FRAME12

  header: number = 0xCC
  h: number = 0
  payload: Uint8Array = new Uint8Array(8)
  checksum: number = 0
  footer: number = 0xBB

  ok: boolean = false
  reason: string = ''

  constructor() {}
}

export class CarFrameUnknown {
  kind: CarFrameKind = CarFrameKind.UNKNOWN
  raw: Uint8Array = new Uint8Array(0)

  constructor(raw: Uint8Array) {
    this.raw = raw
  }
}
