/**
 * 代码指南：
 * 文件：pages/page1/app/TrafficLightTracker.ets
 * 用途：Page1 协调/调度辅助逻辑。
 * 何时修改：相关行为或契约变化时。
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/TrafficLightTracker.ets
 * 用途： 维护交通灯状态时序与稳定输出，抑制抖动识别结果。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * TrafficLightTracker
 * 持续交通灯采样，带窗口投票和过期数据保护。
 */
export enum TrafficLightColor {
  UNKNOWN = 0,
  RED = 1,
  YELLOW = 2,
  GREEN = 3
}

interface TrafficLightSample {
  color: TrafficLightColor
  tsMs: number
}

export interface TrafficLightSnapshot {
  latestColor: TrafficLightColor
  latestAtMs: number
  stableColor: TrafficLightColor
  stableSinceMs: number
  sampleCount: number
  ageMs: number
  stale: boolean
  stableForMs: number
}

export interface TrafficLightTrackerOptions {
  sampleIntervalMs: number
  windowMs: number
  staleMs: number
  minKnownSamples: number
  stableRatio: number
}

export class TrafficLightTracker {
  private timerId: number = -1
  private polling: boolean = false
  private detector?: () => Promise<TrafficLightColor>
  private readonly samples: Array<TrafficLightSample> = []

  private latestColor: TrafficLightColor = TrafficLightColor.UNKNOWN
  private latestAtMs: number = 0
  private stableColor: TrafficLightColor = TrafficLightColor.UNKNOWN
  private stableSinceMs: number = 0

  constructor(private readonly opts: TrafficLightTrackerOptions) {}

  reset(): void {
    this.samples.length = 0
    this.latestColor = TrafficLightColor.UNKNOWN
    this.latestAtMs = 0
    this.stableColor = TrafficLightColor.UNKNOWN
    this.stableSinceMs = 0
  }

  start(detector: () => Promise<TrafficLightColor>): void {
    this.detector = detector
    if (this.timerId !== -1) return
    this.timerId = setInterval((): void => {
      void this.pollOnce()
    }, this.opts.sampleIntervalMs) as number
    void this.pollOnce()
  }

  stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    this.polling = false
  }

  snapshot(nowMs: number): TrafficLightSnapshot {
    const ageMs: number = this.latestAtMs > 0 ? nowMs - this.latestAtMs : Number.MAX_SAFE_INTEGER
    const stale: boolean = this.latestAtMs <= 0 || ageMs > this.opts.staleMs
    const stableColor: TrafficLightColor = stale ? TrafficLightColor.UNKNOWN : this.stableColor
    const stableSinceMs: number = stale ? 0 : this.stableSinceMs
    const stableForMs: number = stableSinceMs > 0 ? Math.max(0, nowMs - stableSinceMs) : 0

    return {
      latestColor: this.latestColor,
      latestAtMs: this.latestAtMs,
      stableColor: stableColor,
      stableSinceMs: stableSinceMs,
      sampleCount: this.samples.length,
      ageMs: ageMs,
      stale: stale,
      stableForMs: stableForMs
    }
  }

  private pruneWindow(nowMs: number): void {
    const minTs: number = nowMs - this.opts.windowMs
    while (this.samples.length > 0 && this.samples[0].tsMs < minTs) {
      this.samples.shift()
    }
  }

  private stableColorFromWindow(): TrafficLightColor {
    let red: number = 0
    let yellow: number = 0
    let green: number = 0

    for (let i: number = 0; i < this.samples.length; i++) {
      const one: TrafficLightSample = this.samples[i]
      if (one.color === TrafficLightColor.RED) red += 1
      else if (one.color === TrafficLightColor.YELLOW) yellow += 1
      else if (one.color === TrafficLightColor.GREEN) green += 1
    }

    const knownTotal: number = red + yellow + green
    if (knownTotal < this.opts.minKnownSamples) return TrafficLightColor.UNKNOWN

    let topColor: TrafficLightColor = TrafficLightColor.RED
    let topCount: number = red
    if (yellow > topCount) {
      topColor = TrafficLightColor.YELLOW
      topCount = yellow
    }
    if (green > topCount) {
      topColor = TrafficLightColor.GREEN
      topCount = green
    }

    const ratio: number = topCount / knownTotal
    if (ratio < this.opts.stableRatio) return TrafficLightColor.UNKNOWN
    return topColor
  }

  private async pollOnce(): Promise<void> {
    const detect: (() => Promise<TrafficLightColor>) | undefined = this.detector
    if (!detect) return
    if (this.polling) return
    this.polling = true

    try {
      const color: TrafficLightColor = await detect()
      const nowMs: number = Date.now()

      this.latestColor = color
      this.latestAtMs = nowMs
      this.samples.push({ color: color, tsMs: nowMs })
      this.pruneWindow(nowMs)

      const nextStableColor: TrafficLightColor = this.stableColorFromWindow()
      if (nextStableColor !== this.stableColor) {
        this.stableColor = nextStableColor
        this.stableSinceMs = nowMs
      }
    } finally {
      this.polling = false
    }
  }
}


