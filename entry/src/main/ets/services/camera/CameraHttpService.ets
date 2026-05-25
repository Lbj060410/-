/**
 * 浠ｇ爜鎸囧崡锛? * 鏂囦欢锛歴ervices/camera/CameraHttpService.ets
 * 鐢ㄩ€旓細鎽勫儚澶磋澶囧彂鐜般€佺姸鎬佹娴嬪強HTTP鏈嶅姟闆嗘垚銆? * 淇敼鏃舵満锛氭憚鍍忓ご婧愰厤缃€佽澶囨娴嬮€昏緫鎴栬姹傚鐞嗛€昏緫鍙戠敓鍙樻洿鏃躲€? * 鐩稿叧鏂囦欢锛歱ages/page2/* 浠ュ強 services/source/*銆? */
import http from '@ohos.net.http'
import image from '@ohos.multimedia.image'

export interface HttpFrameResult {
  ok: boolean
  pixelMap?: image.PixelMap
  errorText: string
  costMs: number
}

export class CameraHttpService {
  private readonly timeoutMs: number = 4000
  // 保证用户名和密码经过 URL 编码，避免特殊字符导致请求失败。

  buildSnapshotUrl(host: string, user: string, pass: string): string {
    const parts: Array<string> = []
    const u: string = user.trim()
    const p: string = pass.trim()
    if (u.length > 0) parts.push(`loginuse=${encodeURIComponent(u)}`)
    if (p.length > 0) parts.push(`loginpas=${encodeURIComponent(p)}`)
    parts.push('res=0')
    return `http://${host}/snapshot.cgi?${parts.join('&')}`
  }
  async fetchSnapshot(host: string, user: string, pass: string): Promise<HttpFrameResult> {
    const start: number = Date.now()
    const url: string = this.buildSnapshotUrl(host, user, pass)

    try {
      const client: http.HttpRequest = http.createHttp()
      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET,
        readTimeout: this.timeoutMs,
        connectTimeout: this.timeoutMs,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })

      const costMs: number = Date.now() - start

      if (resp.responseCode !== 200) {
        client.destroy()
        return { ok: false, errorText: `HTTP ${resp.responseCode}`, costMs }
      }

      const data: ArrayBuffer = resp.result as ArrayBuffer
      client.destroy()

      const src: image.ImageSource = image.createImageSource(data)
      try {
        const pm: image.PixelMap = await src.createPixelMap()
        return { ok: true, pixelMap: pm, errorText: '-', costMs }
      } finally {
        src.release()
      }
    } catch (e) {
      const costMs: number = Date.now() - start
      return { ok: false, errorText: 'HTTP不可达/超时', costMs }
    }
  }
}



