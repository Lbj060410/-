/**
 * 代码指南：
 * 文件： services/source/HttpSnapshotService.ets
 * 用途： 视频/帧源管理（HTTP截图、RTSP、本地视频切换）。
 * 何时修改： 修改源处理流程或新增源类型时。
 * 相关文件： services/recognition/* 及 page2 视图/协调器。
 */
// entry/src/main/ets/services/source/HttpSnapshotService.ets
import http from '@ohos.net.http'

interface HttpBusinessErrorLike {
  code?: number | string
  message?: string
}

export class HttpSnapshotService {
  async fetchJpeg(url: string, timeoutMs: number): Promise<ArrayBuffer> {
    // 低延迟模式：不再强制 3500ms 下限，避免慢请求把实时预览拖成“旧帧”。
    const effectiveTimeoutMs: number = Math.max(250, Math.min(5000, timeoutMs))

    try {
      return await this.requestJpeg(url, effectiveTimeoutMs)
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : ''
      // 某些摄像头忽略 query 鉴权参数，返回 401；自动补一次 Basic 认证重试。
      if (msg.indexOf('http code=401') >= 0) {
        const auth: string = this.tryBuildBasicAuthFromUrl(url)
        if (auth.length > 0) {
          return await this.requestJpeg(url, effectiveTimeoutMs, auth)
        }
      }
      throw e
    }
  }

  private async requestJpeg(url: string, timeoutMs: number, basicAuth: string = ''): Promise<ArrayBuffer> {
    const client: http.HttpRequest = http.createHttp()
    try {
      const reqHeaders: Record<string, string> = {
        'Accept': 'image/jpeg,*/*',
        // 尽可能禁止中间层/终端缓存，确保拿到最新帧。
        'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
        'Pragma': 'no-cache',
        'Expires': '0',
        'If-Modified-Since': '0',
        'Connection': 'close'
      }
      if (basicAuth.length > 0) {
        reqHeaders['Authorization'] = basicAuth
      }

      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET,
        header: reqHeaders,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })

      if (resp.responseCode !== 200) {
        throw new Error(`http code=${resp.responseCode}`)
      }

      const result: Object = resp.result as Object
      if (result instanceof ArrayBuffer) {
        if (result.byteLength <= 0) throw new Error('empty jpeg')
        return result
      }
      if (result instanceof Uint8Array) {
        const data: ArrayBuffer = result.buffer.slice(result.byteOffset, result.byteOffset + result.byteLength)
        if (data.byteLength <= 0) throw new Error('empty jpeg')
        return data
      }
      throw new Error(`unexpected result type=${typeof result}`)
    } catch (e) {
      let msg: string = 'http request failed'
      if (e instanceof Error) {
        msg = e.message
      } else if (typeof e === 'object' && e !== null) {
        const be: HttpBusinessErrorLike = e as HttpBusinessErrorLike
        const codeText: string = typeof be.code !== 'undefined' ? `code=${be.code} ` : ''
        const msgText: string = typeof be.message === 'string' && be.message.length > 0 ? be.message : 'http request failed'
        msg = `${codeText}msg=${msgText}`.trim()
      }
      throw new Error(msg)
    } finally {
      try { client.destroy() } catch (e) {}
    }
  }

  private tryBuildBasicAuthFromUrl(url: string): string {
    const find = (re: RegExp): string => {
      const m: RegExpMatchArray | null = url.match(re)
      if (!m || m.length < 2) return ''
      try { return decodeURIComponent(m[1]) } catch (_) { return m[1] }
    }

    const user: string = find(/[?&](?:loginuse|user|username)=([^&]+)/i)
    const pass: string = find(/[?&](?:loginpas|pwd|password)=([^&]+)/i)
    if (user.length <= 0) return ''

    const token: string = this.base64Encode(`${user}:${pass}`)
    if (token.length <= 0) return ''
    return `Basic ${token}`
  }

  private base64Encode(text: string): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const bytes: Uint8Array = this.utf8Encode(text)
    let out: string = ''
    let i: number = 0
    while (i < bytes.length) {
      const b0: number = bytes[i++]
      const b1: number = i < bytes.length ? bytes[i++] : -1
      const b2: number = i < bytes.length ? bytes[i++] : -1

      const n: number = (b0 << 16) | ((b1 >= 0 ? b1 : 0) << 8) | (b2 >= 0 ? b2 : 0)
      const c0: number = (n >>> 18) & 63
      const c1: number = (n >>> 12) & 63
      const c2: number = (n >>> 6) & 63
      const c3: number = n & 63

      out += chars[c0]
      out += chars[c1]
      out += b1 >= 0 ? chars[c2] : '='
      out += b2 >= 0 ? chars[c3] : '='
    }
    return out
  }

  private utf8Encode(text: string): Uint8Array {
    const bytes: Array<number> = []
    for (let i: number = 0; i < text.length; i++) {
      let code: number = text.charCodeAt(i)
      if (code < 0x80) {
        bytes.push(code)
        continue
      }
      if (code < 0x800) {
        bytes.push(0xC0 | (code >> 6))
        bytes.push(0x80 | (code & 0x3F))
        continue
      }
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
        const next: number = text.charCodeAt(i + 1)
        if (next >= 0xDC00 && next <= 0xDFFF) {
          i += 1
          code = 0x10000 + (((code - 0xD800) << 10) | (next - 0xDC00))
          bytes.push(0xF0 | (code >> 18))
          bytes.push(0x80 | ((code >> 12) & 0x3F))
          bytes.push(0x80 | ((code >> 6) & 0x3F))
          bytes.push(0x80 | (code & 0x3F))
          continue
        }
      }
      bytes.push(0xE0 | (code >> 12))
      bytes.push(0x80 | ((code >> 6) & 0x3F))
      bytes.push(0x80 | (code & 0x3F))
    }
    return new Uint8Array(bytes)
  }
}

