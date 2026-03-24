/**
 * 代码指南：
 * 文件： services/recognition/LibEntryBridge.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
import * as importedLibEntry from 'libentry.so'

type LibEntryApi = {
  loadModel: (name: string, buf: ArrayBuffer) => boolean
  detectOffline: (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number) => string
  loadOnnxModel?: (name: string, buf: ArrayBuffer) => boolean
  detectOnnx?: (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number, nms: number) => string
  loadNcnnModel?: (name: string, paramBuf: ArrayBuffer, binBuf: ArrayBuffer) => boolean
  detectNcnn?: (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number, nms: number) => string
  getLastError?: () => string
  getNcnnLastError?: () => string
  detectPlate: (
    detModelName: string,
    recModelName: string,
    rgba: ArrayBuffer,
    w: number,
    h: number,
    conf: number
  ) => string
  decodeQr: (rgba: ArrayBuffer, w: number, h: number) => string
}

let cachedApi: LibEntryApi | null = null
let lastError: string = ''

function asRecord(v: Object | undefined | null): Record<string, Object> | null {
  if (v === undefined || v === null) return null
  return v as Record<string, Object>
}

function safeGet(v: Object | undefined | null, key: string): Object | undefined {
  const r = asRecord(v)
  if (!r) return undefined
  return r[key]
}

function safeType(v: Object | undefined | null, key: string): string {
  const r = asRecord(v)
  if (!r) return 'none'
  return typeof r[key]
}

function hasApi(v: Object | undefined | null): boolean {
  const mm = asRecord(v)
  if (!mm) return false
  const hasLegacyApi: boolean = typeof mm['loadModel'] === 'function' &&
    typeof mm['detectOffline'] === 'function' &&
    typeof mm['decodeQr'] === 'function'
  const hasNcnnApi: boolean = typeof mm['loadNcnnModel'] === 'function' &&
    typeof mm['detectNcnn'] === 'function'
  return hasLegacyApi || hasNcnnApi
}

function apiScore(v: Object | undefined | null): number {
  const mm = asRecord(v)
  if (!mm) return -1
  if (!hasApi(mm)) return -1
  let score: number = 1
  if (typeof mm['loadModel'] === 'function' && typeof mm['detectOffline'] === 'function') score += 1
  if (typeof mm['loadNcnnModel'] === 'function' && typeof mm['detectNcnn'] === 'function') score += 3
  if (typeof mm['getLastError'] === 'function' || typeof mm['getNcnnLastError'] === 'function') score += 2
  if (typeof mm['detectPlate'] === 'function') score += 1
  return score
}

function asApi(v: Object): LibEntryApi {
  const mm = v as Record<string, Object>
  const detectPlateObj: Object | undefined = mm['detectPlate']
  const getLastErrorObj: Object | undefined = (typeof mm['getLastError'] === 'function')
    ? mm['getLastError']
    : mm['getNcnnLastError']
  const fallbackLoadModel = (_name: string, _buf: ArrayBuffer): boolean => false
  const fallbackDetectOffline = (
    _name: string,
    _rgba: ArrayBuffer,
    _w: number,
    _h: number,
    _conf: number
  ): string => '[]'
  const fallbackDecodeQr = (_rgba: ArrayBuffer, _w: number, _h: number): string => ''
  const fallbackDetectPlate = (
    detModelName: string,
    recModelName: string,
    rgba: ArrayBuffer,
    w: number,
    h: number,
    conf: number
  ): string => {
    const payload = {
      text: '',
      score: 0.0,
      detScore: 0.0,
      x: 0.0,
      y: 0.0,
      w: 0.0,
      h: 0.0
    }
    void detModelName
    void recModelName
    void rgba
    void w
    void h
    void conf
    return JSON.stringify(payload)
  }

  return {
    loadModel: (typeof mm['loadModel'] === 'function')
      ? (mm['loadModel'] as (name: string, buf: ArrayBuffer) => boolean)
      : fallbackLoadModel,
    detectOffline: (typeof mm['detectOffline'] === 'function')
      ? (mm['detectOffline'] as (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number) => string)
      : fallbackDetectOffline,
    loadOnnxModel: (typeof mm['loadOnnxModel'] === 'function')
      ? (mm['loadOnnxModel'] as (name: string, buf: ArrayBuffer) => boolean)
      : undefined,
    detectOnnx: (typeof mm['detectOnnx'] === 'function')
      ? (mm['detectOnnx'] as (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number, nms: number) => string)
      : undefined,
    loadNcnnModel: (typeof mm['loadNcnnModel'] === 'function')
      ? (mm['loadNcnnModel'] as (name: string, paramBuf: ArrayBuffer, binBuf: ArrayBuffer) => boolean)
      : undefined,
    detectNcnn: (typeof mm['detectNcnn'] === 'function')
      ? (mm['detectNcnn'] as (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number, nms: number) => string)
      : undefined,
    getLastError: (typeof getLastErrorObj === 'function')
      ? (getLastErrorObj as () => string)
      : (): string => '',
    getNcnnLastError: (typeof mm['getNcnnLastError'] === 'function')
      ? (mm['getNcnnLastError'] as () => string)
      : undefined,
    decodeQr: (typeof mm['decodeQr'] === 'function')
      ? (mm['decodeQr'] as (rgba: ArrayBuffer, w: number, h: number) => string)
      : fallbackDecodeQr,
    detectPlate: (typeof detectPlateObj === 'function')
      ? (detectPlateObj as (
        detModelName: string,
        recModelName: string,
        rgba: ArrayBuffer,
        w: number,
        h: number,
        conf: number
      ) => string)
      : fallbackDetectPlate
  }
}

function pushCandidate(list: Object[], v: Object | undefined | null): void {
  if (v !== undefined && v !== null) {
    list.push(v)
  }
}

function tryRequireNapi(candidates: Object[]): string[] {
  const msgs: string[] = []
  const g = globalThis as Record<string, Object>
  const reqObj: Object | undefined = g['requireNapi']
  if (typeof reqObj !== 'function') {
    msgs.push('rq=missing')
    return msgs
  }

  const req = reqObj as (name: string, isSystem?: boolean) => Object | undefined | null
  const names: Array<{ tag: string, name: string }> = [
    { tag: 'e', name: 'entry' },
    { tag: 'l', name: 'libentry.so' },
    { tag: 'a', name: '@app:com.example.car/entry/entry' },
    { tag: 'b', name: '@app:com.example.car/entry/libentry.so' },
    { tag: 'c', name: '@app:com.example.car/entry/libentry' },
    { tag: 'm', name: 'entry/entry' },
    { tag: 'n', name: 'libentry' }
  ]
  for (const item of names) {
    try {
      const v = req(item.name)
      pushCandidate(candidates, v)
      const t: string = v === undefined ? 'u' : (v === null ? 'n' : (typeof v).substring(0, 1))
      msgs.push(`${item.tag}d${t}`)
    } catch (_) {
      msgs.push(`${item.tag}dx`)
    }
    try {
      const v2 = req(item.name, false)
      pushCandidate(candidates, v2)
      const t2: string = v2 === undefined ? 'u' : (v2 === null ? 'n' : (typeof v2).substring(0, 1))
      msgs.push(`${item.tag}f${t2}`)
    } catch (_) {
      msgs.push(`${item.tag}fx`)
    }
    try {
      const v3 = req(item.name, true)
      pushCandidate(candidates, v3)
      const t3: string = v3 === undefined ? 'u' : (v3 === null ? 'n' : (typeof v3).substring(0, 1))
      msgs.push(`${item.tag}t${t3}`)
    } catch (_) {
      msgs.push(`${item.tag}tx`)
    }
  }
  return msgs
}

export function resolveLibEntryApi(): LibEntryApi | null {
  if (cachedApi !== null) {
    return cachedApi
  }

  lastError = ''
  const candidates: Object[] = []
  const importedMaybe = importedLibEntry as Object | undefined | null
  pushCandidate(candidates, importedMaybe)
  pushCandidate(candidates, safeGet(importedMaybe, 'default'))
  pushCandidate(candidates, safeGet(importedMaybe, 'entry'))
  const importedDefault = safeGet(importedMaybe, 'default')
  pushCandidate(candidates, safeGet(importedDefault, 'default'))
  pushCandidate(candidates, safeGet(importedDefault, 'entry'))
  const g = globalThis as Record<string, Object>
  pushCandidate(candidates, g['entry'])
  pushCandidate(candidates, g['libentry'])

  const reqMsgs: string[] = tryRequireNapi(candidates)

  let bestObj: Object | null = null
  let bestScore: number = -1
  for (const cand of candidates) {
    const picks: Array<Object | undefined> = [
      cand as Object | undefined,
      safeGet(cand, 'default'),
      safeGet(cand, 'entry')
    ]
    for (const pick of picks) {
      const score: number = apiScore(pick)
      if (score > bestScore && pick !== undefined) {
        bestScore = score
        bestObj = pick as Object
      }
    }
  }
  if (bestObj !== null && bestScore >= 0) {
    cachedApi = asApi(bestObj)
    return cachedApi
  }

  const sigs: string[] = []
  for (let i: number = 0; i < candidates.length && i < 3; i++) {
    const cand = candidates[i]
    const tLoad: string = safeType(cand, 'loadModel')
    const tDet: string = safeType(cand, 'detectOffline')
    const tPlate: string = safeType(cand, 'detectPlate')
    const tQr: string = safeType(cand, 'decodeQr')
    const tNcnnLoad: string = safeType(cand, 'loadNcnnModel')
    const tNcnnDet: string = safeType(cand, 'detectNcnn')
    const tAdd: string = safeType(cand, 'add')
    const tDef: string = safeType(cand, 'default')
    const tEntry: string = safeType(cand, 'entry')
    const sAdd: string = String(safeGet(cand, '__addRegStatus') ?? 'na')
    const sInfer: string = String(safeGet(cand, '__inferRegStatus') ?? 'na')
    const sNcnn: string = String(safeGet(cand, '__ncnnRegStatus') ?? 'na')
    const hLoad: string = String(safeGet(cand, '__hasLoadModel') ?? 'na')
    const hDet: string = String(safeGet(cand, '__hasDetectOffline') ?? 'na')
    const hNcnnLoad: string = String(safeGet(cand, '__hasLoadNcnnModel') ?? 'na')
    const hNcnnDet: string = String(safeGet(cand, '__hasDetectNcnn') ?? 'na')
    const hPlate: string = String(safeGet(cand, '__hasDetectPlate') ?? 'na')
    const hQr: string = String(safeGet(cand, '__hasDecodeQr') ?? 'na')
    const hErr: string = String(safeGet(cand, '__hasGetLastError') ?? 'na')
    sigs.push(`c${i}[L${tLoad} D${tDet} NL${tNcnnLoad} ND${tNcnnDet} P${tPlate} Q${tQr} A${tAdd} Def${tDef} E${tEntry} RS${sInfer}/${sAdd}/${sNcnn} H${hLoad}${hDet}${hNcnnLoad}${hNcnnDet}${hPlate}${hQr}${hErr}]`)
  }
  lastError = `noapi c=${candidates.length} ${sigs.join(' ')} r=${reqMsgs.join('')}`
  return null
}

export function getLibEntryLastError(): string {
  return lastError
}

export function hasOnnxNativeApi(): boolean {
  const api = resolveLibEntryApi()
  return api !== null && typeof api.loadOnnxModel === 'function' && typeof api.detectOnnx === 'function'
}

export function hasNcnnNativeApi(): boolean {
  const api = resolveLibEntryApi()
  return api !== null && typeof api.loadNcnnModel === 'function' && typeof api.detectNcnn === 'function'
}

