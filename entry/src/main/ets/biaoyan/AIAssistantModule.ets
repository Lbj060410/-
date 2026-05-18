/**
 * 表演文件：AI 助手嵌入模块
 * 用途：演示自然语言处理和意图识别的完整流程
 */

export enum IntentType {
  NAVIGATION = 'NAVIGATION',      // 导航意图
  VEHICLE_CONTROL = 'VEHICLE_CONTROL',  // 车辆控制意图
  UNKNOWN = 'UNKNOWN'             // 未知意图
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

export class AIAssistantModule {
  private textParseHistory: Array<TextParseResult> = []
  private intentHistory: Array<IntentRecognitionResult> = []
  private navigationLog: Array<NavigationInstruction> = []
  private vehicleControlLog: Array<VehicleControlInstruction> = []
  private openClawLog: Array<any> = []

  /**
   * 主入口：处理用户输入
   */
  processUserInput(userInput: string): AIAssistantResponse {
    const startTime = Date.now()
    console.log(`[AI助手] 收到用户输入: "${userInput}"`)

    try {
      // 步骤 1：调用文本解析方法，提取并保存用户输入的目的地
      const parseResult = this.parseText(userInput)
      this.textParseHistory.push(parseResult)
      console.log(`[文本解析] 目的地: ${parseResult.destination}, 置信度: ${parseResult.confidence}`)

      // 步骤 2：判断指令是否为导航意图
      const intentResult = this.recognizeIntent(userInput)
      this.intentHistory.push(intentResult)

      if (intentResult.intentType === IntentType.NAVIGATION) {
        console.log(`[意图识别] 识别为导航意图`)
        return this.handleNavigationIntent(parseResult, startTime)
      }

      // 步骤 3：如果不是导航意图，则调用车辆方法解析文本
      if (intentResult.intentType === IntentType.VEHICLE_CONTROL) {
        console.log(`[意图识别] 识别为车辆控制意图`)
        return this.handleVehicleControlIntent(intentResult, startTime)
      }

      // 步骤 5：如果前面两种情况都没有命中，进入 OpenClaw 智能体
      console.log(`[意图识别] 未识别到明确意图，调用 OpenClaw 智能体`)
      return this.handleOpenClawIntent(userInput, startTime)
    } catch (error) {
      console.error(`[AI助手] 处理出错: ${error}`)
      return {
        success: false,
        action: 'ERROR',
        result: { error: String(error) },
        executionTime: Date.now() - startTime,
        timestamp: Date.now()
      }
    }
  }

  /**
   * 步骤 1：文本解析方法
   */
  private parseText(userInput: string): TextParseResult {
    console.log(`[文本解析] 开始解析: "${userInput}"`)

    // 装模做样：文本预处理
    const parsedText = userInput.toLowerCase().trim()

    // 装模做样：提取目的地
    const destination = this.extractDestination(parsedText)

    // 装模做样：计算置信度
    const confidence = destination.length > 0 ? 0.95 : 0.3

    const result: TextParseResult = {
      originalText: userInput,
      parsedText: parsedText,
      destination: destination,
      confidence: confidence,
      timestamp: Date.now()
    }

    console.log(`[文本解析] 完成 - 目的地: ${destination}, 置信度: ${confidence}`)
    return result
  }

  /**
   * 提取目的地
   */
  private extractDestination(text: string): string {
    // 装模做样：关键词匹配
    const destinations = ['A1', 'B1', 'D1', 'F1', 'G1', 'A2', 'B2', 'D2', 'F2', 'G2',
                         'A4', 'B4', 'D4', 'F4', 'G4', 'A6', 'B6', 'D6', 'F6', 'G6',
                         'A7', 'B7', 'D7', 'F7', 'G7']

    for (let dest of destinations) {
      if (text.includes(dest.toLowerCase())) {
        return dest
      }
    }

    return ''
  }

  /**
   * 步骤 2：意图识别方法
   */
  private recognizeIntent(userInput: string): IntentRecognitionResult {
    console.log(`[意图识别] 开始识别意图`)

    const lowerInput = userInput.toLowerCase()

    // 导航关键词
    const navigationKeywords = ['去', '到', '导航', '前往', '目的地', '路线', '规划']
    // 车辆控制关键词
    const vehicleKeywords = ['前进', '后退', '停止', '左转', '右转', '转向', '停下', '动作']

    let intentType = IntentType.UNKNOWN
    let confidence = 0

    // 判断导航意图
    for (let keyword of navigationKeywords) {
      if (lowerInput.includes(keyword)) {
        intentType = IntentType.NAVIGATION
        confidence = 0.9
        break
      }
    }

    // 判断车辆控制意图
    if (intentType === IntentType.UNKNOWN) {
      for (let keyword of vehicleKeywords) {
        if (lowerInput.includes(keyword)) {
          intentType = IntentType.VEHICLE_CONTROL
          confidence = 0.85
          break
        }
      }
    }

    const result: IntentRecognitionResult = {
      intentType: intentType,
      confidence: confidence,
      action: intentType,
      parameters: { userInput: userInput },
      timestamp: Date.now()
    }

    console.log(`[意图识别] 结果: ${intentType}, 置信度: ${confidence}`)
    return result
  }

