/**
 * 代码指南：
 * 文件： services/assistant/TencentAsrFlashService.ets
 * 用途： 通过 HMAC-SHA1 鉴权调用腾讯云极速语音识别 API.
 * 何时修改： API 签名规则或响应格式发生变更时.
 * 相关文件： services/assistant/Page4TencentVoiceInputAdapter.ets.
 */
import http from '@ohos.net.http'
import util from '@ohos.util'
import {
  TENCENT_ASR_APP_ID,
  TENCENT_ASR_ENGINE_MODEL_TYPE,
  TENCENT_ASR_FLASH_VOICE_FORMAT,
  TENCENT_ASR_SECRET_ID,
  TENCENT_ASR_SECRET_KEY,
} from '../../config/TencentAsrConfig'
import { TencentSignUtil } from './TencentSignUtil'

interface FlashRequestConfig {
  appId: string
  secretId: string
  secretKey: string
  engineModelType: string
  voiceFormat: string
}

interface FlashTextCandidate {
  text?: string
  onebest?: string
  sentence?: string
}

export class TencentAsrFlashService {
  private readonly host: string = 'asr.cloud.tencent.com'
  private readonly signer: TencentSignUtil = new TencentSignUtil()

  async recognizePcm(audioBuffer: ArrayBuffer): Promise<string> {
    const cfg: FlashRequestConfig = this.getConfigOrThrow()
    if (audioBuffer.byteLength <= 0) return ''

    const nowSec: number = Math.floor(Date.now() / 1000)
    const expiredSec: number = nowSec + 600
    const nonce: number = this.nextNonce()
    const voiceId: string = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`

    const queryMap: Record<string, string> = {
      secretid: cfg.secretId,
      engine_model_type: cfg.engineModelType,
      timestamp: `${nowSec}`,
      expired: `${expiredSec}`,
      nonce: `${nonce}`,
      voice_id: voiceId,
      voice_format: cfg.voiceFormat
    }
    const query: string = this.toQuery(queryMap)
    const path: string = `/asr/flash/v1/${cfg.appId}`
    const signSource: string = `POST${this.host}${path}?${query}`
    const auth: string = await this.buildAuth(signSource, cfg.secretKey)
    const url: string = `https://${this.host}${path}?${query}`

    const req = http.createHttp()
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.POST,
        connectTimeout: 8000,
        readTimeout: 15000,
        header: {
          'Content-Type': 'application/octet-stream',
          'Authorization': auth
        },
        extraData: audioBuffer
      })
      if (resp.responseCode !== http.ResponseCode.OK) {
        throw new Error(`HTTP ${resp.responseCode}`)
      }
      return this.parseResponseText(resp.result)
    } finally {
      req.destroy()
    }
  }

  private getConfigOrThrow(): FlashRequestConfig {
    if (!TENCENT_ASR_APP_ID.trim() || !TENCENT_ASR_SECRET_ID.trim() || !TENCENT_ASR_SECRET_KEY.trim()) {
      throw new Error('请先在 config/TencentAsrConfig.ets 填写 APP_ID/SECRET_ID/SECRET_KEY')
    }
    return {
      appId: TENCENT_ASR_APP_ID.trim(),
      secretId: TENCENT_ASR_SECRET_ID.trim(),
      secretKey: TENCENT_ASR_SECRET_KEY.trim(),
      engineModelType: TENCENT_ASR_ENGINE_MODEL_TYPE.trim(),
      voiceFormat: TENCENT_ASR_FLASH_VOICE_FORMAT.trim()
    }
  }

  private nextNonce(): number {
    return Math.floor(Math.random() * 2147483647)
  }

  private toQuery(map: Record<string, string>): string {
    const keys: string[] = Object.keys(map).sort()
    const parts: Array<string> = []
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i]
      const v: string = map[k]
      parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    }
    return parts.join('&')
  }

  private async buildAuth(signSource: string, secretKey: string): Promise<string> {
    return this.signer.signBase64(signSource, secretKey)
  }

  private parseResponseText(result: string | Object | ArrayBuffer): string {
    const asString: string = this.resultToString(result)
    if (!asString) return ''
    let obj: Record<string, Object | string | number | boolean> | undefined = undefined
    try {
      obj = JSON.parse(asString) as Record<string, Object | string | number | boolean>
    } catch (e) {
      // 某些端点可能返回纯文本。
      return asString.trim()
    }
    const code = Number(obj['code'] ?? 0)
    if (!Number.isNaN(code) && code !== 0) {
      const message: string = String(obj['message'] ?? obj['msg'] ?? `code=${code}`)
      throw new Error(message)
    }
    return this.extractText(obj)
  }

  private resultToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') return result
    if (result instanceof ArrayBuffer) {
      return this.decodeUtf8(new Uint8Array(result))
    }
    try {
      return JSON.stringify(result)
    } catch (e) {
      void e
      return ''
    }
  }

  private extractText(obj: Record<string, Object | string | number | boolean>): string {
    const direct: Array<string> = [
      String(obj['text'] ?? ''),
      String(obj['result'] ?? ''),
      String(obj['onebest'] ?? '')
    ].map((s: string): string => (s === 'undefined' ? '' : s.trim())).filter((s: string): boolean => s.length > 0)
    if (direct.length > 0) return direct[0]

    const flashResult = obj['flash_result'] as Array<FlashTextCandidate> | undefined
    if (Array.isArray(flashResult) && flashResult.length > 0) {
      const texts: Array<string> = []
      for (let i: number = 0; i < flashResult.length; i++) {
        const item: FlashTextCandidate = flashResult[i]
        const t: string = (item.text ?? item.onebest ?? item.sentence ?? '').trim()
        if (t.length > 0) texts.push(t)
      }
      if (texts.length > 0) return texts.join('')
    }

    const dataObj = obj['data'] as Record<string, Object | string | number | boolean> | undefined
    if (dataObj) {
      const nested: string = this.extractText(dataObj)
      if (nested.length > 0) return nested
    }
    return ''
  }
  private decodeUtf8(buf: Uint8Array): string {
    return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(buf, { stream: false })
  }
}
