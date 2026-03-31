import { GridIdCodec } from './PathPlannerAStar'
import { PendingAckMotion } from './Page1CoordinatorDefs'
import { Page1UiStore } from './Page1UiStore'

export class Page1MetricsCoordinator {
  private readonly ctx: Record<string, any>

  constructor(ctx: object) {
    this.ctx = ctx as Record<string, any>
  }

  clearMetricSpeedAnimation(): void {
    this.ctx.metricSpeedAnimToken += 1
    if (this.ctx.metricSpeedAnimTimerId >= 0) {
      clearTimeout(this.ctx.metricSpeedAnimTimerId)
      this.ctx.metricSpeedAnimTimerId = -1
    }
  }

  clearMetricHeadingAnimation(): void {
    this.ctx.metricHeadingAnimToken += 1
    if (this.ctx.metricHeadingAnimTimerId >= 0) {
      clearTimeout(this.ctx.metricHeadingAnimTimerId)
      this.ctx.metricHeadingAnimTimerId = -1
    }
  }

  clearMetricDistanceAckAnimation(): void {
    this.ctx.metricDistanceAckAnimToken += 1
    if (this.ctx.metricDistanceAckAnimTimerId >= 0) {
      clearTimeout(this.ctx.metricDistanceAckAnimTimerId)
      this.ctx.metricDistanceAckAnimTimerId = -1
    }
  }

  edgeDistanceCm(fromId: string, toId: string): number {
    const a: string = fromId.trim().toUpperCase()
    const b: string = toId.trim().toUpperCase()
    const ac = GridIdCodec.parse(a)
    const bc = GridIdCodec.parse(b)
    if (!ac || !bc) return 57

    const rowA: number = Number.parseInt(a.slice(1), 10)
    const rowB: number = Number.parseInt(b.slice(1), 10)
    const colA: string = a[0]
    const colB: string = b[0]

    if (ac.col === bc.col) {
      const topBottom: boolean =
        (rowA === 1 && rowB === 2) || (rowA === 2 && rowB === 1) ||
        (rowA === 7 && rowB === 6) || (rowA === 6 && rowB === 7)
      return topBottom ? 37 : 57
    }

    if (ac.row === bc.row) {
      const sideEdge: boolean =
        (colA === 'A' && colB === 'B') || (colA === 'B' && colB === 'A') ||
        (colA === 'G' && colB === 'F') || (colA === 'F' && colB === 'G')
      return sideEdge ? 47 : 71
    }
    return 57
  }

  pendingAckDistanceInfo(): { key: string, segCm: number } | undefined {
    const req: PendingAckMotion | undefined = this.ctx.pendingAckMotion
    if (!req) return undefined
    const fromId: string = req.fromId.trim().toUpperCase()
    const toId: string = req.toId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(fromId) || !GridIdCodec.isValidId(toId)) return undefined
    const segCm: number = this.edgeDistanceCm(fromId, toId)
    return { key: `${fromId}->${toId}`, segCm: segCm }
  }

  startMetricDistanceAckRise(key: string, segCm: number): void {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    if (segCm <= 0) return
    if (this.ctx.metricDistanceAckKey === key && this.ctx.metricDistanceAckAnimTimerId >= 0) return

    this.clearMetricDistanceAckAnimation()
    this.ctx.metricDistanceAckKey = key
    this.ctx.metricDistanceAckTargetCm = this.ctx.metricDistanceTotalCm + segCm
    const token: number = this.ctx.metricDistanceAckAnimToken
    const startAtMs: number = Date.now()
    const durationMs: number = 900
    const startCm: number = this.ctx.metricDistanceTotalCm

    const tick = (): void => {
      if (token !== this.ctx.metricDistanceAckAnimToken) return
      const ss: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
      if (!ss) return
      const tRaw: number = (Date.now() - startAtMs) / durationMs
      const t: number = tRaw < 0 ? 0 : (tRaw > 1 ? 1 : tRaw)
      const cur: number = startCm + (this.ctx.metricDistanceAckTargetCm - startCm) * t
      ss.setMetricDistanceCm(cur)
      if (t >= 1) {
        this.ctx.metricDistanceAckAnimTimerId = -1
        return
      }
      this.ctx.metricDistanceAckAnimTimerId = setTimeout(tick, 40) as number
    }

    tick()
  }

  finalizeMetricDistanceAck(): void {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    if (this.ctx.metricDistanceAckKey.length <= 0) {
      const info = this.pendingAckDistanceInfo()
      if (!info) return
      this.ctx.metricDistanceTotalCm += info.segCm
      s.setMetricDistanceCm(this.ctx.metricDistanceTotalCm)
      return
    }
    this.clearMetricDistanceAckAnimation()
    this.ctx.metricDistanceTotalCm = this.ctx.metricDistanceAckTargetCm
    s.setMetricDistanceCm(this.ctx.metricDistanceTotalCm)
    this.ctx.metricDistanceAckKey = ''
    this.ctx.metricDistanceAckTargetCm = this.ctx.metricDistanceTotalCm
  }

  startMetricSpeedRiseAndHoldFromAck01(targetSpeedCms: number): void {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    const target: number = Number.isFinite(targetSpeedCms) ? Math.max(0, targetSpeedCms) : 0
    if (target <= 0) return
    this.clearMetricSpeedAnimation()
    const token: number = this.ctx.metricSpeedAnimToken
    const startAtMs: number = Date.now()
    const riseMs: number = 420

    const tick = (): void => {
      if (token !== this.ctx.metricSpeedAnimToken) return
      const ss: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
      if (!ss) return
      const elapsedMs: number = Date.now() - startAtMs
      let speedCms: number = 0
      if (elapsedMs < riseMs) speedCms = target * (elapsedMs / riseMs)
      else speedCms = target
      if (speedCms < 0) speedCms = 0
      ss.setMetricSpeedCms(speedCms)
      this.ctx.metricSpeedAnimTimerId = setTimeout(tick, 40) as number
    }

    tick()
  }

  animateMetricHeadingTo(headingDeg: number): void {
    const s: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
    if (!s) return
    this.ctx.metricHeadingTargetDeg = this.ctx.normToEightHeading(headingDeg)
    if (this.ctx.metricHeadingAnimTimerId >= 0) return
    const token: number = this.ctx.metricHeadingAnimToken
    const tick = (): void => {
      if (token !== this.ctx.metricHeadingAnimToken) return
      const ss: Page1UiStore | undefined = this.ctx.store as Page1UiStore | undefined
      if (!ss) return
      const cur: number = ss.metricHeadingDeg
      const target: number = this.ctx.metricHeadingTargetDeg
      const err: number = this.ctx.headingErrorDeg(cur, target)
      const absErr: number = Math.abs(err)
      if (absErr <= 1) {
        ss.setMetricHeadingDeg(target)
        this.ctx.metricHeadingAnimTimerId = -1
        return
      }
      const maxStepDeg: number = 10
      const stepDeg: number = absErr <= maxStepDeg ? err : (err > 0 ? maxStepDeg : -maxStepDeg)
      ss.setMetricHeadingDeg(this.ctx.norm360(cur + stepDeg))
      this.ctx.metricHeadingAnimTimerId = setTimeout(tick, 40) as number
    }
    this.ctx.metricHeadingAnimTimerId = setTimeout(tick, 40) as number
  }
}
