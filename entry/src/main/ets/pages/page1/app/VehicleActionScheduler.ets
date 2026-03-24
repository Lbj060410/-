/**
 * 代码指南：
 * 文件：pages/page1/app/VehicleActionScheduler.ets
 * 用途：Page1 协调/调度辅助逻辑。
 * 何时修改：相关行为或契约变化时。
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/VehicleActionScheduler.ets
 * 用途： 动作级调度器，负责动作窗口、节拍和执行时机管理。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * VehicleActionScheduler
 * 控制命令节奏、动作窗口状态和运动启动编排。
 */
import { Page1Action } from '../types/Page1Types'
import { ActionTimingRegistry, MotionTimingProfile } from './ActionTimingRegistry'
import { VehicleMotionHooks, VehicleMotionPlayer } from './VehicleMotionPlayer'

export interface SendAutoActionRequest {
  action: Page1Action
  fromId: string
  toId: string
  nextAction?: Page1Action
  customTiming?: MotionTimingProfile
  advancePathOnFinish?: boolean
  useReverseSpeed?: boolean
  customLogTag?: string
}

export interface VehicleActionSchedulerDeps {
  sendDriveActionDirect(action: Page1Action): Promise<boolean>
  motionPlayer: VehicleMotionPlayer
  timingRegistry: ActionTimingRegistry
  motionHooks: VehicleMotionHooks
}

export interface ScheduledActionWindow {
  action: Page1Action
  fromId: string
  toId: string
  startedAtMs: number
  sendGapMs: number
  nextSendAtMs: number
}

export enum SchedulerCadenceState {
  IDLE = 0,
  WAITING_GAP = 1,
  BLOCKED_BY_MOTION = 2,
  READY = 3
}

export interface SchedulerSnapshot {
  nowMs: number
  cadenceState: SchedulerCadenceState
  motionRunning: boolean
  canSend: boolean
  nextCommandEarliestAtMs: number
  remainingGapMs: number
  currentActionWindow?: ScheduledActionWindow
}

export interface VehicleActionSchedulerCallbacks {
  onReset?(snapshot: SchedulerSnapshot): void
  onActionWindowStart?(window: ScheduledActionWindow, snapshot: SchedulerSnapshot): void
  onActionWindowClear?(window: ScheduledActionWindow, snapshot: SchedulerSnapshot): void
  onCadenceStateChange?(prev: SchedulerCadenceState, next: SchedulerCadenceState, snapshot: SchedulerSnapshot): void
}

export class VehicleActionScheduler {
  private nextCommandEarliestAtMs: number = 0
  private currentActionWindow?: ScheduledActionWindow = undefined
  private callbacks?: VehicleActionSchedulerCallbacks
  private lastCadenceState: SchedulerCadenceState = SchedulerCadenceState.IDLE

  setCallbacks(callbacks?: VehicleActionSchedulerCallbacks): void {
    this.callbacks = callbacks
  }

  reset(): void {
    const nowMs: number = Date.now()
    const prev: ScheduledActionWindow | undefined = this.currentActionWindow
    this.nextCommandEarliestAtMs = 0
    this.currentActionWindow = undefined
    const snap: SchedulerSnapshot = this.snapshot(nowMs, false)
    if (prev && this.callbacks && this.callbacks.onActionWindowClear) {
      this.callbacks.onActionWindowClear(prev, snap)
    }
    this.emitCadenceChangeIfNeeded(snap.cadenceState, snap)
    if (this.callbacks && this.callbacks.onReset) this.callbacks.onReset(snap)
  }

  canSendNextCommand(nowMs: number, motionRunning: boolean): boolean {
    const snap: SchedulerSnapshot = this.snapshot(nowMs, motionRunning)
    return snap.canSend
  }

  snapshot(nowMs: number, motionRunning: boolean): SchedulerSnapshot {
    this.expireActionWindowIfNeeded(nowMs, motionRunning)
    const cadenceState: SchedulerCadenceState = this.resolveCadenceState(nowMs, motionRunning)
    const remainingGapMs: number = Math.max(0, this.nextCommandEarliestAtMs - nowMs)
    const canSend: boolean = cadenceState === SchedulerCadenceState.READY || cadenceState === SchedulerCadenceState.IDLE

    const snap: SchedulerSnapshot = {
      nowMs: nowMs,
      cadenceState: cadenceState,
      motionRunning: motionRunning,
      canSend: canSend,
      nextCommandEarliestAtMs: this.nextCommandEarliestAtMs,
      remainingGapMs: remainingGapMs,
      currentActionWindow: this.currentActionWindow
    }
    this.emitCadenceChangeIfNeeded(cadenceState, snap)
    return snap
  }

  setNextCommandGapFromNow(gapMs: number): void {
    const nowMs: number = Date.now()
    const prev: ScheduledActionWindow | undefined = this.currentActionWindow
    this.nextCommandEarliestAtMs = nowMs + gapMs
    this.currentActionWindow = undefined
    const snap: SchedulerSnapshot = this.snapshot(nowMs, false)
    if (prev && this.callbacks && this.callbacks.onActionWindowClear) {
      this.callbacks.onActionWindowClear(prev, snap)
    }
  }

