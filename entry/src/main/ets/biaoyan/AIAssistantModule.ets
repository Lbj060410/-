/**
 * 表演文件：AI 助手嵌入模块（DeepSeek 风格）
 * 用途：演示“本地规则 + 大模型路由 + 工具调用 + 会话记忆 + 容错降级”的完整流程
 */

export enum IntentType {
  NAVIGATION = 'NAVIGATION',
  VEHICLE_CONTROL = 'VEHICLE_CONTROL',
  SYSTEM_QUERY = 'SYSTEM_QUERY',
  CHAT = 'CHAT',
  UNKNOWN = 'UNKNOWN'
}

export enum VehicleAction {
  MOVE_FORWARD = 'MOVE_FORWARD',
  MOVE_BACKWARD = 'MOVE_BACKWARD',
  STOP = 'STOP',
  TURN_LEFT = 'TURN_LEFT',
  TURN_RIGHT = 'TURN_RIGHT',
  EMERGENCY_STOP = 'EMERGENCY_STOP'
}

export interface TextParseResult {
  originalText: string
  parsedText: string
  destination: string
  confidence: number
  timestamp: number
}

export interface IntentRecognitionResult {
  intentType: IntentType
  confidence: number
  action: string
  parameters: any
  timestamp: number
}

export interface NavigationInstruction {
  destination: string
  isValid: boolean
  reason: string
  timestamp: number
}

export interface VehicleControlInstruction {
  action: VehicleAction
  isValid: boolean
  parameters: any
  timestamp: number
}

export interface AIAssistantResponse {
  success: boolean
  action: string
  result: any
  executionTime: number
  timestamp: number
}

type LlmRole = 'system' | 'user' | 'assistant' | 'tool'

type ToolName = 'plan_navigation' | 'execute_vehicle_control' | 'query_system_status' | 'fallback_chat'

interface LlmMessage {
  role: LlmRole
  content: string
  timestamp: number
  meta?: any
}

interface DeepSeekConfig {
  provider: 'DEEPSEEK'
  apiBase: string
  modelName: string
  timeoutMs: number
  temperature: number
  topP: number
  maxOutputTokens: number
  enableStream: boolean
}

interface ToolCall {
  name: ToolName
  arguments: any
  confidence: number
  reasoning: string
}

interface DeepSeekUsage {
  promptTokens: number
  completionTokens: number
  totalTokens: number
}

interface DeepSeekTrace {
  traceId: string
  sessionId: string
  model: string
  routedIntent: IntentType
  selectedTool: ToolName
  latencyMs: number
  fallbackUsed: boolean
}

interface DeepSeekReply {
  success: boolean
  answer: string
  toolCall: ToolCall
  confidence: number
  usage: DeepSeekUsage
  trace: DeepSeekTrace
}

interface AgentMemorySnapshot {
  sessionId: string
  turnCount: number
  contextSize: number
  lastIntent: IntentType
  lastDestination: string
  lastAction: string
}

const VALID_DESTINATIONS: Array<string> = [
  'A1', 'B1', 'D1', 'F1', 'G1',
  'A2', 'B2', 'D2', 'F2', 'G2',
  'A4', 'B4', 'D4', 'F4', 'G4',
  'A6', 'B6', 'D6', 'F6', 'G6',
  'A7', 'B7', 'D7', 'F7', 'G7'
]

const POI_ALIAS_TO_NODE: Record<string, string> = {
  '火车站': 'D4',
  '港口': 'G7',
  '中心仓库': 'F6',
  '快递点': 'A1',
  '工业园': 'A7',
  '滕王阁': 'B2',
  '珠宝街':'A7',
  '八一广场':'A6',
  '紫荆夜市':"A5",

}

export class AIAssistantModule {
  private daohang: Array<TextParseResult> = []
  private cheliang: Array<IntentRecognitionResult> = []
  private navigationLog: Array<NavigationInstruction> = []
  private vehicleControlLog: Array<VehicleControlInstruction> = []
  private openClawLog: Array<any> = [] // 兼容旧字段名：现存放大模型推理记录

