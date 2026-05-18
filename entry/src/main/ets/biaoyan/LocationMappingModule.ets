/**
 * 表演文件：现实点位映射模块
 * 用途：将现实物流点位名称映射到系统内部网格节点ID
 * 注意：这是表演代码，仅用于展示地名识别和点位映射流程，功能不需要实现
 */

export interface LocationConfig {
  nodeId: string           // 网格节点ID（如 D4）
  primaryName: string      // 主地名（如 "滕王阁物流点"）
  aliases: Array<string>   // 别名列表（如 ["滕王阁", "TengWangGe"]）
  coordinates: {
    x: number
    y: number
  }
  description: string      // 地点描述
}

export interface LocationMappingResult {
  success: boolean
  nodeId: string
  locationName: string
  reason: string
}

/**
 * 地名配置表管理器
 * 维护所有现实物流点位与网格节点的映射关系
 */
export class LocationConfigManager {
  private static readonly LOCATION_CONFIGS: Array<LocationConfig> = [
    {
      nodeId: 'A1',
      primaryName: '滕王阁物流点',
      aliases: ['滕王阁', 'TengWangGe', '腾王阁', '物流点A1'],
      coordinates: { x: 100, y: 100 },
      description: '南昌滕王阁物流配送中心'
    },
    {
      nodeId: 'B2',
      primaryName: '火车站物流点',
      aliases: ['火车站', 'TrainStation', '南昌站', '物流点B2'],
      coordinates: { x: 200, y: 200 },
      description: '南昌火车站物流中转站'
    },
    {
      nodeId: 'D4',
      primaryName: '中心仓库',
      aliases: ['中心', '仓库', 'WarehouseCenter', '物流点D4', '中央仓'],
      coordinates: { x: 400, y: 400 },
      description: '物流中心仓库'
    },
    {
      nodeId: 'F6',
      primaryName: '机场物流点',
      aliases: ['机场', 'Airport', '南昌机场', '物流点F6'],
      coordinates: { x: 600, y: 600 },
      description: '南昌昌北国际机场物流中心'
    },
    {
      nodeId: 'G7',
      primaryName: '港口物流点',
      aliases: ['港口', 'Port', '赣江港', '物流点G7'],
      coordinates: { x: 700, y: 700 },
      description: '赣江港口物流配送中心'
    },
    {
      nodeId: 'A7',
      primaryName: '工业园区',
      aliases: ['工业园', 'IndustrialPark', '园区', '物流点A7'],
      coordinates: { x: 100, y: 700 },
      description: '南昌高新技术产业园区'
    },
    {
      nodeId: 'B4',
      primaryName: '商业广场',
      aliases: ['商业广场', 'ShoppingMall', '广场', '物流点B4'],
      coordinates: { x: 200, y: 400 },
      description: '南昌商业中心广场'
    },
    {
      nodeId: 'F2',
      primaryName: '医院物流点',
      aliases: ['医院', 'Hospital', '人民医院', '物流点F2'],
      coordinates: { x: 600, y: 200 },
      description: '南昌人民医院物流配送点'
    }
  ]

  /**
   * 获取地名配置表副本
   */
  static getLocationConfigs(): Array<LocationConfig> {
    const out: Array<LocationConfig> = []
    for (let i: number = 0; i < LocationConfigManager.LOCATION_CONFIGS.length; i++) {
      const config: LocationConfig = LocationConfigManager.LOCATION_CONFIGS[i]
      out.push({
        nodeId: config.nodeId,
        primaryName: config.primaryName,
        aliases: [...config.aliases],
        coordinates: { x: config.coordinates.x, y: config.coordinates.y },
        description: config.description
      })
    }
    return out
  }

  /**
   * 根据节点ID获取地名配置
   */
  static getConfigByNodeId(nodeId: string): LocationConfig | undefined {
    const x: string = nodeId.trim().toUpperCase()
    for (let i: number = 0; i < LocationConfigManager.LOCATION_CONFIGS.length; i++) {
      if (LocationConfigManager.LOCATION_CONFIGS[i].nodeId === x) {
        return LocationConfigManager.LOCATION_CONFIGS[i]
      }
    }
    return undefined
  }
}

