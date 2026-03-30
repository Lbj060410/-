// @ts-nocheck
import worker from '@ohos.worker'
import * as libentry from 'libentry.so'

interface DetectReq {
  id: number
  modelName: string
  rgba: ArrayBuffer
  w: number
  h: number
  conf: number
  nms: number
}

interface DetectResp {
  id: number
  ok: boolean
  json?: string
  err?: string
}

type WorkerMessageEvent = { data?: DetectReq }

function post(resp: DetectResp): void {
  try {
    worker.workerPort.postMessage(resp)
    return
  } catch (_) {}
  try {
    const postFn = (globalThis as Record<string, (arg: DetectResp) => void>)['postMessage']
    if (typeof postFn === 'function') postFn(resp)
  } catch (_) {}
}

function errorText(err: Object): string {
  if (err instanceof Error) return err.message.length > 0 ? err.message : 'unknown worker error'
  try {
    const txt: string = JSON.stringify(err)
    return txt.length > 0 ? txt : 'unknown worker error'
  } catch (_) {
    return 'unknown worker error'
  }
}

function handleMessage(e: Object): void {
  const req: DetectReq = (e as WorkerMessageEvent).data as DetectReq
  if (!req || typeof req.id !== 'number') return
  try {
    const json: string = libentry.detectNcnn(req.modelName, req.rgba, req.w, req.h, req.conf, req.nms)
    const nativeErr: string = (typeof libentry.getLastError === 'function') ? String(libentry.getLastError()) : ''
    if (nativeErr.length > 0) {
      post({ id: req.id, ok: false, err: nativeErr })
      return
    }
    post({ id: req.id, ok: true, json })
  } catch (err) {
    post({ id: req.id, ok: false, err: errorText(err) })
  }
}

worker.workerPort.onmessage = handleMessage
(globalThis as Record<string, (e: Object) => void>)['onmessage'] = handleMessage
