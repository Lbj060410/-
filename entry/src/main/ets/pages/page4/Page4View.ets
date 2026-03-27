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
  buildOpenClawChatCompletionsUrl,
  OPENCLAW_CHAT_MODEL,
  OPENCLAW_CONNECT_TIMEOUT_MS,
  OPENCLAW_GATEWAY_TOKEN,
  OPENCLAW_READ_TIMEOUT_MS,
  resolveOpenClawHostCandidates
} from '../../config/DeviceNetworkConfig'
import { deviceNetworkResolver } from '../../services/network/DeviceNetworkResolver'
import { OpenClawGatewayClient, OpenClawChatMessage } from '../../services/assistant/OpenClawGatewayClient'
import { installPage4TencentVoiceInputAdapter } from '../../services/assistant/Page4TencentVoiceInputAdapter'
import { page4TencentLocalTtsService } from '../../services/assistant/Page4TencentLocalTtsService'
import hilog from '@ohos.hilog'

const PAGE4_LOG_DOMAIN = 0xFF04
const PAGE4_LOG_TAG = 'page4log'

interface AssistantMessage {
  id: string
  role: 'user' | 'assistant'
  text: string
  tsMs: number
}

interface HistorySession {
  title: string
  messages: Array<AssistantMessage>
  tsMs: number
}

interface Page4VoiceInputAdapter {
  startListening: () => void | Promise<void>
  stopListening: () => string | Promise<string>
}

@Component
export struct Page4View {
  private readonly logTag: string = 'Page4View'
  @State private store: Page1UiStore = page1Store
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

  private longPressTimerId: number = -1
  private readonly longPressThresholdMs: number = 320
  private lastGoodOpenClawHost: string = ''
  private openClawHostCooldownUntilMs: Record<string, number> = {}
  private readonly openClawHostCooldownMs: number = 25000
  private readonly openClawRetryConnectTimeoutMs: number = 2200
  private readonly openClawRetryReadTimeoutMs: number = 16000
  private readonly openClawSystemPrompt: string =
    '你是智能小车的车控助手。优先使用简洁中文回复；涉及行驶或安全动作时先给出明确、安全、可执行的步骤。回答要完整、简洁，尽量控制在50字以内，不要使用省略号。'

  aboutToAppear(): void {
    installPage4TencentVoiceInputAdapter()
    page1Coordinator.bind(this.store)
    void page1Coordinator.start()
    this.chatScroller = new Scroller()
    if (this.messages.length <= 0) {
      this.pushAssistant('您好，我是您的智能助理，有什么我可以帮您？')
    }
    this.stabilizeChatTopOnEnter()
  }

  aboutToDisappear(): void {
    this.clearLongPressTimer()
    this.clearToastTimer()
  }

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        if (this.showSidebar) {
          Column() {
            this.buildSidebarHeader()
            this.buildHistoryList()
          }
          .width('30%')
          .height('100%')
          .backgroundColor('#F8FAFC')
          .border({ width: { right: 1 }, color: '#E2E8F0' })
          .transition({ type: TransitionType.All, translate: { x: -200 }, opacity: 0 })
        }

