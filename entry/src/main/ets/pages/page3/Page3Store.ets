/**
 * 代码指南：
 * 文件： 
pages/page3/Page3Store.ets
 * 用途： 
Page3 coordination and state management.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page3/Page3Store.ets
 * 用途： page3 状态仓库，集中管理页面可观察状态。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * Page3 store placeholder for future 3D integration.
 */

export enum CameraMode {
  FREE = 0,
  FOLLOW = 1,
  BIRD_EYE = 2,
  FIRST_PERSON = 3
}

export interface Page3SceneState {
  carXNorm: number
  carYNorm: number
  carHeadingDeg: number
  speed: number
  pathNodes: Array<string>
  pathIndex: number
  blockedNodes: Array<string>
  detections: Array<string>
  cameraMode: CameraMode
  cameraDistance: number
  cameraAngleDeg: number
  showGrid: boolean
  showPath: boolean
  showObstacles: boolean
  showBoundingBoxes: boolean
}

@Observed
export class Page3Store {
  nativeReady: boolean = false
  scene: Page3SceneState = {
    carXNorm: 0.5,
    carYNorm: 0.5,
    carHeadingDeg: 0,
    speed: 0,
    pathNodes: [],
    pathIndex: 0,
    blockedNodes: [],
    detections: [],
    cameraMode: CameraMode.BIRD_EYE,
    cameraDistance: 5,
    cameraAngleDeg: 45,
    showGrid: true,
    showPath: true,
    showObstacles: true,
    showBoundingBoxes: true
  }

  setNativeReady(v: boolean): void { this.nativeReady = v }
  updateCarPose(xNorm: number, yNorm: number, headingDeg: number, speed: number): void {
    this.scene.carXNorm = xNorm
    this.scene.carYNorm = yNorm
    this.scene.carHeadingDeg = headingDeg
    this.scene.speed = speed
  }
  updatePath(nodes: Array<string>, index: number): void {
    this.scene.pathNodes = nodes
    this.scene.pathIndex = index
  }
  updateObstacles(blockedNodes: Array<string>, _blockedEdges: Array<string>): void {
    this.scene.blockedNodes = blockedNodes
  }
  updateDetections(objects: Array<string>): void { this.scene.detections = objects }
}

export const page3Store: Page3Store = new Page3Store()


