import { AssistantMessage, Page4SessionModule } from './Page4SessionModule'
import { Page4ReplyText } from '../config/Page4ReplyText'

export interface Page4TypingState {
  typingMessageId: string
  typingFullText: string
  typingToken: number
}

export interface Page4TypingHooks {
  findMessageIndexById: (msgId: string) => number
  replaceMessageTextByIndex: (index: number, text: string) => void
  scrollChatToBottomSoon: () => void
  sleepMs: (delayMs: number) => Promise<void>
  autoSpeak: (text: string) => Promise<void>
}

export interface Page4AutoSpeakHooks {
  speak: (text: string) => Promise<void>
  logInfo: (name: string, message: string) => void
  logError: (name: string, message: string) => void
  errorToText: (e: Object) => string
  showToast: (text: string) => void
}

export class Page4TypingTtsModule {
  static async runAssistantTyping(
    msgId: string,
    fullText: string,
    token: number,
    typingCharIntervalMs: number,
    state: Page4TypingState,
    hooks: Page4TypingHooks
  ): Promise<Page4TypingState> {
    let pos: number = 1
    while (pos < fullText.length) {
      if (token !== state.typingToken) return state
      const idx: number = hooks.findMessageIndexById(msgId)
      if (idx < 0) return state

      const remain: number = fullText.length - pos
      const take: number = remain > 120 ? 6 : (remain > 60 ? 4 : (remain > 20 ? 2 : 1))
      pos = Math.min(fullText.length, pos + take)
      hooks.replaceMessageTextByIndex(idx, fullText.substring(0, pos))
      hooks.scrollChatToBottomSoon()
      await hooks.sleepMs(typingCharIntervalMs)
    }

    if (token !== state.typingToken) return state
    state.typingMessageId = ''
    state.typingFullText = ''
    await hooks.autoSpeak(fullText)
    return state
  }

  static stopAssistantTyping(
    messages: Array<AssistantMessage>,
    state: Page4TypingState,
    clearManagedTimer: (timerId: number) => number,
    typingTimerId: number
  ): { state: Page4TypingState, typingTimerId: number, messages: Array<AssistantMessage> } {
    let nextMessages: Array<AssistantMessage> = messages
    if (state.typingMessageId.length > 0 && state.typingFullText.length > 0) {
      const idx: number = Page4SessionModule.findMessageIndexById(messages, state.typingMessageId)
      if (idx >= 0) {
        nextMessages = Page4SessionModule.replaceMessageTextByIndex(messages, idx, state.typingFullText)
      }
    }
    state.typingMessageId = ''
    state.typingFullText = ''
    state.typingToken += 1
    const nextTimerId: number = clearManagedTimer(typingTimerId)
    return { state, typingTimerId: nextTimerId, messages: nextMessages }
  }

  static async maybeAutoSpeakAssistantText(
    text: string,
    voiceReplyEnabled: boolean,
    hooks: Page4AutoSpeakHooks
  ): Promise<void> {
    if (!voiceReplyEnabled) return
    const content: string = text.trim()
    if (content.length <= 0) return

    try {
      hooks.logInfo('sendAutoSpeakRequest', `chars=${content.length}`)
      await hooks.speak(content)
    } catch (e) {
      const msg: string = hooks.errorToText(e as Object)
      hooks.logError('autoSpeakFail', msg)
      hooks.showToast(Page4ReplyText.toastAutoSpeakFail(msg))
    }
  }

  static async previewVoiceReplyAfterEnable(
    latestAssistantMessageText: string,
    hooks: Page4AutoSpeakHooks
  ): Promise<void> {
    try {
      await hooks.speak(Page4ReplyText.AUTO_SPEAK_READY)
      const latestAssistant: string = latestAssistantMessageText.trim()
      if (latestAssistant.length > 0) {
        await hooks.speak(latestAssistant)
      }
    } catch (e) {
      const msg: string = hooks.errorToText(e as Object)
      hooks.logError('previewVoiceReplyAfterEnableFail', msg)
      hooks.showToast(Page4ReplyText.toastVoiceReplyUnavailable(msg))
    }
  }
}
