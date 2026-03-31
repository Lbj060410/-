import { PendingAckMotion } from './Page1CoordinatorDefs'

export interface PathAckState {
  pathAckFirstCommandSent: boolean
  pathAckAwaitingComplete: boolean
  pathAckBlocked: boolean
  pathAckLastSendAtMs: number
  pathAckLastStatusCode: number
  pathAckLastStatusAtMs: number
  pathAckLastCommandText: string
  pathAckLastWaitLogAtMs: number
  pathAckRetrySentCount: number
  pathAckCommandKey: string
  pathAckCommandSeq: number
  pendingAckMotion?: PendingAckMotion
  suppressNextAckCompleteMotion: boolean
  suppressAckCompleteEdgeId: string
  pendingDrivingUltrasonicObstacleEdgeId: string
  pendingDrivingUltrasonicObstacleAtMs: number
}

export function createPathAckState(): PathAckState {
  return {
    pathAckFirstCommandSent: false,
    pathAckAwaitingComplete: false,
    pathAckBlocked: false,
    pathAckLastSendAtMs: 0,
    pathAckLastStatusCode: 0,
    pathAckLastStatusAtMs: 0,
    pathAckLastCommandText: '',
    pathAckLastWaitLogAtMs: 0,
    pathAckRetrySentCount: 0,
    pathAckCommandKey: '',
    pathAckCommandSeq: 0,
    pendingAckMotion: undefined,
    suppressNextAckCompleteMotion: false,
    suppressAckCompleteEdgeId: '',
    pendingDrivingUltrasonicObstacleEdgeId: '',
    pendingDrivingUltrasonicObstacleAtMs: 0
  }
}
