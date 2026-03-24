/**
 * 代码指南：
 * 文件：pages/page1/app/VehicleMotionPlayer.ets
 * 用途：Page1 协调/调度辅助逻辑。
 * 何时修改：相关行为或契约变化时。
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/VehicleMotionPlayer.ets
 * 用途： 运动播放引擎，负责动作阶段推进、事件回调与节拍执行。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * VehicleMotionPlayer
 * 播放模拟车辆运动时间线，包含 PRE/ACTIVE/POST 阶段。
 */
import { Page1Action } from '../types/Page1Types'
import { ActionTimingRegistry, MotionTimingProfile } from './ActionTimingRegistry'

export enum MotionPhase {
  IDLE = 0,
  PRE = 1,
  ACTIVE = 2,
  POST = 3
}

export interface MotionPoint {
  xNorm: number
  yNorm: number
}

export interface BeginMotionParams {
  action: Page1Action
  fromId: string
  toId: string
  startAtMs: number
  nextAction?: Page1Action
  customTiming?: MotionTimingProfile
  advancePathOnFinish?: boolean
  useReverseSpeed?: boolean
  customLogTag?: string
}

export interface VehicleMotionHooks {
  findNode(id: string): MotionPoint | undefined
  updatePoseAndTelemetryForDisplay(xNorm: number, yNorm: number, headingDeg: number, speed: number): void
  updateHeadingOnlyAtCurrentPose(headingDeg: number): void
  segmentHeadingDeg(fromId: string, toId: string): number
  getLogicalHeadingDeg(): number
  setLogicalHeadingDeg(headingDeg: number): void
  maybeHandleMotionArrive(toId: string): Promise<void>
  headingErrorDeg(curDeg: number, desiredDeg: number): number
  norm360(v: number): number
}

export interface MotionPhaseTuning {
  preScale?: number
  activeScale?: number
  postScale?: number
  preOffsetMs?: number
  activeOffsetMs?: number
  postOffsetMs?: number
  minPhaseMs?: number
}

export interface MotionStateSnapshot {
  nowMs: number
  running: boolean
  phase: MotionPhase
  action?: Page1Action
  fromId: string
  toId: string
  startAtMs: number
  elapsedMs: number
  preMs: number
  activeMs: number
  postMs: number
  totalMs: number
  remainingMs: number
  progress: number
  headingFromDeg: number
  headingToDeg: number
  advancePathOnFinish: boolean
  arriveHandled: boolean
  useReverseSpeed: boolean
  customLogTag: string
}

export interface MotionPhaseChangedEvent {
  nowMs: number
  prevPhase: MotionPhase
  nextPhase: MotionPhase
  snapshot: MotionStateSnapshot
}

export interface VehicleMotionPlayerCallbacks {
  onBegin?(snapshot: MotionStateSnapshot): void
  onPhaseChanged?(event: MotionPhaseChangedEvent): void
  onTick?(snapshot: MotionStateSnapshot): void
  onArriveHandled?(snapshot: MotionStateSnapshot): void
  onComplete?(snapshot: MotionStateSnapshot): void
  onReset?(snapshot: MotionStateSnapshot): void
}

export class VehicleMotionPlayer {
  private motionPhase: MotionPhase = MotionPhase.IDLE
  private motionAction?: Page1Action = undefined
  private motionFromId: string = ''
  private motionToId: string = ''
  private motionStartAtMs: number = 0
  private motionPreMs: number = 0
  private motionActiveMs: number = 0
  private motionPostMs: number = 0
  private motionHeadingFromDeg: number = 0
  private motionHeadingToDeg: number = 0
  private motionAdvancePathOnFinish: boolean = false
  private motionArriveHandled: boolean = false
  private motionUseReverseSpeed: boolean = false
  private motionCustomLogTag: string = ''
  private callbacks?: VehicleMotionPlayerCallbacks
  private phaseTuning: MotionPhaseTuning = {}

  constructor(private readonly timingRegistry: ActionTimingRegistry) {}

  setCallbacks(callbacks?: VehicleMotionPlayerCallbacks): void {
    this.callbacks = callbacks
  }

