import fs from '@ohos.file.fs'
import util from '@ohos.util'

export interface Page4PlaceBindingPayload {
  homeNodeId: string
  companyNodeId: string
}

export class Page4PlaceBindingStorageModule {
  static ensurePlaceBindingsLoaded(
    path: string,
    isValidGridId: (id: string) => boolean
  ): { homeNodeId: string, companyNodeId: string } {
    let f: fs.File | undefined = undefined
    try {
      f = fs.openSync(path, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(path)
      const size: number = Number(st.size)
      if (!Number.isFinite(size) || size <= 0 || size > 4096) return { homeNodeId: '', companyNodeId: '' }
      const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
      const readLen: number = fs.readSync(f.fd, buf)
      if (readLen <= 0) return { homeNodeId: '', companyNodeId: '' }
      const bytes: Uint8Array = new Uint8Array(buf, 0, readLen)
      const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
      const parsed: Page4PlaceBindingPayload = JSON.parse(txt) as Page4PlaceBindingPayload
      const home: string = String(parsed.homeNodeId ?? '').trim().toUpperCase()
      const company: string = String(parsed.companyNodeId ?? '').trim().toUpperCase()
      return {
        homeNodeId: isValidGridId(home) ? home : '',
        companyNodeId: isValidGridId(company) ? company : ''
      }
    } catch (_) {
      return { homeNodeId: '', companyNodeId: '' }
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  static persistPlaceBindings(path: string, payload: Page4PlaceBindingPayload): boolean {
    let f: fs.File | undefined = undefined
    try {
      const txt: string = JSON.stringify(payload)
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
