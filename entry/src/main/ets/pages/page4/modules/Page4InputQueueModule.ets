export interface Page4QueueState {
  queuedPromptCount: number
  queuedPromptCap: number
  assistantBusy: boolean
  promptQueueTail: Promise<void>
}

export interface Page4QueueHooks {
  pushAssistant: (text: string) => void
  submitPrompt: (text: string, fromQueue: boolean, source: string) => Promise<void>
}

export class Page4InputQueueModule {
  static async enqueuePrompt(
    raw: string,
    source: string,
    state: Page4QueueState,
    hooks: Page4QueueHooks
  ): Promise<Page4QueueState> {
    const text: string = raw.trim()
    if (text.length <= 0) return state
    if (state.queuedPromptCount >= state.queuedPromptCap) {
      hooks.pushAssistant(`任务队列已满(${state.queuedPromptCap})，请稍后再试。`)
      return state
    }
    const next: Page4QueueState = {
      queuedPromptCount: state.queuedPromptCount + 1,
      queuedPromptCap: state.queuedPromptCap,
      assistantBusy: state.assistantBusy,
      promptQueueTail: state.promptQueueTail
    }
    if (next.queuedPromptCount > 1) {
      hooks.pushAssistant(`已加入队列，前方还有 ${next.queuedPromptCount - 1} 条。`)
    }
    const runOne = async (): Promise<void> => {
      next.assistantBusy = true
      try {
        await hooks.submitPrompt(text, true, source)
      } finally {
        next.queuedPromptCount = Math.max(0, next.queuedPromptCount - 1)
        if (next.queuedPromptCount <= 0) next.assistantBusy = false
      }
    }
    next.promptQueueTail = next.promptQueueTail.then(runOne, runOne)
    await next.promptQueueTail
    return next
  }
}
