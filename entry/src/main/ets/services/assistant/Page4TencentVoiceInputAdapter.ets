/**
 * 代码指南：
 * 文件： services/assistant/Page4TencentVoiceInputAdapter.ets
 * 用途： Page4 hold-to-talk adapter using AudioCapturer + Tencent Realtime ASR.
 * 何时修改： recorder behavior or ASR pipeline changes.
 * 相关文件： pages/page4/Page4View.ets, services/assistant/TencentAsrRealtimeService.ets.
 */
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'
import audio from '@ohos.multimedia.audio'
import {
  TENCENT_ASR_READ_CHUNK_SIZE,
  TENCENT_ASR_SAMPLE_RATE
} from '../../config/TencentAsrConfig'
import { TencentAsrFlashService } from './TencentAsrFlashService'
import { TencentAsrRealtimeService } from './TencentAsrRealtimeService'

interface Page4VoiceInputAdapter {
  startListening: () => void | Promise<void>
  stopListening: () => string | Promise<string>
}

class Page4TencentVoiceInputAdapterImpl implements Page4VoiceInputAdapter {
  private readonly flashService: TencentAsrFlashService = new TencentAsrFlashService()
  private readonly realtimeService: TencentAsrRealtimeService = new TencentAsrRealtimeService()
  private capturer: audio.AudioCapturer | undefined = undefined
  private readLoopRunning: boolean = false
  private listening: boolean = false
  private chunks: Array<Uint8Array> = []
  private totalBytes: number = 0

  async startListening(): Promise<void> {
    if (this.listening) return
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) throw new Error('UI context unavailable')
    const granted: boolean = await this.ensureMicPermission(ctx)
    if (!granted) throw new Error('Microphone permission denied')

    this.resetAudioBuffer()
    await this.realtimeService.startSession()
    try {
      this.capturer = await this.createCapturer()
      await this.capturer.start()
      this.listening = true
      this.startReadLoop()
    } catch (e) {
      await this.realtimeService.abortSession()
      throw e
    }
  }

  async stopListening(): Promise<string> {
    if (!this.listening) return ''
    this.listening = false
    this.stopReadLoop()

    const cap: audio.AudioCapturer | undefined = this.capturer
    this.capturer = undefined
    if (cap) {
      try { await cap.stop() } catch (e) {}
      try { await cap.release() } catch (e) {}
    }
    const pcm: ArrayBuffer = this.mergeChunksToArrayBuffer()
    const pcmBytes: number = pcm.byteLength
    let realtimeText: string = ''
    let realtimeErr: string = ''
    try {
      realtimeText = await this.realtimeService.stopSessionAndWaitResult()
    } catch (e) {
      await this.realtimeService.abortSession()
      realtimeErr = this.errorToText(e, 'unknown realtime error')
      realtimeText = ''
    }
    if (realtimeText.trim().length > 0) {
      this.resetAudioBuffer()
      return realtimeText.trim()
    }

    // 如果 websocket 结果为空，则回退到 flash API。
    let flashText: string = ''
    let flashErr: string = ''
    try {
      if (pcm.byteLength > 0) {
        flashText = await this.flashService.recognizePcm(pcm)
      }
    } catch (e) {
      flashErr = this.errorToText(e, 'unknown flash error')
      flashText = ''
    }
    this.resetAudioBuffer()
    const out: string = flashText.trim()
    if (out.length > 0) return out

    const details: Array<string> = []
    details.push(`audio_bytes=${pcmBytes}`)
    if (realtimeErr.length > 0) details.push(`realtime_err=${realtimeErr}`)
    if (flashErr.length > 0) details.push(`flash_err=${flashErr}`)
    throw new Error(`识别结果为空（${details.join(', ')}）`)
  }

  private errorToText(e: Object, fallback: string): string {
    if (e instanceof Error) {
      if (e.message && e.message.length > 0) return e.message
      return fallback
    }
    const anyE: Record<string, string | number | boolean | Object | undefined> = e as Record<
      string,
      string | number | boolean | Object | undefined
    >
    const code: string = String(anyE['code'] ?? '').trim()
    const msg: string = String(anyE['message'] ?? '').trim()
    if (code.length > 0 && msg.length > 0) return `${code}:${msg}`
    if (msg.length > 0) return msg
    if (code.length > 0) return code
    try {
      return JSON.stringify(e)
    } catch (e2) {
      return fallback
    }
  }

  private async createCapturer(): Promise<audio.AudioCapturer> {
    const opts: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      }
    }
    return await audio.createAudioCapturer(opts)
  }

  private startReadLoop(): void {
    this.readLoopRunning = true
    void this.readLoop()
  }

  private stopReadLoop(): void {
    this.readLoopRunning = false
  }

  private async readLoop(): Promise<void> {
    try {
      while (this.readLoopRunning && this.listening && this.capturer) {
        const ab: ArrayBuffer = await this.capturer.read(TENCENT_ASR_READ_CHUNK_SIZE, true)
        const u8: Uint8Array = new Uint8Array(ab)
        if (u8.length > 0) {
          const copy: Uint8Array = new Uint8Array(u8.length)
          copy.set(u8)
          this.chunks.push(copy)
          this.totalBytes += u8.length
          try {
            await this.realtimeService.sendAudioChunk(ab)
          } catch (e) {}
        }
      }
    } catch (e) {
      // 在阻塞读取期间停止捕获时预期会出现。
    }
  }

  private mergeChunksToArrayBuffer(): ArrayBuffer {
    if (this.totalBytes <= 0) return new ArrayBuffer(0)
    const out: Uint8Array = new Uint8Array(this.totalBytes)
    let offset: number = 0
    for (let i: number = 0; i < this.chunks.length; i++) {
      const c: Uint8Array = this.chunks[i]
      out.set(c, offset)
      offset += c.length
    }
    return out.buffer
  }

  private resetAudioBuffer(): void {
    this.chunks = []
    this.totalBytes = 0
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const ctx = globalThis.abilityContext as common.UIAbilityContext
    return ctx || undefined
  }

  private async ensureMicPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = ['ohos.permission.MICROPHONE' as Permissions]
    try {
      const result = await atManager.requestPermissionsFromUser(ctx, perms)
      for (let i: number = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) return false
      }
      return true
    } catch (e) {
      void e
      return false
    }
  }
}

const page4TencentVoiceInputAdapter: Page4VoiceInputAdapter = new Page4TencentVoiceInputAdapterImpl()

export function installPage4TencentVoiceInputAdapter(): void {
  const root: Record<string, Object | undefined> = globalThis as Record<string, Object | undefined>
  root['page4VoiceInputAdapter'] = page4TencentVoiceInputAdapter as Object
  root['page4VoiceSampleRate'] = TENCENT_ASR_SAMPLE_RATE as unknown as Object
}
