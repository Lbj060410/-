/**
 * 代码指南：
 * 文件： 
pages/page3/Page3Coordinator.ets
 * 用途： 
Page3 coordination and state management.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page3/Page3Coordinator.ets
 * 用途： page3 页面业务协调器，负责页面状态与服务交互编排。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * Page3 coordinator placeholder for future 3D integration.
 */
import { page3Store, Page3Store } from './Page3Store'
import { page1Store, Page1UiStore } from '../page1/app/Page1UiStore'
import { recogStore, RecogStore } from '../../state/RecogStore'
import { Scene3DNativeApi } from '../../services/render3d/Scene3DNativeApi'

export class Page3Coordinator {
  constructor(
    private store: Page3Store,
    private page1: Page1UiStore,
    private recog: RecogStore,
    private nativeApi: Scene3DNativeApi
  ) {}

  start(): void { this.store.setNativeReady(true) }
  stop(): void { this.store.setNativeReady(false) }

  onNativeReady(): void { this.store.setNativeReady(true) }
  onNativeDestroy(): void { this.store.setNativeReady(false) }
}

let coordinatorSingleton: Page3Coordinator | undefined = undefined

export function ensurePage3Coordinator(nativeApi: Scene3DNativeApi): Page3Coordinator {
  if (coordinatorSingleton) return coordinatorSingleton
  coordinatorSingleton = new Page3Coordinator(page3Store, page1Store, recogStore, nativeApi)
  return coordinatorSingleton
}

export function getPage3Coordinator(): Page3Coordinator | undefined {
  return coordinatorSingleton
}

export function shutdownPage3Coordinator(): void {
  if (!coordinatorSingleton) return
  coordinatorSingleton.stop()
  coordinatorSingleton = undefined
}


