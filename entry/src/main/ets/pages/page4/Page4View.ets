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
  OPENCLAW_CHAT_MODEL,
  OPENCLAW_CONNECT_TIMEOUT_MS,
  setRuntimeSecret,
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
import { OpenClawChatMessage } from '../../services/assistant/OpenClawGatewayClient'
import { PcToolGatewayClient } from '../../services/assistant/PcToolGatewayClient'
import { TabletCompanionClient } from '../../services/assistant/TabletCompanionClient'
import { installPage4TencentVoiceInputAdapter } from '../../services/assistant/Page4TencentVoiceInputAdapter'
import { page4TencentLocalTtsService } from '../../services/assistant/Page4TencentLocalTtsService'
import hilog from '@ohos.hilog'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import resourceManager from '@ohos.resourceManager'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'
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
import { Page4Keywords } from './config/Page4Keywords'
import { Page4ReplyText } from './config/Page4ReplyText'
import { Page4GatewayLayer } from './gateway/Page4GatewayLayer'
import { Page4GatewayState } from './gateway/Page4GatewayLayer'

const PAGE4_LOG_DOMAIN = 0xFF04
const PAGE4_LOG_TAG = 'page4log'
const PAGE4_PLACE_BINDING_FILE: string = 'page4_place_bindings.json'
const PAGE4_POI_EXPORT_FILE: string = 'page4_poi_mappings_export.json'
const PAGE4_ORDER_DATA_RAWFILE: string = 'dingdan.txt'
const PAGE4_VOICE_REPLY_PREF_FILE: string = 'page4_voice_reply_pref.json'
const PAGE4_RUNTIME_TOKEN_FILE: string = 'openclaw.env.json'
const PAGE4_PUBLIC_TOKEN_PATHS: Array<string> = [
  '/sdcard/Download/openclaw.env.json',
  '/storage/self/primary/Download/openclaw.env.json',
  '/data/local/tmp/openclaw.env.json',
  '/storage/media/100/local/files/openclaw.env.json',
  '/storage/media/100/local/files/Docs/openclaw.env.json',
  '/storage/media/100/local/files/Docs/Download/openclaw.env.json'
]
const PAGE4_TOKEN_SETUP_HINT: string =
  '/sdcard/Download/openclaw.env.json'
const ADAPTIVE_WEAK_RECOG_INTERVAL_MS: number = 450
const ADAPTIVE_WEAK_SWITCH_COOLDOWN_MS: number = 4000
const ADAPTIVE_WEAK_CONNECT_TIMEOUT_MS: number = 10000
const ADAPTIVE_WEAK_READ_TIMEOUT_MS: number = 60000
const ADAPTIVE_NORMAL_RECOG_INTERVAL_MS: number = 220
const ADAPTIVE_NORMAL_SWITCH_COOLDOWN_MS: number = 2500

type AssistantMessage = SessionAssistantMessage
type HistorySession = SessionHistorySession

