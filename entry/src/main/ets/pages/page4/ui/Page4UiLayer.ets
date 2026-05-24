import { Page4ReplyText } from '../config/Page4ReplyText'

export class Page4UiLayer {
  static formatTime(ts: number): string {
    const d: Date = new Date(ts)
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
  }

  static voiceButtonText(voiceRecording: boolean, voicePressing: boolean): string {
    if (voiceRecording) return Page4ReplyText.VOICE_BUTTON_RECORDING
    if (voicePressing) return Page4ReplyText.VOICE_BUTTON_PRESSING
    return Page4ReplyText.VOICE_BUTTON_IDLE
  }

  static displayModeText(v: number): string {
    if (v === 0) return 'RTSP'
    if (v === 1) return 'HTTP'
    if (v === 2) return 'LOCAL'
    return String(v)
  }

  static buildExampleText(): string {
    return Page4ReplyText.buildExampleText()
  }
}
