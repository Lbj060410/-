export interface Page4VoiceInputAdapter {
  startListening: () => void | Promise<void>
  stopListening: () => string | Promise<string>
}

export class Page4VoiceInputModule {
  // TODO: manage hold-to-talk and ASR flow.
}