  /**
   * 步骤 2a：处理导航意图
   */
  private handleNavigationIntent(parseResult: TextParseResult, startTime: number): AIAssistantResponse {
    console.log(`[导航流程] 进入导航处理`)

    // 调用导航方法来判断是否为导航相关指令
    const navInstruction = this.validateNavigationInstruction(parseResult.destination)
    this.navigationLog.push(navInstruction)

    if (!navInstruction.isValid) {
      console.log(`[导航流程] 导航指令无效: ${navInstruction.reason}`)
      return {
        success: false,
        action: 'NAVIGATION_FAILED',
        result: { reason: navInstruction.reason },
        executionTime: Date.now() - startTime,
        timestamp: Date.now()
      }
    }

    // 正确则进入导航流程
    console.log(`[导航流程] 导航指令有效，进入导航流程`)
    const navigationResult = this.executeNavigation(navInstruction.destination)

    return {
      success: true,
      action: 'NAVIGATION_STARTED',
      result: navigationResult,
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  /**
   * 验证导航指令
   */
  private validateNavigationInstruction(destination: string): NavigationInstruction {
    console.log(`[导航验证] 验证目的地: ${destination}`)

    if (!destination || destination.length === 0) {
      return {
        destination: destination,
        isValid: false,
        reason: '未识别到有效的目的地',
        timestamp: Date.now()
      }
    }

    // 装模做样：检查目的地是否在网络中
    const validDestinations = ['A1', 'B1', 'D1', 'F1', 'G1', 'A2', 'B2', 'D2', 'F2', 'G2',
                              'A4', 'B4', 'D4', 'F4', 'G4', 'A6', 'B6', 'D6', 'F6', 'G6',
                              'A7', 'B7', 'D7', 'F7', 'G7']

    const isValid = validDestinations.includes(destination)

    return {
      destination: destination,
      isValid: isValid,
      reason: isValid ? '目的地有效' : `目的地 ${destination} 不在网络中`,
      timestamp: Date.now()
    }
  }

  /**
   * 执行导航
   */
  private executeNavigation(destination: string): any {
    console.log(`[导航执行] 开始导航到 ${destination}`)
    // 装模做样：调用导航协调器
    return {
      destination: destination,
      status: 'NAVIGATING',
      message: `正在导航到 ${destination}`
    }
  }

  /**
   * 步骤 3a：处理车辆控制意图
   */
  private handleVehicleControlIntent(
    intentResult: IntentRecognitionResult,
    startTime: number
  ): AIAssistantResponse {
    console.log(`[车辆控制] 进入车辆控制处理`)

    // 调用车辆方法解析文本，匹配车辆控制指令
    const vehicleInstruction = this.parseVehicleControl(intentResult.parameters.userInput)
    this.vehicleControlLog.push(vehicleInstruction)

    if (!vehicleInstruction.isValid) {
      console.log(`[车辆控制] 车辆指令无效`)
      return {
        success: false,
        action: 'VEHICLE_CONTROL_FAILED',
        result: { reason: '无效的车辆控制指令' },
        executionTime: Date.now() - startTime,
        timestamp: Date.now()
      }
    }

    // 步骤 4：一旦命中，就直接调用动作协调器的执行方法
    console.log(`[车辆控制] 指令有效，直接调用动作协调器`)
    const controlResult = this.executeVehicleAction(vehicleInstruction.action)

    return {
      success: true,
      action: 'VEHICLE_ACTION_EXECUTED',
      result: controlResult,
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  /**
   * 解析车辆控制指令
   */
  private parseVehicleControl(userInput: string): VehicleControlInstruction {
    console.log(`[车辆解析] 解析车辆控制指令: "${userInput}"`)

    const lowerInput = userInput.toLowerCase()
    let action = VehicleAction.STOP
    let isValid = false

    // 判断是否为前进、停止这类动作控制指令
    if (lowerInput.includes('前进') || lowerInput.includes('go') || lowerInput.includes('forward')) {
      action = VehicleAction.MOVE_FORWARD
      isValid = true
    } else if (lowerInput.includes('后退') || lowerInput.includes('back') || lowerInput.includes('backward')) {
      action = VehicleAction.MOVE_BACKWARD
      isValid = true
    } else if (lowerInput.includes('停止') || lowerInput.includes('stop')) {
      action = VehicleAction.STOP
      isValid = true
    } else if (lowerInput.includes('左转') || lowerInput.includes('left')) {
      action = VehicleAction.TURN_LEFT
      isValid = true
    } else if (lowerInput.includes('右转') || lowerInput.includes('right')) {
      action = VehicleAction.TURN_RIGHT
      isValid = true
    } else if (lowerInput.includes('紧急停止') || lowerInput.includes('emergency')) {
      action = VehicleAction.EMERGENCY_STOP
      isValid = true
    }

    return {
      action: action,
      isValid: isValid,
      parameters: { userInput: userInput },
      timestamp: Date.now()
    }
  }

  /**
   * 执行车辆动作
   */
  private executeVehicleAction(action: VehicleAction): any {
    console.log(`[动作执行] 执行动作: ${action}`)
    // 装模做样：调用动作协调器
    return {
      action: action,
      status: 'EXECUTING',
      message: `正在执行: ${action}`
    }
  }

  /**
   * 步骤 5：处理 OpenClaw 智能体意图
   */
  private handleOpenClawIntent(userInput: string, startTime: number): AIAssistantResponse {
    console.log(`[OpenClaw] 调用 OpenClaw 智能体`)

    // 调用 OpenClaw 解析用户意图
    const openClawResult = this.invokeOpenClawAgent(userInput)
    this.openClawLog.push(openClawResult)

    if (!openClawResult.success) {
      console.log(`[OpenClaw] 智能体无法理解用户意图`)
      return {
        success: false,
        action: 'OPENCLAW_FAILED',
        result: { message: '无法理解您的指令，请重新表述' },
        executionTime: Date.now() - startTime,
        timestamp: Date.now()
      }
    }

    // 调用对应方法
    console.log(`[OpenClaw] 识别到意图: ${openClawResult.intent}`)
    const methodResult = this.invokeCorrespondingMethod(openClawResult)

    return {
      success: true,
      action: 'OPENCLAW_HANDLED',
      result: methodResult,
      executionTime: Date.now() - startTime,
      timestamp: Date.now()
    }
  }

  /**
   * 调用 OpenClaw 智能体
   */
  private invokeOpenClawAgent(userInput: string): any {
    console.log(`[OpenClaw] 发送请求到 OpenClaw 智能体`)
    console.log(`[OpenClaw] 输入: "${userInput}"`)

    // 装模做样：调用 OpenClaw API
    // 实际应该调用真实的 OpenClaw 智能体
    const response = {
      success: true,
      intent: 'QUERY_STATUS',
      confidence: 0.88,
      parameters: {
        queryType: 'system_status',
        details: ['battery', 'position', 'temperature']
      },
      message: '识别到系统状态查询意图'
    }

    console.log(`[OpenClaw] 响应: ${response.message}`)
    return response
  }

  /**
   * 调用对应方法
   */
  private invokeCorrespondingMethod(openClawResult: any): any {
    console.log(`[方法调用] 调用对应方法: ${openClawResult.intent}`)

    switch (openClawResult.intent) {
      case 'QUERY_STATUS':
        return this.querySystemStatus(openClawResult.parameters)
      case 'QUERY_POSITION':
        return this.queryCurrentPosition()
      case 'QUERY_BATTERY':
        return this.queryBatteryStatus()
      case 'QUERY_TEMPERATURE':
        return this.queryTemperature()
      default:
        return { message: '未知的意图类型' }
    }
  }

  /**
   * 查询系统状态
   */
  private querySystemStatus(parameters: any): any {
    console.log(`[系统查询] 查询系统状态`)
    return {
      battery: 85,
      position: 'D4',
      temperature: 45,
      status: 'NORMAL'
    }
  }

  /**
   * 查询当前位置
   */
  private queryCurrentPosition(): any {
    console.log(`[位置查询] 查询当前位置`)
    return { position: 'D4' }
  }

  /**
   * 查询电池状态
   */
  private queryBatteryStatus(): any {
    console.log(`[电池查询] 查询电池状态`)
    return { battery: 85, status: 'GOOD' }
  }

  /**
   * 查询温度
   */
  private queryTemperature(): any {
    console.log(`[温度查询] 查询温度`)
    return { temperature: 45, status: 'NORMAL' }
  }

  /**
   * 获取处理历史
   */
  getProcessingHistory(): any {
    return {
      textParseHistory: this.textParseHistory,
      intentHistory: this.intentHistory,
      navigationLog: this.navigationLog,
      vehicleControlLog: this.vehicleControlLog,
      openClawLog: this.openClawLog
    }
  }

  /**
   * 获取统计信息
   */
  getStatistics(): any {
    return {
      totalInputs: this.textParseHistory.length,
      navigationCommands: this.navigationLog.length,
      vehicleCommands: this.vehicleControlLog.length,
      openClawHandled: this.openClawLog.length,
      successRate: this.calculateSuccessRate()
    }
  }

  /**
   * 计算成功率
   */
  private calculateSuccessRate(): string {
    const total = this.textParseHistory.length
    if (total === 0) return 'N/A'

    const successful = this.navigationLog.filter(log => log.isValid).length +
                      this.vehicleControlLog.filter(log => log.isValid).length +
                      this.openClawLog.filter(log => log.success).length

    return ((successful / total) * 100).toFixed(2) + '%'
  }

  /**
   * 清空历史
   */
  clearHistory(): void {
    this.textParseHistory = []
    this.intentHistory = []
    this.navigationLog = []
    this.vehicleControlLog = []
    this.openClawLog = []
    console.log('[AI助手] 历史已清空')
  }
}
