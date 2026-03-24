/**
 * 代码指南：
 * 文件： services/control/CarConnectionState.ets
 * 用途： Module implementation for this project layer.
 * 何时修改： the feature owned by this file needs behavior updates.
 * 相关文件： search usages of exported symbols to find callers and impact scope.
 */
export enum CarConnectionState {
  IDLE = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  RECONNECTING = 3,
  FAILED = 4
}