interface OutboundOrder {
  orderId: string
  skuCode: string
  productName: string
  quantity: number
  zone: string
  status: string
  createTime: string
}


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
  @State private queryThinkingVisible: boolean = false
  @State private queryThinkingStageText: string = '\u601d\u8003\u4e2d...'
  @State private queryThinkingProgressPct: number = 0
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
  private queryThinkingTimerId: number = -1
  private queryThinkingToken: number = 0
  private queryThinkingStartMs: number = 0
  private readonly queryThinkingMinDurationMs: number = 3000

  private longPressTimerId: number = -1
  private readonly managedTimerIds: Set<number> = new Set<number>()
  private readonly longPressThresholdMs: number = 320
  private lastGoodOpenClawHost: string = ''
  private openClawHostCooldownUntilMs: Record<string, number> = {}
  private readonly openClawHostCooldownMs: number = 25000
  private openClawWsSessionKey: string = ''
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
    '你是无人物流车的车控与调度助手。默认地址=江西省南昌市。优先使用简洁中文回复；涉及行驶、安全、货物操作时先给出明确、安全、可执行的步骤。' +
    '如果进入AI问答，请按固定格式回复：第一行“思考过程：”用1到2句简短说明判断依据；第二行“最终回答：”给出结论与建议。不要使用省略号。'
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
  private placeBindingTraceText: string = 'placeBinding.idle'
  private readonly routeArrivalTimeoutMs: number = 180000
  private readonly routeArrivalPollMs: number = 300
  private outboundOrders: Array<OutboundOrder> = []

  aboutToAppear(): void {
    this.loadVoiceReplyPreference()
    this.loadRuntimeTokenConfig()
    void this.ensureMediaReadPermissionAndReloadTokenConfig()
    this.ensurePlaceBindingsLoaded()
    void this.ensureOrderDataLoaded()
    installPage4TencentVoiceInputAdapter()
    page1Coordinator.bind(this.store)
    void page1Coordinator.start()
    this.applyAdaptiveStrategy()
    this.chatScroller = new Scroller()
    if (this.messages.length <= 0) {
      this.pushAssistant(Page4ReplyText.WELCOME)
    }
    this.stabilizeChatTopOnEnter()
  }

  aboutToDisappear(): void {
    this.stopAssistantTyping()
    this.endQueryThinkingProgress()
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
              this.persistVoiceReplyPreference()
              this.showToast(this.voiceReplyEnabled ? Page4ReplyText.VOICE_REPLY_ON : Page4ReplyText.VOICE_REPLY_OFF)
              if (this.voiceReplyEnabled) void this.previewVoiceReplyAfterEnable()
              else page4TencentLocalTtsService.stop()
            },
            onNewChat: (): void => {
              if (this.isCurrentNewChat()) {
                this.showToast(Page4ReplyText.NEW_CHAT_EXISTS)
                return
              }
              this.archiveCurrentChatTitle()
              animateTo({ duration: 300 }, (): void => {
                this.messages = []
                this.currentChatTitle = '新对话'
                this.pushAssistant(Page4ReplyText.WELCOME)
              })
              this.scrollChatToTopSoon()
            }
          })
          Page4ChatPanel({
            chatScroller: this.chatScroller,
            messages: this.messages,
            assistantBusy: this.assistantBusy,
            queryThinkingVisible: this.queryThinkingVisible,
            queryThinkingStageText: this.queryThinkingStageText,
            queryThinkingProgressPct: this.queryThinkingProgressPct
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
    if (this.voiceRecording) return Page4ReplyText.VOICE_BUTTON_RECORDING
    if (this.voicePressing) return Page4ReplyText.VOICE_BUTTON_PRESSING
    return Page4ReplyText.VOICE_BUTTON_IDLE
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
      this.pushAssistant(Page4ReplyText.VOICE_ADAPTER_MISSING)
      return
    }
    try {
      await Promise.resolve(adapter.startListening())
      this.voiceRecording = true
    } catch (e) {
      this.voiceRecording = false
      const msg: string = e instanceof Error ? e.message : 'unknown error'
      this.pushAssistant(Page4ReplyText.voiceInputStartFail(msg))
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
      this.pushAssistant(Page4ReplyText.voiceRecognizeFail(msg))
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
    this.typingToken += 1
    const token: number = this.typingToken
    void this.runAssistantTyping(msgId, fullText, token)
  }

  private beginStreamingAssistant(): string {
    this.stopAssistantTyping()
    const msgId: string = this.nextId()
    this.messages.push({
      id: msgId,
      role: 'assistant',
      text: '',
      tsMs: Date.now()
    })
    this.trimMessages()
    this.scrollChatToBottomSoon()
    return msgId
  }

  private updateStreamingAssistant(msgId: string, text: string): void {
    const idx: number = this.findMessageIndexById(msgId)
    if (idx < 0) return
    this.replaceMessageTextByIndex(idx, this.buildStreamingAssistantText(text))
    this.scrollChatToBottomSoon()
  }

  private finishStreamingAssistant(msgId: string, text: string): void {
    const idx: number = this.findMessageIndexById(msgId)
    const finalText: string = Page4OpenClawChatModule.ensureVisibleReasoningText(text)
    if (idx >= 0) {
      this.replaceMessageTextByIndex(idx, finalText)
    } else {
      this.pushAssistant(finalText)
      return
    }
    this.scrollChatToBottomSoon()
    void this.maybeAutoSpeakAssistantText(finalText)
  }

  private cancelStreamingAssistant(msgId: string): void {
    const idx: number = this.findMessageIndexById(msgId)
    if (idx < 0) return
    this.messages = this.messages.filter((msg: AssistantMessage): boolean => msg.id !== msgId)
  }

  private buildStreamingAssistantText(text: string): string {
    const body: string = text.trim()
    if (body.length <= 0) return '思考过程：正在分析当前问题...\n最终回答：'
    if (body.indexOf('思考过程') >= 0 || body.indexOf('最终回答') >= 0 || body.indexOf('结论') >= 0) return body
    return `思考过程：正在分析当前问题...\n最终回答：${body}`
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
      this.showToast(Page4ReplyText.toastAutoSpeakFail(msg))
    }
  }

  private async previewVoiceReplyAfterEnable(): Promise<void> {
    try {
      await page4TencentLocalTtsService.speak(Page4ReplyText.AUTO_SPEAK_READY)
      const latestAssistant: string = this.latestAssistantMessageText()
      if (latestAssistant.length > 0) {
        await page4TencentLocalTtsService.speak(latestAssistant)
      }
    } catch (e) {
      const msg: string = this.errorToText(e)
      this.logError('previewVoiceReplyAfterEnableFail', msg)
      this.showToast(Page4ReplyText.toastVoiceReplyUnavailable(msg))
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
      receipts.push(this.buildReceipt(Page4ReplyText.stopActionText(), true, true))
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'stop failed'
      receipts.push(this.buildReceipt(Page4ReplyText.stopActionFail(msg), false, false))
    }
    if (GridIdCodec.isValidId(target)) {
      const backReceipts: Array<Page4ExecutionReceipt> = await this.routeWithReplanAndWaitArrival(target)
      for (let i: number = 0; i < backReceipts.length; i++) receipts.push(backReceipts[i])
    } else {
      receipts.push(this.buildReceipt(Page4ReplyText.undoNoSafePoint('fallback'), false, false))
    }
    this.pushAssistant(Page4ReplyText.undoResult(this.renderReceiptsSummary(receipts)))
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
        this.pushAssistant(Page4ReplyText.adaptiveWeakEnabled())
      }
      return
    }
    videoStore.setRecognizeIntervalMs(ADAPTIVE_NORMAL_RECOG_INTERVAL_MS)
    videoStore.switchCooldownMs = ADAPTIVE_NORMAL_SWITCH_COOLDOWN_MS
    this.adaptiveOpenClawConnectTimeoutMs = this.openClawRetryConnectTimeoutMs
    this.adaptiveOpenClawReadTimeoutMs = this.openClawRetryReadTimeoutMs
    this.queuedPromptCap = this.normalQueuedPromptCap
    if (forceNotify) {
      this.pushAssistant(Page4ReplyText.adaptiveNormalEnabled())
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
      done: Page4ReplyText.receiptDone(done)
    }
  }

  private latestAckText(): string {
    const arr = commStore.diagKeyRxFrames
    if (!arr || arr.length <= 0) return Page4ReplyText.latestAckMissing()
    const last = arr[arr.length - 1]
    if (!last) return Page4ReplyText.latestAckMissing()
    return `${last.cmdHex} ${last.summary}`
  }

  private renderReceiptsSummary(receipts: Array<Page4ExecutionReceipt>): string {
    if (receipts.length <= 0) return Page4ReplyText.receiptSummaryEmpty()
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
    return { ok: false, receipt: this.buildReceipt(Page4ReplyText.routeFailReceipt(dest, detail), false, false), appliedDest: '' }
  }

  private async sleepMs(delayMs: number): Promise<void> {
    return await new Promise<void>((resolve: () => void): void => {
      this.setManagedTimeout((): void => resolve(), Math.max(0, Math.trunc(delayMs)))
    })
  }

  private async ensureQueryThinkingShown(minMs: number = this.queryThinkingMinDurationMs): Promise<void> {
    if (!this.queryThinkingVisible) return
    const elapsedMs: number = Math.max(0, Date.now() - this.queryThinkingStartMs)
    const remainMs: number = Math.max(0, Math.trunc(minMs) - elapsedMs)
    if (remainMs > 0) await this.sleepMs(remainMs)
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
      receipts.push(this.buildReceipt(Page4ReplyText.routeArrived(routed.appliedDest), true, true))
    } else {
      const curText: string = wait.finalNode.length > 0 ? wait.finalNode : '未知'
      receipts.push(this.buildReceipt(Page4ReplyText.routeArriveTimeout(routed.appliedDest, curText), true, false))
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
      return { ok: false, summary: `PC_TOOL_GATEWAY_TOKEN 为空，请在 ${PAGE4_TOKEN_SETUP_HINT} 配置 token 文件。` }
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
      return { ok: false, summary: `TABLET_COMPANION_TOKEN 为空，请在 ${PAGE4_TOKEN_SETUP_HINT} 配置 token 文件。` }
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
      .replace(Page4Keywords.buildMultiTaskConnectorRegex(), '|')
      .replace(Page4Keywords.buildMultiTaskSeparatorRegex(), '|')
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

    if (this.containsAny(lower, Page4Keywords.AUTO_FOLLOW_ON)) {
      return { kind: 'auto_follow', enabled: true }
    }
    if (this.containsAny(lower, Page4Keywords.AUTO_FOLLOW_OFF)) {
      return { kind: 'auto_follow', enabled: false }
    }
    if (this.containsAny(lower, Page4Keywords.SEND_MODE_REAL)) {
      return { kind: 'send_mode', mode: 'REAL_SEND' }
    }
    if (this.containsAny(lower, Page4Keywords.SEND_MODE_DRY)) {
      return { kind: 'send_mode', mode: 'DRY_RUN' }
    }
    if (this.looksLikeCaptureFrameIntent(lower)) {
      return { kind: 'capture_frame' }
    }
    if (this.containsAny(lower, Page4Keywords.QUERY_STATUS)) {
      return { kind: 'query_status' }
    }
    if (this.containsAny(lower, Page4Keywords.QUERY_VISION)) {
      return { kind: 'query_vision' }
    }
    if (this.containsAny(lower, Page4Keywords.QUERY_COMM)) {
      return { kind: 'query_comm' }
    }
    if (this.containsAny(lower, Page4Keywords.QUERY_VIDEO)) {
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
    return this.containsAny(x, Page4Keywords.MULTI_TASK_MARKERS)
  }

  private loadRuntimeTokenConfig(): void {
    this.clearRuntimeTokenSecrets()
    const paths: Array<string> = []
    for (let i: number = 0; i < PAGE4_PUBLIC_TOKEN_PATHS.length; i++) {
      paths.push(PAGE4_PUBLIC_TOKEN_PATHS[i])
    }
    paths.push(`${this.getFilesDir()}/${PAGE4_RUNTIME_TOKEN_FILE}`)
    for (let i: number = 0; i < paths.length; i++) {
      if (this.tryLoadRuntimeTokenConfigFromPath(paths[i])) return
    }
  }

  private async ensureMediaReadPermissionAndReloadTokenConfig(): Promise<void> {
    const granted: boolean = await this.ensureMediaReadPermission()
    if (granted) {
      this.loadRuntimeTokenConfig()
      return
    }
    hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG,
      'READ_MEDIA not granted, token file in shared storage may be inaccessible')
  }

  private async ensureMediaReadPermission(): Promise<boolean> {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) return false
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = ['ohos.permission.READ_MEDIA' as Permissions]
    try {
      const result = await atManager.requestPermissionsFromUser(ctx, perms)
      if (!result || !Array.isArray(result.authResults) || result.authResults.length <= 0) return false
      return result.authResults[0] === 0
    } catch (e) {
      hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, 'request READ_MEDIA failed: %{public}s',
        e instanceof Error ? e.message : String(e))
      return false
    }
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const root: Record<string, Object | undefined> = globalThis as Record<string, Object | undefined>
    return root['abilityContext'] as common.UIAbilityContext | undefined
  }

  private loadVoiceReplyPreference(): void {
    let f: fs.File | undefined = undefined
    try {
      const path: string = `${this.getFilesDir()}/${PAGE4_VOICE_REPLY_PREF_FILE}`
      f = fs.openSync(path, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(path)
      const size: number = Number(st.size)
      if (!Number.isFinite(size) || size <= 0 || size > 256) return
      const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
      const readLen: number = fs.readSync(f.fd, buf)
      if (readLen <= 0) return
      const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(
        new Uint8Array(buf, 0, readLen),
        { stream: false }
      )
      const obj: Record<string, Object | string | number | boolean | undefined> =
        JSON.parse(txt) as Record<string, Object | string | number | boolean | undefined>
      const enabled: Object | string | number | boolean | undefined = obj['enabled']
      this.voiceReplyEnabled = enabled === true
    } catch (_) {
      // ignore and keep default
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* ignore close error */ }
      }
    }
  }

  private persistVoiceReplyPreference(): void {
    let f: fs.File | undefined = undefined
    try {
      const path: string = `${this.getFilesDir()}/${PAGE4_VOICE_REPLY_PREF_FILE}`
      const txt: string = JSON.stringify({ enabled: this.voiceReplyEnabled })
      try { fs.unlinkSync(path) } catch (_) { /* ignore unlink failure */ }
      f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(f.fd, txt)
    } catch (e) {
      hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, 'persist voice reply preference failed: %{public}s',
        e instanceof Error ? e.message : String(e))
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* ignore close error */ }
      }
    }
  }

  private parseInlineTokenSetupCommand(text: string): { matched: boolean, token: string } {
    const raw: string = text.trim()
    if (raw.length <= 0) return { matched: false, token: '' }
    const lower: string = raw.toLowerCase()
    const prefixes: Array<string> = ['设置token', '设置 token', 'settoken', 'set token']
    for (let i: number = 0; i < prefixes.length; i++) {
      const prefix: string = prefixes[i]
      if (!lower.startsWith(prefix)) continue
      let token: string = raw.substring(prefix.length).trim()
      token = this.trimTokenCommandDelimiters(token)
      if ((token.startsWith('"') && token.endsWith('"')) || (token.startsWith('\'') && token.endsWith('\''))) {
        token = token.substring(1, token.length - 1).trim()
      }
      return { matched: true, token: token }
    }
    return { matched: false, token: '' }
  }

  private trimTokenCommandDelimiters(raw: string): string {
    let out: string = raw.trim()
    while (out.length > 0) {
      const ch: string = out.charAt(0)
      if (ch === ':' || ch === '：' || ch === '=' || ch === ',' || ch === '，') {
        out = out.substring(1).trim()
        continue
      }
      break
    }
    return out
  }

  private applyRuntimeTokenForAllEndpoints(token: string): void {
    const one: string = token.trim()
    if (one.length <= 0) return
    const keys: Array<string> = [
      'OPENCLAW_GATEWAY_TOKEN',
      'OPENCLAW_GATEWAY_TOKEN_FALLBACK',
      'PC_TOOL_GATEWAY_TOKEN',
      'PC_TOOL_GATEWAY_TOKEN_FALLBACK',
      'TABLET_COMPANION_TOKEN',
      'TABLET_COMPANION_TOKEN_FALLBACK'
    ]
    for (let i: number = 0; i < keys.length; i++) {
      setRuntimeSecret(keys[i], one)
    }
  }

  private persistRuntimeTokenToFilesDir(token: string): boolean {
    let f: fs.File | undefined = undefined
    try {
      const one: string = token.trim()
      if (one.length <= 0) return false
      const payload: Record<string, string> = {
        OPENCLAW_GATEWAY_TOKEN: one,
        OPENCLAW_GATEWAY_TOKEN_FALLBACK: one,
        PC_TOOL_GATEWAY_TOKEN: one,
        PC_TOOL_GATEWAY_TOKEN_FALLBACK: one,
        TABLET_COMPANION_TOKEN: one,
        TABLET_COMPANION_TOKEN_FALLBACK: one
      }
      const txt: string = JSON.stringify(payload)
      const path: string = `${this.getFilesDir()}/${PAGE4_RUNTIME_TOKEN_FILE}`
      try { fs.unlinkSync(path) } catch (_) { /* ignore unlink failure */ }
      f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(f.fd, txt)
      return true
    } catch (e) {
      hilog.warn(PAGE4_LOG_DOMAIN, PAGE4_LOG_TAG, 'persist token file failed: %{public}s',
        e instanceof Error ? e.message : String(e))
      return false
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* ignore close failure */ }
      }
    }
  }

  private clearRuntimeTokenSecrets(): void {
    const keys: Array<string> = [
      'OPENCLAW_GATEWAY_TOKEN',
      'OPENCLAW_GATEWAY_TOKEN_FALLBACK',
      'PC_TOOL_GATEWAY_TOKEN',
      'PC_TOOL_GATEWAY_TOKEN_FALLBACK',
      'TABLET_COMPANION_TOKEN',
      'TABLET_COMPANION_TOKEN_FALLBACK'
    ]
    for (let i: number = 0; i < keys.length; i++) {
      setRuntimeSecret(keys[i], '')
    }
  }

  private tryLoadRuntimeTokenConfigFromPath(path: string): boolean {
    let f: fs.File | undefined = undefined
    try {
      f = fs.openSync(path, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(path)
      const size: number = Number(st.size)
      if (!Number.isFinite(size) || size <= 0 || size > 8192) return false
      const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
      const readLen: number = fs.readSync(f.fd, buf)
      if (readLen <= 0) return false
      const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(
        new Uint8Array(buf, 0, readLen),
        { stream: false }
      )
      const obj: Record<string, Object | string | number | boolean | undefined> =
        JSON.parse(txt) as Record<string, Object | string | number | boolean | undefined>
      this.applyRuntimeTokenFromConfig(obj, 'OPENCLAW_GATEWAY_TOKEN')
      this.applyRuntimeTokenFromConfig(obj, 'OPENCLAW_GATEWAY_TOKEN_FALLBACK')
      this.applyRuntimeTokenFromConfig(obj, 'PC_TOOL_GATEWAY_TOKEN')
      this.applyRuntimeTokenFromConfig(obj, 'PC_TOOL_GATEWAY_TOKEN_FALLBACK')
      this.applyRuntimeTokenFromConfig(obj, 'TABLET_COMPANION_TOKEN')
      this.applyRuntimeTokenFromConfig(obj, 'TABLET_COMPANION_TOKEN_FALLBACK')
      return true
    } catch (_) {
      return false
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) { /* ignore close error */ }
      }
    }
  }

  private applyRuntimeTokenFromConfig(
    obj: Record<string, Object | string | number | boolean | undefined>,
    key: string
  ): void {
    const raw: Object | string | number | boolean | undefined = obj[key]
    const val: string = typeof raw === 'string' ? raw.trim() : ''
    setRuntimeSecret(key, val)
  }

  private looksLikeControlIntent(text: string, lower: string): boolean {
    if (text.trim().length <= 0) return false
    if (this.looksLikeMultiTask(text)) return true
    if (this.extractDestNode(text).length > 0) return true
    return this.containsAny(lower, Page4Keywords.CONTROL_INTENT)
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
      this.pushAssistant(Page4ReplyText.executeReceipt(this.renderReceiptsSummary(receipts)))
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

  private beginQueryThinkingProgress(stageText: string = '\u601d\u8003\u4e2d...'): void {
    this.queryThinkingToken += 1
    const token: number = this.queryThinkingToken
    this.queryThinkingVisible = true
    this.queryThinkingStartMs = Date.now()
    this.queryThinkingStageText = stageText
    this.queryThinkingProgressPct = 8
    this.queryThinkingTimerId = this.clearManagedTimer(this.queryThinkingTimerId)
    const tick = (): void => {
      if (token !== this.queryThinkingToken) return
      const cap: number = this.queryThinkingStageText.indexOf('\u6574\u7406') >= 0 ? 92 : 78
      const step: number = this.queryThinkingStageText.indexOf('\u6574\u7406') >= 0 ? 4 : 3
      const next: number = Math.min(cap, this.queryThinkingProgressPct + step)
      this.queryThinkingProgressPct = next
      this.queryThinkingTimerId = this.setManagedTimeout((): void => tick(), 220)
    }
    this.queryThinkingTimerId = this.setManagedTimeout((): void => tick(), 180)
  }

  private setQueryThinkingProgress(stageText: string, pct: number): void {
    if (!this.queryThinkingVisible) return
    this.queryThinkingStageText = stageText
    const n: number = Math.max(0, Math.min(100, Math.round(pct)))
    if (n > this.queryThinkingProgressPct) this.queryThinkingProgressPct = n
  }

  private endQueryThinkingProgress(): void {
    this.queryThinkingToken += 1
    this.queryThinkingTimerId = this.clearManagedTimer(this.queryThinkingTimerId)
    this.queryThinkingProgressPct = 100
    this.queryThinkingVisible = false
    this.queryThinkingStartMs = 0
    this.queryThinkingStageText = '\u601d\u8003\u4e2d...'
    this.queryThinkingProgressPct = 0
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
    return Page4PromptContextModule.buildOpenClawRuntimeContextPrompt(
      mode,
      this.store.autoFollowEnabled,
      mappingText,
      this.placeBindingTraceText
    )
  }

  private buildOpenClawRuntimeContextPromptLite(): string {
    const mode: string = this.store.realSendEnabled ? 'REAL_SEND' : 'DRY_RUN'
    return Page4PromptContextModule.buildOpenClawRuntimeContextPromptLite(
      mode,
      this.store.autoFollowEnabled,
      this.connStateText(),
      this.currentBatteryPct(),
      this.formatPlaceBinding('home'),
      this.formatPlaceBinding('company'),
      this.placeBindingTraceText
    )
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
    const m1: RegExpMatchArray | null = upper.match(Page4Keywords.buildRouteTargetRegex())
    if (m1 && m1.length > 1) return m1[1]
    const antiNav: RegExpMatchArray | null = upper.match(Page4Keywords.buildRouteAntiSourceRegex())
    if (antiNav) return ''
    const m2: RegExpMatchArray | null = upper.match(Page4Keywords.buildGridNodeRegex())
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

    if (this.containsAny(raw, Page4Keywords.ROUTE_HOME_SHORTCUT_RAW) ||
      this.containsAny(lower, Page4Keywords.ROUTE_HOME_SHORTCUT_LOWER)) {
      return homeNode
    }

    if (this.containsAny(raw, Page4Keywords.ROUTE_COMPANY_SHORTCUT_RAW) ||
      this.containsAny(lower, Page4Keywords.ROUTE_COMPANY_SHORTCUT_LOWER)) {
      return companyNode
    }

    if (this.containsAny(raw, Page4Keywords.ROUTE_WAREHOUSE_SHORTCUT_RAW)) {
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
    if (this.containsAny(textLower, Page4Keywords.CONTROL_ACTION_REPEAT)) {
      return this.lastAction
    }
    if (this.containsAny(textLower, Page4Keywords.ACTION_SCRAM)) return Page1Action.SCRAM
    if (this.containsAny(textLower, Page4Keywords.ACTION_STOP)) return Page1Action.STOP
    if (this.containsAny(textLower, Page4Keywords.ACTION_GO)) return Page1Action.GO
    if (this.containsAny(textLower, Page4Keywords.ACTION_BACK)) return Page1Action.BACK
    if (this.containsAny(textLower, Page4Keywords.ACTION_LEFT)) return Page1Action.LEFT
    if (this.containsAny(textLower, Page4Keywords.ACTION_RIGHT)) return Page1Action.RIGHT
    if (this.containsAny(textLower, Page4Keywords.ACTION_UTURN)) return Page1Action.UTURN
    return undefined
  }

  private buildStatusSummaryText(): string {
    const base: string = Page4ReplyText.queryStatusSummary(
      this.connStateText(),
      this.store.realSendEnabled,
      this.store.autoFollowEnabled,
      this.store.riskText,
      this.store.riskScore,
      this.store.txFrames,
      this.store.rxFrames,
      recogStore.recogText
    )
    return `${base} | 电量=${this.currentBatteryPct()}%`
  }

  private currentBatteryPct(): number {
    const pct: number = Math.trunc(Number(this.store.batteryPct))
    if (!Number.isFinite(pct)) return 68
    return Math.max(0, Math.min(100, pct))
  }

  private looksLikeBatteryQueryIntent(text: string, lower: string): boolean {
    if (this.containsAny(lower, Page4Keywords.BATTERY_QUERY_LOWER)) return true
    return this.containsAny(text, Page4Keywords.BATTERY_QUERY_TEXT)
  }

  private buildBatteryQueryText(): string {
    const pct: number = this.currentBatteryPct()
    if (pct >= 60) {
      return `小车当前电量为${pct}%，电量较充足，可继续执行当前任务；若接下来有长距离路线，建议任务间隙补能到80%以上。`
    }
    if (pct >= 30) {
      return `小车当前电量为${pct}%，可继续短时运行；建议优先完成近距离任务，并尽快安排补能。`
    }
    return `小车当前电量为${pct}%，电量偏低；建议暂停新增任务，优先返回补能后再继续作业。`
  }

  private buildOrderQueryText(
    queryText: string,
    mode: 'all' | 'earliest' | 'latest' = 'all',
    statusFilter: string = ''
  ): string {
    return Page4RuntimeDiagnosticsModule.buildOrderQueryText(this.outboundOrders, queryText, mode, statusFilter)
  }

  private async ensureOrderDataLoaded(): Promise<void> {
    if (this.outboundOrders.length > 0) return
    const rm: resourceManager.ResourceManager | undefined = this.getAbilityResourceManager()
    if (!rm) return
    try {
      const rawData: Object = await rm.getRawFileContent(PAGE4_ORDER_DATA_RAWFILE)
      const buf: ArrayBuffer | undefined = this.toArrayBuffer(rawData)
      if (!buf) return
      const bytes: Uint8Array = new Uint8Array(buf)
      const text: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
      this.outboundOrders = this.parseOutboundOrdersText(text)
      this.logInfo('orderDataLoaded', `count=${this.outboundOrders.length}`)
    } catch (e) {
      this.logError('orderDataLoadFail', e instanceof Error ? e.message : String(e))
    }
  }

  private getAbilityResourceManager(): resourceManager.ResourceManager | undefined {
    const root: Record<string, Object | undefined> = globalThis as Record<string, Object | undefined>
    const ctxObj: Object | undefined = root['abilityContext']
    if (!ctxObj) return undefined
    const ctx: Record<string, Object | undefined> = ctxObj as Record<string, Object | undefined>
    const rmObj: Object | undefined = ctx['resourceManager']
    if (!rmObj) return undefined
    return rmObj as resourceManager.ResourceManager
  }

  private toArrayBuffer(dataObj: Object | undefined | null): ArrayBuffer | undefined {
    if (dataObj === undefined || dataObj === null) return undefined

    const maybeArrayBuffer = dataObj as ArrayBuffer
    if (maybeArrayBuffer instanceof ArrayBuffer) {
      return maybeArrayBuffer.slice(0)
    }

    const maybeBytes = dataObj as Uint8Array
    const rawObj = maybeBytes.buffer as Object | undefined
    if (rawObj) {
      const raw: ArrayBuffer = rawObj as ArrayBuffer
      const byteOffsetNum: number = Number(maybeBytes.byteOffset)
      const byteLengthNum: number = Number(maybeBytes.byteLength)
      if (Number.isFinite(byteOffsetNum) && Number.isFinite(byteLengthNum) && byteLengthNum > 0) {
        return raw.slice(byteOffsetNum, byteOffsetNum + byteLengthNum)
      }
    }

    const mapObj = dataObj as Record<string, Object | undefined>
    const nestedData: Object | undefined = mapObj['data']
    if (nestedData !== undefined) {
      return this.toArrayBuffer(nestedData)
    }
    return undefined
  }

  private parseOutboundOrdersText(raw: string): Array<OutboundOrder> {
    const out: Array<OutboundOrder> = []
    const blocks: Array<string> | null = raw.match(/\{[\s\S]*?\}/g)
    if (!blocks || blocks.length <= 0) return out
    for (let i: number = 0; i < blocks.length; i++) {
      const one: OutboundOrder | undefined = this.parseOutboundOrderBlock(blocks[i])
      if (!one) continue
      out.push(one)
    }
    return out
  }

  private parseOutboundOrderBlock(block: string): OutboundOrder | undefined {
    const orderId: string = this.pickFieldString(block, 'orderId')
    const skuCode: string = this.pickFieldString(block, 'skuCode')
    const productName: string = this.pickFieldString(block, 'productName')
    const quantity: number = this.pickFieldNumber(block, 'quantity')
    const zone: string = this.pickFieldString(block, 'zone')
    const status: string = this.pickFieldString(block, 'status')
    const createTime: string = this.pickFieldString(block, 'createTime')
    if (orderId.length <= 0 || skuCode.length <= 0 || createTime.length <= 0) return undefined
    return {
      orderId,
      skuCode,
      productName,
      quantity,
      zone,
      status,
      createTime
    }
  }

  private pickFieldString(block: string, key: string): string {
    const m: RegExpMatchArray | null = block.match(new RegExp(`${key}\\s*:\\s*'([^']*)'`))
    if (!m || m.length < 2) return ''
    return m[1].trim()
  }

  private pickFieldNumber(block: string, key: string): number {
    const m: RegExpMatchArray | null = block.match(new RegExp(`${key}\\s*:\\s*(-?\\d+(?:\\.\\d+)?)`))
    if (!m || m.length < 2) return 0
    const v: number = Number(m[1])
    if (!Number.isFinite(v)) return 0
    return Math.trunc(v)
  }

  private looksLikeOrderQueryIntent(text: string, lower: string): boolean {
    return Page4RuntimeDiagnosticsModule.looksLikeOrderQueryIntent(
      text,
      lower,
      (src: string, keys: Array<string>): boolean => this.containsAny(src, keys)
    )
  }

  private buildVisionSummaryText(): string {
    const r = recogStore.lastRecog
    if (!r) return Page4ReplyText.noVisionResult()
    if (!r.ok) return Page4ReplyText.visionFailed(r.errorText)

    let labels: string = ''
    const maxN: number = r.boxes.length > 3 ? 3 : r.boxes.length
    for (let i: number = 0; i < maxN; i++) {
      const one = r.boxes[i]
      const part: string = `${one.label}(${one.score.toFixed(2)})`
      labels = labels.length <= 0 ? part : `${labels}, ${part}`
    }
    if (labels.length <= 0) labels = Page4ReplyText.visionNoBoxes()
    return Page4ReplyText.visionSummary(r.engine, r.boxes.length, labels)
  }

  private looksLikeCaptureFrameIntent(textLower: string): boolean {
    return this.containsAny(textLower, Page4Keywords.CAPTURE_FRAME)
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
    return Page4ReplyText.buildExampleText()
  }

  private buildOpenClawMessages(maxHistory: number = 8): Array<OpenClawChatMessage> {
    return Page4PromptContextModule.buildOpenClawMessages(
      this.messages,
      this.openClawSystemPrompt,
      this.buildOpenClawRuntimeContextPromptLite(),
      maxHistory
    )
  }

  private buildBatteryOpenClawMessages(maxHistory: number = 8): Array<OpenClawChatMessage> {
    const out: Array<OpenClawChatMessage> = this.buildOpenClawMessages(maxHistory)
    out.push({
      role: 'system',
      content:
        `补充上下文：当前小车真实电量=${this.currentBatteryPct()}%。` +
        `如果用户正在查询电量，必须明确回复“小车当前电量为${this.currentBatteryPct()}%”，并给出简短建议，不要编造其他电量数值。`
    })
    return out
  }

  private async answerByOpenClaw(customMessages?: Array<OpenClawChatMessage>): Promise<boolean> {
    return await Page4OpenClawChatModule.answerByOpenClaw({
      resolveTokenCandidates: (): Array<string> => resolveOpenClawTokenCandidates(),
      resolveHosts: (): Array<string> => this.rankOpenClawHosts(resolveOpenClawHostCandidates(deviceNetworkResolver.resolveGatewayIp())),
      buildOpenClawMessages: (): Array<OpenClawChatMessage> => customMessages ?? this.buildOpenClawMessages(),
      gatewayState: (): Page4GatewayState => ({
        lastGoodOpenClawHost: this.lastGoodOpenClawHost,
        openClawHostCooldownUntilMs: this.openClawHostCooldownUntilMs,
        openClawHostCooldownMs: this.openClawHostCooldownMs,
        openClawWsSessionKey: this.openClawWsSessionKey
      }),
      applyGatewayState: (state): void => {
        this.lastGoodOpenClawHost = state.lastGoodOpenClawHost
        this.openClawHostCooldownUntilMs = state.openClawHostCooldownUntilMs
        this.openClawWsSessionKey = String(state.openClawWsSessionKey ?? '').trim()
      },
      setAssistantBusy: (busy: boolean): void => { this.assistantBusy = busy },
      setManagedTimeout: (cb: () => void, delayMs: number): number => this.setManagedTimeout(cb, delayMs),
      clearManagedTimer: (id: number): number => this.clearManagedTimer(id),
      connectTimeoutMs: (): number => Math.min(12000, this.adaptiveOpenClawConnectTimeoutMs),
      readTimeoutMs: (): number => Math.min(60000, this.adaptiveOpenClawReadTimeoutMs),
      model: OPENCLAW_CHAT_MODEL,
      pushAssistant: (text: string, typed?: boolean): void => this.pushAssistant(text, typed),
      beginStreamingAssistant: (): string => this.beginStreamingAssistant(),
      updateStreamingAssistant: (msgId: string, text: string): void => this.updateStreamingAssistant(msgId, text),
      finishStreamingAssistant: (msgId: string, text: string): void => this.finishStreamingAssistant(msgId, text),
      cancelStreamingAssistant: (msgId: string): void => this.cancelStreamingAssistant(msgId),
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
      this.pushAssistant(Page4ReplyText.invalidRouteNode(dest))
      return true
    }
    this.logInfo('sendRoutePlanRequest', `dest=${dest}`)
    const routeReceipts: Array<Page4ExecutionReceipt> = await this.routeWithReplanAndWaitArrival(dest)
    const routedOk: boolean = routeReceipts.length > 0 && routeReceipts[0].sent
    if (routedOk) this.logInfo('sendRoutePlanSuccess', `dest=${dest}`)
    else this.logError('sendRoutePlanFail', `dest=${dest}, reason=${this.lastRouteFailureReason}`)
    const targetText: string = this.routeTargetDisplayText(dest, inputText)
    if (routedOk) {
      this.pushAssistant(Page4ReplyText.routeSuccess(targetText, this.renderReceiptsSummary(routeReceipts)))
    } else {
      this.pushAssistant(Page4ReplyText.routeFail(this.renderReceiptsSummary(routeReceipts)))
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
      this.pushAssistant(Page4ReplyText.routeSuccess(targetText, this.renderReceiptsSummary([routed.receipt])))
    } else {
      this.pushAssistant(Page4ReplyText.routeFail(this.renderReceiptsSummary([routed.receipt])))
    }
    return true
  }

  private routeTargetDisplayText(destNodeId: string, inputText: string): string {
    const raw: string = inputText.trim()
    const lower: string = raw.toLowerCase()
    if (this.containsAny(raw, Page4Keywords.ROUTE_TARGET_DISPLAY_HOME_RAW) ||
      this.containsAny(lower, Page4Keywords.ROUTE_TARGET_DISPLAY_HOME_LOWER)) {
      return Page4Keywords.PLACE_NAME_HOME
    }
    if (this.containsAny(raw, Page4Keywords.ROUTE_TARGET_DISPLAY_COMPANY_RAW) ||
      this.containsAny(lower, Page4Keywords.ROUTE_TARGET_DISPLAY_COMPANY_LOWER)) {
      return Page4Keywords.PLACE_NAME_COMPANY
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

    const tokenSetup = this.parseInlineTokenSetupCommand(text)
    if (tokenSetup.matched) {
      const token: string = tokenSetup.token.trim()
      if (token.length <= 0) {
        this.pushAssistant('未检测到 token。请发送：设置token sk-xxxx')
        return
      }
      this.applyRuntimeTokenForAllEndpoints(token)
      const persisted: boolean = this.persistRuntimeTokenToFilesDir(token)
      if (persisted) {
        this.loadRuntimeTokenConfig()
        this.pushAssistant('token 已写入应用私有配置并立即生效。')
      } else {
        this.pushAssistant('token 已临时生效，但写入本地配置失败。')
      }
      return
    }

    if (!fromQueue && this.assistantBusy) {
      this.pushAssistant(Page4ReplyText.PREVIOUS_BUSY)
      return
    }

    this.applyAdaptiveStrategy()
    this.pushUser(text)
    this.inputText = ''

    const lower: string = text.toLowerCase()
    const showQueryThinking: boolean = true
    this.beginQueryThinkingProgress(Page4ReplyText.QUERY_THINKING)
    try {
      if (await this.handlePlaceBindingPrompt(text, lower)) {
        this.endQueryThinkingProgress()
        return
      }

      if (await this.quickRouteToPlaceShortcut(text)) {
        this.endQueryThinkingProgress()
        return
      }

      const aliasLearn: string = this.learnAliasFromText(text)
      if (aliasLearn.length > 0) {
        this.pushAssistant(aliasLearn)
        this.endQueryThinkingProgress()
        return
      }

    if (this.containsAny(lower, Page4Keywords.UNDO_QUERY)) {
      await this.undoLastActionToSafePoint()
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.ADAPTIVE_STRATEGY_QUERY)) {
      this.applyAdaptiveStrategy(true)
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.ROUTE_REASON_QUERY)) {
      const reason: string = this.lastRouteFailureReason.length > 0 ? this.lastRouteFailureReason : '暂无失败记录'
      const replan: string = this.lastReplanSummary.length > 0 ? this.lastReplanSummary : '暂无重规划记录'
      this.pushAssistant(Page4ReplyText.routeReasonSummary(reason, replan))
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.POI_MAPPING_QUERY)) {
      this.pushAssistant(this.buildPoiMappingSummaryText())
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.EXPORT_POI_QUERY)) {
      const exp = this.exportPoiMappingsToFile()
      if (exp.ok) this.pushAssistant(Page4ReplyText.exportPoiMappingsSuccess(exp.path))
      else this.pushAssistant(Page4ReplyText.exportPoiMappingsFail(exp.error))
      this.endQueryThinkingProgress()
      return
    }

    const localTasks: Array<Page4PlannedTask> = this.parseLocalPlannedTasks(text)
    if (localTasks.length >= 2) {
      await this.executePlannedTasks(localTasks)
      this.endQueryThinkingProgress()
      return
    }

    if (this.looksLikeControlIntent(text, lower)) {
      const openClawTasks: Array<Page4PlannedTask> = await this.planTasksByOpenClaw(text)
      if (openClawTasks.length > 0) {
        await this.executePlannedTasks(openClawTasks)
        this.endQueryThinkingProgress()
        return
      }
    }

    if (this.containsAny(lower, Page4Keywords.HELP_QUERY)) {
      this.pushAssistant(this.buildExampleText())
      this.endQueryThinkingProgress()
      return
    }

    if (this.looksLikeCaptureFrameIntent(lower)) {
      this.pushAssistant(this.buildCameraFrameSummaryText())
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.QUERY_STATUS)) {
      this.pushAssistant(this.buildStatusSummaryText())
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.QUERY_VISION)) {
      this.pushAssistant(this.buildVisionSummaryText())
      this.endQueryThinkingProgress()
      return
    }

    if (this.looksLikeBatteryQueryIntent(text, lower)) {
      await this.ensureQueryThinkingShown()
      const answered: boolean = await this.answerByOpenClaw(this.buildBatteryOpenClawMessages())
      if (!answered) this.pushAssistant(this.buildBatteryQueryText())
      this.endQueryThinkingProgress()
      return
    }

    if (this.looksLikeOrderQueryIntent(text, lower)) {
      this.setQueryThinkingProgress(Page4ReplyText.QUERY_PREPARING, 64)
      let query: string = ''
      const idMatch: RegExpMatchArray | null = text.match(Page4Keywords.buildOrderIdRegex())
      const skuMatch: RegExpMatchArray | null = text.match(Page4Keywords.buildOrderSkuRegex())
      if (idMatch && idMatch.length > 0) query = idMatch[0]
      else if (skuMatch && skuMatch.length > 0) query = skuMatch[0]
      let mode: 'all' | 'earliest' | 'latest' = 'all'
      if (this.containsAny(lower, Page4Keywords.ORDER_QUERY_SCOPE_EARLIEST)) mode = 'earliest'
      if (this.containsAny(lower, Page4Keywords.ORDER_QUERY_SCOPE_LATEST)) mode = 'latest'
      if (this.containsAny(lower, Page4Keywords.ORDER_QUERY_SCOPE_ALL)) mode = 'all'
      let statusFilter: string = ''
      if (this.containsAny(lower, Page4Keywords.ORDER_QUERY_STATUS_SHIPPED)) {
        statusFilter = Page4Keywords.ORDER_STATUS_SHIPPED_TEXT
      }
      await this.ensureQueryThinkingShown()
      this.pushAssistant(this.buildOrderQueryText(query, mode, statusFilter))
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.AUTO_FOLLOW_ON)) {
      this.store.autoFollowEnabled = true
      this.store.pushLog('info assistant.autoFollow set=ON')
      this.pushAssistant(Page4ReplyText.autoFollowEnabled())
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.AUTO_FOLLOW_OFF)) {
      this.store.autoFollowEnabled = false
      this.store.pushLog('info assistant.autoFollow set=OFF')
      this.pushAssistant(Page4ReplyText.autoFollowDisabled())
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.SEND_MODE_REAL)) {
      this.store.setRealSendEnabled(true)
      this.pushAssistant(Page4ReplyText.sendModeReal())
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.SEND_MODE_DRY)) {
      this.store.setRealSendEnabled(false)
      this.pushAssistant(Page4ReplyText.sendModeDry())
      this.endQueryThinkingProgress()
      return
    }
    /*1.先尝试解析用户是否在下发“导航目标”*/
    const dest: string = this.extractDestNode(text)
    /*2.命中导航意图就直接走导航链路，优先保证控制实时性*/
    if (await this.RaprouteWith(dest, text)) {
      this.endQueryThinkingProgress()
      return
    }
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
        this.pushAssistant(
          Page4ReplyText.executeReceipt(this.renderReceiptsSummary([this.buildReceipt(this.actionName(action), true, true)]))
        )
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'action failed'
        this.logError('sendVehicleActionFail', `action=${this.actionName(action)}, reason=${msg}`)
        this.pushAssistant(
          Page4ReplyText.executeReceipt(
            this.renderReceiptsSummary([this.buildReceipt(Page4ReplyText.actionFail(msg), false, false)])
          )
        )
      }
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.QUERY_COMM)) {
      this.pushAssistant(
        Page4ReplyText.buildCommSummary(
          commStore.commStateText,
          commStore.commConnected,
          commStore.commReconnectCount,
          commStore.txPackets,
          commStore.rxPackets
        )
      )
      this.endQueryThinkingProgress()
      return
    }

    if (this.containsAny(lower, Page4Keywords.QUERY_VIDEO)) {
      this.pushAssistant(
        Page4ReplyText.buildVideoSummary(
          videoStore.displayMode,
          videoStore.rtspStateText,
          videoStore.diagVideoFps,
          videoStore.statusText
        )
      )
      this.endQueryThinkingProgress()
      return
    }
    /*5.前两类都不命中时，再进入AI问答兜底*/
      await this.answerByOpenClaw()
      this.endQueryThinkingProgress()
    } finally {
      if (showQueryThinking && this.queryThinkingVisible) {
        this.endQueryThinkingProgress()
      }
    }
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
    this.updatePlaceBindingTrace(`bind.load -> ${this.placeBindingTraceStateText()}`)
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

  private updatePlaceBindingTrace(text: string): void {
    const body: string = text.trim()
    this.placeBindingTraceText = Page4PromptContextModule.compactMethodTraceText(body)
  }

  private placeBindingTraceStateText(): string {
    const home: string = GridIdCodec.isValidId(this.homeNodeId) ? this.homeNodeId : '-'
    const company: string = GridIdCodec.isValidId(this.companyNodeId) ? this.companyNodeId : '-'
    return `home=${home} company=${company}`
  }

  private async handlePlaceBindingPrompt(text: string, lower: string): Promise<boolean> {
    this.ensurePlaceBindingsLoaded()

    const query = this.wantsPlaceBindingQuery(lower)
    if (query) {
      this.setQueryThinkingProgress(Page4ReplyText.QUERY_PREPARING, 64)
      await this.ensureQueryThinkingShown()
      const parts: Array<string> = []
      if (query.askHome) parts.push(this.formatPlaceBinding('home'))
      if (query.askCompany) parts.push(this.formatPlaceBinding('company'))
      this.updatePlaceBindingTrace(`bind.query -> ${this.placeBindingTraceStateText()}`)
      this.pushAssistant(parts.length > 0 ? parts.join('，') : `${this.formatPlaceBinding('home')}，${this.formatPlaceBinding('company')}`)
      return true
    }

    let req: { role: Page4PlaceRole, placeText: string } | undefined = this.parsePlaceBindingRequest(text)
    let parseMethodName: string = 'parsePlaceBindingRequest'
    if (!req && this.looksLikePlaceBindingIntent(lower)) {
      req = await this.parsePlaceBindingByOpenClaw(text)
      parseMethodName = 'parsePlaceBindingByOpenClaw'
    }
    if (!req) return false

    const nodeFromPlace: string = this.extractDestNode(req.placeText)
    const nodeFromAll: string = this.extractDestNode(text)
    const node: string = GridIdCodec.isValidId(nodeFromPlace) ? nodeFromPlace : nodeFromAll
    if (!GridIdCodec.isValidId(node)) {
      const roleText: string = this.placeRoleText(req.role)
      await this.ensureQueryThinkingShown()
      this.updatePlaceBindingTrace(`bind.fail -> ${parseMethodName} role=${roleText}`)
      this.pushAssistant(Page4ReplyText.placeBindingUnresolved(roleText))
      return true
    }

    const roleText: string = this.placeRoleText(req.role)
    if (req.role === 'home') this.homeNodeId = node
    else this.companyNodeId = node
    this.setQueryThinkingProgress(Page4ReplyText.QUERY_PREPARING, 72)
    page1Store.setPlaceConfigured(this.homeNodeId, this.companyNodeId)
    const ok: boolean = this.persistPlaceBindings()
    await this.ensureQueryThinkingShown()
    this.updatePlaceBindingTrace(
      `bind.ok -> ${parseMethodName} save=${ok ? 'ok' : 'fail'} ${this.placeBindingTraceStateText()}`
    )
    if (ok) {
      this.pushAssistant(
        Page4ReplyText.placeBindingSetSuccess(
          roleText,
          node,
          req.placeText,
          this.formatPlaceBinding('home'),
          this.formatPlaceBinding('company')
        )
      )
    } else {
      this.pushAssistant(Page4ReplyText.placeBindingSetPersistFail(roleText, node))
    }
    return true
  }

  private looksLikePlaceBindingIntent(lower: string): boolean {
    const hasRole: boolean = this.containsAny(lower, Page4Keywords.PLACE_BINDING_ROLE_TOKENS)
    if (!hasRole) return false
    if (this.containsAny(lower, Page4Keywords.PLACE_BINDING_INTENT_BLOCKERS)) return false
    return this.containsAny(lower, Page4Keywords.PLACE_BINDING_SETTERS)
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

    const rs = await Page4GatewayLayer.completeOpenClaw(
      {
        lastGoodOpenClawHost: this.lastGoodOpenClawHost,
        openClawHostCooldownUntilMs: this.openClawHostCooldownUntilMs,
        openClawHostCooldownMs: this.openClawHostCooldownMs,
        openClawWsSessionKey: this.openClawWsSessionKey
      },
      messages,
      hosts,
      tokenCandidates,
      Math.min(OPENCLAW_CONNECT_TIMEOUT_MS, this.adaptiveOpenClawConnectTimeoutMs),
      Math.min(OPENCLAW_READ_TIMEOUT_MS, this.adaptiveOpenClawReadTimeoutMs),
      OPENCLAW_CHAT_MODEL
    )
    this.lastGoodOpenClawHost = rs.state.lastGoodOpenClawHost
    this.openClawHostCooldownUntilMs = rs.state.openClawHostCooldownUntilMs
    this.openClawWsSessionKey = String(rs.state.openClawWsSessionKey ?? '').trim()
    if (rs.ok) {
      return this.parsePlaceBindingPlanText(rs.text)
    }
    return undefined
  }
}
