export interface VisionState {
  aheadVisionPending: boolean
  aheadVisionReadyAtMs: number
  aheadVisionEdgeId: string
  lastVisionLogAtMs: number
  lastYoloTriggerAtMs: number
}

export function createVisionState(): VisionState {
  return {
    aheadVisionPending: false,
    aheadVisionReadyAtMs: 0,
    aheadVisionEdgeId: '',
    lastVisionLogAtMs: 0,
    lastYoloTriggerAtMs: 0
  }
}