/**
 * 现实点位映射模块
 * 负责将用户输入的地名转换为系统内部网格节点ID
 */
export class LocationMappingModule {
  private locationConfigs: Array<LocationConfig> = []
  private mappingHistory: Array<LocationMappingResult> = []

  constructor() {
    this.initializeLocationConfigs()
  }

  /**
   * 初始化地名配置表
   */
  private initializeLocationConfigs(): void {
    console.log('[点位映射] 初始化地名配置表')
    this.locationConfigs = LocationConfigManager.getLocationConfigs()
    console.log(`[点位映射] 加载了 ${this.locationConfigs.length} 个物流点位`)
  }

  /**
   * 主入口：将用户输入的地名映射到节点ID
   */
  mapLocationToNodeId(userInput: string): LocationMappingResult {
    console.log(`[点位映射] 收到用户输入: "${userInput}"`)

    // 步骤 1：对外部输入进行处理，去掉前后空格
    const cleanedInput: string = this.cleanInput(userInput)
    console.log(`[点位映射] 清理后的输入: "${cleanedInput}"`)

    // 步骤 2：进行内容判断，如果输入为空就直接返回上层
    if (!this.isValidInput(cleanedInput)) {
      console.log('[点位映射] 输入为空或无效，直接返回')
      return {
        success: false,
        nodeId: '',
        locationName: '',
        reason: '输入为空或无效'
      }
    }

    // 步骤 3：若有数据则调用方法，获取地名配置表
    console.log('[点位映射] 开始匹配地名')
    const matchResult: LocationMappingResult = this.matchLocationName(cleanedInput)

    // 记录映射历史
    this.mappingHistory.push(matchResult)

    return matchResult
  }

  /**
   * 步骤 1：清理输入 - 去掉前后空格和特殊字符
   */
  private cleanInput(input: string): string {
    // 去掉前后空格
    let cleaned: string = input.trim()

    // 转换为小写便于匹配
    cleaned = cleaned.toLowerCase()

    // 去掉常见的冗余词汇
    cleaned = cleaned.replace(/物流点/g, '')
    cleaned = cleaned.replace(/去/g, '')
    cleaned = cleaned.replace(/到/g, '')
    cleaned = cleaned.replace(/导航/g, '')

    // 再次去掉前后空格
    cleaned = cleaned.trim()

    return cleaned
  }

  /**
   * 步骤 2：验证输入是否有效
   */
  private isValidInput(input: string): boolean {
    if (!input || input.length === 0) {
      console.log('[点位映射] 输入验证失败：输入为空')
      return false
    }

    if (input.length > 100) {
      console.log('[点位映射] 输入验证失败：输入过长')
      return false
    }

    return true
  }

  /**
   * 步骤 3-5：匹配地名或别名，返回对应节点ID
   */
  private matchLocationName(cleanedInput: string): LocationMappingResult {
    console.log(`[点位映射] 开始在 ${this.locationConfigs.length} 个地点中匹配`)

    // 遍历所有地名配置
    for (let i: number = 0; i < this.locationConfigs.length; i++) {
      const config: LocationConfig = this.locationConfigs[i]

      // 匹配主地名
      if (this.isMatch(cleanedInput, config.primaryName)) {
        console.log(`[点位映射] 匹配到主地名: ${config.primaryName} -> ${config.nodeId}`)
        return {
          success: true,
          nodeId: config.nodeId,
          locationName: config.primaryName,
          reason: '匹配到主地名'
        }
      }

      // 匹配别名
      for (let j: number = 0; j < config.aliases.length; j++) {
        const alias: string = config.aliases[j]
        if (this.isMatch(cleanedInput, alias)) {
          console.log(`[点位映射] 匹配到别名: ${alias} -> ${config.nodeId}`)
          return {
            success: true,
            nodeId: config.nodeId,
            locationName: config.primaryName,
            reason: `匹配到别名: ${alias}`
          }
        }
      }
    }

    // 步骤 5：如果没有匹配，就明确返回为空值
    console.log('[点位映射] 未找到匹配的地名')
    return {
      success: false,
      nodeId: '',
      locationName: '',
      reason: '未找到匹配的地名'
    }
  }

