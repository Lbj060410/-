/**
 * 代码指南：
 * 文件： pages/page4/Page4View.ets
 * 用途： Clean assistant chat page with text input and hold-to-talk entry.
 * 何时修改： adjusting chat UI, local intent parsing, or voice-input handoff.
 * 相关文件： pages/page1/app/Page1Coordinator.ets, pages/page1/app/Page1UiStore.ets.
 */
import { page1Coordinator } from '../page1/app/Page1Coordinator'
import { page1Store, Page1UiStore, CarConnState } from '../page1/app/Page1UiStore'
import { GridIdCodec } from '../page1/app/PathPlannerAStar'
import { Page1Action } from '../page1/types/Page1Types'
import { Page1Theme } from '../page1/Page1Theme'
import { commStore } from '../../state/CommStore'
import { recogStore } from '../../state/RecogStore'
import { videoStore } from '../../state/VideoStore'
import {
  buildPcToolGatewayUrl,
  buildTabletCompanionUrl,
  buildOpenClawChatCompletionsUrl,
  OPENCLAW_CHAT_MODEL,
  OPENCLAW_CONNECT_TIMEOUT_MS,
  OPENCLAW_GATEWAY_TOKEN,
  resolveOpenClawTokenCandidates,
  PC_TOOL_CONNECT_TIMEOUT_MS,
  PC_TOOL_GATEWAY_TOKEN,
  resolvePcToolTokenCandidates,
  PC_TOOL_READ_TIMEOUT_MS,
  TABLET_COMPANION_CONNECT_TIMEOUT_MS,
  TABLET_COMPANION_NODE_ID,
  TABLET_COMPANION_READ_TIMEOUT_MS,
  TABLET_COMPANION_TOKEN,
  resolveTabletCompanionTokenCandidates,
  OPENCLAW_READ_TIMEOUT_MS,
  resolveTabletCompanionHostCandidates,
  resolvePcToolGatewayHostCandidates,
  resolveOpenClawHostCandidates
} from '../../config/DeviceNetworkConfig'
import { deviceNetworkResolver } from '../../services/network/DeviceNetworkResolver'
import { OpenClawGatewayClient, OpenClawChatMessage } from '../../services/assistant/OpenClawGatewayClient'
import { PcToolGatewayClient } from '../../services/assistant/PcToolGatewayClient'
import { TabletCompanionClient } from '../../services/assistant/TabletCompanionClient'
import { installPage4TencentVoiceInputAdapter } from '../../services/assistant/Page4TencentVoiceInputAdapter'
import { page4TencentLocalTtsService } from '../../services/assistant/Page4TencentLocalTtsService'
import hilog from '@ohos.hilog'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import { AssistantMessage as SessionAssistantMessage, HistorySession as SessionHistorySession, Page4SessionModule } from './modules/Page4SessionModule'
import { Page4InputQueueModule } from './modules/Page4InputQueueModule'
import { Page4LocalIntentModule } from './modules/Page4LocalIntentModule'
import { Page4PromptContextModule } from './modules/Page4PromptContextModule'
import { Page4VoiceUiModule } from './modules/Page4VoiceUiModule'
import { Page4TimerModule } from './modules/Page4TimerModule'
import { Page4RuntimeDiagnosticsModule } from './modules/Page4RuntimeDiagnosticsModule'
import { Page4OpenClawChatModule } from './modules/Page4OpenClawChatModule'
import { Page4OpenClawTaskPlannerModule } from './modules/Page4OpenClawTaskPlannerModule'
import { Page4PoiBindingModule, Page4AliasItem, Page4PlaceBindingPayload, Page4PlaceBindingPlan, Page4PlaceRole } from './modules/Page4PoiBindingModule'
import { Page4VoiceFlowModule } from './modules/Page4VoiceFlowModule'
import { Page4PlannedTask, Page4PlannedTaskKind, Page4OpenClawPlanQaModule } from './modules/Page4OpenClawPlanQaModule'
import { Page4ExecutionReceipt, Page4RouteExecutionModule } from './modules/Page4RouteExecutionModule'
import { Page4TaskExecutionModule } from './modules/Page4TaskExecutionModule'
import { Page4VoiceInputAdapter } from './modules/Page4VoiceInputModule'
import { Page4TopNavBar } from './ui/Page4TopNavBar'
import { Page4Sidebar } from './ui/Page4Sidebar'
import { Page4ChatPanel } from './ui/Page4ChatPanel'
import { Page4InputPanel } from './ui/Page4InputPanel'

const PAGE4_LOG_DOMAIN = 0xFF04
const PAGE4_LOG_TAG = 'page4log'
const PAGE4_PLACE_BINDING_FILE: string = 'page4_place_bindings.json'
const PAGE4_POI_EXPORT_FILE: string = 'page4_poi_mappings_export.json'
const ADAPTIVE_WEAK_RECOG_INTERVAL_MS: number = 450
const ADAPTIVE_WEAK_SWITCH_COOLDOWN_MS: number = 4000
const ADAPTIVE_WEAK_CONNECT_TIMEOUT_MS: number = 10000
const ADAPTIVE_WEAK_READ_TIMEOUT_MS: number = 60000
const ADAPTIVE_NORMAL_RECOG_INTERVAL_MS: number = 220
const ADAPTIVE_NORMAL_SWITCH_COOLDOWN_MS: number = 2500

type AssistantMessage = SessionAssistantMessage
type HistorySession = SessionHistorySession


@Component
export struct Page4View {
  private readonly logTag: string = 'Page4View'
  private readonly maxMessages: number = 120
  private readonly maxHistorySessions: number = 24
  private readonly store: Page1UiStore = page1Store
  @State private inputText: string = ''
  @State private messages: Array<AssistantMessage> = []
  @State private seq: number = 0
  @State private voicePressing: boolean = false
  @State private voiceRecording: boolean = false
  @State private voiceHintShown: boolean = false
  @State private assistantBusy: boolean = false
  @State private inputMode: 'text' | 'voice' = 'text'
  @State private showSidebar: boolean = false
  @State private voiceReplyEnabled: boolean = false
  @State private currentChatTitle: string = '新对话'
  @State private historyTitles: Array<string> = []
  @State private historySessions: Array<HistorySession> = []
  @State private toastVisible: boolean = false
  @State private toastText: string = ''
  private chatScroller: Scroller = new Scroller()
  private toastTimerId: number = -1
  private typingTimerId: number = -1
  private typingToken: number = 0
  private readonly typingCharIntervalMs: number = 24
  private typingMessageId: string = ''
  private typingFullText: string = ''

  private longPressTimerId: number = -1
  private readonly managedTimerIds: Set<number> = new Set<number>()
  private readonly longPressThresholdMs: number = 320
  private lastGoodOpenClawHost: string = ''
  private openClawHostCooldownUntilMs: Record<string, number> = {}
  private readonly openClawHostCooldownMs: number = 25000
  private readonly openClawRetryConnectTimeoutMs: number = 12000
  private readonly openClawRetryReadTimeoutMs: number = 60000
  private adaptiveOpenClawConnectTimeoutMs: number = 12000
  private adaptiveOpenClawReadTimeoutMs: number = 60000
  private readonly pcToolAllowedCmdPrefixes: Array<string> = [
    'Get-Process',
    'Get-Service',
    'Get-ChildItem',
    'Get-Content',
    'Test-Path',
    'whoami',
    'hostname'
  ]
  private readonly openClawSystemPrompt: string =
    '你是无人物流车的车控与调度助手。默认地址=江西省南昌市。优先使用简洁中文回复；涉及行驶、安全、货物操作时先给出明确、安全、可执行的步骤。回答要完整、简洁，尽量控制在50字以内，不要使用省略号。'
  private promptQueueTail: Promise<void> = Promise.resolve()
  private queuedPromptCount: number = 0
  private queuedPromptCap: number = 24
  private weakNetQueuedPromptCap: number = 10
  private normalQueuedPromptCap: number = 24
  private lastDestNodeId: string = ''
  private lastAction?: Page1Action = undefined
  private lastRouteFailureReason: string = ''
  private lastReplanSummary: string = ''

  private getFilesDir(): string {
    return getContext(this).filesDir
  }
  private lastSafeNodeId: string = ''
  private prevSafeNodeId: string = ''
  private aliasDict: Array<Page4AliasItem> = []
  private placeBindingsLoaded: boolean = false
  private homeNodeId: string = ''
  private companyNodeId: string = ''
  private readonly routeArrivalTimeoutMs: number = 180000
  private readonly routeArrivalPollMs: number = 300

  aboutToAppear(): void {
    this.ensurePlaceBindingsLoaded()
    installPage4TencentVoiceInputAdapter()
    page1Coordinator.bind(this.store)
    void page1Coordinator.start()
    this.applyAdaptiveStrategy()
    this.chatScroller = new Scroller()
    if (this.messages.length <= 0) {
      this.pushAssistant('您好，我是您的智能助理，有什么我可以帮您？')
    }
    this.stabilizeChatTopOnEnter()
  }

  aboutToDisappear(): void {
    this.stopAssistantTyping()
    this.clearLongPressTimer()
    this.clearToastTimer()
    this.clearAllManagedTimers()
    page4TencentLocalTtsService.stop()
  }

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        if (this.showSidebar) {
          Page4Sidebar({
            historyTitles: this.historyTitles,
            historySessions: this.historySessions,
            onOpenHistory: (session: HistorySession): void => {
              if (!this.isCurrentNewChat()) {
                this.archiveCurrentChatTitle()
              }
              const restored: Array<AssistantMessage> = []
              for (let k: number = 0; k < session.messages.length; k++) restored.push(session.messages[k])
              animateTo({ duration: 200 }, (): void => {
                this.messages = restored
                this.currentChatTitle = session.title
                this.showSidebar = false
              })
              this.scrollChatToBottomSoon()
            }
          })
        }

        Column() {
          Page4TopNavBar({
            showSidebar: this.showSidebar,
            currentChatTitle: this.currentChatTitle,
            voiceReplyEnabled: this.voiceReplyEnabled,
            onToggleSidebar: (): void => {
              animateTo({ duration: 200, curve: Curve.EaseInOut }, (): void => {
                this.showSidebar = !this.showSidebar
              })
            },
            onToggleVoiceReply: (): void => {
              this.voiceReplyEnabled = !this.voiceReplyEnabled
              this.showToast(this.voiceReplyEnabled ? '已开启本机播报' : '已关闭本机播报')
              if (this.voiceReplyEnabled) void this.previewVoiceReplyAfterEnable()
              else page4TencentLocalTtsService.stop()
            },
            onNewChat: (): void => {
              if (this.isCurrentNewChat()) {
                this.showToast('已经在新对话中')
                return
              }
              this.archiveCurrentChatTitle()
              animateTo({ duration: 300 }, (): void => {
                this.messages = []
                this.currentChatTitle = '新对话'
                this.pushAssistant('您好，我是您的智能助理，有什么我可以帮您？')
              })
              this.scrollChatToTopSoon()
            }
          })
          Page4ChatPanel({
            chatScroller: this.chatScroller,
            messages: this.messages,
            assistantBusy: this.assistantBusy
          })
          Page4InputPanel({
            inputMode: this.inputMode,
            inputText: this.inputText,
            voiceRecording: this.voiceRecording,
            onToggleMode: (): void => {
              this.inputMode = this.inputMode === 'voice' ? 'text' : 'voice'
            },
            onInputChange: (v: string): void => {
              this.inputText = v
            },
            onSubmitText: (): void => {
              if (!this.inputText) return
              void this.enqueuePrompt(this.inputText, 'text')
            },
            onVoiceTouch: (event: TouchEvent): void => this.onVoiceTouch(event)
          })
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(Page1Theme.BG)
      }
      .width('100%')
      .height('100%')

