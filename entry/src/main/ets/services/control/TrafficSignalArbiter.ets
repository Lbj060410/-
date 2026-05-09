import { CarProtocolService } from './CarProtocolService'

export type TrafficSignalToken = 'R' | 'G'
export type TrafficSignalSource = 'GATE' | 'BYPASS'

export interface TrafficSignalSendResult {
  sent: boolean
  reason: string
}

class TrafficSignalArbiter {
  private gateSessionActive: boolean = false
  private gateSessionKey: string = ''
  private lastToken: string = ''
  private lastSentAtMs: number = 0
  private sending: boolean = false

  beginGateSession(key: string): void {
    const k: string = key.trim().toUpperCase()
    if (k.length <= 0) return
    this.gateSessionActive = true
    this.gateSessionKey = k
  }

  endGateSession(): void {
    this.gateSessionActive = false
    this.gateSessionKey = ''
  }

  isGateSessionActive(): boolean {
    return this.gateSessionActive
  }

  async send(
    proto: CarProtocolService,
    token: TrafficSignalToken,
    source: TrafficSignalSource,
    minIntervalMs: number
  ): Promise<TrafficSignalSendResult> {
    if (this.sending) return { sent: false, reason: 'busy' }
    if (source === 'BYPASS' && this.gateSessionActive) {
      return { sent: false, reason: `gate-session-active:${this.gateSessionKey}` }
    }
    const nowMs: number = Date.now()
    if (token === this.lastToken && (nowMs - this.lastSentAtMs) < minIntervalMs) {
      return { sent: false, reason: 'min-interval' }
    }
    this.sending = true
    try {
      if (token === 'R') {
        await proto.SendTrafficRedOrYellow(false)
      } else {
        await proto.SendTrafficGreen(false)
      }
      this.lastToken = token
      this.lastSentAtMs = nowMs
      return { sent: true, reason: 'ok' }
    } finally {
      this.sending = false
    }
  }
}

export const trafficSignalArbiter: TrafficSignalArbiter = new TrafficSignalArbiter()
