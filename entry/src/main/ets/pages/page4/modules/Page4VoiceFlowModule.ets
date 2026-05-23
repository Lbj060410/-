import { Page4ReplyText } from '../config/Page4ReplyText'

export interface Page4VoiceFlowDeps {
  longPressTimerId: number
  longPressThresholdMs: number
  voicePressing: boolean
  voiceRecording: boolean
  voiceHintShown: boolean
  setManagedTimeout: (cb: () => void, delayMs: number) => number
  clearLongPressTimer: () => void
  pushAssistant: (text: string) => void
  enqueuePrompt: (text: string, source: string) => Promise<void>
  splitPromptToClauses: (text: string) => Array<string>
  startVoiceListening: () => Promise<void>
  stopVoiceListening: () => Promise<string>
  voiceHintText: () => string
}

export class Page4VoiceFlowModule {
  static onVoicePressDown(deps: Page4VoiceFlowDeps): Partial<Page4VoiceFlowDeps> {
    deps.clearLongPressTimer()
    const id: number = deps.setManagedTimeout((): void => {
      void deps.startVoiceListening()
    }, deps.longPressThresholdMs)
    return { voicePressing: true, longPressTimerId: id }
  }

  static async onVoicePressUp(deps: Page4VoiceFlowDeps): Promise<Partial<Page4VoiceFlowDeps>> {
    if (deps.longPressTimerId >= 0) {
      deps.clearLongPressTimer()
      if (!deps.voiceHintShown) deps.pushAssistant(deps.voiceHintText())
      return { voicePressing: false, voiceHintShown: true }
    }
    if (!deps.voiceRecording) return { voicePressing: false }
    const asrText: string = await deps.stopVoiceListening()
    if (asrText.trim().length <= 0) {
      deps.pushAssistant(Page4ReplyText.voiceNotRecognized())
      return { voicePressing: false, voiceRecording: false }
    }
    const clauses: Array<string> = deps.splitPromptToClauses(asrText)
    if (clauses.length <= 1) {
      await deps.enqueuePrompt(asrText, 'voice')
      return { voicePressing: false, voiceRecording: false }
    }
    deps.pushAssistant(Page4ReplyText.voiceMultiClauseRecognized(clauses.length))
    for (let i: number = 0; i < clauses.length; i++) await deps.enqueuePrompt(clauses[i], 'voice')
    return { voicePressing: false, voiceRecording: false }
  }
}
