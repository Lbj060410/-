// @ts-nocheck
import worker from '@ohos.worker'

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

interface PendingItem {
  resolve: (json: string) => void
  reject: (err: Error) => void
  timerId: number
}

export class NcnnWorkerClient {
  private wk?: worker.ThreadWorker
  private started: boolean = false
  private seq: number = 0
  private readonly pending: Map<number, PendingItem> = new Map<number, PendingItem>()
  private readonly defaultTimeoutMs: number = 2000
  private readonly workerScriptPath: string = 'entry/ets/workers/NcnnDetectWorker.ets'

  private ensureWorker(): void {
    if (this.started && this.wk) return
    const wk: worker.ThreadWorker = new worker.ThreadWorker(this.workerScriptPath)
    this.wk = wk
    this.started = true

    wk.onmessage = (evt: Object): void => {
      const resp: DetectResp = (evt as { data?: DetectResp }).data as DetectResp
      if (!resp || typeof resp.id !== 'number') return
      const item: PendingItem | undefined = this.pending.get(resp.id)
      if (!item) return
      this.pending.delete(resp.id)
      try { clearTimeout(item.timerId) } catch (_) {}
      if (resp.ok) {
        item.resolve(resp.json ?? '[]')
      } else {
        item.reject(new Error(resp.err ?? 'worker detect failed'))
      }
    }

    wk.onerror = (err: Error): void => {
      const msg: string = err && err.message ? err.message : 'worker error'
      this.rejectAll(`ncnn worker error: ${msg}`)
      this.resetWorker()
    }
  }

  async detect(
    modelName: string,
    rgba: ArrayBuffer,
    w: number,
    h: number,
    conf: number,
    nms: number,
    timeoutMs?: number
  ): Promise<string> {
    this.ensureWorker()
    if (!this.wk) throw new Error('ncnn worker unavailable')

    const id: number = ++this.seq
    const safeTimeoutMs: number = Math.max(300, Math.trunc(timeoutMs ?? this.defaultTimeoutMs))
    return await new Promise<string>((resolve, reject): void => {
      const timerId: number = setTimeout((): void => {
        this.pending.delete(id)
        reject(new Error(`ncnn worker timeout: ${safeTimeoutMs}ms`))
      }, safeTimeoutMs) as number
      this.pending.set(id, { resolve, reject, timerId })

      const req: DetectReq = { id, modelName, rgba, w, h, conf, nms }
      try {
        this.wk!.postMessage(req)
      } catch (e) {
        this.pending.delete(id)
        try { clearTimeout(timerId) } catch (_) {}
        reject(new Error(e instanceof Error ? e.message : 'worker postMessage failed'))
      }
    })
  }

  shutdown(): void {
    this.rejectAll('ncnn worker shutdown')
    this.resetWorker()
  }

  private rejectAll(msg: string): void {
    this.pending.forEach((item: PendingItem): void => {
      try { clearTimeout(item.timerId) } catch (_) {}
      item.reject(new Error(msg))
    })
    this.pending.clear()
  }

  private resetWorker(): void {
    const wk: worker.ThreadWorker | undefined = this.wk
    this.wk = undefined
    this.started = false
    if (!wk) return
    try { wk.terminate() } catch (_) {}
  }
}

let singleton: NcnnWorkerClient | undefined

export function getNcnnWorkerClient(): NcnnWorkerClient {
  if (!singleton) singleton = new NcnnWorkerClient()
  return singleton
}

