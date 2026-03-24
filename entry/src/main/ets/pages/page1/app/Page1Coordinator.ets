/**
 * 代码指南：
 * 文件： 
pages/page1/app/Page1Coordinator.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/Page1Coordinator.ets
 * 用途： 聚合 page1 协调器主类，负责路径、控制、识别与状态流转的总调度。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * Thin entry wrapper for Page1 coordinator.
 * The implementation is split into Page1CoordinatorCore.ets to keep this entry file small.
 */
export { Page1Coordinator, page1Coordinator } from './Page1CoordinatorCore'


