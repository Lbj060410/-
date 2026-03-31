export interface EmergencyState {
  motionCommandBlockUntilMs: number
  motionCommandBlockReason: string
  motionCommandBlockLastLogAtMs: number
  emergencyAlarmBurstActive: boolean
  emergencyAlarmBurstAckAtMs: number
  emergencyAlarmBurstLastSendAtMs: number
  yolov26barrierEmergencyBusy: boolean
  emergencyRecoverBypassUntilMs: number
  emergencyMotionCommandLocked: boolean
  emergencyCommandSeq: number
  emergencyPendingReplan: boolean
  emergencyPendingBlockedEdgeId: string
  lastYolov26BarrierEmergencyTaskId: string
  lastYolov26BarrierEmergencyTsMs: number
}

export function createEmergencyState(): EmergencyState {
  return {
    motionCommandBlockUntilMs: 0,
    motionCommandBlockReason: '',
    motionCommandBlockLastLogAtMs: 0,
    emergencyAlarmBurstActive: false,
    emergencyAlarmBurstAckAtMs: 0,
    emergencyAlarmBurstLastSendAtMs: 0,
    yolov26barrierEmergencyBusy: false,
    emergencyRecoverBypassUntilMs: 0,
    emergencyMotionCommandLocked: false,
    emergencyCommandSeq: 0,
    emergencyPendingReplan: false,
    emergencyPendingBlockedEdgeId: '',
    lastYolov26BarrierEmergencyTaskId: '',
    lastYolov26BarrierEmergencyTsMs: 0
  }
}