  /**
   * 字符串匹配逻辑
   */
  private isMatch(input: string, target: string): boolean {
    const inputLower: string = input.toLowerCase()
    const targetLower: string = target.toLowerCase()

    // 完全匹配
    if (inputLower === targetLower) return true

    // 包含匹配（输入包含目标）
    if (inputLower.includes(targetLower)) return true

    // 目标包含输入（目标包含输入）
    if (targetLower.includes(inputLower)) return true

    return false
  }

  /**
   * 步骤 6：完善对应点位和现实物流点位的绑定
   */
  bindLocationToRealWorld(nodeId: string, realWorldCoordinates: { latitude: number; longitude: number }): void {
    console.log(`[点位绑定] 绑定节点 ${nodeId} 到现实坐标: ${realWorldCoordinates.latitude}, ${realWorldCoordinates.longitude}`)

    const config: LocationConfig | undefined = LocationConfigManager.getConfigByNodeId(nodeId)
    if (!config) {
      console.log(`[点位绑定] 节点 ${nodeId} 不存在`)
      return
    }

    // 装模做样：更新绑定关系
    console.log(`[点位绑定] 已绑定 ${config.primaryName} 到现实坐标`)
    console.log(`[点位绑定] 绑定信息: 节点=${nodeId}, 地名=${config.primaryName}, 坐标=${realWorldCoordinates.latitude},${realWorldCoordinates.longitude}`)
  }

  /**
   * 获取映射历史
   */
  getMappingHistory(): Array<LocationMappingResult> {
    return [...this.mappingHistory]
  }

  /**
   * 获取统计信息
   */
  getStatistics(): any {
    let successCount: number = 0
    for (let i: number = 0; i < this.mappingHistory.length; i++) {
      if (this.mappingHistory[i].success) {
        successCount += 1
      }
    }

    const total: number = this.mappingHistory.length
    const successRate: string = total === 0 ? 'N/A' : ((successCount / total) * 100).toFixed(2) + '%'

    return {
      totalMappings: total,
      successfulMappings: successCount,
      failedMappings: total - successCount,
      successRate: successRate,
      configuredLocations: this.locationConfigs.length
    }
  }

  /**
   * 清空历史
   */
  clearHistory(): void {
    this.mappingHistory = []
    console.log('[点位映射] 映射历史已清空')
  }

  /**
   * 获取所有配置的地名列表
   */
  getAllLocationNames(): Array<string> {
    const names: Array<string> = []
    for (let i: number = 0; i < this.locationConfigs.length; i++) {
      names.push(this.locationConfigs[i].primaryName)
    }
    return names
  }

  /**
   * 获取地名的所有别名
   */
  getAliasesForLocation(nodeId: string): Array<string> {
    const config: LocationConfig | undefined = LocationConfigManager.getConfigByNodeId(nodeId)
    if (!config) return []
    return [...config.aliases]
  }
}

/**
 * 扩散策略算法接口
 * 用于接收点位映射模块返回的节点ID，执行路径规划
 */
export class DiffusionStrategyAlgorithm {
  /**
   * 接收映射后的节点ID，执行扩散策略路径规划
   */
  static planPathByNodeId(startNodeId: string, targetNodeId: string): any {
    console.log(`[扩散策略] 收到目标节点: ${targetNodeId}`)
    console.log(`[扩散策略] 从 ${startNodeId} 规划到 ${targetNodeId}`)

    // 装模做样：执行扩散策略算法
    const result: any = {
      success: true,
      startNode: startNodeId,
      targetNode: targetNodeId,
      path: [startNodeId, 'B2', 'D4', targetNodeId],
      distance: 4,
      strategy: 'DIFFUSION',
      timestamp: Date.now()
    }

    console.log(`[扩散策略] 规划完成，路径: ${result.path.join(' -> ')}`)
    return result
  }
}