  setPhaseTuning(tuning?: MotionPhaseTuning): void {
    this.phaseTuning = tuning ? tuning : {}
  }

  private isTurnAction(a: Page1Action | undefined): boolean {
    return a === Page1Action.LEFT || a === Page1Action.RIGHT || a === Page1Action.UTURN
  }

  private isMoveAction(a: Page1Action | undefined): boolean {
    return a === Page1Action.GO || a === Page1Action.BACK
  }

  private shouldSkipPostMs(current: Page1Action, next?: Page1Action): boolean {
    if (next === undefined) return false
    if (current === Page1Action.GO && next === Page1Action.GO) return true
    if (this.isTurnAction(current) && this.isTurnAction(next)) return true
    return false
  }

  private tunePhaseMs(baseMs: number, scale: number, offset: number, minMs: number): number {
    const scaled: number = Math.round(baseMs * scale + offset)
    if (scaled < minMs) return minMs
    return scaled
  }

  private applyPhaseTuning(timing: MotionTimingProfile): MotionTimingProfile {
    const t: MotionPhaseTuning = this.phaseTuning
    const minMs: number = Math.max(0, t.minPhaseMs !== undefined ? t.minPhaseMs : 0)
    const preScale: number = t.preScale !== undefined ? t.preScale : 1.0
    const activeScale: number = t.activeScale !== undefined ? t.activeScale : 1.0
    const postScale: number = t.postScale !== undefined ? t.postScale : 1.0
    const preOffset: number = t.preOffsetMs !== undefined ? t.preOffsetMs : 0
    const activeOffset: number = t.activeOffsetMs !== undefined ? t.activeOffsetMs : 0
    const postOffset: number = t.postOffsetMs !== undefined ? t.postOffsetMs : 0

    return {
      preMs: this.tunePhaseMs(timing.preMs, preScale, preOffset, minMs),
      activeMs: this.tunePhaseMs(timing.activeMs, activeScale, activeOffset, minMs),
      postMs: this.tunePhaseMs(timing.postMs, postScale, postOffset, minMs),
      sendGapMs: timing.sendGapMs
    }
  }

  snapshot(nowMs: number): MotionStateSnapshot {
    const running: boolean = this.motionPhase !== MotionPhase.IDLE && this.motionAction !== undefined
    const elapsedMs: number = running ? Math.max(0, nowMs - this.motionStartAtMs) : 0
    const totalMs: number = this.motionPreMs + this.motionActiveMs + this.motionPostMs
    const remainingMs: number = running ? Math.max(0, totalMs - elapsedMs) : 0
    const progress: number = totalMs > 0 ? Math.min(1, Math.max(0, elapsedMs / totalMs)) : (running ? 0 : 1)

    return {
      nowMs: nowMs,
      running: running,
      phase: this.motionPhase,
      action: this.motionAction,
      fromId: this.motionFromId,
      toId: this.motionToId,
      startAtMs: this.motionStartAtMs,
      elapsedMs: elapsedMs,
      preMs: this.motionPreMs,
      activeMs: this.motionActiveMs,
      postMs: this.motionPostMs,
      totalMs: totalMs,
      remainingMs: remainingMs,
      progress: progress,
      headingFromDeg: this.motionHeadingFromDeg,
      headingToDeg: this.motionHeadingToDeg,
      advancePathOnFinish: this.motionAdvancePathOnFinish,
      arriveHandled: this.motionArriveHandled,
      useReverseSpeed: this.motionUseReverseSpeed,
      customLogTag: this.motionCustomLogTag
    }
  }

  private emitPhaseChanged(prev: MotionPhase, next: MotionPhase, nowMs: number): void {
    if (prev === next) return
    if (!this.callbacks || !this.callbacks.onPhaseChanged) return
    this.callbacks.onPhaseChanged({
      nowMs: nowMs,
      prevPhase: prev,
      nextPhase: next,
      snapshot: this.snapshot(nowMs)
    })
  }