  private readonly modelConfig: DeepSeekConfig = {
    provider: 'DEEPSEEK',
    apiBase: 'https://api.deepseek.com/v1/chat/completions',
    modelName: 'deepseek-reasoner',
    timeoutMs: 12000,
    temperature: 0.2,
    topP: 0.85,
    maxOutputTokens: 512,
    enableStream: true
  }

  private sessionId: string = this.buildId('SESSION')
  private turnCount: number = 0
  private llmContext: Array<LlmMessage> = []
  private lastIntent: IntentType = IntentType.UNKNOWN
  private lastDestination: string = ''
  private lastAction: string = ''

  constructor() {
    this.seedSystemPrompt()
  }

  /**
   * 主入口：处理用户输入
   */
  processUserInput(userInput: string): AIAssistantResponse {
    const startTime = Date.now()
    // 1.文本解析方法
    const traceId = this.buildId('TRACE')
    console.log(`[AI] 输入(${traceId}): "${userInput}"`)

    try {
      const normalizedInput = (userInput || '').trim()
      if (normalizedInput.length <= 0) {
        return this.buildErrorResponse(startTime, 'EMPTY_INPUT', '输入为空，请重新描述需求')
      }
      //若判定为导航意图
      const parseResult = this.parseText(normalizedInput)

      //若判定为车辆控制意图
      const intentResult = this.recognizeIntent(normalizedInput)

      this.lastIntent = intentResult.intentType
      this.appendContext('user', normalizedInput, {
        parseResult: parseResult,
        intentResult: intentResult
      })
      //降级至openclaw
      const llmReply = this.invokeDeepSeekModelSimulated(traceId, normalizedInput, parseResult, intentResult)

      // Step4: 执行工具调用并生成业务结果
      const response = this.routeByToolCall(llmReply, parseResult, intentResult, startTime)

      // Step5: 回写会话上下文（assistant turn）
      this.appendContext('assistant', this.composeAssistantSummary(response), {
        action: response.action,
        success: response.success,
        trace: llmReply.trace
      })

      this.turnCount += 1
      this.trimContextWindow(24)

      return response
    } catch (error) {
      console.error(`[AI] 处理失败(${traceId}): ${String(error)}`)
      return this.buildErrorResponse(startTime, 'RUNTIME_ERROR', String(error))
    }
  }

  private seedSystemPrompt(): void {
    const systemPrompt = [
      '你是车端智能助手，负责导航、车辆动作与状态问答。',
      '优先保证安全：紧急相关请求必须触发安全动作。',
      '输出必须选择一个工具调用：plan_navigation / execute_vehicle_control / query_system_status / fallback_chat。',
      '当用户意图不明确时，选择 fallback_chat 并生成澄清回复。'
    ].join(' ')

    this.llmContext.push({
      role: 'system',
      content: systemPrompt,
      timestamp: Date.now()
    })
  }

  /**
   * 文本解析：抽取目的地、标准化输入
   */
  private parseText(userInput: string): TextParseResult {
    const parsedText = userInput.toLowerCase().trim()
    const destination = this.extractDestination(userInput)

    let confidence = 0.35
    if (destination.length > 0) {
      confidence = 0.95
    } else if (this.mightContainNavigationIntent(parsedText)) {
      confidence = 0.62
    }

    const result: TextParseResult = {
      originalText: userInput,
      parsedText: parsedText,
      destination: destination,
      confidence: confidence,
      timestamp: Date.now()
    }

    console.log(`[Parse] destination=${destination || 'N/A'}, confidence=${confidence}`)
    return result
  }

