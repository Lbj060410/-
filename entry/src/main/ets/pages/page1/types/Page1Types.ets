/**
 * 代码指南：
 * 文件： pages/page1/types/Page1Types.ets
 * 用途： Shared type definitions used by page1 modules.
 * 何时修改： adding/changing TypeScript interfaces/enums for page1.
 * 相关文件： app/*, components/*, net/* in pages/page1/.
 */
export enum Page1Action {
  GO = 0,
  BACK = 1,
  LEFT = 2,
  RIGHT = 3,
  LEFT_HALF = 4,
  RIGHT_HALF = 5,
  UTURN = 6,
  ALARM = 7,
  STOP = 8,
  LAMP = 9,
  LANGUAGE = 10,
  SCRAM= 11,
  TFTA=12,
  LIGHT=13,
  TFTB=14,
  STROBE=15
}

export interface CarTelemetry {
  tsMs: number
  speed: number
  headingDeg: number
  odomMm: number
  ultraFrontCm: number
  ultraBackCm: number
  irDistCm: number
  lightLux: number
  rfid: string
}

