/**
 * 代码指南：
 * 文件： services/control/CarConnectionState.ets
 * 用途： 本项目层的模块功能实现。
 * 何时修改： 本文件所属功能需要更新行为逻辑时。
 * 相关文件： 搜索导出符号的使用处，以查找调用方及影响范围。
 */
export enum CarConnectionState {
  IDLE = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  RECONNECTING = 3,
  FAILED = 4
}
