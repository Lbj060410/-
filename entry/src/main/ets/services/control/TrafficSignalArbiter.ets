import { CarProtocolService } from './CarProtocolService'

export type TrafficSignalToken = 'R' | 'G'
export type TrafficSignalSource = 'GATE' | 'BYPASS'

interface SendResult {
  sent: boolean
  reason: string
}

class TrafficSignalArbiter {
  private gateSessionActive: boolean = false
  private gateSessionKey: string = ''
  private bypassPaused: boolean = false
  private bypassPauseReason: string = ''
  private busy: boolean = false
  private lastToken: string = ''
  private lastSentAtMs: number = 0

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

  setBypassPaused(paused: boolean, reason: string = ''): void {
    this.bypassPaused = paused
    this.bypassPauseReason = paused ? reason.trim() : ''
  }

  async send(
    proto: CarProtocolService,
    token: TrafficSignalToken,
    source: TrafficSignalSource,
    minIntervalMs: number
  ): Promise<SendResult> {
    if (source === 'BYPASS' && this.bypassPaused) {
      return { sent: false, reason: `bypass-paused:${this.bypassPauseReason}` }
    }
    if (source === 'BYPASS' && this.gateSessionActive) {
      return { sent: false, reason: `gate-session-active:${this.gateSessionKey}` }
    }
    if (this.busy) {
      return { sent: false, reason: 'busy' }
    }

    const nowMs: number = Date.now()
    const safeMinIntervalMs: number = Math.max(0, Math.round(minIntervalMs))
    if (safeMinIntervalMs > 0 &&
      this.lastToken === token &&
      this.lastSentAtMs > 0 &&
      (nowMs - this.lastSentAtMs) < safeMinIntervalMs) {
      return { sent: false, reason: `same-token-within-${safeMinIntervalMs}ms` }
    }

    this.busy = true
    try {
      if (token === 'R') {
        await proto.red()
      } else {
        await proto.green()
      }
      this.lastToken = token
      this.lastSentAtMs = nowMs
      return { sent: true, reason: 'sent' }
    } finally {
      this.busy = false
    }
  }
}

export const trafficSignalArbiter: TrafficSignalArbiter = new TrafficSignalArbiter()
