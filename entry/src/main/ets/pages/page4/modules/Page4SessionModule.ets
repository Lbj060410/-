export interface AssistantMessage {
  id: string
  role: 'user' | 'assistant'
  text: string
  tsMs: number
}

export interface HistorySession {
  title: string
  messages: Array<AssistantMessage>
  tsMs: number
}

export class Page4SessionModule {
  static findMessageIndexById(messages: Array<AssistantMessage>, msgId: string): number {
    for (let i: number = messages.length - 1; i >= 0; i--) {
      if (messages[i].id === msgId) return i
    }
    return -1
  }

  static replaceMessageTextByIndex(messages: Array<AssistantMessage>, index: number, text: string): Array<AssistantMessage> {
    if (index < 0 || index >= messages.length) return messages
    const next: Array<AssistantMessage> = []
    for (let i: number = 0; i < messages.length; i++) {
      const one: AssistantMessage = messages[i]
      if (i === index) next.push({ id: one.id, role: one.role, text, tsMs: one.tsMs })
      else next.push(one)
    }
    return next
  }

  static trimMessages(messages: Array<AssistantMessage>, maxMessages: number): Array<AssistantMessage> {
    if (messages.length <= maxMessages) return messages
    const keepFrom: number = messages.length - maxMessages
    return messages.slice(keepFrom)
  }

  static latestAssistantMessageText(messages: Array<AssistantMessage>): string {
    for (let i: number = messages.length - 1; i >= 0; i--) {
      const one: AssistantMessage = messages[i]
      if (one.role === 'assistant') return one.text.trim()
    }
    return ''
  }

  static isCurrentNewChat(messages: Array<AssistantMessage>): boolean {
    for (let i: number = 0; i < messages.length; i++) {
      if (messages[i].role === 'user') return false
    }
    return true
  }

  static summarizeTitleByFirstSentence(text: string): string {
    const raw: string = text.trim()
    if (raw.length <= 0) return ''
    let end: number = raw.length
    const seps: Array<string> = ['。', '！', '？', '.', '!', '?', '；', ';', '\n']
    for (let i: number = 0; i < seps.length; i++) {
      const pos: number = raw.indexOf(seps[i])
      if (pos >= 0 && pos < end) end = pos
    }
    let out: string = raw.substring(0, end).trim()
    if (out.length > 14) out = `${out.substring(0, 14)}...`
    return out
  }

  static deriveCurrentChatTitle(messages: Array<AssistantMessage>): string {
    for (let i: number = 0; i < messages.length; i++) {
      const m: AssistantMessage = messages[i]
      if (m.role !== 'user') continue
      const title: string = this.summarizeTitleByFirstSentence(m.text)
      return title.length > 0 ? title : '新对话'
    }
    return '新对话'
  }

  static archiveSession(
    currentTitle: string,
    messages: Array<AssistantMessage>,
    historySessions: Array<HistorySession>,
    maxHistorySessions: number
  ): { sessions: Array<HistorySession>, titles: Array<string> } {
    const title: string = currentTitle.trim()
    if (title.length <= 0 || title === '新对话') {
      return { sessions: historySessions, titles: historySessions.map((s: HistorySession): string => s.title) }
    }
    if (this.isCurrentNewChat(messages)) {
      return { sessions: historySessions, titles: historySessions.map((s: HistorySession): string => s.title) }
    }
    const savedMessages: Array<AssistantMessage> = []
    for (let i: number = 0; i < messages.length; i++) savedMessages.push(messages[i])
    const session: HistorySession = { title, messages: savedMessages, tsMs: Date.now() }
    const nextSessions: Array<HistorySession> = [session]
    const nextTitles: Array<string> = [title]
    for (let i: number = 0; i < historySessions.length; i++) {
      nextSessions.push(historySessions[i])
      nextTitles.push(historySessions[i].title)
    }
    if (nextSessions.length > maxHistorySessions) {
      return { sessions: nextSessions.slice(0, maxHistorySessions), titles: nextTitles.slice(0, maxHistorySessions) }
    }
    return { sessions: nextSessions, titles: nextTitles }
  }
}