      if (this.toastVisible) {
        Text(this.toastText)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor('#D9000000')
          .borderRadius(12)
      }
    }
    .width('100%')
    .height('100%')
  }
  private formatTime(ts: number): string {
    const d = new Date(ts)
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
  }

  @Builder
  private statusRow(label: string, value: string, color: string): void {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(Page1Theme.TEXT_TERTIARY)
      Blank()
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
    }
    .width('100%')
  }

  @Builder
  private quickTaskBtn(text: string, prompt: string, danger: boolean = false): void {
    Button(text)
      .width('100%')
      .height(48)
      .borderRadius(12)
      .backgroundColor(danger ? Page1Theme.DANGER : Page1Theme.CARD_HOVER)
      .fontColor(Page1Theme.TEXT_PRIMARY)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .onClick((): void => {
        void this.enqueuePrompt(prompt, 'quick')
      })
  }

  private voiceButtonText(): string {
    if (this.voiceRecording) return '松开发送'
    if (this.voicePressing) return '继续按住说话'
    return '按住说话'
  }

  private onVoiceTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.onVoicePressDown()
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      void this.onVoicePressUp()
      return
    }
  }

  private onVoicePressDown(): void {
    const rs = Page4VoiceFlowModule.onVoicePressDown({
      longPressTimerId: this.longPressTimerId,
      longPressThresholdMs: this.longPressThresholdMs,
      voicePressing: this.voicePressing,
      voiceRecording: this.voiceRecording,
      voiceHintShown: this.voiceHintShown,
      setManagedTimeout: (cb: () => void, delayMs: number): number =>
        this.setManagedTimeout((): void => {
          this.longPressTimerId = -1
          cb()
        }, delayMs),
      clearLongPressTimer: (): void => this.clearLongPressTimer(),
      pushAssistant: (text: string): void => this.pushAssistant(text),
      enqueuePrompt: async (text: string, source: string): Promise<void> => await this.enqueuePrompt(text, source),
      splitPromptToClauses: (text: string): Array<string> => this.splitPromptToClauses(text),
      startVoiceListening: async (): Promise<void> => await this.startVoiceListening(),
      stopVoiceListening: async (): Promise<string> => await this.stopVoiceListening(),
      voiceHintText: (): string => Page4VoiceUiModule.voiceHintText()
    })
    this.voicePressing = rs.voicePressing ?? this.voicePressing
    this.longPressTimerId = rs.longPressTimerId ?? this.longPressTimerId
  }

  private async onVoicePressUp(): Promise<void> {
    const rs = await Page4VoiceFlowModule.onVoicePressUp({
      longPressTimerId: this.longPressTimerId,
      longPressThresholdMs: this.longPressThresholdMs,
      voicePressing: this.voicePressing,
      voiceRecording: this.voiceRecording,
      voiceHintShown: this.voiceHintShown,
      setManagedTimeout: (cb: () => void, delayMs: number): number => this.setManagedTimeout(cb, delayMs),
      clearLongPressTimer: (): void => this.clearLongPressTimer(),
      pushAssistant: (text: string): void => this.pushAssistant(text),
      enqueuePrompt: async (text: string, source: string): Promise<void> => await this.enqueuePrompt(text, source),
      splitPromptToClauses: (text: string): Array<string> => this.splitPromptToClauses(text),
      startVoiceListening: async (): Promise<void> => await this.startVoiceListening(),
      stopVoiceListening: async (): Promise<string> => await this.stopVoiceListening(),
      voiceHintText: (): string => Page4VoiceUiModule.voiceHintText()
    })
    this.voicePressing = rs.voicePressing ?? this.voicePressing
    this.voiceRecording = rs.voiceRecording ?? this.voiceRecording
    this.voiceHintShown = rs.voiceHintShown ?? this.voiceHintShown
  }

  private async startVoiceListening(): Promise<void> {
    const adapter: Page4VoiceInputAdapter | undefined = this.resolveVoiceInputAdapter()
    if (!adapter) {
      this.pushAssistant('当前未接入系统语音识别。你可以先文字输入，后续可把 ASR 适配器挂到 page4VoiceInputAdapter。')
      return
    }
    try {
      await Promise.resolve(adapter.startListening())
      this.voiceRecording = true
    } catch (e) {
      this.voiceRecording = false
      const msg: string = e instanceof Error ? e.message : 'unknown error'
      this.pushAssistant(`语音输入启动失败：${msg}`)
    }
  }

  private async stopVoiceListening(): Promise<string> {
    const adapter: Page4VoiceInputAdapter | undefined = this.resolveVoiceInputAdapter()
    if (!adapter) {
      return ''
    }
    try {
      const text: string = await Promise.resolve(adapter.stopListening())
      return typeof text === 'string' ? text : ''
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'unknown error'
      this.pushAssistant(`语音识别失败：${msg}`)
      return ''
    }
  }

  private resolveVoiceInputAdapter(): Page4VoiceInputAdapter | undefined {
    const root: Record<string, Object | undefined> = globalThis as Record<string, Object | undefined>
    return Page4VoiceUiModule.resolveVoiceInputAdapter(root) as Page4VoiceInputAdapter | undefined
  }

  private clearLongPressTimer(): void {
    this.longPressTimerId = this.clearManagedTimer(this.longPressTimerId)
  }

  private clearToastTimer(): void {
    this.toastTimerId = this.clearManagedTimer(this.toastTimerId)
  }

  private showToast(text: string): void {
    this.toastText = text
    this.toastVisible = true
    this.clearToastTimer()
    this.toastTimerId = this.setManagedTimeout((): void => {
      this.toastTimerId = -1
      this.toastVisible = false
    }, 2000)
  }

  private scrollChatToTopSoon(): void {
    this.setManagedTimeout((): void => {
      this.chatScroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 0, curve: Curve.Linear }
      })
    }, 0)
  }

  private scrollChatToBottomSoon(): void {
    this.setManagedTimeout((): void => {
      this.chatScroller.scrollEdge(Edge.Bottom)
    }, 0)
  }

  private stabilizeChatTopOnEnter(): void {
    this.setManagedTimeout((): void => {
      this.chatScroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 0, curve: Curve.Linear }
      })
    }, 180)
  }

  private nextId(): string {
    this.seq += 1
    return `${Date.now()}-${this.seq}`
  }

  private pushUser(text: string): void {
    this.messages.push({
      id: this.nextId(),
      role: 'user',
      text: text,
      tsMs: Date.now()
    })
    this.trimMessages()
    this.maybeRefreshCurrentChatTitleByFirstUserSentence()
    this.scrollChatToBottomSoon()
  }

  private pushAssistant(text: string, typed: boolean = false): void {
    this.stopAssistantTyping()
    if (typed) {
      this.pushAssistantTyped(text)
      return
    }
    this.messages.push({
      id: this.nextId(),
      role: 'assistant',
      text: text,
      tsMs: Date.now()
    })
    this.trimMessages()
    this.scrollChatToBottomSoon()
    void this.maybeAutoSpeakAssistantText(text)
  }

  private pushAssistantTyped(text: string): void {
    const fullText: string = text
    if (fullText.length <= 0) {
      this.pushAssistant('')
      return
    }
    const msgId: string = this.nextId()
    const tsMs: number = Date.now()
    this.messages.push({
      id: msgId,
      role: 'assistant',
      text: '',
      tsMs
    })
    this.trimMessages()
    this.scrollChatToBottomSoon()
    const firstIdx: number = this.findMessageIndexById(msgId)
    if (firstIdx >= 0) {
      this.replaceMessageTextByIndex(firstIdx, fullText.substring(0, 1))
    }
    this.typingMessageId = msgId
    this.typingFullText = fullText
    const token: number = this.typingToken
    void this.runAssistantTyping(msgId, fullText, token)
  }

  private async runAssistantTyping(msgId: string, fullText: string, token: number): Promise<void> {
    let pos: number = 1
    while (pos < fullText.length) {
      if (token !== this.typingToken) return
      const idx: number = this.findMessageIndexById(msgId)
      if (idx < 0) return

      const remain: number = fullText.length - pos
      const take: number = remain > 120 ? 6 : (remain > 60 ? 4 : (remain > 20 ? 2 : 1))
      pos = Math.min(fullText.length, pos + take)
      this.replaceMessageTextByIndex(idx, fullText.substring(0, pos))
      this.scrollChatToBottomSoon()
      await this.sleepMs(this.typingCharIntervalMs)
    }
    if (token !== this.typingToken) return
    this.typingMessageId = ''
    this.typingFullText = ''
    void this.maybeAutoSpeakAssistantText(fullText)
  }

  private stopAssistantTyping(): void {
    if (this.typingMessageId.length > 0 && this.typingFullText.length > 0) {
      const idx: number = this.findMessageIndexById(this.typingMessageId)
      if (idx >= 0) {
        this.replaceMessageTextByIndex(idx, this.typingFullText)
      }
    }
    this.typingMessageId = ''
    this.typingFullText = ''
    this.typingToken += 1
    this.typingTimerId = this.clearManagedTimer(this.typingTimerId)
  }

  private findMessageIndexById(msgId: string): number {
    return Page4SessionModule.findMessageIndexById(this.messages, msgId)
  }

  private replaceMessageTextByIndex(index: number, text: string): void {
    this.messages = Page4SessionModule.replaceMessageTextByIndex(this.messages, index, text)
  }

  private trimMessages(): void {
    this.messages = Page4SessionModule.trimMessages(this.messages, this.maxMessages)
  }

  private async maybeAutoSpeakAssistantText(text: string): Promise<void> {
    if (!this.voiceReplyEnabled) return
    const content: string = text.trim()
    if (content.length <= 0) return

    try {
      this.logInfo('sendAutoSpeakRequest', `chars=${content.length}`)
      await page4TencentLocalTtsService.speak(content)
    } catch (e) {
      const msg: string = this.errorToText(e)
      this.logError('autoSpeakFail', msg)
      this.showToast(`自动播报失败：${msg}`)
    }
  }

  private async previewVoiceReplyAfterEnable(): Promise<void> {
    try {
      await page4TencentLocalTtsService.speak('语音播报已开启')
      const latestAssistant: string = this.latestAssistantMessageText()
      if (latestAssistant.length > 0) {
        await page4TencentLocalTtsService.speak(latestAssistant)
      }
    } catch (e) {
      const msg: string = this.errorToText(e)
      this.logError('previewVoiceReplyAfterEnableFail', msg)
      this.showToast(`本机播报不可用：${msg}`)
    }
  }

  private latestAssistantMessageText(): string {
    return Page4SessionModule.latestAssistantMessageText(this.messages)
  }

  private errorToText(e: Object): string {
    return Page4RuntimeDiagnosticsModule.errorToText(e)
  }

  private isCurrentNewChat(): boolean {
    return Page4SessionModule.isCurrentNewChat(this.messages)
  }

  private archiveCurrentChatTitle(): void {
    const archived = Page4SessionModule.archiveSession(
      this.currentChatTitle,
      this.messages,
      this.historySessions,
      this.maxHistorySessions
    )
    this.historySessions = archived.sessions
    this.historyTitles = archived.titles
  }

  private maybeRefreshCurrentChatTitleByFirstUserSentence(): void {
    this.currentChatTitle = Page4SessionModule.deriveCurrentChatTitle(this.messages)
  }

  private summarizeTitleByFirstSentence(text: string): string {
    return Page4SessionModule.summarizeTitleByFirstSentence(text)
  }

  private connStateText(): string {
    if (this.store.connState === CarConnState.CONNECTED) return 'CONNECTED'
    if (this.store.connState === CarConnState.CONNECTING) return 'CONNECTING'
    if (this.store.connState === CarConnState.RECONNECTING) return 'RECONNECTING'
    if (this.store.connState === CarConnState.FAILED) return 'FAILED'
    return 'IDLE'
  }

  private connStateColor(): string {
    if (this.store.connState === CarConnState.CONNECTED) return Page1Theme.SUCCESS
    if (this.store.connState === CarConnState.CONNECTING) return Page1Theme.WARNING
    if (this.store.connState === CarConnState.RECONNECTING) return Page1Theme.WARNING
    if (this.store.connState === CarConnState.FAILED) return Page1Theme.DANGER
    return Page1Theme.TEXT_TERTIARY
  }

  private containsAny(text: string, keys: Array<string>): boolean {
    return Page4LocalIntentModule.containsAny(text, keys)
  }

  private async enqueuePrompt(raw: string, source: string = 'text'): Promise<void> {
    const next = await Page4InputQueueModule.enqueuePrompt(
      raw,
      source,
      {
        queuedPromptCount: this.queuedPromptCount,
        queuedPromptCap: this.queuedPromptCap,
        assistantBusy: this.assistantBusy,
        promptQueueTail: this.promptQueueTail
      },
      {
        pushAssistant: (text: string): void => this.pushAssistant(text),
        submitPrompt: async (text: string, fromQueue: boolean, src: string): Promise<void> => await this.submitPrompt(text, fromQueue, src)
      }
    )
    this.queuedPromptCount = next.queuedPromptCount
    this.assistantBusy = next.assistantBusy
    this.promptQueueTail = next.promptQueueTail
  }

  private learnAliasFromText(text: string): string {
    const rs = Page4LocalIntentModule.learnAliasFromText(text, this.aliasDict)
    this.aliasDict = rs.aliasDict
    return rs.message
  }

  private resolveAliasNode(text: string): string {
    return Page4LocalIntentModule.resolveAliasNode(
      text,
      this.aliasDict,
      (x: string): string => this.normalizePlaceInput(x)
    )
  }

  private resolveContextDestNode(input: string): string {
    return Page4LocalIntentModule.resolveContextDestNode(input, this.lastDestNodeId)
  }

  private rememberSafePointFromStore(): void {
    const cur: string = this.store.currentSnapNodeId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(cur)) return
    if (cur === this.lastSafeNodeId) return
    this.prevSafeNodeId = this.lastSafeNodeId
    this.lastSafeNodeId = cur
  }

  private async undoLastActionToSafePoint(): Promise<void> {
    const target: string = GridIdCodec.isValidId(this.prevSafeNodeId) ? this.prevSafeNodeId : this.lastSafeNodeId
    const receipts: Array<Page4ExecutionReceipt> = []
    try {
      await page1Coordinator.onAction(Page1Action.STOP)
      this.lastAction = Page1Action.STOP
      receipts.push(this.buildReceipt('停止', true, true))
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'stop failed'
      receipts.push(this.buildReceipt(`停止失败(${msg})`, false, false))
    }
    if (GridIdCodec.isValidId(target)) {
      const backReceipts: Array<Page4ExecutionReceipt> = await this.routeWithReplanAndWaitArrival(target)
      for (let i: number = 0; i < backReceipts.length; i++) receipts.push(backReceipts[i])
    } else {
      receipts.push(this.buildReceipt('回退安全点(未记录安全点)', false, false))
    }
    this.pushAssistant(`撤销结果：${this.renderReceiptsSummary(receipts)}`)
  }

  private isNightOrWeakNetwork(): boolean {
    const hour: number = new Date().getHours()
    const isNight: boolean = hour >= 20 || hour <= 6
    const weakConn: boolean =
      !commStore.commConnected ||
      commStore.commReconnectCount >= 3 ||
      this.containsAny(commStore.commStateText, ['RECONNECT', 'FAIL', 'ERROR'])
    return isNight || weakConn
  }

  private applyAdaptiveStrategy(forceNotify: boolean = false): void {
    const weak: boolean = this.isNightOrWeakNetwork()
    if (weak) {
      videoStore.setRecognizeIntervalMs(ADAPTIVE_WEAK_RECOG_INTERVAL_MS)
      videoStore.switchCooldownMs = ADAPTIVE_WEAK_SWITCH_COOLDOWN_MS
      this.adaptiveOpenClawConnectTimeoutMs = ADAPTIVE_WEAK_CONNECT_TIMEOUT_MS
      this.adaptiveOpenClawReadTimeoutMs = ADAPTIVE_WEAK_READ_TIMEOUT_MS
      this.queuedPromptCap = this.weakNetQueuedPromptCap
      if (forceNotify) {
        this.pushAssistant('已启用夜间/弱网策略：低频识别、延长超时、队列上限收紧。')
      }
      return
    }
    videoStore.setRecognizeIntervalMs(ADAPTIVE_NORMAL_RECOG_INTERVAL_MS)
    videoStore.switchCooldownMs = ADAPTIVE_NORMAL_SWITCH_COOLDOWN_MS
    this.adaptiveOpenClawConnectTimeoutMs = this.openClawRetryConnectTimeoutMs
    this.adaptiveOpenClawReadTimeoutMs = this.openClawRetryReadTimeoutMs
    this.queuedPromptCap = this.normalQueuedPromptCap
    if (forceNotify) {
      this.pushAssistant('已恢复常规策略。')
    }
  }

  private buildRouteFallbackCandidates(dest: string): Array<string> {
    const out: Array<string> = []
    const pushUnique = (id: string): void => {
      const x: string = id.trim().toUpperCase()
      if (!GridIdCodec.isValidId(x)) return
      for (let i: number = 0; i < out.length; i++) {
        if (out[i] === x) return
      }
      out.push(x)
    }
    pushUnique(dest)
    const parsed = GridIdCodec.parse(dest)
    if (!parsed) return out
    const col: number = parsed.col
    const row: number = parsed.row
    const cols: Array<number> = [col - 1, col + 1]
    const rows: Array<number> = [row - 1, row + 1]
    for (let i: number = 0; i < cols.length; i++) {
      const c: number = cols[i]
      if (c < 0 || c > 6) continue
      const id: string = String.fromCharCode(65 + c) + String(row)
      pushUnique(id)
    }
    for (let i: number = 0; i < rows.length; i++) {
      const r: number = rows[i]
      if (r < 1 || r > 7) continue
      const id: string = String.fromCharCode(65 + col) + String(r)
      pushUnique(id)
    }
    return out
  }

  private buildReceipt(taskText: string, sent: boolean, done: boolean): Page4ExecutionReceipt {
    const ackText: string = this.latestAckText()
    return {
      taskText: taskText,
      sent: sent,
      ack: ackText,
      done: done ? '完成/已生效' : '未完成'
    }
  }

  private latestAckText(): string {
    const arr = commStore.diagKeyRxFrames
    if (!arr || arr.length <= 0) return 'ACK未观测'
    const last = arr[arr.length - 1]
    if (!last) return 'ACK未观测'
    return `${last.cmdHex} ${last.summary}`
  }

  private renderReceiptsSummary(receipts: Array<Page4ExecutionReceipt>): string {
    if (receipts.length <= 0) return '无执行项'
    const parts: Array<string> = []
    for (let i: number = 0; i < receipts.length; i++) {
      const r: Page4ExecutionReceipt = receipts[i]
      parts.push(`${i + 1}.${r.taskText}[sent=${r.sent ? 'Y' : 'N'},ack=${r.ack},done=${r.done}]`)
    }
    return parts.join('；')
  }

  private async routeWithReplan(dest: string): Promise<{ ok: boolean, receipt: Page4ExecutionReceipt, appliedDest: string }> {
    const candidates: Array<string> = this.buildRouteFallbackCandidates(dest)
    let firstErr: string = ''
    for (let i: number = 0; i < candidates.length; i++) {
      const goal: string = candidates[i]
      try {
        this.rememberSafePointFromStore()
        await page1Coordinator.startManualRoute(goal)
        this.lastDestNodeId = goal
        const taskText: string = i <= 0 ? `导航 ${goal}` : `重规划导航 ${goal}`
        if (i > 0) {
          this.lastReplanSummary = `原目标${dest}失败，改为${goal}`
        }
        return { ok: true, receipt: this.buildReceipt(taskText, true, true), appliedDest: goal }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'route failed'
        if (firstErr.length <= 0) firstErr = msg
        this.lastRouteFailureReason = msg
      }
    }
    const detail: string = firstErr.length > 0 ? firstErr : '规划失败'
    this.lastRouteFailureReason = detail
    this.lastReplanSummary = `原目标${dest}失败，未找到可替代方案`
    return { ok: false, receipt: this.buildReceipt(`导航失败(${dest}:${detail})`, false, false), appliedDest: '' }
  }

  private async sleepMs(delayMs: number): Promise<void> {
    return await new Promise<void>((resolve: () => void): void => {
      this.setManagedTimeout((): void => resolve(), Math.max(0, Math.trunc(delayMs)))
    })
  }

  private async waitUntilArriveNode(destNodeId: string): Promise<{ arrived: boolean, finalNode: string, reason: string }> {
    const goal: string = destNodeId.trim().toUpperCase()
    if (!GridIdCodec.isValidId(goal)) return { arrived: false, finalNode: '', reason: 'bad_goal' }
    const deadlineMs: number = Date.now() + this.routeArrivalTimeoutMs
    while (Date.now() <= deadlineMs) {
      const cur: string = this.store.currentSnapNodeId.trim().toUpperCase()
      if (cur === goal) return { arrived: true, finalNode: cur, reason: 'arrived' }
      await this.sleepMs(this.routeArrivalPollMs)
    }
    const finalNode: string = this.store.currentSnapNodeId.trim().toUpperCase()
    return { arrived: false, finalNode: finalNode, reason: 'timeout' }
  }

  private async routeWithReplanAndWaitArrival(dest: string): Promise<Array<Page4ExecutionReceipt>> {
    const receipts: Array<Page4ExecutionReceipt> = []
    const routed = await this.routeWithReplan(dest)
    receipts.push(routed.receipt)
    if (!routed.ok || !GridIdCodec.isValidId(routed.appliedDest)) return receipts
    const wait = await this.waitUntilArriveNode(routed.appliedDest)
    if (wait.arrived) {
      receipts.push(this.buildReceipt(`到达 ${routed.appliedDest}`, true, true))
    } else {
      const curText: string = wait.finalNode.length > 0 ? wait.finalNode : '未知'
      receipts.push(this.buildReceipt(`等待到达超时(${routed.appliedDest}, 当前=${curText})`, true, false))
    }
    return receipts
  }

  private parseMethodBooleanArg(
    args: Record<string, Object | string | number | boolean | undefined>,
    key: string
  ): boolean | undefined {
    const v: Object | string | number | boolean | undefined = args[key]
    if (typeof v === 'boolean') return v
    const s: string = String(v ?? '').trim().toLowerCase()
    if (s === 'true' || s === '1' || s === 'on' || s === 'yes') return true
    if (s === 'false' || s === '0' || s === 'off' || s === 'no') return false
    return undefined
  }

  private async executeRegistryMethod(task: Page4PlannedTask): Promise<Array<Page4ExecutionReceipt>> {
    const name: string = this.normalizeMethodName(String(task.methodName ?? ''))
    const args: Record<string, Object | string | number | boolean | undefined> = task.methodArgs ?? {}
    const out: Array<Page4ExecutionReceipt> = []
    if (!this.isAllowedMethodName(name)) {
      out.push(this.buildReceipt(`未注册方法:${name}`, false, false))
      return out
    }

    if (name === 'start_manual_route') {
      const destRaw: string = String(args['dest'] ?? args['destNodeId'] ?? '').trim().toUpperCase()
      const dest: string = destRaw.length > 0 ? destRaw : this.extractDestNode(String(args['text'] ?? ''))
      if (!GridIdCodec.isValidId(dest)) {
        out.push(this.buildReceipt(`start_manual_route 参数错误 dest=${destRaw}`, false, false))
        return out
      }
      const routedReceipts: Array<Page4ExecutionReceipt> = await this.routeWithReplanAndWaitArrival(dest)
      for (let i: number = 0; i < routedReceipts.length; i++) out.push(routedReceipts[i])
      return out
    }

    if (name === 'send_action') {
      const actionToken: string = String(args['action'] ?? '').trim()
      const action: Page1Action | undefined = this.mapActionToken(actionToken)
      if (typeof action === 'undefined') {
        out.push(this.buildReceipt(`send_action 参数错误 action=${actionToken}`, false, false))
        return out
      }
      this.rememberSafePointFromStore()
      await page1Coordinator.onAction(action)
      this.lastAction = action
      out.push(this.buildReceipt(this.actionName(action), true, true))
      return out
    }

    if (name === 'set_auto_follow') {
      const enabled: boolean | undefined = this.parseMethodBooleanArg(args, 'enabled')
      if (typeof enabled === 'undefined') {
        out.push(this.buildReceipt('set_auto_follow 参数错误 enabled', false, false))
        return out
      }
      this.store.autoFollowEnabled = enabled
      this.store.pushLog(`info assistant.autoFollow set=${enabled ? 'ON' : 'OFF'}`)
      out.push(this.buildReceipt(enabled ? '自动跟随开启' : '自动跟随关闭', true, true))
      return out
    }

    if (name === 'set_send_mode') {
      const mode: string = String(args['mode'] ?? '').trim().toUpperCase()
      if (mode !== 'REAL_SEND' && mode !== 'DRY_RUN') {
        out.push(this.buildReceipt(`set_send_mode 参数错误 mode=${mode}`, false, false))
        return out
      }
      this.store.setRealSendEnabled(mode === 'REAL_SEND')
      out.push(this.buildReceipt(mode === 'REAL_SEND' ? '真车模式' : '仿真模式', true, true))
      return out
    }

    if (name === 'speak_text') {
      const text: string = String(args['text'] ?? '').trim()
      if (text.length <= 0) {
        out.push(this.buildReceipt('speak_text 参数错误 text为空', false, false))
        return out
      }
      const content: string = text.length > 80 ? text.substring(0, 80) : text
      const ok: boolean = await page1Coordinator.speakText(content)
      out.push(this.buildReceipt(`语音播报:${content}`, ok, ok))
      return out
    }

    if (name === 'undo_to_safe_point') {
      let stopOk: boolean = false
      try {
        await page1Coordinator.onAction(Page1Action.STOP)
        this.lastAction = Page1Action.STOP
        out.push(this.buildReceipt('撤销-停止', true, true))
        stopOk = true
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'stop failed'
        out.push(this.buildReceipt(`撤销-停止失败(${msg})`, false, false))
      }
      const target: string = GridIdCodec.isValidId(this.prevSafeNodeId) ? this.prevSafeNodeId : this.lastSafeNodeId
      if (stopOk && GridIdCodec.isValidId(target)) {
        const backReceipts: Array<Page4ExecutionReceipt> = await this.routeWithReplanAndWaitArrival(target)
        for (let i: number = 0; i < backReceipts.length; i++) out.push(backReceipts[i])
      } else if (stopOk) {
        out.push(this.buildReceipt('撤销-回安全点(未记录安全点)', false, false))
      }
      return out
    }

    if (name === 'get_camera_frame') {
      out.push(this.buildReceipt(this.buildCameraFrameSummaryText(), true, true))
      return out
    }

    if (name === 'query_status') {
      out.push(this.buildReceipt(this.buildStatusSummaryText(), true, true))
      return out
    }
    if (name === 'query_vision') {
      out.push(this.buildReceipt(this.buildVisionSummaryText(), true, true))
      return out
    }
    if (name === 'query_comm') {
      out.push(this.buildReceipt(
        `通信=${commStore.commStateText} connected=${commStore.commConnected} reconnect=${commStore.commReconnectCount}`,
        true,
        true
      ))
      return out
    }
    if (name === 'query_video') {
      out.push(this.buildReceipt(`视频=${videoStore.rtspStateText} fps=${videoStore.diagVideoFps}`, true, true))
      return out
    }
    if (name === 'set_recognition') {
      const enabled: boolean | undefined = this.parseMethodBooleanArg(args, 'enabled')
      if (typeof enabled === 'undefined') {
        out.push(this.buildReceipt('set_recognition 参数错误 enabled', false, false))
        return out
      }
      videoStore.setRecognitionEnabled(enabled)
      out.push(this.buildReceipt(enabled ? '识别已开启' : '识别已关闭', true, true))
      return out
    }
    if (name === 'set_auto_report') {
      const enabled: boolean | undefined = this.parseMethodBooleanArg(args, 'enabled')
      if (typeof enabled === 'undefined') {
        out.push(this.buildReceipt('set_auto_report 参数错误 enabled', false, false))
        return out
      }
      recogStore.setAutoReportEnabled(enabled)
      out.push(this.buildReceipt(enabled ? '自动回传已开启' : '自动回传已关闭', true, true))
      return out
    }
    if (name === 'set_vision_mode') {
      const mode: string = String(args['mode'] ?? '').trim().toLowerCase()
      if (mode === 'traffic') {
        videoStore.setPage2TrafficEnabled(true)
        out.push(this.buildReceipt('视觉模型已切换为 traffic', true, true))
        return out
      }
      if (mode === 'barrier' || mode === 'yolov26barrier') {
        videoStore.setPage2Yolov26BarrierEnabled(true)
        out.push(this.buildReceipt('视觉模型已切换为 yolov26barrier', true, true))
        return out
      }
      out.push(this.buildReceipt(`set_vision_mode 参数错误 mode=${mode}`, false, false))
      return out
    }
    if (name === 'set_adaptive_strategy') {
      const mode: string = String(args['mode'] ?? '').trim().toLowerCase()
      if (mode === 'weak' || mode === 'night') {
        videoStore.setRecognizeIntervalMs(ADAPTIVE_WEAK_RECOG_INTERVAL_MS)
        videoStore.switchCooldownMs = ADAPTIVE_WEAK_SWITCH_COOLDOWN_MS
        this.adaptiveOpenClawConnectTimeoutMs = ADAPTIVE_WEAK_CONNECT_TIMEOUT_MS
        this.adaptiveOpenClawReadTimeoutMs = ADAPTIVE_WEAK_READ_TIMEOUT_MS
        this.queuedPromptCap = this.weakNetQueuedPromptCap
        out.push(this.buildReceipt('策略已切换为弱网/夜间', true, true))
        return out
      }
      if (mode === 'normal') {
        videoStore.setRecognizeIntervalMs(ADAPTIVE_NORMAL_RECOG_INTERVAL_MS)
        videoStore.switchCooldownMs = ADAPTIVE_NORMAL_SWITCH_COOLDOWN_MS
        this.adaptiveOpenClawConnectTimeoutMs = this.openClawRetryConnectTimeoutMs
        this.adaptiveOpenClawReadTimeoutMs = this.openClawRetryReadTimeoutMs
        this.queuedPromptCap = this.normalQueuedPromptCap
        out.push(this.buildReceipt('策略已切换为常规', true, true))
        return out
      }
      out.push(this.buildReceipt(`set_adaptive_strategy 参数错误 mode=${mode}`, false, false))
      return out
    }
    if (name === 'tablet_set_alarm') {
      const hourText: string = String(args['hour'] ?? '').trim()
      const minuteText: string = String(args['minute'] ?? '').trim()
      const label: string = String(args['label'] ?? '').trim()
      const hour: number = Math.trunc(Number(hourText))
      const minute: number = Math.trunc(Number(minuteText))
      if (!Number.isFinite(hour) || !Number.isFinite(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        out.push(this.buildReceipt('tablet_set_alarm 参数错误 hour/minute', false, false))
        return out
      }
      const r = await this.callTabletCompanion('set_alarm', { hour, minute, label })
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'tablet_open_app') {
      const bundleName: string = String(args['bundleName'] ?? args['bundle'] ?? '').trim()
      if (bundleName.length <= 0) {
        out.push(this.buildReceipt('tablet_open_app 参数错误 bundleName为空', false, false))
        return out
      }
      const r = await this.callTabletCompanion('open_app', { bundleName })
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'tablet_list_alarm') {
      const r = await this.callTabletCompanion('list_alarm', {})
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'tablet_start_ability') {
      const bundleName: string = String(args['bundleName'] ?? args['bundle'] ?? '').trim()
      const abilityName: string = String(args['abilityName'] ?? '').trim()
      const paramsRaw: Object | string | number | boolean | undefined = args['parameters']
      const parameters: Record<string, Object | string | number | boolean | undefined> =
        typeof paramsRaw === 'object' && paramsRaw !== null
          ? (paramsRaw as Record<string, Object | string | number | boolean | undefined>)
          : {}
      if (bundleName.length <= 0) {
        out.push(this.buildReceipt('tablet_start_ability 参数错误 bundleName为空', false, false))
        return out
      }
      const r = await this.callTabletCompanion('start_ability', { bundleName, abilityName, parameters })
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'tablet_open_url') {
      const url: string = String(args['url'] ?? '').trim()
      if (url.length <= 0) {
        out.push(this.buildReceipt('tablet_open_url 参数错误 url为空', false, false))
        return out
      }
      const r = await this.callTabletCompanion('open_url', { url })
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'read_file') {
      const path: string = String(args['path'] ?? '').trim()
      if (path.length <= 0) {
        out.push(this.buildReceipt('read_file 参数错误 path为空', false, false))
        return out
      }
      if (path.endsWith('/') || path.endsWith('\\')) {
        out.push(this.buildReceipt(`read_file 参数错误 path疑似目录:${path}`, false, false))
        return out
      }
      const r = await this.callPcToolGateway('read_file', { path })
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'process_list') {
      const r = await this.callPcToolGateway('process_list', {})
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }
    if (name === 'exec_cmd') {
      const cmd: string = String(args['cmd'] ?? args['command'] ?? '').trim()
      if (cmd.length <= 0) {
        out.push(this.buildReceipt('exec_cmd 参数错误 cmd为空', false, false))
        return out
      }
      if (!this.isAllowedPcExecCmd(cmd)) {
        out.push(this.buildReceipt(`exec_cmd 被策略拒绝:${cmd}`, false, false))
        return out
      }
      const r = await this.callPcToolGateway('exec_cmd', { cmd })
      out.push(this.buildReceipt(r.summary, r.ok, r.ok))
      return out
    }

    out.push(this.buildReceipt(`未实现方法:${name}`, false, false))
    return out
  }

  private isAllowedPcExecCmd(cmd: string): boolean {
    const s: string = cmd.trim().toLowerCase()
    if (s.length <= 0) return false
    if (s.indexOf('remove-item') >= 0 || s.indexOf('rm ') >= 0 || s.indexOf('del ') >= 0) return false
    if (s.indexOf('format-') >= 0 || s.indexOf('shutdown') >= 0 || s.indexOf('restart-computer') >= 0) return false
    for (let i: number = 0; i < this.pcToolAllowedCmdPrefixes.length; i++) {
      const p: string = this.pcToolAllowedCmdPrefixes[i].toLowerCase()
      if (s === p || s.startsWith(`${p} `)) return true
    }
    return false
  }

  private summarizePcToolText(toolName: string, text: string): string {
    const body: string = text.trim()
    if (body.length <= 0) return `${toolName}: 空结果`
    const oneLine: string = body.split('\n').join(' ').split('\r').join(' ')
    const short: string = oneLine.length > 120 ? `${oneLine.substring(0, 120)}...` : oneLine
    return `${toolName}: ${short}`
  }

  private summarizeTabletCompanionText(action: string, text: string): string {
    const body: string = text.trim()
    if (body.length <= 0) return `tablet.${action}: 空结果`
    const oneLine: string = body.split('\n').join(' ').split('\r').join(' ')
    const short: string = oneLine.length > 120 ? `${oneLine.substring(0, 120)}...` : oneLine
    return `tablet.${action}: ${short}`
  }

  private normalizeGatewayErrorText(raw: string): string {
    const text: string = raw.trim()
    if (text.length <= 0) return '请求失败'
    const low: string = text.toLowerCase()
    if (low.indexOf('missing scope') >= 0) {
      return `权限不足(${text})，请改用具备 operator.read/operator.write 的 token`
    }
    if (low.indexOf('eisdir') >= 0 || low.indexOf('illegal operation on a directory') >= 0) {
      return `路径是目录而非文件(${text})，请传具体文件路径`
    }
    if (low.indexOf('timeout') >= 0 || low.indexOf('timed out') >= 0 || low.indexOf('connect failed') >= 0) {
      return `网络超时(${text})`
    }
    if (low.indexOf('unauthorized') >= 0 || low.indexOf('forbidden') >= 0 || low.indexOf('401') >= 0 || low.indexOf('403') >= 0) {
      return `鉴权失败(${text})`
    }
    return text
  }

  private async callPcToolGateway(
    toolName: string,
    args: Record<string, Object | string | number | boolean | undefined>
  ): Promise<{ ok: boolean, summary: string }> {
    const primaryToken: string = PC_TOOL_GATEWAY_TOKEN.trim()
    const tokens: Array<string> = resolvePcToolTokenCandidates()
    if (tokens.length <= 0 && primaryToken.length <= 0) {
      return { ok: false, summary: 'PC_TOOL_GATEWAY_TOKEN 为空，请先配置。' }
    }
    const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
    const hosts: Array<string> = this.rankOpenClawHosts(resolvePcToolGatewayHostCandidates(gatewayIp))
    if (hosts.length <= 0) {
      return { ok: false, summary: '未检测到 PC 工具网关主机地址。' }
    }
    const errs: Array<string> = []
    for (let i: number = 0; i < hosts.length; i++) {
      const host: string = hosts[i]
      for (let k: number = 0; k < tokens.length; k++) {
        const token: string = tokens[k]
        const client: PcToolGatewayClient = new PcToolGatewayClient({
          endpoint: buildPcToolGatewayUrl(host, toolName),
          bearerToken: token,
          connectTimeoutMs: PC_TOOL_CONNECT_TIMEOUT_MS,
          readTimeoutMs: PC_TOOL_READ_TIMEOUT_MS
        })
        const result = await client.call(args)
        if (result.ok) {
          this.markOpenClawHostSuccess(host)
          return { ok: true, summary: this.summarizePcToolText(toolName, result.text) }
        }
        const errText: string = this.normalizeGatewayErrorText(result.errorText)
        errs.push(`${host}/${k + 1}:${errText}`)
      }
      this.markOpenClawHostFail(host)
    }
    const merged: string = errs.length > 0 ? errs.join(' | ') : '请求失败'
    return { ok: false, summary: `${toolName}: ${merged}` }
  }

  private async callTabletCompanion(
    action: string,
    args: Record<string, Object | string | number | boolean | undefined>
  ): Promise<{ ok: boolean, summary: string }> {
    const primaryToken: string = TABLET_COMPANION_TOKEN.trim()
    const tokens: Array<string> = resolveTabletCompanionTokenCandidates()
    if (tokens.length <= 0 && primaryToken.length <= 0) {
      return { ok: false, summary: 'TABLET_COMPANION_TOKEN 为空，请先配置。' }
    }
    const nodeId: string = TABLET_COMPANION_NODE_ID.trim()
    if (nodeId.length <= 0) {
      return { ok: false, summary: 'TABLET_COMPANION_NODE_ID 为空，请先配置。' }
    }
    const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
    const hosts: Array<string> = this.rankOpenClawHosts(resolveTabletCompanionHostCandidates(gatewayIp))
    if (hosts.length <= 0) {
      return { ok: false, summary: '未检测到平板伴侣代理主机地址。' }
    }
    const errs: Array<string> = []
    for (let i: number = 0; i < hosts.length; i++) {
      const host: string = hosts[i]
      for (let k: number = 0; k < tokens.length; k++) {
        const token: string = tokens[k]
        const client: TabletCompanionClient = new TabletCompanionClient({
          endpoint: buildTabletCompanionUrl(host, action),
          bearerToken: token,
          nodeId,
          connectTimeoutMs: TABLET_COMPANION_CONNECT_TIMEOUT_MS,
          readTimeoutMs: TABLET_COMPANION_READ_TIMEOUT_MS
        })
        const result = await client.invoke(args)
        if (result.ok) {
          this.markOpenClawHostSuccess(host)
          return { ok: true, summary: this.summarizeTabletCompanionText(action, result.text) }
        }
        const errText: string = this.normalizeGatewayErrorText(result.errorText)
        errs.push(`${host}/${k + 1}:${errText}`)
      }
      this.markOpenClawHostFail(host)
    }
    const merged: string = errs.length > 0 ? errs.join(' | ') : '请求失败'
    return { ok: false, summary: `tablet.${action}: ${merged}` }
  }

  private splitPromptToClauses(text: string): Array<string> {
    const src: string = text
      .replace(/然后|接着|随后|并且|并且再|同时|接下来|再去|再到/g, '|')
      .replace(/[，,；;。.!！?？\n]/g, '|')
    const raw: Array<string> = src.split('|')
    const out: Array<string> = []
    for (let i: number = 0; i < raw.length; i++) {
      const one: string = raw[i].trim()
      if (one.length > 0) out.push(one)
    }
    return out
  }

  private parseTaskFromClause(clause: string): Page4PlannedTask | undefined {
    const lower: string = clause.toLowerCase()
    const dest: string = this.extractDestNode(clause)
    if (dest.length > 0 && GridIdCodec.isValidId(dest)) {
      return { kind: 'route', destNodeId: dest }
    }

    const action: Page1Action | undefined = this.resolveActionByText(lower)
    if (action !== undefined) {
      return { kind: 'action', action: action }
    }

    if (this.containsAny(lower, ['开启自动跟随', '打开自动跟随', '自动跟随开启', '自动驾驶开启'])) {
      return { kind: 'auto_follow', enabled: true }
    }
    if (this.containsAny(lower, ['关闭自动跟随', '停止自动跟随', '自动跟随关闭', '自动驾驶关闭'])) {
      return { kind: 'auto_follow', enabled: false }
    }
    if (this.containsAny(lower, ['开启真车模式', '真车模式', 'real_send'])) {
      return { kind: 'send_mode', mode: 'REAL_SEND' }
    }
    if (this.containsAny(lower, ['开启仿真模式', '仿真模式', 'dry_run', '关闭真车模式'])) {
      return { kind: 'send_mode', mode: 'DRY_RUN' }
    }
    if (this.looksLikeCaptureFrameIntent(lower)) {
      return { kind: 'capture_frame' }
    }
    if (this.containsAny(lower, ['查询状态', '状态', 'status'])) {
      return { kind: 'query_status' }
    }
    if (this.containsAny(lower, ['识别状态', '视觉状态', '识别结果', 'vision'])) {
      return { kind: 'query_vision' }
    }
    if (this.containsAny(lower, ['网络', '通信'])) {
      return { kind: 'query_comm' }
    }
    if (this.containsAny(lower, ['视频', '相机'])) {
      return { kind: 'query_video' }
    }

    return undefined
  }

  private parseLocalPlannedTasks(text: string): Array<Page4PlannedTask> {
    const clauses: Array<string> = this.splitPromptToClauses(text)
    const out: Array<Page4PlannedTask> = []
    for (let i: number = 0; i < clauses.length; i++) {
      const task: Page4PlannedTask | undefined = this.parseTaskFromClause(clauses[i])
      if (!task) continue
      out.push(task)
    }
    return out
  }

  private looksLikeMultiTask(text: string): boolean {
    const x: string = text.trim()
    if (x.length <= 0) return false
    if (this.splitPromptToClauses(x).length >= 2) return true
    return this.containsAny(x, ['然后', '接着', '并且', '同时', '再', '随后', ';', '；', ',', '，'])
  }

  private looksLikeControlIntent(text: string, lower: string): boolean {
    if (text.trim().length <= 0) return false
    if (this.looksLikeMultiTask(text)) return true
    if (this.extractDestNode(text).length > 0) return true
    const keywords: Array<string> = [
      '导航', '前往', '去', '到',
      '返仓', '回仓', '返航', '回基地', '回中心', '回物流中心', '回快递点', '回仓库', '返仓库',
      '前进', '后退', '左转', '右转', '掉头', '停止', '急停', '刹车',
      '自动跟随', '自动驾驶', '真车模式', '仿真模式', 'real_send', 'dry_run',
      '撤销', '回到安全点',
      '抓拍', '截图', '拍照', '相机', '视频',
      '查询状态', '状态', '识别', '视觉', '通信', '网络',
      '读取文件', '读文件', '文件内容', '进程列表', '查询进程', '执行命令', '命令行', 'process', 'read_file', 'exec_cmd'
    ]
    return this.containsAny(lower, keywords)
  }

  private mapActionToken(actionText: string): Page1Action | undefined {
    const t: string = actionText.trim().toUpperCase()
    if (t === 'GO' || t === 'FORWARD') return Page1Action.GO
    if (t === 'BACK' || t === 'BACKWARD') return Page1Action.BACK
    if (t === 'LEFT' || t === 'TURN_LEFT') return Page1Action.LEFT
    if (t === 'RIGHT' || t === 'TURN_RIGHT') return Page1Action.RIGHT
    if (t === 'UTURN' || t === 'U_TURN') return Page1Action.UTURN
    if (t === 'STOP') return Page1Action.STOP
    if (t === 'SCRAM' || t === 'ESTOP') return Page1Action.SCRAM
    return undefined
  }

  private normalizeMethodName(raw: string): string {
    const name: string = raw.trim().toLowerCase()
    if (name === 'undo_last_action') return 'undo_to_safe_point'
    if (name === 'capture_current_frame') return 'get_camera_frame'
    return name
  }

  private isAllowedMethodName(raw: string): boolean {
    const name: string = this.normalizeMethodName(raw)
    const allowed: Array<string> = [
      'start_manual_route',
      'send_action',
      'set_auto_follow',
      'set_send_mode',
      'speak_text',
      'undo_to_safe_point',
      'get_camera_frame',
      'query_status',
      'query_vision',
      'query_comm',
      'query_video',
      'read_file',
      'process_list',
      'exec_cmd',
      'set_recognition',
      'set_auto_report',
      'set_vision_mode',
      'set_adaptive_strategy',
      'tablet_set_alarm',
      'tablet_open_app',
      'tablet_list_alarm',
      'tablet_start_ability',
      'tablet_open_url'
    ]
    for (let i: number = 0; i < allowed.length; i++) {
      if (allowed[i] === name) return true
    }
    return false
  }

  private extractJsonObject(text: string): string {
    const src: string = text.trim()
    if (src.length <= 0) return ''
    const codeBlock: RegExpMatchArray | null = src.match(/```(?:json)?\s*([\s\S]*?)```/i)
    const body: string = codeBlock && codeBlock.length > 1 ? codeBlock[1].trim() : src
    const start: number = body.indexOf('{')
    const end: number = body.lastIndexOf('}')
    if (start < 0 || end <= start) return ''
    return body.substring(start, end + 1)
  }

  private mapOpenClawPlan(text: string): Array<Page4PlannedTask> {
    const jsonText: string = this.extractJsonObject(text)
    if (jsonText.length <= 0) return []
    try {
      const root: Record<string, Object | string | number | boolean | Array<Object>> =
        JSON.parse(jsonText) as Record<string, Object | string | number | boolean | Array<Object>>
      const arr: Array<Record<string, Object | string | number | boolean>> = Array.isArray(root['tasks'])
        ? (root['tasks'] as Array<Record<string, Object | string | number | boolean>>)
        : []
      const out: Array<Page4PlannedTask> = []
      for (let i: number = 0; i < arr.length; i++) {
        const t: Record<string, Object | string | number | boolean> = arr[i]
        const typeText: string = String(t['type'] ?? '').trim().toLowerCase()
        if (typeText === 'route') {
          const dest: string = String(t['dest'] ?? '').trim().toUpperCase()
          if (dest.length > 0) out.push({ kind: 'route', destNodeId: dest })
          continue
        }
        if (typeText === 'action') {
          const action: Page1Action | undefined = this.mapActionToken(String(t['action'] ?? ''))
          if (action !== undefined) out.push({ kind: 'action', action: action })
          continue
        }
        if (typeText === 'auto_follow') {
          const v: string = String(t['enabled'] ?? '').trim().toLowerCase()
          if (v === 'true' || v === '1' || v === 'on') out.push({ kind: 'auto_follow', enabled: true })
          else if (v === 'false' || v === '0' || v === 'off') out.push({ kind: 'auto_follow', enabled: false })
          continue
        }
        if (typeText === 'send_mode') {
          const v: string = String(t['mode'] ?? '').trim().toUpperCase()
          if (v === 'REAL_SEND' || v === 'DRY_RUN') out.push({ kind: 'send_mode', mode: v as 'REAL_SEND' | 'DRY_RUN' })
          continue
        }
        if (typeText === 'capture_frame') {
          out.push({ kind: 'capture_frame' })
          continue
        }
        if (typeText === 'undo') {
          out.push({ kind: 'undo' })
          continue
        }
        if (typeText === 'query_status') {
          out.push({ kind: 'query_status' })
          continue
        }
        if (typeText === 'query_vision') {
          out.push({ kind: 'query_vision' })
          continue
        }
        if (typeText === 'query_comm') {
          out.push({ kind: 'query_comm' })
          continue
        }
        if (typeText === 'query_video') {
          out.push({ kind: 'query_video' })
          continue
        }
        if (typeText === 'method') {
          const name: string = this.normalizeMethodName(String(t['name'] ?? ''))
          const argsRaw: Object | string | number | boolean | undefined = t['args']
          const args: Record<string, Object | string | number | boolean | undefined> =
            typeof argsRaw === 'object' && argsRaw !== null
              ? (argsRaw as Record<string, Object | string | number | boolean | undefined>)
              : {}
          if (!this.isAllowedMethodName(name)) continue
          out.push({ kind: 'method', methodName: name, methodArgs: args })
          continue
        }
        if (typeText === 'call') {
          const name: string = this.normalizeMethodName(String(t['method'] ?? ''))
          const argsRaw: Object | string | number | boolean | undefined = t['params']
          const args: Record<string, Object | string | number | boolean | undefined> =
            typeof argsRaw === 'object' && argsRaw !== null
              ? (argsRaw as Record<string, Object | string | number | boolean | undefined>)
              : {}
          if (!this.isAllowedMethodName(name)) continue
          out.push({ kind: 'method', methodName: name, methodArgs: args })
          continue
        }
      }
      return out
    } catch (e) {
      hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, 'mapOpenClawPlan JSON解析失败: %{public}s',
        e instanceof Error ? e.message : String(e))
      return []
    }
  }

  private async planTasksByOpenClaw(input: string): Promise<Array<Page4PlannedTask>> {
    return await Page4OpenClawTaskPlannerModule.planTasksByOpenClaw(input, {
      resolveTokenCandidates: (): Array<string> => resolveOpenClawTokenCandidates(),
      resolveHosts: (): Array<string> => this.rankOpenClawHosts(resolveOpenClawHostCandidates(deviceNetworkResolver.resolveGatewayIp())),
      gatewayState: (): {
        lastGoodOpenClawHost: string,
        openClawHostCooldownUntilMs: Record<string, number>,
        openClawHostCooldownMs: number
      } => ({
        lastGoodOpenClawHost: this.lastGoodOpenClawHost,
        openClawHostCooldownUntilMs: this.openClawHostCooldownUntilMs,
        openClawHostCooldownMs: this.openClawHostCooldownMs
      }),
      applyGatewayState: (state): void => {
        this.lastGoodOpenClawHost = state.lastGoodOpenClawHost
        this.openClawHostCooldownUntilMs = state.openClawHostCooldownUntilMs
      },
      mapOpenClawPlan: (text: string): Array<Page4PlannedTask> => this.mapOpenClawPlan(text),
      buildRuntimePrompt: (): string => this.buildOpenClawRuntimeContextPrompt(),
      connectTimeoutMs: (): number => Math.min(10000, this.adaptiveOpenClawConnectTimeoutMs),
      readTimeoutMs: (): number => Math.min(60000, this.adaptiveOpenClawReadTimeoutMs),
      model: OPENCLAW_CHAT_MODEL
    })
  }

  private async executePlannedTasks(tasks: Array<Page4PlannedTask>): Promise<void> {
    const receipts = await Page4TaskExecutionModule.executePlannedTasks(tasks, {
      isValidGridId: (id: string): boolean => GridIdCodec.isValidId(id),
      routeWithReplanAndWaitArrival: async (dest: string): Promise<Array<Page4ExecutionReceipt>> => await this.routeWithReplanAndWaitArrival(dest),
      rememberSafePointFromStore: (): void => this.rememberSafePointFromStore(),
      onAction: async (action: Page1Action): Promise<void> => await page1Coordinator.onAction(action),
      setLastAction: (action: Page1Action): void => { this.lastAction = action },
      actionName: (action: Page1Action): string => this.actionName(action),
      setAutoFollowEnabled: (enabled: boolean): void => {
        this.store.autoFollowEnabled = enabled
        this.store.pushLog(`info assistant.autoFollow set=${enabled ? 'ON' : 'OFF'}`)
      },
      setRealSendEnabled: (enabled: boolean): void => this.store.setRealSendEnabled(enabled),
      executeRegistryMethod: async (task: Page4PlannedTask): Promise<Array<Page4ExecutionReceipt>> => await this.executeRegistryMethod(task),
      getUndoTarget: (): string => GridIdCodec.isValidId(this.prevSafeNodeId) ? this.prevSafeNodeId : this.lastSafeNodeId,
      buildCameraFrameSummaryText: (): string => this.buildCameraFrameSummaryText(),
      buildStatusSummaryText: (): string => this.buildStatusSummaryText(),
      buildVisionSummaryText: (): string => this.buildVisionSummaryText(),
      buildCommSummaryText: (): string =>
        `通信=${commStore.commStateText} connected=${commStore.commConnected} reconnect=${commStore.commReconnectCount}`,
      buildVideoSummaryText: (): string => `视频=${videoStore.rtspStateText} fps=${videoStore.diagVideoFps}`,
      buildReceipt: (taskText: string, sent: boolean, done: boolean): Page4ExecutionReceipt => this.buildReceipt(taskText, sent, done)
    })
    if (receipts.length > 0) {
      this.pushAssistant(`执行回执：${this.renderReceiptsSummary(receipts)}`)
    }
  }

  private setManagedTimeout(cb: () => void, delayMs: number): number {
    return Page4TimerModule.setManagedTimeout(this.managedTimerIds, cb, delayMs)
  }

  private clearManagedTimer(timerId: number): number {
    return Page4TimerModule.clearManagedTimer(this.managedTimerIds, timerId)
  }

  private clearAllManagedTimers(): void {
    Page4TimerModule.clearAllManagedTimers(this.managedTimerIds)
  }

  private mapPoiNameToNode(input: string): string {
    return Page4PoiBindingModule.mapPoiNameToNode(
      input,
      this.getPoiMappings(),
      (text: string): string => this.normalizePlaceInput(text)
    )
  }

  private getPoiMappings(): Array<{ node: string, aliases: Array<string> }> {
    return [
      { node: 'B1', aliases: ['海昏侯', '海昏侯国遗址', '海昏侯国遗址公园','快递点'] },
      { node: 'D1', aliases: ['江西省博物馆', '省博物馆'] },
      { node: 'F1', aliases: ['青山湖风景区', '青山湖'] },
      { node: 'A2', aliases: ['梅岭风景区', '梅岭'] },
      /*B2对应滕王阁*/
      { node: 'B2', aliases: ['滕王阁'] },
      { node: 'F2', aliases: ['八一广场'] },
      { node: 'G2', aliases: ['高新区住宅群', '艾溪湖东岸小区', '艾溪湖东岸', '艾溪湖'] },
      { node: 'A4', aliases: ['南昌之星摩天轮', '南昌之星', '摩天轮'] },
      { node: 'B4', aliases: ['万寿宫历史文化街区', '万寿宫'] },
      { node: 'F4', aliases: ['八一起义纪念馆'] },
      /*G4对应南昌火车站*/
      { node: 'G4', aliases: ['南昌火车站', '铁路社区', '火车站'] },
      { node: 'A6', aliases: ['赣江风光带', '风光带'] },
      { node: 'B6', aliases: ['绳金塔'] },
      { node: 'F6', aliases: ['青云谱小区群', '三店西路社区', '青云谱'] },
      { node: 'G6', aliases: ['象湖湿地公园', '象湖新城小区', '象湖新城', '象湖'] },
      { node: 'B7', aliases: ['秋水广场', '昌南体育中心'] },
      { node: 'D7', aliases: ['八大山人纪念馆', '八大山人'] },
      { node: 'F7', aliases: ['小蓝工业园', '莲塘住宅区', '莲塘','物流中心'] },
      // crash_hilog.txt 中的黑线/道路参考，映射到代表点位
      { node: 'D1', aliases: ['英雄大道'] },
      { node: 'F1', aliases: ['扬子洲大桥'] },
      { node: 'B2', aliases: ['阳明路', '八一大桥', '中山路'] },
      { node: 'B4', aliases: ['南昌大桥', '站前路'] },
      { node: 'F4', aliases: ['抚河路', '象山路'] },
      { node: 'B6', aliases: ['昌南大道'] },
      { node: 'A4', aliases: ['枫生快速路'] },
      { node: 'B2', aliases: ['赣江', '八一桥', '南昌桥'] },
      { node: 'G4', aliases: ['洪都大道'] }
    ]
  }

  private buildPoiMappingSummaryText(): string {
    return Page4PoiBindingModule.buildPoiMappingSummaryText(
      this.getPoiMappings(),
      this.aliasDict,
      (id: string): boolean => GridIdCodec.isValidId(id),
      (role: Page4PlaceRole): string => this.formatPlaceBinding(role)
    )
  }

  private exportPoiMappingsToFile(): { ok: boolean, path: string, error: string } {
    this.ensurePlaceBindingsLoaded()
    const exportPath: string = `${this.getFilesDir()}/${PAGE4_POI_EXPORT_FILE}`
    return Page4PoiBindingModule.exportPoiMappingsToFile(
      exportPath,
      this.homeNodeId,
      this.companyNodeId,
      this.getPoiMappings(),
      this.aliasDict
    )
  }

  private buildOpenClawRuntimeContextPrompt(): string {
    const mappingText: string = this.buildPoiMappingSummaryText()
    const mode: string = this.store.realSendEnabled ? 'REAL_SEND' : 'DRY_RUN'
    return Page4PromptContextModule.buildOpenClawRuntimeContextPrompt(mode, this.store.autoFollowEnabled, mappingText)
  }

  private buildOpenClawRuntimeContextPromptLite(): string {
    const mode: string = this.store.realSendEnabled ? 'REAL_SEND' : 'DRY_RUN'
    return Page4PromptContextModule.buildOpenClawRuntimeContextPromptLite(mode, this.store.autoFollowEnabled, this.connStateText())
  }

  private normalizePlaceInput(text: string): string {
    return Page4PromptContextModule.normalizePlaceInput(text)
  }

  private extractDestNode(input: string): string {
    const aliasNode: string = this.resolveAliasNode(input)
    if (aliasNode.length > 0) return aliasNode

    const fromContext: string = this.resolveContextDestNode(input)
    if (fromContext.length > 0) return fromContext

    const fromShortcut: string = this.resolveFastDestShortcut(input)
    if (fromShortcut.length > 0) return fromShortcut

    const upper: string = input.trim().toUpperCase()
    const m1: RegExpMatchArray | null = upper.match(/(?:导航到|前往|去|到达|前进到)\s*([A-Z]\d{1,2})/)
    if (m1 && m1.length > 1) return m1[1]
    const antiNav: RegExpMatchArray | null = upper.match(/(?:离开|从|出发|起点|LEAVE|FROM|DEPART)\s*([A-Z]\d{1,2})/)
    if (antiNav) return ''
    const m2: RegExpMatchArray | null = upper.match(/\b([A-Z]\d{1,2})\b/)
    if (m2 && m2.length > 1) return m2[1]
    const mapped: string = this.mapPoiNameToNode(input)
    if (mapped.length > 0) return mapped
    return ''
  }

  private resolveFastDestShortcut(input: string): string {
    const raw: string = input.trim()
    if (raw.length <= 0) return ''
    const lower: string = raw.toLowerCase()
    const homeNode: string = GridIdCodec.isValidId(this.homeNodeId) ? this.homeNodeId : ''
    const companyNode: string = GridIdCodec.isValidId(this.companyNodeId) ? this.companyNodeId : ''

    if (this.containsAny(raw, [
      '前往物流中心', '去物流中心', '到物流中心', '返回物流中心', '回物流中心',
      '返仓', '回仓', '返航', '回基地', '返回基地', '回中心'
    ]) || this.containsAny(lower, ['go home', 'to home'])) {
      return homeNode
    }

    if (this.containsAny(raw, [
      '前往快递点', '去快递点', '到快递点', '返回快递点', '回快递点',
      '前往公司仓库', '去公司仓库', '到公司仓库', '返回公司仓库', '回公司仓库'
    ]) || this.containsAny(lower, ['go company', 'to company'])) {
      return companyNode
    }

    if (this.containsAny(raw, ['返回快递点'])) {
      return companyNode
    }

    if (this.containsAny(raw, ['前往仓库', '去仓库', '到仓库', '回仓库', '返回仓库'])) {
      if (companyNode.length > 0) return companyNode
      return homeNode
    }

    return ''
  }

  private actionName(action: Page1Action): string {
    if (action === Page1Action.GO) return '前进'
    if (action === Page1Action.BACK) return '后退'
    if (action === Page1Action.LEFT) return '左转'
    if (action === Page1Action.RIGHT) return '右转'
    if (action === Page1Action.UTURN) return '掉头'
    if (action === Page1Action.STOP) return '停止'
    if (action === Page1Action.SCRAM) return '紧急停止'
    if (action === Page1Action.TFTA) return 'TFTA'
    return '动作'
  }

  private resolveActionByText(textLower: string): Page1Action | undefined {
    if (this.containsAny(textLower, ['再来一次', '重复上一动作', '继续刚才动作', 'repeat'])) {
      return this.lastAction
    }
    if (this.containsAny(textLower, ['紧急停止', '急停', 'scram'])) return Page1Action.SCRAM
    if (this.containsAny(textLower, ['停止', '停车', 'stop'])) return Page1Action.STOP
    if (this.containsAny(textLower, ['前进', '向前', 'go'])) return Page1Action.GO
    if (this.containsAny(textLower, ['后退', '倒车', 'back'])) return Page1Action.BACK
    if (this.containsAny(textLower, ['左转'])) return Page1Action.LEFT
    if (this.containsAny(textLower, ['右转'])) return Page1Action.RIGHT
    if (this.containsAny(textLower, ['掉头'])) return Page1Action.UTURN
    return undefined
  }

  private buildStatusSummaryText(): string {
    const mode: string = this.store.realSendEnabled ? 'REAL_SEND' : 'DRY_RUN'
    const recText: string = recogStore.recogText.length > 0 ? recogStore.recogText : '-'
    return `链路=${this.connStateText()} | 模式=${mode} | 自动跟随=${this.store.autoFollowEnabled ? 'ON' : 'OFF'} | 风险=${this.store.riskText}(${this.store.riskScore}) | TX/RX=${this.store.txFrames}/${this.store.rxFrames} | Recog=${recText}`
  }

  private buildOrderQueryText(
    queryText: string,
    mode: 'all' | 'earliest' | 'latest' = 'all',
    statusFilter: string = ''
  ): string {
    void queryText
    void mode
    void statusFilter
    return '暂无订单数据，请接入真实数据源'
  }

  private looksLikeOrderQueryIntent(text: string, lower: string): boolean {
    const hasDomain: boolean = this.containsAny(lower, [
      '订单', '出库单', '订单记录', '拣货', '复核', '发货', '出库'
    ])
    if (!hasDomain) return false
    const hasVerb: boolean = this.containsAny(lower, [
      '查', '查询', '查找', '查看', '看看', '给我', '列出', '统计', '记录'
    ])
    if (hasVerb) return true
    if (this.containsAny(lower, ['已发货'])) return true
    if (this.containsAny(lower, ['最早', '最晚', '最新', '全部', '所有'])) return true
    if (text.match(/OUT-\d{8}-\d{3}/i)) return true
    if (text.match(/[A-Z]{2}-\d{4}/i)) return true
    return false
  }

  private buildVisionSummaryText(): string {
    const r = recogStore.lastRecog
    if (!r) return '暂无识别结果。'
    if (!r.ok) return `识别失败: ${r.errorText}`

    let labels: string = ''
    const maxN: number = r.boxes.length > 3 ? 3 : r.boxes.length
    for (let i: number = 0; i < maxN; i++) {
      const one = r.boxes[i]
      const part: string = `${one.label}(${one.score.toFixed(2)})`
      labels = labels.length <= 0 ? part : `${labels}, ${part}`
    }
    if (labels.length <= 0) labels = '无检测框'
    return `识别引擎=${r.engine} | boxes=${r.boxes.length} | ${labels}`
  }

  private looksLikeCaptureFrameIntent(textLower: string): boolean {
    return this.containsAny(textLower, [
      '获取当前摄像头画面',
      '获取当前画面',
      '抓取当前画面',
      '读取当前画面',
      '保存当前画面',
      '给我当前画面',
      '看一下当前画面',
      'camera frame',
      'current frame',
      'capture frame'
    ])
  }

  private displayModeText(v: number): string {
    if (v === 0) return 'RTSP'
    if (v === 1) return 'HTTP'
    if (v === 2) return 'LOCAL'
    return String(v)
  }

  private buildCameraFrameSummaryText(): string {
    const hasFrame: boolean = typeof videoStore.livePixelMap !== 'undefined'
    const nowMs: number = Date.now()
    const lastOkMs: number = Math.max(0, Math.trunc(videoStore.lastOkFrameTimeMs))
    const ageText: string = lastOkMs > 0 ? `${Math.max(0, nowMs - lastOkMs)}ms` : '未知'
    const frameText: string = hasFrame ? '已获取当前摄像头画面' : '当前暂无可用摄像头画面'

    return `${frameText} | 模式=${this.displayModeText(videoStore.displayMode)} | rtsp=${videoStore.rtspStateText} | fps=${videoStore.diagVideoFps} | 最近画面年龄=${ageText}`
  }

  private buildExampleText(): string {
    return '示例指令：\n1. 导航到 D4\n2. 前往物流中心 / 回仓 / 返仓 / 回快递点\n3. 前进 / 后退 / 左转 / 右转 / 停止\n4. 开启自动跟随 / 关闭自动跟随\n5. 开启真车模式 / 开启仿真模式\n6. 查询状态\n7. 识别状态\n8. 获取当前摄像头画面\n9. 查看所有点位映射名称\n10. 导出点位映射为JSON\n11. 读取文件 C:\\\\temp\\\\a.txt\n12. 查询进程列表\n13. 执行命令 Get-Process'
  }

  private buildOpenClawMessages(maxHistory: number = 8): Array<OpenClawChatMessage> {
    return Page4PromptContextModule.buildOpenClawMessages(
      this.messages,
      this.openClawSystemPrompt,
      this.buildOpenClawRuntimeContextPromptLite(),
      maxHistory
    )
  }

  private async answerByOpenClaw(): Promise<void> {
    await Page4OpenClawChatModule.answerByOpenClaw({
      resolveTokenCandidates: (): Array<string> => resolveOpenClawTokenCandidates(),
      resolveHosts: (): Array<string> => this.rankOpenClawHosts(resolveOpenClawHostCandidates(deviceNetworkResolver.resolveGatewayIp())),
      buildOpenClawMessages: (): Array<OpenClawChatMessage> => this.buildOpenClawMessages(),
      gatewayState: (): { lastGoodOpenClawHost: string, openClawHostCooldownUntilMs: Record<string, number>, openClawHostCooldownMs: number } => ({
        lastGoodOpenClawHost: this.lastGoodOpenClawHost,
        openClawHostCooldownUntilMs: this.openClawHostCooldownUntilMs,
        openClawHostCooldownMs: this.openClawHostCooldownMs
      }),
      applyGatewayState: (state): void => {
        this.lastGoodOpenClawHost = state.lastGoodOpenClawHost
        this.openClawHostCooldownUntilMs = state.openClawHostCooldownUntilMs
      },
      setAssistantBusy: (busy: boolean): void => { this.assistantBusy = busy },
      setManagedTimeout: (cb: () => void, delayMs: number): number => this.setManagedTimeout(cb, delayMs),
      clearManagedTimer: (id: number): number => this.clearManagedTimer(id),
      connectTimeoutMs: (): number => Math.min(12000, this.adaptiveOpenClawConnectTimeoutMs),
      readTimeoutMs: (): number => Math.min(60000, this.adaptiveOpenClawReadTimeoutMs),
      model: OPENCLAW_CHAT_MODEL,
      pushAssistant: (text: string, typed?: boolean): void => this.pushAssistant(text, typed),
      logInfo: (name: string, message: string): void => this.logInfo(name, message),
      logError: (name: string, message: string): void => this.logError(name, message)
    })
  }

  private rankOpenClawHosts(inputHosts: Array<string>): Array<string> {
    const out: Array<string> = []
    const normal: Array<string> = []
    const cooling: Array<string> = []
    const nowMs: number = Date.now()
    const pushUnique = (arr: Array<string>, host: string): void => {
      for (let i: number = 0; i < arr.length; i++) {
        if (arr[i] === host) return
      }
      arr.push(host)
    }

    for (let i: number = 0; i < inputHosts.length; i++) {
      const host: string = inputHosts[i].trim()
      if (host.length <= 0) continue
      if (this.isOpenClawHostCooling(host, nowMs)) {
        pushUnique(cooling, host)
      } else {
        pushUnique(normal, host)
      }
    }

    const preferred: string = this.lastGoodOpenClawHost.trim()
    if (preferred.length > 0) {
      for (let i: number = 0; i < normal.length; i++) {
        if (normal[i] === preferred) {
          out.push(preferred)
          break
        }
      }
    }

    for (let i: number = 0; i < normal.length; i++) {
      const host: string = normal[i]
      let exists: boolean = false
      for (let j: number = 0; j < out.length; j++) {
        if (out[j] === host) {
          exists = true
          break
        }
      }
      if (!exists) out.push(host)
    }

    for (let i: number = 0; i < cooling.length; i++) {
      out.push(cooling[i])
    }

    return out
  }

  private isOpenClawHostCooling(host: string, nowMs: number): boolean {
    const untilMs: number | undefined = this.openClawHostCooldownUntilMs[host]
    return typeof untilMs === 'number' && untilMs > nowMs
  }

  private markOpenClawHostSuccess(host: string): void {
    this.lastGoodOpenClawHost = host
    this.openClawHostCooldownUntilMs[host] = 0
  }

  private markOpenClawHostFail(host: string): void {
    this.openClawHostCooldownUntilMs[host] = Date.now() + this.openClawHostCooldownMs
  }

  //方法调用
  private async RaprouteWith(dest: string, inputText: string = ''): Promise<boolean> {
    if (dest.length <= 0) return false
    if (!GridIdCodec.isValidId(dest)) {
      this.pushAssistant(`"${dest}" 不是合法的路网节点，请说如 "导航到D4" 等有效节点。`)
      return true
    }
    this.logInfo('sendRoutePlanRequest', `dest=${dest}`)
    const routeReceipts: Array<Page4ExecutionReceipt> = await this.routeWithReplanAndWaitArrival(dest)
    const routedOk: boolean = routeReceipts.length > 0 && routeReceipts[0].sent
    if (routedOk) this.logInfo('sendRoutePlanSuccess', `dest=${dest}`)
    else this.logError('sendRoutePlanFail', `dest=${dest}, reason=${this.lastRouteFailureReason}`)
    const targetText: string = this.routeTargetDisplayText(dest, inputText)
    if (routedOk) {
      this.pushAssistant(`已成功导航到 ${targetText}。执行回执：${this.renderReceiptsSummary(routeReceipts)}`)
    } else {
      this.pushAssistant(`导航失败。执行回执：${this.renderReceiptsSummary(routeReceipts)}`)
    }
    return true
  }

  private async quickRouteToPlaceShortcut(text: string): Promise<boolean> {
    const quickDest: string = this.resolveFastDestShortcut(text)
    if (!GridIdCodec.isValidId(quickDest)) return false

    this.logInfo('quickRouteShortcut', `dest=${quickDest}`)
    const routed = await this.routeWithReplan(quickDest)
    const targetText: string = this.routeTargetDisplayText(quickDest, text)
    if (routed.ok) {
      this.pushAssistant(`已成功导航到 ${targetText}。执行回执：${this.renderReceiptsSummary([routed.receipt])}`)
    } else {
      this.pushAssistant(`导航失败。执行回执：${this.renderReceiptsSummary([routed.receipt])}`)
    }
    return true
  }

  private routeTargetDisplayText(destNodeId: string, inputText: string): string {
    const raw: string = inputText.trim()
    const lower: string = raw.toLowerCase()
    if (this.containsAny(raw, ['物流中心', '回仓', '返仓', '返航', '回基地', '回中心']) || this.containsAny(lower, ['go home', 'to home'])) {
      return '物流中心'
    }
    if (this.containsAny(raw, ['快递点', '公司仓库', '回快递点', '返回快递点']) || this.containsAny(lower, ['go company', 'to company'])) {
      return '快递点'
    }
    const x: string = destNodeId.trim().toUpperCase()
    const mappings: Array<{ node: string, aliases: Array<string> }> = this.getPoiMappings()
    for (let i: number = 0; i < mappings.length; i++) {
      const one = mappings[i]
      if (one.node.trim().toUpperCase() !== x) continue
      for (let j: number = 0; j < one.aliases.length; j++) {
        const alias: string = one.aliases[j].trim()
        if (alias.length > 0) return alias
      }
    }
    return x
  }

  private async submitPrompt(raw: string, fromQueue: boolean = false, _source: string = 'text'): Promise<void> {
    const text: string = raw.trim()
    if (text.length <= 0) return

    if (!fromQueue && this.assistantBusy) {
      this.pushAssistant('上一条消息仍在处理中，请稍候。')
      return
    }

    this.applyAdaptiveStrategy()
    this.pushUser(text)
    this.inputText = ''

    const lower: string = text.toLowerCase()
    if (await this.handlePlaceBindingPrompt(text, lower)) {
      return
    }

    if (await this.quickRouteToPlaceShortcut(text)) {
      return
    }

    const aliasLearn: string = this.learnAliasFromText(text)
    if (aliasLearn.length > 0) {
      this.pushAssistant(aliasLearn)
      return
    }

    if (this.containsAny(lower, ['撤销', 'undo', '回到上一个安全点', '回到安全点'])) {
      await this.undoLastActionToSafePoint()
      return
    }

    if (this.containsAny(lower, ['夜间策略', '弱网策略', '稳态策略', '稳定策略'])) {
      this.applyAdaptiveStrategy(true)
      return
    }

    if (this.containsAny(lower, ['导航失败原因', '失败原因', '重规划方案', '为什么失败'])) {
      const reason: string = this.lastRouteFailureReason.length > 0 ? this.lastRouteFailureReason : '暂无失败记录'
      const replan: string = this.lastReplanSummary.length > 0 ? this.lastReplanSummary : '暂无重规划记录'
      this.pushAssistant(`导航语义查询：失败原因=${reason}；新方案=${replan}`)
      return
    }

    if (this.containsAny(lower, ['所有点位', '点位映射', '映射名称', '点位列表', '全部点位','查看所有映射点位'])) {
      this.pushAssistant(this.buildPoiMappingSummaryText())
      return
    }

    if (this.containsAny(lower, ['导出点位映射', '导出映射', '导出点位', '导出json', '导出为json'])) {
      const exp = this.exportPoiMappingsToFile()
      if (exp.ok) this.pushAssistant(`已导出点位映射：${exp.path}`)
      else this.pushAssistant(`导出点位映射失败：${exp.error}`)
      return
    }

    const localTasks: Array<Page4PlannedTask> = this.parseLocalPlannedTasks(text)
    if (localTasks.length >= 2) {
      await this.executePlannedTasks(localTasks)
      return
    }

    if (this.looksLikeControlIntent(text, lower)) {
      const openClawTasks: Array<Page4PlannedTask> = await this.planTasksByOpenClaw(text)
      if (openClawTasks.length > 0) {
        await this.executePlannedTasks(openClawTasks)
        return
      }
    }

    if (this.containsAny(lower, ['示例', '例子', 'help', '帮助', '怎么用'])) {
      this.pushAssistant(this.buildExampleText())
      return
    }

    if (this.looksLikeCaptureFrameIntent(lower)) {
      this.pushAssistant(this.buildCameraFrameSummaryText())
      return
    }

    if (this.containsAny(lower, ['查询状态', '状态', 'status'])) {
      this.pushAssistant(this.buildStatusSummaryText())
      return
    }

    if (this.containsAny(lower, ['识别状态', '视觉状态', '识别结果', 'vision'])) {
      this.pushAssistant(this.buildVisionSummaryText())
      return
    }

    if (this.looksLikeOrderQueryIntent(text, lower)) {
      let query: string = ''
      const idMatch: RegExpMatchArray | null = text.match(/OUT-\d{8}-\d{3}/i)
      const skuMatch: RegExpMatchArray | null = text.match(/[A-Z]{2}-\d{4}/i)
      if (idMatch && idMatch.length > 0) query = idMatch[0]
      else if (skuMatch && skuMatch.length > 0) query = skuMatch[0]
      let mode: 'all' | 'earliest' | 'latest' = 'all'
      if (this.containsAny(lower, ['最早'])) mode = 'earliest'
      if (this.containsAny(lower, ['最晚', '最新'])) mode = 'latest'
      if (this.containsAny(lower, ['全部', '所有'])) mode = 'all'
      let statusFilter: string = ''
      if (this.containsAny(lower, ['已发货'])) statusFilter = '已发货'
      this.pushAssistant(this.buildOrderQueryText(query, mode, statusFilter))
      return
    }

    if (this.containsAny(lower, ['开启自动跟随', '打开自动跟随', '自动跟随开启', '自动驾驶开启'])) {
      this.store.autoFollowEnabled = true
      this.store.pushLog('info assistant.autoFollow set=ON')
      this.pushAssistant('已开启自动跟随。')
      return
    }

    if (this.containsAny(lower, ['关闭自动跟随', '停止自动跟随', '自动跟随关闭', '自动驾驶关闭'])) {
      this.store.autoFollowEnabled = false
      this.store.pushLog('info assistant.autoFollow set=OFF')
      this.pushAssistant('已关闭自动跟随。')
      return
    }

    if (this.containsAny(lower, ['开启真车模式', '真车模式', 'real_send'])) {
      this.store.setRealSendEnabled(true)
      this.pushAssistant('已切换到 REAL_SEND。')
      return
    }

    if (this.containsAny(lower, ['开启仿真模式', '仿真模式', 'dry_run', '关闭真车模式'])) {
      this.store.setRealSendEnabled(false)
      this.pushAssistant('已切换到 DRY_RUN。')
      return
    }
    /*1.先尝试解析用户是否在下发“导航目标”*/
    const dest: string = this.extractDestNode(text)
    /*2.命中导航意图就直接走导航链路，优先保证控制实时性*/
    if (await this.RaprouteWith(dest, text))return
    /*3.如果不是导航，再识别是否是前进/停止等动作控制指令*/
    const action: Page1Action | undefined = this.resolveActionByText(lower)
    if (action !== undefined) {
      try {
        this.rememberSafePointFromStore()
        this.logInfo('sendVehicleActionRequest', `action=${this.actionName(action)}`)
        /*4.命中动作后直达底层协调器执行，避免多余中间环节*/
        await page1Coordinator.onAction(action)
        this.logInfo('sendVehicleActionSuccess', `action=${this.actionName(action)}`)
        this.lastAction = action
        this.pushAssistant(`执行回执：${this.renderReceiptsSummary([this.buildReceipt(this.actionName(action), true, true)])}`)
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'action failed'
        this.logError('sendVehicleActionFail', `action=${this.actionName(action)}, reason=${msg}`)
        this.pushAssistant(`执行回执：${this.renderReceiptsSummary([this.buildReceipt(`动作失败:${msg}`, false, false)])}`)
      }
      return
    }

    if (this.containsAny(lower, ['网络', '通信'])) {
      this.pushAssistant(`通信状态=${commStore.commStateText} | connected=${commStore.commConnected} | reconnect=${commStore.commReconnectCount} | tx/rx=${commStore.txPackets}/${commStore.rxPackets}`)
      return
    }

    if (this.containsAny(lower, ['视频', '相机'])) {
      this.pushAssistant(`视频模式=${videoStore.displayMode} | rtsp=${videoStore.rtspStateText} | fps=${videoStore.diagVideoFps} | status=${videoStore.statusText}`)
      return
    }
    /*5.前两类都不命中时，再进入AI问答兜底*/
    await this.answerByOpenClaw()
  }

  private logInfo(name: string, message: string): void {
    const text: string = `[info][${this.logTag}][${name}] ${message}`
    hilog.info(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, '%{public}s', text)
  }

  private logError(name: string, message: string): void {
    const text: string = `[error][${this.logTag}][${name}] ${message}`
    hilog.error(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, '%{public}s', text)
  }

  private ensurePlaceBindingsLoaded(): void {
    if (this.placeBindingsLoaded) return
    this.placeBindingsLoaded = true

    let f: fs.File | undefined = undefined
    try {
      const bindingPath: string = `${this.getFilesDir()}/${PAGE4_PLACE_BINDING_FILE}`
      f = fs.openSync(bindingPath, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(bindingPath)
      const size: number = Number(st.size)
      if (!Number.isFinite(size) || size <= 0 || size > 4096) {
        return
      }
      const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
      const readLen: number = fs.readSync(f.fd, buf)
      if (readLen <= 0) {
        return
      }
      const bytes: Uint8Array = new Uint8Array(buf, 0, readLen)
      const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
      const parsed: Page4PlaceBindingPayload = JSON.parse(txt) as Page4PlaceBindingPayload
      const home: string = String(parsed.homeNodeId ?? '').trim().toUpperCase()
      const company: string = String(parsed.companyNodeId ?? '').trim().toUpperCase()
      this.homeNodeId = GridIdCodec.isValidId(home) ? home : ''
      this.companyNodeId = GridIdCodec.isValidId(company) ? company : ''
    } catch (e) {
      hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, '加载点位绑定失败，使用空配置: %{public}s',
        e instanceof Error ? e.message : String(e))
      this.homeNodeId = ''
      this.companyNodeId = ''
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
    }
    page1Store.setPlaceConfigured(this.homeNodeId, this.companyNodeId)
  }

  private persistPlaceBindings(): boolean {
    let f: fs.File | undefined = undefined
    try {
      const payload: Page4PlaceBindingPayload = {
        homeNodeId: this.homeNodeId,
        companyNodeId: this.companyNodeId
      }
      const txt: string = JSON.stringify(payload)
      const bindingPath: string = `${this.getFilesDir()}/${PAGE4_PLACE_BINDING_FILE}`
      try { fs.unlinkSync(bindingPath) } catch (_) { /* 资源释放失败可安全忽略 */ }
      f = fs.openSync(bindingPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(f.fd, txt)
      return true
    } catch (e) {
      hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, '写入点位绑定失败: %{public}s',
        e instanceof Error ? e.message : String(e))
      return false
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* 资源释放失败可安全忽略 */ }
      }
    }
  }


  private parsePlaceRoleToken(raw: string): '' | Page4PlaceRole {
    return Page4PoiBindingModule.parsePlaceRoleToken(raw)
  }

  private placeRoleText(role: '' | Page4PlaceRole): string {
    return Page4PoiBindingModule.placeRoleText(role)
  }

  private parsePlaceBindingRequest(text: string): { role: Page4PlaceRole, placeText: string } | undefined {
    return Page4PoiBindingModule.parsePlaceBindingRequest(text)
  }

  private wantsPlaceBindingQuery(rawLower: string): { askHome: boolean, askCompany: boolean } | undefined {
    return Page4PoiBindingModule.wantsPlaceBindingQuery(
      rawLower,
      (text: string, keys: Array<string>): boolean => this.containsAny(text, keys)
    )
  }

  private formatPlaceBinding(role: Page4PlaceRole): string {
    const node: string = role === 'home' ? this.homeNodeId : this.companyNodeId
    return Page4PoiBindingModule.formatPlaceBinding(
      role,
      node,
      (id: string): boolean => GridIdCodec.isValidId(id)
    )
  }

  private async handlePlaceBindingPrompt(text: string, lower: string): Promise<boolean> {
    this.ensurePlaceBindingsLoaded()

    const query = this.wantsPlaceBindingQuery(lower)
    if (query) {
      const parts: Array<string> = []
      if (query.askHome) parts.push(this.formatPlaceBinding('home'))
      if (query.askCompany) parts.push(this.formatPlaceBinding('company'))
      this.pushAssistant(parts.length > 0 ? parts.join('，') : `${this.formatPlaceBinding('home')}，${this.formatPlaceBinding('company')}`)
      return true
    }

    let req: { role: Page4PlaceRole, placeText: string } | undefined = this.parsePlaceBindingRequest(text)
    if (!req && this.looksLikePlaceBindingIntent(lower)) {
      req = await this.parsePlaceBindingByOpenClaw(text)
    }
    if (!req) return false

    const nodeFromPlace: string = this.extractDestNode(req.placeText)
    const nodeFromAll: string = this.extractDestNode(text)
    const node: string = GridIdCodec.isValidId(nodeFromPlace) ? nodeFromPlace : nodeFromAll
    if (!GridIdCodec.isValidId(node)) {
      const roleText: string = this.placeRoleText(req.role)
      this.pushAssistant(`未识别到可用点位，无法设置${roleText}。请直接说节点（如“将D4设置为${roleText}”）或说可映射地名。`)
      return true
    }

    const roleText: string = this.placeRoleText(req.role)
    if (req.role === 'home') this.homeNodeId = node
    else this.companyNodeId = node
    page1Store.setPlaceConfigured(this.homeNodeId, this.companyNodeId)
    const ok: boolean = this.persistPlaceBindings()
    if (ok) {
      this.pushAssistant(`已设置：${roleText}=${node}（来源“${req.placeText}”）。${this.formatPlaceBinding('home')}，${this.formatPlaceBinding('company')}`)
    } else {
      this.pushAssistant(`已设置：${roleText}=${node}，但写入失败（本次运行仍生效）。`)
    }
    return true
  }

  private looksLikePlaceBindingIntent(lower: string): boolean {
    const hasRole: boolean =
      lower.indexOf('物流中心') >= 0 ||
      lower.indexOf('快递点') >= 0 || lower.indexOf('公司仓库') >= 0
    if (!hasRole) return false
    if (this.containsAny(lower, ['映射', '点位', '查询', '查看', '有没有', '是否'])) return false
    return this.containsAny(lower, ['设置', '设为', '记为', '定义为', '改为', '改成', '当成', '作为'])
  }

  private parsePlaceBindingPlanText(text: string): Page4PlaceBindingPlan | undefined {
    return Page4OpenClawChatModule.parsePlaceBindingPlanText(text)
  }

  private stripJsonCodeFence(text: string): string {
    return Page4OpenClawChatModule.stripJsonCodeFence(text)
  }

  private async parsePlaceBindingByOpenClaw(input: string): Promise<Page4PlaceBindingPlan | undefined> {
    const tokenCandidates: Array<string> = resolveOpenClawTokenCandidates()
    if (tokenCandidates.length <= 0) return undefined
    const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
    const hosts: Array<string> = this.rankOpenClawHosts(resolveOpenClawHostCandidates(gatewayIp))
    if (hosts.length <= 0) return undefined

    const messages: Array<OpenClawChatMessage> = [
      {
        role: 'system',
        content:
          '你是无人物流车位置映射解析器。把用户话语解析为严格JSON，不要解释。' +
          '输出格式：{"role":"home|company","place":"地点原文"}。' +
          '语义约定：home 表示物流中心，company 表示快递点。' +
          '如果无法确定，输出：{"role":"","place":""}。'
      },
      {
        role: 'system',
        content: this.buildOpenClawRuntimeContextPrompt()
      },
      {
        role: 'user',
        content: input
      }
    ]

    for (let i: number = 0; i < hosts.length; i++) {
      const host: string = hosts[i]
      for (let k: number = 0; k < tokenCandidates.length; k++) {
        const token: string = tokenCandidates[k]
        const client: OpenClawGatewayClient = new OpenClawGatewayClient({
          endpoint: buildOpenClawChatCompletionsUrl(host),
          bearerToken: token,
          model: OPENCLAW_CHAT_MODEL,
          connectTimeoutMs: Math.min(OPENCLAW_CONNECT_TIMEOUT_MS, this.adaptiveOpenClawConnectTimeoutMs),
          readTimeoutMs: Math.min(OPENCLAW_READ_TIMEOUT_MS, this.adaptiveOpenClawReadTimeoutMs)
        })
        try {
          const result = await client.complete(messages)
          if (!result.ok) {
            continue
          }
          const plan: Page4PlaceBindingPlan | undefined = this.parsePlaceBindingPlanText(result.text)
          if (plan) {
            this.markOpenClawHostSuccess(host)
            return plan
          }
        } catch (e) {
          hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG,
            'parsePlaceBindingByOpenClaw 候选失败 host=%{public}s: %{public}s',
            host, e instanceof Error ? e.message : String(e))
          continue
        }
      }
      this.markOpenClawHostFail(host)
    }
    return undefined
  }
}