        Column() {
          this.buildTopNavBar()
          this.buildChatPanel()
          this.buildInputArea()
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

  @Builder
  private buildTopNavBar(): void {
    Row() {
      this.buildSidebarToggleButton()

      Blank()

      Text(this.currentChatTitle)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily('STSong')
        .fontColor(Page1Theme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Blank()

      Row({ space: 10 }) {
        this.buildVoiceReplyButton()
        this.buildNewChatButton()
      }
    }
    .width('100%')
    .height(74)
    .padding({ left: 16, right: 16 })
    .margin({ top: 15 })
    .backgroundColor(Page1Theme.BG)
    .shadow({ radius: 10, color: '#00000008', offsetX: 0, offsetY: 2 })
    .alignItems(VerticalAlign.Bottom)
    .zIndex(10)
  }

  @Builder
  private buildSidebarToggleButton(): void {
    Button() {
      Image(this.showSidebar ? $rawfile('icon/关闭侧边栏.png') : $rawfile('icon/开启侧边栏.png'))
        .width(24)
        .height(24)
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderWidth(0)
    .stateEffect(false)
    .onClick((): void => {
      animateTo({ duration: 200, curve: Curve.EaseInOut }, (): void => {
        this.showSidebar = !this.showSidebar
      })
    })
  }

  @Builder
  private buildNewChatButton(): void {
    Button() {
      Image($rawfile('icon/添加新对话.png'))
        .width(28)
        .height(28)
    }
    .height(40)
    .width(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .borderWidth(0)
    .stateEffect(false)
    .onClick((): void => {
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
    })
  }

  @Builder
  private buildVoiceReplyButton(): void {
    Button() {
      Image(this.voiceReplyEnabled ? $rawfile('icon/语音播报开启.png') : $rawfile('icon/语音播报关闭.png'))
        .width(28)
        .height(28)
    }
    .height(40)
    .width(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .borderWidth(0)
    .stateEffect(false)
    .onClick((): void => {
      this.voiceReplyEnabled = !this.voiceReplyEnabled
      this.showToast(this.voiceReplyEnabled ? '已开启本机播报' : '已关闭本机播报')
    })
  }

  @Builder
  private buildSidebarHeader(): void {
    Row({ space: 12 }) {
      Stack() {
        Circle({ width: 40, height: 40 }).fill('#EEF3FF')
        Text('🤖').fontSize(20)
      }
      Column() {
        Text('智能助理')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Page1Theme.TEXT_PRIMARY)
        Text('随时待命')
          .fontSize(12)
          .fontColor(Page1Theme.SUCCESS)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 40, left: 24, right: 24, bottom: 20 })
  }

  @Builder
  private buildHistoryList(): void {
    Column() {
      Text('历史记录')
        .fontSize(12)
        .fontColor(Page1Theme.TEXT_TERTIARY)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 24, bottom: 12 })

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.historyTitles,
            (title: string, index: number) => {
              Button() {
                Text(title)
                  .fontSize(13)
                  .fontColor(Page1Theme.TEXT_SECONDARY)
                  .fontWeight(FontWeight.Medium)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
                .width('100%')
                .height(44)
                .padding({ left: 14, right: 14 })
                .backgroundColor('#F8FAFC')
                .borderRadius(0)
                .borderWidth(0)
                .stateEffect(false)
                .onClick((): void => {
                  if (index >= this.historySessions.length) return
                  const session: HistorySession = this.historySessions[index]
                  if (!this.isCurrentNewChat()) {
                    this.archiveCurrentChatTitle()
                  }
                  const restored: Array<AssistantMessage> = []
                  for (let k: number = 0; k < session.messages.length; k++) {
                    restored.push(session.messages[k])
                  }
                  animateTo({ duration: 200 }, (): void => {
                    this.messages = restored
                    this.currentChatTitle = session.title
                    this.showSidebar = false
                  })
                  this.scrollChatToBottomSoon()
                })
            },
            (title: string, index: number): string => `${title}-${index}`)
        }
        .padding({ left: 0, right: 0 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildChatPanel(): void {
    Column() {
      Scroll(this.chatScroller) {
        Column({ space: 24 }) {
          ForEach(this.messages, (msg: AssistantMessage) => {
            Row() {
              if (msg.role === 'assistant') {
                Column({ space: 4 }) {
                  Text(msg.text)
                    .fontSize(15)
                    .fontColor(Page1Theme.TEXT_PRIMARY)
                    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
                    .borderRadius({ topLeft: 4, topRight: 20, bottomLeft: 20, bottomRight: 20 })
                    .backgroundColor(Page1Theme.BG)
                    .constraintSize({ maxWidth: '80%' })
                  Text(this.formatTime(msg.tsMs))
                    .fontSize(11)
                    .fontColor(Page1Theme.TEXT_TERTIARY)
                    .margin({ left: 6 })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
              } else {
                Blank()
                Column({ space: 4 }) {
                  Text(msg.text)
                    .fontSize(15)
                    .fontColor('#FFFFFF')
                    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
                    .borderRadius({ topLeft: 20, topRight: 4, bottomLeft: 20, bottomRight: 20 })
                    .linearGradient(Page1Theme.PRIMARY_GRADIENT)
                    .shadow({ radius: 16, color: '#2F6BFF4D', offsetX: 0, offsetY: 6 })
                    .constraintSize({ maxWidth: '80%' })
                  Text(this.formatTime(msg.tsMs))
                    .fontSize(11)
                    .fontColor(Page1Theme.TEXT_TERTIARY)
                    .margin({ right: 6 })
                }
                .alignItems(HorizontalAlign.End)
              }
            }
            .width('100%')
          }, (msg: AssistantMessage): string => msg.id)

          if (this.assistantBusy) {
            Row() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(Page1Theme.PRIMARY)
                Text('思考中...')
                  .fontSize(13)
                  .fontColor(Page1Theme.TEXT_TERTIARY)
                  .margin({ left: 8 })
              }
              .padding({ left: 18, right: 18, top: 12, bottom: 12 })
              .backgroundColor(Page1Theme.BG)
              .borderRadius({ topLeft: 4, topRight: 20, bottomLeft: 20, bottomRight: 20 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Top)
          }
        }
        .width('100%')
        .padding({ top: 0, bottom: 32, left: 24, right: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.None)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildInputArea(): void {
    Row({ space: 12 }) {
      Button() {
        Image(this.inputMode === 'voice' ? $rawfile('icon/文字输入.png') : $rawfile('icon/语音输入.png'))
          .width(28)
          .height(28)
      }
      .width(48)
      .height(48)
      .backgroundColor('transparent')
      .borderWidth(0)
      .stateEffect(false)
      .onClick((): void => {
        animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, (): void => {
          this.inputMode = this.inputMode === 'voice' ? 'text' : 'voice'
        })
      })

      if (this.inputMode === 'text') {
        TextInput({ text: this.inputText, placeholder: '发送指令或提问...' })
          .layoutWeight(1)
          .height(48)
          .backgroundColor('#F1F5F9')
          .borderRadius(24)
          .fontSize(15)
          .fontColor(Page1Theme.TEXT_PRIMARY)
          .padding({ left: 20, right: 20 })
          .onChange((v: string): void => {
            this.inputText = v
          })
          .onSubmit(() => {
            if (this.assistantBusy || !this.inputText) {
              return
            }
            void this.submitPrompt(this.inputText)
          })

        if (this.inputText.length > 0) {
          Button() {
            Text('↑')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .linearGradient(Page1Theme.PRIMARY_GRADIENT)
          .shadow({ radius: 12, color: '#2F6BFF66', offsetX: 0, offsetY: 4 })
          .transition({ type: TransitionType.Insert, scale: { x: 0.1, y: 0.1 } })
          .onClick((): void => {
            if (this.assistantBusy || !this.inputText) {
              return
            }
            void this.submitPrompt(this.inputText)
          })
        }
      } else {
        Button(this.voiceRecording ? '松开发送 / 滑动取消' : '按住说话')
          .layoutWeight(1)
          .height(48)
          .backgroundColor(this.voiceRecording ? '#EEF3FF' : '#F1F5F9')
          .fontColor(this.voiceRecording ? Page1Theme.PRIMARY : Page1Theme.TEXT_PRIMARY)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .borderRadius(24)
          .onTouch((event: TouchEvent): void => {
            this.onVoiceTouch(event)
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 32 })
    .backgroundColor('#FFFFFF')
    .shadow({ radius: 30, color: '#0000000A', offsetX: 0, offsetY: -4 })
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
        if (this.assistantBusy) {
          return
        }
        void this.submitPrompt(prompt)
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
    this.voicePressing = true
    this.clearLongPressTimer()
    this.longPressTimerId = setTimeout((): void => {
      this.longPressTimerId = -1
      void this.startVoiceListening()
    }, this.longPressThresholdMs) as unknown as number
  }

  private async onVoicePressUp(): Promise<void> {
    this.voicePressing = false

    if (this.longPressTimerId >= 0) {
      this.clearLongPressTimer()
      if (!this.voiceHintShown) {
        this.voiceHintShown = true
        this.pushAssistant('语音输入方式：按住说话，松开后自动发送识别文本。')
      }
      return
    }

    if (!this.voiceRecording) {
      return
    }

    this.voiceRecording = false
    const asrText: string = await this.stopVoiceListening()
    if (asrText.trim().length <= 0) {
      this.pushAssistant('未识别到语音内容，请重试。')
      return
    }
    await this.submitPrompt(asrText)
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
    const adapter: Page4VoiceInputAdapter | undefined = root['page4VoiceInputAdapter'] as Page4VoiceInputAdapter | undefined
    if (!adapter) return undefined
    if (typeof adapter.startListening !== 'function') return undefined
    if (typeof adapter.stopListening !== 'function') return undefined
    return adapter
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimerId >= 0) {
      clearTimeout(this.longPressTimerId)
      this.longPressTimerId = -1
    }
  }

  private clearToastTimer(): void {
    if (this.toastTimerId >= 0) {
      clearTimeout(this.toastTimerId)
      this.toastTimerId = -1
    }
  }

  private showToast(text: string): void {
    this.toastText = text
    this.toastVisible = true
    this.clearToastTimer()
    this.toastTimerId = setTimeout((): void => {
      this.toastTimerId = -1
      this.toastVisible = false
    }, 2000) as unknown as number
  }

  private scrollChatToTopSoon(): void {
    setTimeout((): void => {
      this.chatScroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 0, curve: Curve.Linear }
      })
    }, 0)
  }

  private scrollChatToBottomSoon(): void {
    setTimeout((): void => {
      this.chatScroller.scrollTo({
        xOffset: 0,
        yOffset: 1000000,
        animation: { duration: 220, curve: Curve.EaseOut }
      })
    }, 0)
  }

  private stabilizeChatTopOnEnter(): void {
    this.scrollChatToTopSoon()
    setTimeout((): void => {
      this.chatScroller.scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: { duration: 0, curve: Curve.Linear }
      })
    }, 80)
    setTimeout((): void => {
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
    this.maybeRefreshCurrentChatTitleByFirstUserSentence()
    this.scrollChatToBottomSoon()
  }

  private pushAssistant(text: string): void {
    this.messages.push({
      id: this.nextId(),
      role: 'assistant',
      text: text,
      tsMs: Date.now()
    })
    this.scrollChatToBottomSoon()
    void this.maybeAutoSpeakAssistantText(text)
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

  private errorToText(e: Object): string {
    if (e instanceof Error) {
      const msg: string = e.message.trim()
      return msg.length > 0 ? msg : 'unknown error'
    }
    const anyObj: Record<string, Object | string | number | boolean> = e as Record<string, Object | string | number | boolean>
    const code: string = String(anyObj['code'] ?? '')
    const msg: string = String(anyObj['message'] ?? '')
    const details: string = String(anyObj['details'] ?? '')
    const out: string = `${code} ${msg} ${details}`.trim()
    if (out.length > 0 && out !== 'undefined undefined undefined') return out
    try {
      const asJson: string = JSON.stringify(e)
      if (asJson.length > 0 && asJson !== '{}') return asJson
    } catch (_) {}
    return 'unknown error'
  }

  private isCurrentNewChat(): boolean {
    for (let i: number = 0; i < this.messages.length; i++) {
      if (this.messages[i].role === 'user') return false
    }
    return true
  }

  private archiveCurrentChatTitle(): void {
    const title: string = this.currentChatTitle.trim()
    if (title.length <= 0 || title === '新对话') return
    if (this.isCurrentNewChat()) return

    const savedMessages: Array<AssistantMessage> = []
    for (let i: number = 0; i < this.messages.length; i++) {
      savedMessages.push(this.messages[i])
    }
    const session: HistorySession = { title: title, messages: savedMessages, tsMs: Date.now() }

    const nextSessions: Array<HistorySession> = [session]
    const nextTitles: Array<string> = [title]
    for (let i: number = 0; i < this.historySessions.length; i++) {
      nextSessions.push(this.historySessions[i])
      nextTitles.push(this.historySessions[i].title)
    }
    this.historySessions = nextSessions
    this.historyTitles = nextTitles
  }

  private maybeRefreshCurrentChatTitleByFirstUserSentence(): void {
    for (let i: number = 0; i < this.messages.length; i++) {
      const m: AssistantMessage = this.messages[i]
      if (m.role !== 'user') continue
      const title: string = this.summarizeTitleByFirstSentence(m.text)
      this.currentChatTitle = title.length > 0 ? title : '新对话'
      return
    }
    this.currentChatTitle = '新对话'
  }

  private summarizeTitleByFirstSentence(text: string): string {
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
    const x: string = text.toLowerCase()
    for (let i: number = 0; i < keys.length; i++) {
      if (x.indexOf(keys[i].toLowerCase()) >= 0) return true
    }
    return false
  }

  private extractDestNode(input: string): string {
    const upper: string = input.trim().toUpperCase()
    // 优先匹配明确的导航关键词（最高优先级，不受反向词干扰）
    const m1: RegExpMatchArray | null = upper.match(/(?:导航到|前往|去|到达|前进到)\s*([A-Z]\d{1,2})/)
    if (m1 && m1.length > 1) return m1[1]
    // 如果节点 ID 出现在"出发/离开/从/起点"等非目标语境后，不当作目的地
    const antiNav: RegExpMatchArray | null = upper.match(/(?:离开|从|出发|起点|LEAVE|FROM|DEPART)\s*([A-Z]\d{1,2})/)
    if (antiNav) return ''
    // 兜底：仅剩一个独立节点 ID 且无反向语境时才识别为目的地
    const m2: RegExpMatchArray | null = upper.match(/\b([A-Z]\d{1,2})\b/)
    if (m2 && m2.length > 1) return m2[1]
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
    if (action === Page1Action.STROBE) return '道闸'
    return '动作'
  }

  private resolveActionByText(textLower: string): Page1Action | undefined {
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

  private buildExampleText(): string {
    return '示例指令：\n1. 导航到 D4\n2. 前进 / 后退 / 左转 / 右转 / 停止\n3. 开启自动跟随 / 关闭自动跟随\n4. 开启真车模式 / 开启仿真模式\n5. 查询状态\n6. 识别状态'
  }

  private buildOpenClawMessages(maxHistory: number = 14): Array<OpenClawChatMessage> {
    const out: Array<OpenClawChatMessage> = []
    out.push({
      role: 'system',
      content: this.openClawSystemPrompt
    })

    const begin: number = this.messages.length > maxHistory ? this.messages.length - maxHistory : 0
    for (let i: number = begin; i < this.messages.length; i++) {
      const msg: AssistantMessage = this.messages[i]
      const text: string = msg.text.trim()
      if (text.length <= 0) continue
      out.push({
        role: msg.role === 'assistant' ? 'assistant' : 'user',
        content: text
      })
    }
    return out
  }

  private async answerByOpenClaw(): Promise<void> {
    const token: string = OPENCLAW_GATEWAY_TOKEN.trim()
    if (token.length <= 0) {
      this.pushAssistant('OpenClaw token 为空，请在 DeviceNetworkConfig.ets 配置 OPENCLAW_GATEWAY_TOKEN。')
      return
    }

    const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
    const hosts: Array<string> = this.rankOpenClawHosts(resolveOpenClawHostCandidates(gatewayIp))
    if (hosts.length <= 0) {
      this.pushAssistant('未检测到 OpenClaw 主机地址。请在 DeviceNetworkConfig.ets 设置 OPENCLAW_GATEWAY_HOST。')
      return
    }

    const reqMessages: Array<OpenClawChatMessage> = this.buildOpenClawMessages()

    this.assistantBusy = true
    try {
      const errs: Array<string> = []
      for (let i: number = 0; i < hosts.length; i++) {
        const host: string = hosts[i]
        const endpoint: string = buildOpenClawChatCompletionsUrl(host)
        const connectTimeoutMs: number =
          i <= 0 ? OPENCLAW_CONNECT_TIMEOUT_MS : Math.min(OPENCLAW_CONNECT_TIMEOUT_MS, this.openClawRetryConnectTimeoutMs)
        const readTimeoutMs: number =
          i <= 0 ? OPENCLAW_READ_TIMEOUT_MS : Math.min(OPENCLAW_READ_TIMEOUT_MS, this.openClawRetryReadTimeoutMs)
        const client: OpenClawGatewayClient = new OpenClawGatewayClient({
          endpoint,
          bearerToken: token,
          model: OPENCLAW_CHAT_MODEL,
          connectTimeoutMs,
          readTimeoutMs
        })

        this.logInfo('sendOpenClawRequest', `host=${host}, model=${OPENCLAW_CHAT_MODEL}, messages=${reqMessages.length}, ct=${connectTimeoutMs}, rt=${readTimeoutMs}`)
        const result = await client.complete(reqMessages)
        if (result.ok) {
          this.markOpenClawHostSuccess(host)
          this.logInfo('sendOpenClawSuccess', `host=${host}, chars=${result.text.length}`)
          this.pushAssistant(result.text)
          return
        }

        this.markOpenClawHostFail(host)
        const codeText: string = result.responseCode > 0 ? `HTTP ${result.responseCode}` : 'NETWORK'
        this.logError('sendOpenClawFail', `host=${host}, code=${codeText}, reason=${result.errorText}`)
        errs.push(`${host} ${codeText} ${result.errorText}`)
      }

      const merged: string = errs.length > 0 ? errs.join(' || ') : 'unknown'
      this.pushAssistant(`OpenClaw请求失败：${merged}`)
    } finally {
      this.assistantBusy = false
    }
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

  private async submitPrompt(raw: string): Promise<void> {
    const text: string = raw.trim()
    if (text.length <= 0) return

    if (this.assistantBusy) {
      this.pushAssistant('上一条消息仍在处理中，请稍候。')
      return
    }

    this.pushUser(text)
    this.inputText = ''

    const lower: string = text.toLowerCase()

    if (this.containsAny(lower, ['示例', '例子', 'help', '帮助', '怎么用'])) {
      this.pushAssistant(this.buildExampleText())
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

    const dest: string = this.extractDestNode(text)
    if (dest.length > 0) {
      if (!GridIdCodec.isValidId(dest)) {
        this.pushAssistant(`"${dest}" 不是合法的路网节点，请说如 "导航到D4" 等有效节点。`)
        return
      }
      try {
        this.logInfo('sendRoutePlanRequest', `dest=${dest}`)
        await page1Coordinator.startManualRoute(dest)
        this.logInfo('sendRoutePlanSuccess', `dest=${dest}`)
        this.pushAssistant(`已设置目的地 ${dest} 并触发路径规划。`)
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'route failed'
        this.logError('sendRoutePlanFail', `dest=${dest}, reason=${msg}`)
        this.pushAssistant(`目的地指令失败: ${msg}`)
      }
      return
    }

    const action: Page1Action | undefined = this.resolveActionByText(lower)
    if (action !== undefined) {
      try {
        this.logInfo('sendVehicleActionRequest', `action=${this.actionName(action)}`)
        await page1Coordinator.onAction(action)
        this.logInfo('sendVehicleActionSuccess', `action=${this.actionName(action)}`)
        this.pushAssistant(`已执行动作：${this.actionName(action)}。`)
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : 'action failed'
        this.logError('sendVehicleActionFail', `action=${this.actionName(action)}, reason=${msg}`)
        this.pushAssistant(`动作执行失败: ${msg}`)
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
}
