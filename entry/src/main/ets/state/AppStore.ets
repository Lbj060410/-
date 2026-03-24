/**
 * 代码指南：
 * 文件： state/AppStore.ets
 * 用途： 应用级共享状态/存储模块。
 * 何时修改： 新增跨页面状态或调整全局数据结构时。
 * 相关文件： 读写状态存储值的页面视图、协调器及各类服务。
 */
// entry/src/main/ets/state/AppStore.ets
// Barrel re-export — 向后兼容：重新导出各子 Store
export { CommStore, commStore } from './CommStore'
export { VideoStore, videoStore, DisplayMode, RtspState } from './VideoStore'
export { RecogStore, recogStore } from './RecogStore'

