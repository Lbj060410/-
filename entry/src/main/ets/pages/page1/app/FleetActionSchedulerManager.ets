/**
 * 代码指南：
 * 文件： 
pages/page1/app/FleetActionSchedulerManager.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/FleetActionSchedulerManager.ets
 * 用途： 管理车队动作调度入口与调度生命周期，协调多动作执行顺序。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * FleetActionSchedulerManager
 * Multi-instance scheduler manager for future multi-vehicle orchestration.
 */
import { SendAutoActionRequest, SchedulerSnapshot, VehicleActionScheduler, VehicleActionSchedulerDeps } from './VehicleActionScheduler'

export interface FleetSchedulerSnapshot {
  vehicleId: string
  snapshot: SchedulerSnapshot
}

export class FleetActionSchedulerManager {
  private readonly schedulers: Map<string, VehicleActionScheduler> = new Map<string, VehicleActionScheduler>()

  private normalizeVehicleId(vehicleId: string): string {
    return vehicleId.trim().toUpperCase()
  }

  getOrCreate(vehicleId: string): VehicleActionScheduler {
    const id: string = this.normalizeVehicleId(vehicleId)
    let scheduler: VehicleActionScheduler | undefined = this.schedulers.get(id)
    if (scheduler) return scheduler
    scheduler = new VehicleActionScheduler()
    this.schedulers.set(id, scheduler)
    return scheduler
  }

  has(vehicleId: string): boolean {
    const id: string = this.normalizeVehicleId(vehicleId)
    return this.schedulers.has(id)
  }

  remove(vehicleId: string): boolean {
    const id: string = this.normalizeVehicleId(vehicleId)
    return this.schedulers.delete(id)
  }

  clear(): void {
    this.schedulers.clear()
  }

  vehicleIds(): Array<string> {
    const out: Array<string> = []
    this.schedulers.forEach((_scheduler: VehicleActionScheduler, key: string): void => {
      out.push(key)
    })
    return out
  }

  canSendNextCommand(vehicleId: string, nowMs: number, motionRunning: boolean): boolean {
    return this.getOrCreate(vehicleId).canSendNextCommand(nowMs, motionRunning)
  }

  snapshot(vehicleId: string, nowMs: number, motionRunning: boolean): SchedulerSnapshot {
    return this.getOrCreate(vehicleId).snapshot(nowMs, motionRunning)
  }

  snapshots(nowMs: number, motionRunningByVehicleId?: Map<string, boolean>): Array<FleetSchedulerSnapshot> {
    const out: Array<FleetSchedulerSnapshot> = []
    this.schedulers.forEach((scheduler: VehicleActionScheduler, vehicleId: string): void => {
      const motionRunning: boolean = motionRunningByVehicleId ? (motionRunningByVehicleId.get(vehicleId) === true) : false
      out.push({
        vehicleId: vehicleId,
        snapshot: scheduler.snapshot(nowMs, motionRunning)
      })
    })
    return out
  }

  async sendAutoActionWithTiming(vehicleId: string, req: SendAutoActionRequest, deps: VehicleActionSchedulerDeps): Promise<boolean> {
    return await this.getOrCreate(vehicleId).sendAutoActionWithTiming(req, deps)
  }

  beginMotionOnlyWithTiming(vehicleId: string, req: SendAutoActionRequest, deps: VehicleActionSchedulerDeps): void {
    this.getOrCreate(vehicleId).beginMotionOnlyWithTiming(req, deps)
  }
}


