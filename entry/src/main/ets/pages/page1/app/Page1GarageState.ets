export interface GarageState {
  gateDepartInProgress: boolean
  gateDepartLastSentKey: string
  gateDepartLastSentAtMs: number
  garageDepartStopSent: boolean
  garageDepartReady03: boolean
  garageDepartAckRetryCount: number
  garageFinalCarportSent: boolean
  garageWaitingParkDone04: boolean
  garagePendingCarportLevel: number
  garageCarportAckPending: boolean
  garageCarportAckRetryDone: boolean
  garageCarportAckPendingLevel: number
  garageCarportAckSentAtMs: number
  trafficGateWaiting: boolean
  trafficGateEdgeKey: string
  trafficGateLastLogAtMs: number
  gateBillingRunning: boolean
  gateBillingStartAtMs: number
  gateBillingElapsedMs: number
}

export function createGarageState(): GarageState {
  return {
    gateDepartInProgress: false,
    gateDepartLastSentKey: '',
    gateDepartLastSentAtMs: 0,
    garageDepartStopSent: false,
    garageDepartReady03: false,
    garageDepartAckRetryCount: 0,
    garageFinalCarportSent: false,
    garageWaitingParkDone04: false,
    garagePendingCarportLevel: 0,
    garageCarportAckPending: false,
    garageCarportAckRetryDone: false,
    garageCarportAckPendingLevel: 0,
    garageCarportAckSentAtMs: 0,
    trafficGateWaiting: false,
    trafficGateEdgeKey: '',
    trafficGateLastLogAtMs: 0,
    gateBillingRunning: false,
    gateBillingStartAtMs: 0,
    gateBillingElapsedMs: 0
  }
}