  private extractDestination(text: string): string {
    const raw = (text || '').toUpperCase()

    // 1) 直接匹配网格点位
    const nodeMatches = raw.match(/[A-Z]\d+/g)
    if (nodeMatches) {
      for (let node of nodeMatches) {
        if (VALID_DESTINATIONS.includes(node)) {
          return node
        }
      }
    }

    // 2) 通过地名别名映射
    for (let alias in POI_ALIAS_TO_NODE) {
      if (text.includes(alias)) {
        return POI_ALIAS_TO_NODE[alias]
      }
    }

    return ''
  }

  /**
   * 意图识别（本地轻量分类）
   */
  private recognizeIntent(userInput: string): IntentRecognitionResult {
    const text = (userInput || '').toLowerCase()

    const navKeywords = ['去', '到', '导航', '前往', '目的地', '路线', '规划']
    const vehicleKeywords = ['前进', '后退', '停止', '左转', '右转', '转向', '停下', '紧急停止', 'go', 'stop', 'left', 'right']
    const queryKeywords = ['电量', '温度', '位置', '状态', '电池', 'where', 'battery', 'status', 'temperature']

    let intentType = IntentType.UNKNOWN
    let confidence = 0.2

    if (this.containsAny(text, navKeywords) || this.extractDestination(userInput).length > 0) {
      intentType = IntentType.NAVIGATION
      confidence = 0.9
    } else if (this.containsAny(text, vehicleKeywords)) {
      intentType = IntentType.VEHICLE_CONTROL
      confidence = 0.88
    } else if (this.containsAny(text, queryKeywords)) {
      intentType = IntentType.SYSTEM_QUERY
      confidence = 0.86
    } else if (text.length > 0) {
      intentType = IntentType.CHAT
      confidence = 0.58
    }

    const result: IntentRecognitionResult = {
      intentType: intentType,
      confidence: confidence,
      action: intentType,
      parameters: { userInput: userInput },
      timestamp: Date.now()
    }

    console.log(`[Intent] intent=${intentType}, confidence=${confidence}`)
    return result
  }

  /**
   * DeepSeek 大模型推理（模拟）：输出 tool-call 风格结果
   */
  private invokeDeepSeekModelSimulated(
    traceId: string,
    userInput: string,
    parseResult: TextParseResult,
    intentResult: IntentRecognitionResult
  ): DeepSeekReply {
    const t0 = Date.now()

    const toolCall = this.selectToolCallByReasoning(userInput, parseResult, intentResult)
    const answer = this.composeModelAnswer(toolCall, parseResult)

    const promptTokens = this.estimateTokens(this.serializePromptForDebug(userInput, parseResult, intentResult))
    const completionTokens = this.estimateTokens(answer)

    const usage: DeepSeekUsage = {
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: promptTokens + completionTokens
    }

    const trace: DeepSeekTrace = {
      traceId: traceId,
      sessionId: this.sessionId,
      model: this.modelConfig.modelName,
      routedIntent: intentResult.intentType,
      selectedTool: toolCall.name,
      latencyMs: Date.now() - t0,
      fallbackUsed: toolCall.name === 'fallback_chat'
    }

    const reply: DeepSeekReply = {
      success: true,
      answer: answer,
      toolCall: toolCall,
      confidence: toolCall.confidence,
      usage: usage,
      trace: trace
    }

    this.printStreamingPreview(reply)
    return reply
  }

