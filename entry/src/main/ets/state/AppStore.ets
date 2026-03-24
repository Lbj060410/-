/**
 * 代码指南：
 * 文件： state/AppStore.ets
 * 用途： Shared app-level store/state module.
 * 何时修改： adding cross-page state or adjusting global data shape.
 * 相关文件： page views/coordinators and services that read/write store values.
 */
// entry/src/main/ets/state/AppStore.ets
// Barrel re-export — 向后兼容：重新导出各子 Store
export { CommStore, commStore } from './CommStore'
export { VideoStore, videoStore, DisplayMode, RtspState } from './VideoStore'
export { RecogStore, recogStore } from './RecogStore'

