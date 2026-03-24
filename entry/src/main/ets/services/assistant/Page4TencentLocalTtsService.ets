/**
 * 代码指南：
 * 文件： services/assistant/Page4TencentLocalTtsService.ets
 * 用途： 为 page4 助手提供腾讯云语音合成（V3 API）+ 本地手机播放功能.
 * 何时修改： 腾讯云语音合成请求参数、签名算法或播放逻辑发生变更时.
 */
import http from '@ohos.net.http'
import media from '@ohos.multimedia.media'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import {
  TENCENT_ASR_SECRET_ID,
  TENCENT_ASR_SECRET_KEY
} from '../../config/TencentAsrConfig'

interface TtsRequestConfig {
  secretId: string
  secretKey: string
}

interface TtsResponseShape {
  Response?: {
    Audio?: string
    RequestId?: string
    Error?: {
      Code?: string
      Message?: string
    }
  }
}

class Tc3Signer {
  private readonly encoder: util.TextEncoder = new util.TextEncoder()

  buildAuthorization(
    secretId: string,
    secretKey: string,
    service: string,
    host: string,
    action: string,
    timestamp: number,
    body: string
  ): string {
    const date: string = this.formatDate(timestamp)
    const algorithm: string = 'TC3-HMAC-SHA256'
    const signedHeaders: string = 'content-type;host;x-tc-action'
    const canonicalHeaders: string =
      `content-type:application/json; charset=utf-8\nhost:${host}\nx-tc-action:${action.toLowerCase()}\n`
    const hashedRequestPayload: string = this.hex(this.sha256(this.utf8(body)))
    const canonicalRequest: string =
      `POST\n/\n\n${canonicalHeaders}\n${signedHeaders}\n${hashedRequestPayload}`
    const credentialScope: string = `${date}/${service}/tc3_request`
    const stringToSign: string =
      `${algorithm}\n${timestamp}\n${credentialScope}\n${this.hex(this.sha256(this.utf8(canonicalRequest)))}`

    const secretDate: Uint8Array = this.hmacSha256(this.utf8(`TC3${secretKey}`), this.utf8(date))
    const secretService: Uint8Array = this.hmacSha256(secretDate, this.utf8(service))
    const secretSigning: Uint8Array = this.hmacSha256(secretService, this.utf8('tc3_request'))
    const signature: string = this.hex(this.hmacSha256(secretSigning, this.utf8(stringToSign)))

    return `${algorithm} Credential=${secretId}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`
  }

  private formatDate(timestamp: number): string {
    const d: Date = new Date(timestamp * 1000)
    const y: number = d.getUTCFullYear()
    const m: string = `${d.getUTCMonth() + 1}`.padStart(2, '0')
    const day: string = `${d.getUTCDate()}`.padStart(2, '0')
    return `${y}-${m}-${day}`
  }

  private utf8(s: string): Uint8Array {
    return this.encoder.encodeInto(s)
  }

  private hmacSha256(key: Uint8Array, message: Uint8Array): Uint8Array {
    const blockSize: number = 64
    let useKey: Uint8Array = key
    if (useKey.length > blockSize) useKey = this.sha256(useKey)

    const paddedKey: Uint8Array = new Uint8Array(blockSize)
    paddedKey.set(useKey.subarray(0, Math.min(useKey.length, blockSize)))

    const ipad: Uint8Array = new Uint8Array(blockSize)
    const opad: Uint8Array = new Uint8Array(blockSize)
    for (let i: number = 0; i < blockSize; i++) {
      ipad[i] = paddedKey[i] ^ 0x36
      opad[i] = paddedKey[i] ^ 0x5c
    }
    const inner: Uint8Array = this.sha256(this.concat(ipad, message))
    return this.sha256(this.concat(opad, inner))
  }

