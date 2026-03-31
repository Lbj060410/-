export interface ParkingState {
  parkingInProgress: boolean
  parkingSequenceToken: number
  lastUltrasonicP1: number
  lastUltrasonicAtMs: number
  parkingUltrasonicPending: boolean
  parkingUltrasonicRequestAtMs: number
  parkingUltrasonicExpireAtMs: number
  parkingAwaitingUltrasonicDecision: boolean
  parkingAwaitingArrivedId: string
  parkingAwaitingGoalId: string
  parkingAwaitingRequestedAtMs: number
  parkingUltrasonicDecisionBusy: boolean
}

export function createParkingState(): ParkingState {
  return {
    parkingInProgress: false,
    parkingSequenceToken: 0,
    lastUltrasonicP1: -1,
    lastUltrasonicAtMs: 0,
    parkingUltrasonicPending: false,
    parkingUltrasonicRequestAtMs: 0,
    parkingUltrasonicExpireAtMs: 0,
    parkingAwaitingUltrasonicDecision: false,
    parkingAwaitingArrivedId: '',
    parkingAwaitingGoalId: '',
    parkingAwaitingRequestedAtMs: 0,
    parkingUltrasonicDecisionBusy: false
  }
}
