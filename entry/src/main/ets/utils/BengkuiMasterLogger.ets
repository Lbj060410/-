import hilog from '@ohos.hilog'

const BENGKUI_MASTER_DOMAIN: number = 0xFF0B
const BENGKUI_MASTER_TAG: string = 'bengkuimaster'
const BENGKUI_MASTER_THROTTLE_MS: number = 3000
const BENGKUI_MASTER_MAX_TEXT_LEN: number = 900
const BENGKUI_MASTER_MAX_KEYS: number = 256

const recentLogAtBySig: Record<string, number> = {}
let recentLogKeyCount: number = 0

type BengkuiErrLike = Object | string | number | boolean | undefined | null

function normalizeText(raw: string): string {
  const oneLine: string = raw.replace(/\r/g, ' ').replace(/\n/g, ' ')
  if (oneLine.length <= BENGKUI_MASTER_MAX_TEXT_LEN) return oneLine
  return `${oneLine.substring(0, BENGKUI_MASTER_MAX_TEXT_LEN)}...(truncated)`
}

export function bengkuiMasterErrText(err: BengkuiErrLike): string {
  if (err === undefined || err === null) return 'unknown'
  if (err instanceof Error) {
    const msg: string = err.message.trim().length > 0 ? err.message.trim() : 'Error(no-message)'
    const stackText: string = typeof err.stack === 'string' ? err.stack.trim() : ''
    if (stackText.length > 0) return normalizeText(`${msg} | ${stackText}`)
    return normalizeText(msg)
  }
  try {
    const txt: string = JSON.stringify(err)
    if (txt.length > 0 && txt !== '{}') return normalizeText(txt)
  } catch (_) {}
  return normalizeText(String(err))
}

export function isBengkuiIgnorableCameraHttpError(err: BengkuiErrLike): boolean {
  const text: string = bengkuiMasterErrText(err).toLowerCase()
  if (text.length <= 0) return false
  if (text.indexOf('code=2300028') >= 0) return true
  if (text.indexOf('timeout was reached') >= 0) return true
  if (text.indexOf('code=2300056') >= 0) return true
  if (text.indexOf('failure when receiving data from the peer') >= 0) return true
  return false
}

function shouldLog(sig: string): boolean {
  const nowMs: number = Date.now()
  const lastAtMs: number = recentLogAtBySig[sig] ?? 0
  if (lastAtMs > 0 && nowMs - lastAtMs < BENGKUI_MASTER_THROTTLE_MS) {
    return false
  }
  recentLogAtBySig[sig] = nowMs
  if (lastAtMs <= 0) {
    recentLogKeyCount += 1
    if (recentLogKeyCount > BENGKUI_MASTER_MAX_KEYS) {
      const keys: Array<string> = Object.keys(recentLogAtBySig)
      for (let i: number = 0; i < keys.length; i++) {
        delete recentLogAtBySig[keys[i]]
      }
      recentLogKeyCount = 0
    }
  }
  return true
}

export function bengkuiMasterError(scene: string, err?: BengkuiErrLike, extra: string = ''): void {
  const sceneText: string = scene.trim().length > 0 ? scene.trim() : 'unknown-scene'
  const errText: string = bengkuiMasterErrText(err)
  const extraText: string = extra.trim()
  const sig: string = normalizeText(`${sceneText}|${errText}|${extraText}`)
  if (!shouldLog(sig)) return

  let msg: string = `[${sceneText}] err=${errText}`
  if (extraText.length > 0) msg += ` | ${normalizeText(extraText)}`
  try {
    hilog.error(BENGKUI_MASTER_DOMAIN, BENGKUI_MASTER_TAG, '%{public}s', msg)
  } catch (_) {
    try { console.error(msg) } catch (_) {}
  }
}
