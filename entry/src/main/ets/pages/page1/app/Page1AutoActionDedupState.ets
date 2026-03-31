export interface AutoActionDedupState {
  lastAutoActionFingerprint: string
  lastAutoActionDedupLogAtMs: number
}

export function createAutoActionDedupState(): AutoActionDedupState {
  return {
    lastAutoActionFingerprint: '',
    lastAutoActionDedupLogAtMs: 0
  }
}
