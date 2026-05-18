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
    return { startListening: adapter.startListening, stopListening: adapter.stopListening }
  }

  static voiceHintText(): string {
    return '语音输入方式：按住说话，松开后自动发送识别文本。'
  }
}
