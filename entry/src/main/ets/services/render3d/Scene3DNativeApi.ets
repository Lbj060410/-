/**
 * 代码指南：
 * 文件： 
services/render3d/Scene3DNativeApi.ets
 * 用途： 
Module Scene3DNativeApi responsibilities
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/services/render3d/Scene3DNativeApi.ets
 * 用途： 3D 场景原生接口封装，桥接 ArkTS 与原生 3D 能力。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * Native 3D bridge placeholder.
 * Current behavior is no-op but API is preserved for future implementation.
 */
import { CameraMode } from '../../pages/page3/Page3Store'

export class Scene3DNativeApi {
  init(_width: number, _height: number): boolean { return false }
  destroy(): void {}
  updateCarPose(_xNorm: number, _yNorm: number, _headingDeg: number): void {}
  updatePath(_nodes: Array<string>, _currentIndex: number): void {}
  updateObstacles(_blockedNodes: Array<string>): void {}
  updateDetections(_objects: Array<string>): void {}
  updateCamera(_mode: CameraMode, _distance: number, _angleDeg: number): void {}
  updateRenderOptions(
    _showGrid: boolean,
    _showPath: boolean,
    _showObstacles: boolean,
    _showBoundingBoxes: boolean
  ): void {}
  render(): void {}
  switchCarModel(_modelIndex: number): void {}
}