  private sha256(data: Uint8Array): Uint8Array {
    const k: Uint32Array = new Uint32Array([
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ])

    const h: Uint32Array = new Uint32Array([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ])

    const padded: Uint8Array = this.sha256Pad(data)
    const w: Uint32Array = new Uint32Array(64)

    for (let offset: number = 0; offset < padded.length; offset += 64) {
      for (let i: number = 0; i < 16; i++) {
        const idx: number = offset + i * 4
        w[i] = (((padded[idx] << 24) >>> 0) |
          ((padded[idx + 1] << 16) >>> 0) |
          ((padded[idx + 2] << 8) >>> 0) |
          (padded[idx + 3] >>> 0)) >>> 0
      }
      for (let i: number = 16; i < 64; i++) {
        const s0: number = (this.ror(w[i - 15], 7) ^ this.ror(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0
        const s1: number = (this.ror(w[i - 2], 17) ^ this.ror(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0
      }

      let a: number = h[0]
      let b: number = h[1]
      let c: number = h[2]
      let d: number = h[3]
      let e: number = h[4]
      let f: number = h[5]
      let g: number = h[6]
      let hh: number = h[7]

      for (let i: number = 0; i < 64; i++) {
        const S1: number = (this.ror(e, 6) ^ this.ror(e, 11) ^ this.ror(e, 25)) >>> 0
        const ch: number = ((e & f) ^ ((~e) & g)) >>> 0
        const temp1: number = (hh + S1 + ch + k[i] + w[i]) >>> 0
        const S0: number = (this.ror(a, 2) ^ this.ror(a, 13) ^ this.ror(a, 22)) >>> 0
        const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0
        const temp2: number = (S0 + maj) >>> 0

        hh = g
        g = f
        f = e
        e = (d + temp1) >>> 0
        d = c
        c = b
        b = a
        a = (temp1 + temp2) >>> 0
      }

      h[0] = (h[0] + a) >>> 0
      h[1] = (h[1] + b) >>> 0
      h[2] = (h[2] + c) >>> 0
      h[3] = (h[3] + d) >>> 0
      h[4] = (h[4] + e) >>> 0
      h[5] = (h[5] + f) >>> 0
      h[6] = (h[6] + g) >>> 0
      h[7] = (h[7] + hh) >>> 0
    }

    const out: Uint8Array = new Uint8Array(32)
    for (let i: number = 0; i < 8; i++) {
      out[i * 4] = (h[i] >>> 24) & 0xff
      out[i * 4 + 1] = (h[i] >>> 16) & 0xff
      out[i * 4 + 2] = (h[i] >>> 8) & 0xff
      out[i * 4 + 3] = h[i] & 0xff
    }
    return out
  }

  private sha256Pad(data: Uint8Array): Uint8Array {
    const originalLen: number = data.length
    const bitLenHi: number = Math.floor((originalLen * 8) / 0x100000000)
    const bitLenLo: number = (originalLen * 8) >>> 0
    const padLen: number = ((56 - ((originalLen + 1) % 64)) + 64) % 64
    const totalLen: number = originalLen + 1 + padLen + 8
    const out: Uint8Array = new Uint8Array(totalLen)
    out.set(data, 0)
    out[originalLen] = 0x80
    out[totalLen - 8] = (bitLenHi >>> 24) & 0xff
    out[totalLen - 7] = (bitLenHi >>> 16) & 0xff
    out[totalLen - 6] = (bitLenHi >>> 8) & 0xff
    out[totalLen - 5] = bitLenHi & 0xff
    out[totalLen - 4] = (bitLenLo >>> 24) & 0xff
    out[totalLen - 3] = (bitLenLo >>> 16) & 0xff
    out[totalLen - 2] = (bitLenLo >>> 8) & 0xff
    out[totalLen - 1] = bitLenLo & 0xff
    return out
  }

  private ror(v: number, n: number): number {
    return ((v >>> n) | (v << (32 - n))) >>> 0
  }

  private concat(a: Uint8Array, b: Uint8Array): Uint8Array {
    const out: Uint8Array = new Uint8Array(a.length + b.length)
    out.set(a, 0)
    out.set(b, a.length)
    return out
  }

  private hex(bytes: Uint8Array): string {
    let out: string = ''
    for (let i: number = 0; i < bytes.length; i++) {
      const one: string = (bytes[i] & 0xff).toString(16).padStart(2, '0')
      out = out.length <= 0 ? one : `${out}${one}`
    }
    return out
  }
}

export class Page4TencentLocalTtsService {
  private readonly logTag: string = 'Page4TencentLocalTtsService'
  private readonly host: string = 'tts.tencentcloudapi.com'
  private readonly service: string = 'tts'
  private readonly version: string = '2019-08-23'
  private readonly action: string = 'TextToVoice'
  private readonly region: string = 'ap-guangzhou'
  private readonly signer: Tc3Signer = new Tc3Signer()
  private readonly cacheDir: string = '/data/storage/el2/base/haps/entry/files/page4_tts'
  private queue: Promise<void> = Promise.resolve()
  private speakSeq: number = 0
  private activePlayer?: media.AVPlayer
  private readonly maxSpeakCharsPerChunk: number = 120

  speak(text: string): Promise<void> {
    const content: string = this.normalizeText(text)
    if (content.length <= 0) return Promise.resolve()
    const seq: number = ++this.speakSeq
    this.logInfo('speakStart', `seq=${seq}, chars=${content.length}`)
    this.interruptActivePlayback()
    this.queue = this.queue.catch((): void => {}).then(async (): Promise<void> => {
      if (seq !== this.speakSeq) return
      const chunks: Array<string> = this.splitToSpeakChunks(content)
      this.logInfo('speakChunks', `seq=${seq}, chunks=${chunks.length}`)
      await this.speakPipeline(chunks, seq)
    })
    return this.queue
  }

  private async speakPipeline(chunks: Array<string>, seq: number): Promise<void> {
    if (chunks.length <= 0) return
    const cfg: TtsRequestConfig = this.getConfigOrThrow()

    let nextPromise: Promise<string> | undefined = this.synthChunkToFile(cfg, chunks[0], seq)
    for (let i: number = 0; i < chunks.length; i++) {
      if (seq !== this.speakSeq) return
      const currentPromise: Promise<string> = nextPromise as Promise<string>
      if (i + 1 < chunks.length) {
        nextPromise = this.synthChunkToFile(cfg, chunks[i + 1], seq)
      } else {
        nextPromise = undefined
      }
      const filePath: string = await currentPromise
      if (seq !== this.speakSeq || filePath.length <= 0) return
      try {
        await this.playFile(filePath, seq)
      } finally {
        this.cleanupAudioFile(filePath)
      }
    }
  }

  private async synthChunkToFile(cfg: TtsRequestConfig, text: string, seq: number): Promise<string> {
    if (seq !== this.speakSeq) return ''
    const audioBytes: Uint8Array = await this.requestByV3(cfg, text)
    if (seq !== this.speakSeq) return ''
    return this.writeAudioFile(audioBytes)
  }

  private getConfigOrThrow(): TtsRequestConfig {
    const secretId: string = TENCENT_ASR_SECRET_ID.trim()
    const secretKey: string = TENCENT_ASR_SECRET_KEY.trim()
    if (secretId.length <= 0 || secretKey.length <= 0) {
      throw new Error('腾讯TTS密钥为空，请检查 TencentAsrConfig.ets')
    }
    return { secretId, secretKey }
  }

  private normalizeText(input: string): string {
    let x: string = input
    x = x.replace(/```[\s\S]*?```/g, ' ')
    x = x.replace(/`[^`]*`/g, ' ')
    x = x.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1')
    x = x.replace(/https?:\/\/\S+/g, ' ')
    x = x.split('\n').join(' ').split('\r').join(' ')
    x = x.replace(/\s+/g, ' ').trim()
    return x
  }

  private splitToSpeakChunks(input: string): Array<string> {
    if (input.length <= this.maxSpeakCharsPerChunk) return [input]
    const out: Array<string> = []
    let remain: string = input
    while (remain.length > this.maxSpeakCharsPerChunk) {
      let cut: number = this.maxSpeakCharsPerChunk
      const punc: Array<string> = ['。', '！', '？', '；', ',', '，', '.', '!', '?', ';', ' ']
      for (let i: number = 0; i < punc.length; i++) {
        const idx: number = remain.lastIndexOf(punc[i], this.maxSpeakCharsPerChunk)
        if (idx >= 40) {
          cut = idx + 1
          break
        }
      }
      const one: string = remain.substring(0, cut).trim()
      if (one.length > 0) out.push(one)
      remain = remain.substring(cut).trim()
    }
    if (remain.length > 0) out.push(remain)
    return out
  }

  private async requestByV3(cfg: TtsRequestConfig, text: string): Promise<Uint8Array> {
    const bodyObj: Record<string, Object | string | number | boolean> = {
      Text: text,
      SessionId: `page4_${Date.now()}_${Math.floor(Math.random() * 1000000)}`,
      VoiceType: 0,
      SampleRate: 16000,
      Codec: 'mp3',
      Speed: 0,
      Volume: 3
    }
    const body: string = JSON.stringify(bodyObj)
    const timestamp: number = Math.floor(Date.now() / 1000)
    const authorization: string = this.signer.buildAuthorization(
      cfg.secretId,
      cfg.secretKey,
      this.service,
      this.host,
      this.action,
      timestamp,
      body
    )

    const req: http.HttpRequest = http.createHttp()
    try {
      this.logInfo('sendTtsV3Request', `host=${this.host}, action=${this.action}, textChars=${text.length}`)
      const resp: http.HttpResponse = await req.request(`https://${this.host}`, {
        method: http.RequestMethod.POST,
        connectTimeout: 8000,
        readTimeout: 30000,
        header: {
          'Content-Type': 'application/json; charset=utf-8',
          'Host': this.host,
          'X-TC-Action': this.action,
          'X-TC-Version': this.version,
          'X-TC-Region': this.region,
          'X-TC-Timestamp': `${timestamp}`,
          'Authorization': authorization
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING
      })
      if (resp.responseCode !== http.ResponseCode.OK) {
        this.logError('sendTtsV3HttpFail', `responseCode=${resp.responseCode}`)
        throw new Error(`HTTP ${resp.responseCode}`)
      }
      const textResp: string = typeof resp.result === 'string' ? resp.result : String(resp.result ?? '')
      return this.parseAudioFromV3(textResp)
    } catch (e) {
      this.logError('sendTtsV3RequestFail', this.errorToText(e))
      throw new Error(this.errorToText(e))
    } finally {
      req.destroy()
    }
  }

  private parseAudioFromV3(textResp: string): Uint8Array {
    let obj: TtsResponseShape
    try {
      obj = JSON.parse(textResp) as TtsResponseShape
    } catch (e) {
      throw new Error(`TTS响应解析失败: ${textResp}`)
    }

    const errCode: string = obj?.Response?.Error?.Code ?? ''
    const errMessage: string = obj?.Response?.Error?.Message ?? ''
    if (errCode.length > 0 || errMessage.length > 0) {
      throw new Error(`${errCode} ${errMessage}`.trim())
    }

    const audioB64: string = obj?.Response?.Audio ?? ''
    if (audioB64.length <= 0) throw new Error('TTS返回音频为空')
    const bytes: Uint8Array = this.decodeBase64(audioB64)
    if (bytes.length <= 0) throw new Error('TTS音频解码为空')
    // mp3 should usually start with ID3 or frame sync 0xFF.
    const head0: number = bytes[0] & 0xff
    const head1: number = bytes.length > 1 ? (bytes[1] & 0xff) : 0
    const head2: number = bytes.length > 2 ? (bytes[2] & 0xff) : 0
    const looksMp3: boolean =
      (head0 === 0x49 && head1 === 0x44 && head2 === 0x33) || // ID3
      (head0 === 0xff) // frame sync
    if (!looksMp3) {
      const previewLen: number = bytes.length > 160 ? 160 : bytes.length
      const preview: string = this.safeUtf8(bytes.subarray(0, previewLen))
      throw new Error(`TTS音频头异常: ${preview}`)
    }
    return bytes
  }

  private decodeBase64(input: string): Uint8Array {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    const clean: string = input.replace(/\s/g, '')
    const table: Record<string, number> = {}
    for (let i: number = 0; i < chars.length; i++) table[chars[i]] = i

    const out: Array<number> = []
    let i: number = 0
    while (i < clean.length) {
      const c1: string = clean[i] ?? 'A'
      const c2: string = clean[i + 1] ?? 'A'
      const c3: string = clean[i + 2] ?? 'A'
      const c4: string = clean[i + 3] ?? 'A'
      i += 4

      const b1: number = table[c1] ?? 0
      const b2: number = table[c2] ?? 0
      const b3: number = c3 === '=' ? 0 : (table[c3] ?? 0)
      const b4: number = c4 === '=' ? 0 : (table[c4] ?? 0)

      const n: number = ((b1 << 18) | (b2 << 12) | (b3 << 6) | b4) >>> 0
      out.push((n >>> 16) & 0xff)
      if (c3 !== '=') out.push((n >>> 8) & 0xff)
      if (c4 !== '=') out.push(n & 0xff)
    }
    return new Uint8Array(out)
  }

  private writeAudioFile(bytes: Uint8Array): string {
    this.ensureDir(this.cacheDir)
    const path: string = `${this.cacheDir}/tts_${Date.now()}_${Math.floor(Math.random() * 100000)}.mp3`
    const f: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
    try {
      fs.writeSync(f.fd, bytes.buffer)
    } finally {
      fs.closeSync(f.fd)
    }
    return path
  }

  private ensureDir(path: string): void {
    try {
      fs.mkdirSync(path)
    } catch (e) {
      this.logInfo('ensureDirExists', `path=${path}`)
    }
  }

  private cleanupAudioFile(path: string): void {
    if (path.length <= 0) return
    try {
      fs.unlinkSync(path)
      this.logInfo('audioFileCleanup', `path=${path}`)
    } catch (e) {
      this.logInfo('audioFileCleanupSkip', `path=${path}, reason=${this.errorToText(e)}`)
    }
  }

  private async playFile(path: string, seq: number): Promise<void> {
    if (seq !== this.speakSeq) return
    const player: media.AVPlayer = await media.createAVPlayer()
    this.activePlayer = player
    this.logInfo('playStart', `seq=${seq}, path=${path}`)
    const sourceFile: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY)
    const stat = fs.statSync(path)
    const fileSize: number = Number(stat.size ?? 0)
    if (fileSize <= 0) {
      this.safeCloseFd(sourceFile.fd, 'playSourceEarlyClose')
      throw new Error('TTS音频文件为空')
    }

    await new Promise<void>((resolve, reject): void => {
      let ended: boolean = false
      const onStateChange = (state: string): void => {
        this.logInfo('playState', `seq=${seq}, state=${state}`)
        if (seq !== this.speakSeq) {
          finish(true)
          return
        }
        if (state === 'initialized') {
          try { player.prepare() } catch (e) { finish(false, 'prepare failed') }
          return
        }
        if (state === 'prepared') {
          try { player.play() } catch (e) { finish(false, 'play failed') }
          return
        }
        if (state === 'completed') {
          finish(true)
        }
      }
      const onError = (err: Object): void => {
        const e: Record<string, Object | string | number | boolean> = err as Record<string, Object | string | number | boolean>
        this.logError('playError', `seq=${seq}, code=${String(e['code'] ?? '')}, message=${String(e['message'] ?? '')}`)
        finish(false, `avplayer error ${String(e['code'] ?? '')} ${String(e['message'] ?? '')}`.trim())
      }
      const finish = (ok: boolean, errText: string = ''): void => {
        if (ended) return
        ended = true
        clearTimeout(timerId)
        this.safeCloseFd(sourceFile.fd, 'playSourceClose')
        try {
          player.off('stateChange')
          player.off('error')
        } catch (e) {
          this.logInfo('playListenerDetachSkip', this.errorToText(e))
        }
        if (this.activePlayer === player) this.activePlayer = undefined
        try {
          player.reset()
        } catch (e) {
          this.logInfo('playResetSkip', this.errorToText(e))
        }
        try {
          player.release()
        } catch (e) {
          this.logInfo('playReleaseSkip', this.errorToText(e))
        }
        if (ok) this.logInfo('playDone', `seq=${seq}`)
        else this.logError('playFail', `seq=${seq}, reason=${errText}`)
        if (ok) resolve()
        else reject(new Error(errText.length > 0 ? errText : 'TTS播放失败'))
      }

      const timerId: number = setTimeout((): void => {
        finish(false, 'TTS播放超时')
      }, 30000) as number

      player.on('stateChange', onStateChange)
      player.on('error', onError)

      try {
        player.reset()
        // 对于拒绝直接 fdSrc 的平台，优先使用 fd:// URL。
        player.url = `fd://${sourceFile.fd}`
      } catch (e) {
        try {
          player.reset()
          player.fdSrc = {
            fd: sourceFile.fd,
            offset: 0,
            length: fileSize
          }
        } catch (e2) {
          finish(false, `set source failed ${this.errorToText(e2)}`)
        }
      }
    })
  }

  private errorToText(e: Object): string {
    if (e instanceof Error) {
      const msg: string = e.message.trim()
      return msg.length > 0 ? msg : 'unknown error'
    }
    const anyObj: Record<string, Object | string | number | boolean> = e as Record<string, Object | string | number | boolean>
    const code: string = String(anyObj['code'] ?? '')
    const msg: string = String(anyObj['message'] ?? '')
    const details: string = String(anyObj['details'] ?? '')
    const out: string = `${code} ${msg} ${details}`.trim()
    if (out.length > 0 && out !== 'undefined undefined undefined') return out
    try {
      const asJson: string = JSON.stringify(e)
      if (asJson.length > 0 && asJson !== '{}') return asJson
    } catch (_) {}
    return 'unknown error'
  }

  private safeUtf8(bytes: Uint8Array): string {
    try {
      return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
    } catch (_) {
      return '[binary]'
    }
  }

  private interruptActivePlayback(): void {
    const p: media.AVPlayer | undefined = this.activePlayer
    if (!p) return
    this.logInfo('playInterrupt', `seq=${this.speakSeq}`)
    try { p.off('stateChange') } catch (e) { this.logInfo('interruptOffStateSkip', this.errorToText(e)) }
    try { p.off('error') } catch (e) { this.logInfo('interruptOffErrorSkip', this.errorToText(e)) }
    try { p.stop() } catch (e) { this.logInfo('interruptStopSkip', this.errorToText(e)) }
    try { p.reset() } catch (e) { this.logInfo('interruptResetSkip', this.errorToText(e)) }
    try { p.release() } catch (e) { this.logInfo('interruptReleaseSkip', this.errorToText(e)) }
    this.activePlayer = undefined
  }

  private safeCloseFd(fd: number, name: string): void {
    try {
      fs.closeSync(fd)
    } catch (e) {
      this.logInfo(name, this.errorToText(e))
    }
  }

  private logInfo(name: string, message: string): void {
    console.info(`[info][${this.logTag}][${name}] ${message}`)
  }

  private logError(name: string, message: string): void {
    console.error(`[error][${this.logTag}][${name}] ${message}`)
  }
}

export const page4TencentLocalTtsService: Page4TencentLocalTtsService = new Page4TencentLocalTtsService()