  private setPhase(next: MotionPhase, nowMs: number): void {
    const prev: MotionPhase = this.motionPhase
    this.motionPhase = next
    this.emitPhaseChanged(prev, next, nowMs)
  }

  private doReset(nowMs: number, emit: boolean): void {
    const wasRunning: boolean = this.running()
    this.motionPhase = MotionPhase.IDLE
    this.motionAction = undefined
    this.motionFromId = ''
    this.motionToId = ''
    this.motionStartAtMs = 0
    this.motionPreMs = 0
    this.motionActiveMs = 0
    this.motionPostMs = 0
    this.motionHeadingFromDeg = 0
    this.motionHeadingToDeg = 0
    this.motionAdvancePathOnFinish = false
    this.motionArriveHandled = false
    this.motionUseReverseSpeed = false
    this.motionCustomLogTag = ''

    if (emit && wasRunning && this.callbacks && this.callbacks.onReset) {
      this.callbacks.onReset(this.snapshot(nowMs))
    }
  }

  reset(): void {
    this.doReset(Date.now(), true)
  }

  running(): boolean {
    return this.motionPhase !== MotionPhase.IDLE && this.motionAction !== undefined
  }

  currentAction(): Page1Action | undefined {
    return this.motionAction
  }

  currentFromId(): string {
    return this.motionFromId
  }

  currentToId(): string {
    return this.motionToId
  }

  usesReverseSpeed(): boolean {
    return this.motionUseReverseSpeed
  }

  begin(params: BeginMotionParams, hooks: VehicleMotionHooks): void {
    const baseTiming: MotionTimingProfile = params.customTiming ? params.customTiming : this.timingRegistry.timingForAction(params.action)
    const tunedTiming: MotionTimingProfile = this.applyPhaseTuning(baseTiming)
    const actualPostMs: number = this.shouldSkipPostMs(params.action, params.nextAction) ? 0 : tunedTiming.postMs
    const nowMs: number = params.startAtMs

    const prevPhase: MotionPhase = this.motionPhase
    this.motionAction = params.action
    this.motionFromId = params.fromId
    this.motionToId = params.toId
    this.motionStartAtMs = params.startAtMs
    this.motionPreMs = tunedTiming.preMs
    this.motionActiveMs = tunedTiming.activeMs
    this.motionPostMs = actualPostMs
    this.motionAdvancePathOnFinish = params.advancePathOnFinish === true
    this.motionArriveHandled = false
    this.motionUseReverseSpeed = params.useReverseSpeed === true
    this.motionCustomLogTag = params.customLogTag ? params.customLogTag : ''

    this.motionHeadingFromDeg = hooks.getLogicalHeadingDeg()
    if (this.isTurnAction(params.action) || this.isMoveAction(params.action)) {
      this.motionHeadingToDeg = hooks.segmentHeadingDeg(params.fromId, params.toId)
    } else {
      this.motionHeadingToDeg = hooks.getLogicalHeadingDeg()
    }

    this.motionPhase = MotionPhase.PRE
    this.emitPhaseChanged(prevPhase, MotionPhase.PRE, nowMs)

    if (this.callbacks && this.callbacks.onBegin) {
      this.callbacks.onBegin(this.snapshot(nowMs))
    }
  }

  private async maybeHandleMotionArrive(hooks: VehicleMotionHooks): Promise<void> {
    if (!this.motionAdvancePathOnFinish) return
    if (this.motionArriveHandled) return
    this.motionArriveHandled = true
    await hooks.maybeHandleMotionArrive(this.motionToId)
    if (this.callbacks && this.callbacks.onArriveHandled) {
      this.callbacks.onArriveHandled(this.snapshot(Date.now()))
    }
  }