  setNextCommandEarliestAtMs(tsMs: number): void {
    const nowMs: number = Date.now()
    this.nextCommandEarliestAtMs = tsMs
    if (nowMs >= tsMs) {
      const prev: ScheduledActionWindow | undefined = this.currentActionWindow
      this.currentActionWindow = undefined
      if (prev) {
        const snap: SchedulerSnapshot = this.snapshot(nowMs, false)
        if (this.callbacks && this.callbacks.onActionWindowClear) {
          this.callbacks.onActionWindowClear(prev, snap)
        }
      }
    }
  }

  getNextCommandEarliestAtMs(): number {
    return this.nextCommandEarliestAtMs
  }

  currentAction(): ScheduledActionWindow | undefined {
    return this.currentActionWindow
  }

  private resolveCadenceState(nowMs: number, motionRunning: boolean): SchedulerCadenceState {
    if (motionRunning) return SchedulerCadenceState.BLOCKED_BY_MOTION
    if (nowMs < this.nextCommandEarliestAtMs) return SchedulerCadenceState.WAITING_GAP
    if (this.nextCommandEarliestAtMs <= 0) return SchedulerCadenceState.IDLE
    return SchedulerCadenceState.READY
  }

  private emitCadenceChangeIfNeeded(next: SchedulerCadenceState, snap: SchedulerSnapshot): void {
    const prev: SchedulerCadenceState = this.lastCadenceState
    if (prev === next) return
    this.lastCadenceState = next
    if (this.callbacks && this.callbacks.onCadenceStateChange) {
      this.callbacks.onCadenceStateChange(prev, next, snap)
    }
  }

  private expireActionWindowIfNeeded(nowMs: number, motionRunning: boolean): void {
    if (!this.currentActionWindow) return
    if (nowMs < this.currentActionWindow.nextSendAtMs) return
    const expired: ScheduledActionWindow = this.currentActionWindow
    this.currentActionWindow = undefined
    if (this.callbacks && this.callbacks.onActionWindowClear) {
      const preview: SchedulerSnapshot = {
        nowMs: nowMs,
        cadenceState: this.resolveCadenceState(nowMs, motionRunning),
        motionRunning: motionRunning,
        canSend: !motionRunning && nowMs >= this.nextCommandEarliestAtMs,
        nextCommandEarliestAtMs: this.nextCommandEarliestAtMs,
        remainingGapMs: Math.max(0, this.nextCommandEarliestAtMs - nowMs),
        currentActionWindow: undefined
      }
      this.callbacks.onActionWindowClear(expired, preview)
    }
  }

  private markActionWindow(action: Page1Action, fromId: string, toId: string, startedAtMs: number, sendGapMs: number): void {
    const gap: number = Math.max(0, sendGapMs)
    const nextSendAtMs: number = startedAtMs + gap
    const prev: ScheduledActionWindow | undefined = this.currentActionWindow
    this.nextCommandEarliestAtMs = nextSendAtMs
    const window: ScheduledActionWindow = {
      action: action,
      fromId: fromId,
      toId: toId,
      startedAtMs: startedAtMs,
      sendGapMs: gap,
      nextSendAtMs: nextSendAtMs
    }
    this.currentActionWindow = window

    const snap: SchedulerSnapshot = this.snapshot(startedAtMs, false)
    if (prev && this.callbacks && this.callbacks.onActionWindowClear) {
      this.callbacks.onActionWindowClear(prev, snap)
    }
    if (this.callbacks && this.callbacks.onActionWindowStart) {
      this.callbacks.onActionWindowStart(window, snap)
    }
  }

  async sendAutoActionWithTiming(req: SendAutoActionRequest, deps: VehicleActionSchedulerDeps): Promise<boolean> {
    const sent: boolean = await deps.sendDriveActionDirect(req.action)
    if (!sent) return false

    const startAtMs: number = Date.now()

    const timing: MotionTimingProfile = req.customTiming ? req.customTiming : deps.timingRegistry.timingForAction(req.action)
    this.markActionWindow(req.action, req.fromId, req.toId, startAtMs, timing.sendGapMs)

    deps.motionPlayer.begin({
      action: req.action,
      fromId: req.fromId,
      toId: req.toId,
      startAtMs: startAtMs,
      nextAction: req.nextAction,
      customTiming: timing,
      advancePathOnFinish: req.advancePathOnFinish,
      useReverseSpeed: req.useReverseSpeed,
      customLogTag: req.customLogTag
    }, deps.motionHooks)
    return true
  }

  beginMotionOnlyWithTiming(req: SendAutoActionRequest, deps: VehicleActionSchedulerDeps): void {
    const startAtMs: number = Date.now()
    const timing: MotionTimingProfile = req.customTiming ? req.customTiming : deps.timingRegistry.timingForAction(req.action)
    this.markActionWindow(req.action, req.fromId, req.toId, startAtMs, timing.sendGapMs)

    deps.motionPlayer.begin({
      action: req.action,
      fromId: req.fromId,
      toId: req.toId,
      startAtMs: startAtMs,
      nextAction: req.nextAction,
      customTiming: timing,
      advancePathOnFinish: req.advancePathOnFinish,
      useReverseSpeed: req.useReverseSpeed,
      customLogTag: req.customLogTag
    }, deps.motionHooks)
  }
}