  private selectToolCallByReasoning(
    userInput: string,
    parseResult: TextParseResult,
    intentResult: IntentRecognitionResult
  ): ToolCall {
    const text = userInput.toLowerCase()

    if (intentResult.intentType === IntentType.NAVIGATION) {
      return {
        name: 'plan_navigation',
        arguments: {
          destination: parseResult.destination,
          priority: 'SAFETY_FIRST',
          replanPolicy: 'DYNAMIC'
        },
        confidence: parseResult.destination.length > 0 ? 0.96 : 0.72,
        reasoning: '检测到导航意图，优先走路径规划工具。'
      }
    }

    if (intentResult.intentType === IntentType.VEHICLE_CONTROL) {
      return {
        name: 'execute_vehicle_control',
        arguments: {
          actionText: userInput,
          safetyGate: true
        },
        confidence: 0.9,
        reasoning: '检测到车辆动作控制意图，路由到动作执行工具。'
      }
    }

    if (intentResult.intentType === IntentType.SYSTEM_QUERY) {
      return {
        name: 'query_system_status',
        arguments: {
          queryText: userInput,
          fields: this.extractStatusFields(text)
        },
        confidence: 0.89,
        reasoning: '检测到状态查询意图，路由到状态工具。'
      }
    }

    return {
      name: 'fallback_chat',
      arguments: {
        question: userInput,
        needClarify: true
      },
      confidence: 0.55,
      reasoning: '意图不确定，先走对话澄清。'
    }
  }

  private composeModelAnswer(toolCall: ToolCall, parseResult: TextParseResult): string {
    switch (toolCall.name) {
      case 'plan_navigation':
        if ((toolCall.arguments?.destination || '').length > 0) {
          return `已识别导航目标 ${toolCall.arguments.destination}，准备生成安全优先路径。`
        }
        return '已识别导航意图，但目标点不明确，请补充终点。'
      case 'execute_vehicle_control':
        return '已识别车辆控制意图，正在执行安全门控后的动作下发。'
      case 'query_system_status':
        return '已识别状态查询意图，正在聚合车端状态数据。'
      default:
        return '我已理解你的请求方向，但关键信息不足，请补充具体目标或动作。'
    }
  }

  private serializePromptForDebug(
    userInput: string,
    parseResult: TextParseResult,
    intentResult: IntentRecognitionResult
  ): string {
    return [
      `session=${this.sessionId}`,
      `turn=${this.turnCount}`,
      `user=${userInput}`,
      `parsed=${parseResult.parsedText}`,
      `destination=${parseResult.destination}`,
      `intent=${intentResult.intentType}`
    ].join('\n')
  }

  private printStreamingPreview(reply: DeepSeekReply): void {
    if (!this.modelConfig.enableStream) {
      return
    }

    const chunks = this.chunkText(reply.answer, 12)
    for (let i = 0; i < chunks.length; i++) {
      console.log(`[DeepSeekStream/${reply.trace.traceId}] chunk${i + 1}: ${chunks[i]}`)
    }
  }

  private routeByToolCall(
    llmReply: DeepSeekReply,
    parseResult: TextParseResult,
    intentResult: IntentRecognitionResult,
    startTime: number
  ): AIAssistantResponse {
    switch (llmReply.toolCall.name) {
      case 'plan_navigation':
        return this.handleNavigationToolCall(llmReply, parseResult, startTime)
      case 'execute_vehicle_control':
        return this.handleVehicleToolCall(llmReply, intentResult, startTime)
      case 'query_system_status':
        return this.handleStatusToolCall(llmReply, startTime)
      default:
        return this.handleFallbackToolCall(llmReply, startTime)
    }
  }

