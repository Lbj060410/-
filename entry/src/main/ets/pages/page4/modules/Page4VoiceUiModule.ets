import { Page4ReplyText } from '../config/Page4ReplyText'

export class Page4VoiceUiModule {
  static resolveVoiceInputAdapter(root: Record<string, Object | undefined>): {
    startListening: () => void | Promise<void>,
    stopListening: () => string | Promise<string>
  } | undefined {
    const adapter = root['page4VoiceInputAdapter'] as {
      startListening?: () => void | Promise<void>,
      stopListening?: () => string | Promise<string>
    } | undefined
    if (!adapter) return undefined
    if (typeof adapter.startListening !== 'function') return undefined
    if (typeof adapter.stopListening !== 'function') return undefined
    return {
      // 保留原实例作为调用方，避免类方法脱离实例后丢失 this。
      startListening: (): void | Promise<void> => adapter.startListening!(),
      stopListening: (): string | Promise<string> => adapter.stopListening!()
    }
  }

  static voiceHintText(): string {
    return Page4ReplyText.VOICE_HINT
  }
}
