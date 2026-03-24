/**
 * 代码指南：
 * 文件：pages/page1/types/PoseTypes.ets
 * 用途：page1 模块使用的共享类型定义。
 * 何时修改：为 page1 添加/更改 TypeScript 接口/枚举时。
 * 相关文件：pages/page1/ 中的 app/*、components/*、net/*。
 */
// entry/src/main/ets/pages/page1/types/PoseTypes.ets

export enum PoseSource {
  INIT = 0,
  DEAD_RECKONING = 1,
  RFID_CORRECT = 2,
  MANUAL = 3
}

export interface Pose2D {
  tsMs: number
  xNorm: number
  yNorm: number
  headingDeg: number
  confidence: number // 0~1
  source: PoseSource
}