  private handleNavigationToolCall(
    llmReply: DeepSeekReply,
    parseResult: TextParseResult,
    startTime: number
  ): AIAssistantResponse {
    const destination = (llmReply.toolCall.arguments?.destination || parseResult.destination || '').toUpperCase()
    const navInstruction = this.validateNavigationInstruction(destination)
    this.navigationLog.push(navInstruction)

    if (!navInstruction.isValid) {
      return {
        success: false,
        action: 'NAVIGATION_FAILED',
        result: {
          reason: navInstruction.reason,
          llm: llmReply
        },
        executionTime: Date.now() - startTime,
        timestamp: Date.now()
      }
    }

    this.lastDestination = destination
    const navigationResult = this.executeNavigation(destination)

    return {
      success: true,
      action: 'NAVIGATION_STARTED',
      result: {
        ...navigationResult,
        llm: llmReply
      },
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  private validateNavigationInstruction(destination: string): NavigationInstruction {
    if (!destination || destination.length <= 0) {
      return {
        destination: destination,
        isValid: false,
        reason: '未识别到有效目的地，请提供类似 D4 / G7 的节点或地名。',
        timestamp: Date.now()
      }
    }

    const isValid = VALID_DESTINATIONS.includes(destination)
    return {
      destination: destination,
      isValid: isValid,
      reason: isValid ? '目的地合法，可进入规划流程。' : `目的地 ${destination} 不在当前网格图中。`,
      timestamp: Date.now()
    }
  }

  private executeNavigation(destination: string): any {
    console.log(`[Navigation] start -> ${destination}`)

    const hops = this.estimateHopsToDestination(destination)
    const eta = Number((hops * 1.9).toFixed(2))

    return {
      destination: destination,
      mode: 'AUTO_ROUTE',
      planner: 'WAVEFRONT+BEAM',
      status: 'NAVIGATING',
      estimatedHops: hops,
      estimatedTimeSec: eta,
      message: `已启动导航，预计 ${eta}s 到达 ${destination}`
    }
  }

  private handleVehicleToolCall(
    llmReply: DeepSeekReply,
    intentResult: IntentRecognitionResult,
    startTime: number
  ): AIAssistantResponse {
    const userInput = String(intentResult.parameters?.userInput || '')
    const vehicleInstruction = this.parseVehicleControl(userInput)
    this.vehicleControlLog.push(vehicleInstruction)

    if (!vehicleInstruction.isValid) {
      return {
        success: false,
        action: 'VEHICLE_CONTROL_FAILED',
        result: {
          reason: '无法识别车辆动作，请明确说“前进/后退/左转/右转/停止”。',
          llm: llmReply
        },
        executionTime: Date.now() - startTime,
        timestamp: Date.now()
      }
    }

    this.lastAction = vehicleInstruction.action
    const controlResult = this.executeVehicleAction(vehicleInstruction.action)

    return {
      success: true,
      action: 'VEHICLE_ACTION_EXECUTED',
      result: {
        ...controlResult,
        llm: llmReply
      },
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  private parseVehicleControl(userInput: string): VehicleControlInstruction {
    const text = userInput.toLowerCase()
    let action: VehicleAction = VehicleAction.STOP
    let isValid = false

    if (text.includes('紧急停止') || text.includes('emergency')) {
      action = VehicleAction.EMERGENCY_STOP
      isValid = true
    } else if (text.includes('前进') || text.includes('go') || text.includes('forward')) {
      action = VehicleAction.MOVE_FORWARD
      isValid = true
    } else if (text.includes('后退') || text.includes('back') || text.includes('backward')) {
      action = VehicleAction.MOVE_BACKWARD
      isValid = true
    } else if (text.includes('左转') || text.includes('left')) {
      action = VehicleAction.TURN_LEFT
      isValid = true
    } else if (text.includes('右转') || text.includes('right')) {
      action = VehicleAction.TURN_RIGHT
      isValid = true
    } else if (text.includes('停止') || text.includes('停下') || text.includes('stop')) {
      action = VehicleAction.STOP
      isValid = true
    }

    return {
      action: action,
      isValid: isValid,
      parameters: {
        userInput: userInput,
        safetyGate: true
      },
      timestamp: Date.now()
    }
  }

  private executeVehicleAction(action: VehicleAction): any {
    console.log(`[VehicleAction] execute=${action}`)

    const speedProfile = action === VehicleAction.MOVE_FORWARD || action === VehicleAction.MOVE_BACKWARD
      ? 'LINEAR_0.6'
      : 'ANGULAR_0.4'

    return {
      action: action,
      status: 'EXECUTING',
      safetyChecked: true,
      speedProfile: speedProfile,
      message: `动作 ${action} 已下发（模拟）`
    }
  }

  private handleStatusToolCall(llmReply: DeepSeekReply, startTime: number): AIAssistantResponse {
    const fields: Array<string> = Array.isArray(llmReply.toolCall.arguments?.fields)
      ? llmReply.toolCall.arguments.fields
      : []

    const status = this.querySystemStatus({ fields: fields })

    return {
      success: true,
      action: 'SYSTEM_STATUS_REPORTED',
      result: {
        status: status,
        llm: llmReply
      },
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  private handleFallbackToolCall(llmReply: DeepSeekReply, startTime: number): AIAssistantResponse {
    return {
      success: true,
      action: 'LLM_CHAT_REPLY',
      result: {
        message: llmReply.answer,
        suggestion: '可以告诉我目的地节点（如 D4）或具体车辆动作（如 前进/左转）。',
        llm: llmReply
      },
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  private querySystemStatus(parameters: any): any {
    const position = this.lastDestination.length > 0 ? this.lastDestination : 'D4'

    const fullStatus = {
      battery: 85,
      position: position,
      temperature: 45,
      cpuLoad: 0.37,
      networkRttMs: 28,
      navState: 'READY',
      modelSession: {
        sessionId: this.sessionId,
        turnCount: this.turnCount,
        contextSize: this.llmContext.length
      }
    }

    const fields: Array<string> = Array.isArray(parameters?.fields) ? parameters.fields : []
    if (fields.length <= 0) {
      return fullStatus
    }

    const partial: Record<string, any> = {}
    for (let field of fields) {
      if (field in fullStatus) {
        partial[field] = (fullStatus as Record<string, any>)[field]
      }
    }

    return Object.keys(partial).length > 0 ? partial : fullStatus
  }

  private extractStatusFields(text: string): Array<string> {
    const out: Array<string> = []

    if (text.includes('电') || text.includes('battery')) {
      out.push('battery')
    }
    if (text.includes('位置') || text.includes('where') || text.includes('position')) {
      out.push('position')
    }
    if (text.includes('温度') || text.includes('temperature')) {
      out.push('temperature')
    }

    return out
  }

  private mightContainNavigationIntent(text: string): boolean {
    const navHints = ['去', '到', '导航', '前往', '路线', '规划']
    return this.containsAny(text, navHints)
  }

  private containsAny(text: string, keywords: Array<string>): boolean {
    for (let keyword of keywords) {
      if (text.includes(keyword)) {
        return true
      }
    }
    return false
  }

  private estimateHopsToDestination(destination: string): number {
    if (!VALID_DESTINATIONS.includes(destination)) {
      return 0
    }

    // 简化估算：按列/行索引曼哈顿距离
    const cols: Array<string> = ['A', 'B', 'D', 'F', 'G']
    const rows: Array<number> = [1, 2, 4, 6, 7]
    const from = 'D4'

    const fromCol = cols.indexOf(from[0])
    const fromRow = rows.indexOf(Number.parseInt(from.slice(1)))
    const toCol = cols.indexOf(destination[0])
    const toRow = rows.indexOf(Number.parseInt(destination.slice(1)))

    if (fromCol < 0 || fromRow < 0 || toCol < 0 || toRow < 0) {
      return 0
    }

    return Math.abs(fromCol - toCol) + Math.abs(fromRow - toRow)
  }

  private appendContext(role: LlmRole, content: string, meta?: any): void {
    this.llmContext.push({
      role: role,
      content: content,
      timestamp: Date.now(),
      meta: meta
    })
  }

  private trimContextWindow(maxMessages: number): void {
    if (this.llmContext.length <= maxMessages) {
      return
    }

    // 保留第一个 system prompt
    const system = this.llmContext.length > 0 ? [this.llmContext[0]] : []
    const tail = this.llmContext.slice(-(maxMessages - system.length))
    this.llmContext = [...system, ...tail]
  }

  private composeAssistantSummary(response: AIAssistantResponse): string {
    const resultText = typeof response.result === 'object'
      ? JSON.stringify(response.result)
      : String(response.result)
    return `action=${response.action}, success=${response.success}, result=${resultText}`
  }

  private estimateTokens(text: string): number {
    const normalized = (text || '').trim()
    if (normalized.length <= 0) {
      return 0
    }
    return Math.max(1, Math.ceil(normalized.length / 4))
  }

  private chunkText(text: string, size: number): Array<string> {
    const out: Array<string> = []
    let i = 0
    while (i < text.length) {
      out.push(text.slice(i, i + size))
      i += size
    }
    return out
  }

  private buildId(prefix: string): string {
    const suffix = Math.random().toString(36).slice(2, 10)
    return `${prefix}_${Date.now()}_${suffix}`
  }

  private buildErrorResponse(startTime: number, code: string, message: string): AIAssistantResponse {
    return {
      success: false,
      action: code,
      result: {
        error: message
      },
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  /**
   * 获取处理历史
   */
  getProcessingHistory(): any {
    return {
      textParseHistory: [...this.daohang],
      intentHistory: [...this.cheliang],
      navigationLog: [...this.navigationLog],
      vehicleControlLog: [...this.vehicleControlLog],
      openClawLog: [...this.openClawLog],
      llmContext: [...this.llmContext],
      memory: this.getMemorySnapshot()
    }
  }

  /**
   * 获取统计信息
   */
  getStatistics(): any {
    const totalInputs = this.daohang.length
    const navOk = this.navigationLog.filter((item) => item.isValid).length
    const vehOk = this.vehicleControlLog.filter((item) => item.isValid).length
    const llmOk = this.openClawLog.filter((item) => item.success).length

    const avgLatencyMs = this.openClawLog.length > 0
      ? this.openClawLog.reduce((sum: number, item: any) => sum + Number(item?.trace?.latencyMs || 0), 0) / this.openClawLog.length
      : 0

    return {
      totalInputs: totalInputs,
      navigationCommands: this.navigationLog.length,
      vehicleCommands: this.vehicleControlLog.length,
      llmHandled: this.openClawLog.length,
      successRate: this.calculateSuccessRate(),
      avgModelLatencyMs: Number(avgLatencyMs.toFixed(2)),
      memory: this.getMemorySnapshot(),
      model: {
        provider: this.modelConfig.provider,
        modelName: this.modelConfig.modelName,
        stream: this.modelConfig.enableStream
      },
      successBreakdown: {
        navigationSuccess: navOk,
        vehicleSuccess: vehOk,
        llmSuccess: llmOk
      }
    }
  }

  private getMemorySnapshot(): AgentMemorySnapshot {
    return {
      sessionId: this.sessionId,
      turnCount: this.turnCount,
      contextSize: this.llmContext.length,
      lastIntent: this.lastIntent,
      lastDestination: this.lastDestination,
      lastAction: this.lastAction
    }
  }

  /**
   * 计算成功率
   */
  private calculateSuccessRate(): string {
    const total = this.daohang.length
    if (total <= 0) {
      return 'N/A'
    }

    const successful =
      this.navigationLog.filter((log) => log.isValid).length +
      this.vehicleControlLog.filter((log) => log.isValid).length +
      this.openClawLog.filter((log) => log.success).length

    return `${((successful / total) * 100).toFixed(2)}%`
  }

  /**
   * 清空历史并重置会话
   */
  clearHistory(): void {
    this.daohang = []
    this.cheliang = []
    this.navigationLog = []
    this.vehicleControlLog = []
    this.openClawLog = []

    this.sessionId = this.buildId('SESSION')
    this.turnCount = 0
    this.lastIntent = IntentType.UNKNOWN
    this.lastDestination = ''
    this.lastAction = ''
    this.llmContext = []
    this.seedSystemPrompt()

    console.log('[AI] 历史与会话上下文已重置')
  }
}