  async update(nowMs: number, hooks: VehicleMotionHooks): Promise<void> {
    if (!this.running() || this.motionAction === undefined) return

    const fromNode: MotionPoint | undefined = hooks.findNode(this.motionFromId)
    const toNode: MotionPoint | undefined = hooks.findNode(this.motionToId)
    const elapsedMs: number = nowMs - this.motionStartAtMs
    const preEndMs: number = this.motionPreMs
    const activeEndMs: number = this.motionPreMs + this.motionActiveMs
    const postEndMs: number = this.motionPreMs + this.motionActiveMs + this.motionPostMs

    if (elapsedMs < preEndMs) {
      this.setPhase(MotionPhase.PRE, nowMs)
      if (this.isMoveAction(this.motionAction)) {
        if (fromNode) {
          const speed: number = this.motionUseReverseSpeed ? -20 : 0
          hooks.updatePoseAndTelemetryForDisplay(
            fromNode.xNorm,
            fromNode.yNorm,
            this.motionHeadingToDeg,
            speed === 0 ? 0 : speed
          )
        }
      } else if (this.isTurnAction(this.motionAction)) {
        hooks.updateHeadingOnlyAtCurrentPose(this.motionHeadingFromDeg)
      }
      if (this.callbacks && this.callbacks.onTick) this.callbacks.onTick(this.snapshot(nowMs))
      return
    }

    if (elapsedMs < activeEndMs) {
      this.setPhase(MotionPhase.ACTIVE, nowMs)

      let activeT: number = 1
      if (this.motionActiveMs > 0) {
        activeT = (elapsedMs - preEndMs) / this.motionActiveMs
      }
      if (activeT < 0) activeT = 0
      if (activeT > 1) activeT = 1

      if (this.motionAction === Page1Action.GO || this.motionAction === Page1Action.BACK) {
        if (fromNode && toNode) {
          const xNorm: number = fromNode.xNorm + (toNode.xNorm - fromNode.xNorm) * activeT
          const yNorm: number = fromNode.yNorm + (toNode.yNorm - fromNode.yNorm) * activeT
          const speed: number = this.motionAction === Page1Action.BACK || this.motionUseReverseSpeed ? -20 : 20
          hooks.updatePoseAndTelemetryForDisplay(xNorm, yNorm, this.motionHeadingToDeg, speed)
        }
      } else if (this.isTurnAction(this.motionAction)) {
        const headingDeg: number = hooks.norm360(
          this.motionHeadingFromDeg + hooks.headingErrorDeg(this.motionHeadingFromDeg, this.motionHeadingToDeg) * activeT
        )
        hooks.updateHeadingOnlyAtCurrentPose(headingDeg)
      }
      if (this.callbacks && this.callbacks.onTick) this.callbacks.onTick(this.snapshot(nowMs))
      return
    }

    if (elapsedMs < postEndMs) {
      this.setPhase(MotionPhase.POST, nowMs)

      if (this.motionAction === Page1Action.GO || this.motionAction === Page1Action.BACK) {
        if (toNode) {
          hooks.updatePoseAndTelemetryForDisplay(toNode.xNorm, toNode.yNorm, this.motionHeadingToDeg, 0)
        }
        await this.maybeHandleMotionArrive(hooks)
      } else if (this.isTurnAction(this.motionAction)) {
        hooks.updateHeadingOnlyAtCurrentPose(this.motionHeadingToDeg)
        hooks.setLogicalHeadingDeg(this.motionHeadingToDeg)
      }
      if (this.callbacks && this.callbacks.onTick) this.callbacks.onTick(this.snapshot(nowMs))
      return
    }

    if (this.motionAction === Page1Action.GO || this.motionAction === Page1Action.BACK) {
      if (toNode) {
        hooks.updatePoseAndTelemetryForDisplay(toNode.xNorm, toNode.yNorm, this.motionHeadingToDeg, 0)
      }
      hooks.setLogicalHeadingDeg(this.motionHeadingToDeg)
      await this.maybeHandleMotionArrive(hooks)
    } else if (this.isTurnAction(this.motionAction)) {
      hooks.setLogicalHeadingDeg(this.motionHeadingToDeg)
      hooks.updateHeadingOnlyAtCurrentPose(this.motionHeadingToDeg)
    }

    if (this.callbacks && this.callbacks.onComplete) {
      this.callbacks.onComplete(this.snapshot(nowMs))
    }
    this.doReset(nowMs, true)
  }
}


