/**
 * 代码指南：
 * 文件：services/camera/CameraHttpService.ets
 * 用途：摄像头设备发现、状态检测及HTTP服务集成。
 * 修改时机：摄像头源配置、设备检测逻辑或请求处理逻辑发生变更时。
 * 相关文件：pages/page2/* 以及 services/source/*。
 */
import http from '@ohos.net.http'
import image from '@ohos.multimedia.image'

export interface HttpFrameResult {
  ok: boolean
  pixelMap?: image.PixelMap
  errorText: string
  costMs: number
}

export class CameraHttpService {
  private readonly timeoutMs: number = 2500
  // ��֤�������й�������ɢ���� URL �ַ�����

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
      return { ok: false, errorText: 'HTTP���ɴ�/��ʱ', costMs }
    }
  }
}


