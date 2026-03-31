export interface TimingState {
  pauseUntilMs: number
  lastReplanAtMs: number
  lastYoloTriggerAtMs: number
  aheadVisionReadyAtMs: number
  lastVisionLogAtMs: number
  manualGoLastSentAtMs: number
  lastMotionCompleteAtMs: number
  pathAckLastSendAtMs: number
  pathAckLastStatusAtMs: number
  pathAckLastWaitLogAtMs: number
  pendingDrivingUltrasonicObstacleAtMs: number
  lightMetricLastQueryAtMs: number
  realSendConnectKickAtMs: number
}

export function createTimingState(): TimingState {
  return {
    pauseUntilMs: 0,
    lastReplanAtMs: 0,
    lastYoloTriggerAtMs: 0,
    aheadVisionReadyAtMs: 0,
    lastVisionLogAtMs: 0,
    manualGoLastSentAtMs: 0,
    lastMotionCompleteAtMs: 0,
    pathAckLastSendAtMs: 0,
    pathAckLastStatusAtMs: 0,
    pathAckLastWaitLogAtMs: 0,
    pendingDrivingUltrasonicObstacleAtMs: 0,
    lightMetricLastQueryAtMs: 0,
    realSendConnectKickAtMs: 0
  }
}
