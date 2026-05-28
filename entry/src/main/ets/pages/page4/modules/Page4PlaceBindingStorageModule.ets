import fs from '@ohos.file.fs'
import util from '@ohos.util'

export interface Page4PlaceBindingPayload {
  homeNodeId: string
  companyNodeId: string
  homeAlias?: string
  companyAlias?: string
  updateTsMs?: number
  updateSeq?: number
  source?: string
}

export interface Page4PlaceBindingResult {
  homeNodeId: string
  companyNodeId: string
  homeAlias: string
  companyAlias: string
  updateTsMs: number
  updateSeq: number
  source: string
}

export class Page4PlaceBindingStorageModule {
  static ensurePlaceBindingsLoaded(
    path: string,
    isValidGridId: (id: string) => boolean
  ): Page4PlaceBindingResult {
    let f: fs.File | undefined = undefined
    try {
      f = fs.openSync(path, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(path)
      const size: number = Number(st.size)
      if (!Number.isFinite(size) || size <= 0 || size > 8192) {
        return { homeNodeId: '', companyNodeId: '', homeAlias: '', companyAlias: '', updateTsMs: 0, updateSeq: 0, source: 'empty_file' }
      }
      const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
      const readLen: number = fs.readSync(f.fd, buf)
      if (readLen <= 0) {
        return { homeNodeId: '', companyNodeId: '', homeAlias: '', companyAlias: '', updateTsMs: 0, updateSeq: 0, source: 'empty_read' }
      }
      const bytes: Uint8Array = new Uint8Array(buf, 0, readLen)
      const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
      const parsed: Page4PlaceBindingPayload = JSON.parse(txt) as Page4PlaceBindingPayload
      const home: string = String(parsed.homeNodeId ?? '').trim().toUpperCase()
      const company: string = String(parsed.companyNodeId ?? '').trim().toUpperCase()
      return {
        homeNodeId: isValidGridId(home) ? home : '',
        companyNodeId: isValidGridId(company) ? company : '',
        homeAlias: String(parsed.homeAlias ?? ''),
        companyAlias: String(parsed.companyAlias ?? ''),
        updateTsMs: Number(parsed.updateTsMs ?? 0),
        updateSeq: Number(parsed.updateSeq ?? 0),
        source: String(parsed.source ?? 'file')
      }
    } catch (_) {
      return { homeNodeId: '', companyNodeId: '', homeAlias: '', companyAlias: '', updateTsMs: 0, updateSeq: 0, source: 'parse_error' }
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  static persistPlaceBindings(path: string, payload: Page4PlaceBindingPayload): boolean {
    let f: fs.File | undefined = undefined
    try {
      const enriched: Page4PlaceBindingPayload = {
        ...payload,
        updateTsMs: Date.now(),
        source: payload.source ?? 'app'
      }
      const txt: string = JSON.stringify(enriched)
      try { fs.unlinkSync(path) } catch (_) {}
      f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(f.fd, txt)
      return true
    } catch (_) {
      return false
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }
}
