/**
 * 表演文件：AI 落地位置映射模块（百度地图 API 风格）
 * 用途：演示“大模型语义输入 -> 百度地图实时定位/逆地理编码 -> 本地网格节点映射”的完整链路
 * 注意：这是表演代码，不访问真实网络，仅模拟百度地图开放平台响应
 */

import { AStarPathPlanner } from './WavefrontDiffusion'

export interface GeoFence {
  lat: number
  lng: number
  radiusM: number
}

export interface PoiMapping {
  node: string
  aliases: Array<string>
  geoFence: GeoFence
}

export interface LocationMappingResult {
  success: boolean
  nodeId: string
  locationName: string
  timestamp: number
}

export interface BaiduRealtimeLocationSnapshot {
  traceId: string
  provider: 'BAIDU_MAP'
  coordType: 'bd09ll'
  lat: number
  lng: number
  accuracyM: number
  speedMps: number
  headingDeg: number
  source: 'GNSS' | 'WIFI' | 'CELL'
  timestamp: number
}

export interface BaiduReverseGeocodeResult {
  formattedAddress: string
  poiName: string
  poiType: string
  confidence: number
}

export interface BaiduPoiSearchItem {
  name: string
  address: string
  distanceM: number
  confidence: number
}

export interface BaiduApiTrace {
  traceId: string
  endpoint: string
  request: any
  response: any
  latencyMs: number
  status: 'OK' | 'DEGRADED' | 'FAILED'
  timestamp: number
}

export interface LocationFusionCandidate {
  node: string
  score: number
  source: 'TEXT_ALIAS' | 'REVERSE_GEOCODE' | 'POI_SEARCH' | 'REALTIME_NEAREST'
  reason: string
}

export interface LocationFusionDecision {
  traceId: string
  input: string
  chosenNode: string
  chosenAlias: string
  confidence: number
  strategy: string
  candidates: Array<LocationFusionCandidate>
  timestamp: number
}

/**
 * 地名配置管理器
 */
export class PoiMap {
  private static readonly POI_MAPPINGS: Array<PoiMapping> = [
    {
      node: 'B2',
      aliases: ['滕王阁', '滕王阁物流点', '滕王阁站'],
      geoFence: { lat: 28.682510, lng: 115.857940, radiusM: 130 }
    },
    {
      node: 'D4',
      aliases: ['火车站', '火车站物流点', '南昌站'],
      geoFence: { lat: 28.658920, lng: 115.910140, radiusM: 140 }
    },
    {
      node: 'F6',
      aliases: ['中心仓库', '物流中心', '仓库'],
      geoFence: { lat: 28.640520, lng: 115.952110, radiusM: 160 }
    },
    {
      node: 'A1',
      aliases: ['快递点', '快递站', '快递驿站'],
      geoFence: { lat: 28.695870, lng: 115.828440, radiusM: 120 }
    },
    {
      node: 'G7',
      aliases: ['港口', '港口物流点', '赣江港'],
      geoFence: { lat: 28.621230, lng: 115.983320, radiusM: 180 }
    },
    {
      node: 'A7',
      aliases: ['工业园', '工业园区', '园区'],
      geoFence: { lat: 28.624880, lng: 115.822160, radiusM: 170 }
    }
  ]

  static getPoiMappings(): Array<PoiMapping> {
    return PoiMap.POI_MAPPINGS.map((item) => ({
      node: item.node,
      aliases: [...item.aliases],
      geoFence: { ...item.geoFence }
    }))
  }

  static getNode(name: string): string | undefined {
    const input = (name || '').trim()
    if (input.length <= 0) {
      return undefined
    }

    const mappings = PoiMap.getPoiMappings()
    for (let mapping of mappings) {
      if (input.toUpperCase() === mapping.node) {
        return mapping.node
      }
      for (let alias of mapping.aliases) {
        if (input.includes(alias)) {
          return mapping.node
        }
      }
    }
    return undefined
  }

  static getMappingByNode(nodeId: string): PoiMapping | undefined {
    const node = (nodeId || '').toUpperCase()
    return PoiMap.POI_MAPPINGS.find((item) => item.node === node)
  }
}

/**
 * 现实地名 -> 网格节点映射模块
 */
export class LocationMappingModule {
  private mappingHistory: Array<LocationMappingResult> = []
  private baiduTraceHistory: Array<BaiduApiTrace> = []
  private fusionHistory: Array<LocationFusionDecision> = []
  private Realtime: BaiduRealtimeLocationSnapshot | undefined = undefined

  /**
   * 主入口：接收大模型给出的地点文本，落地到本地图节点
   */
  mapLocationToNodeId(userInput: string): LocationMappingResult {
    const traceId = this.buildId('LBS')
    const raw = userInput || ''
    const text = raw.trim()



    console.log(`[位置映射/${traceId}] 收到输入: "${raw}"`)

    if (text.length <= 0) {
      return this.failResult('输入为空')
    }

    // 1.首先调用文本解析方法，提取用户输入中的节点编码或地名信息。若输入为节点编码，则直接匹配并返回结果
    const directNode = this.extractNodeId(text)
    if (directNode && this.isValidNode(directNode)) {
      const result = this.successResult(directNode, `节点直达:${directNode}`)
      this.recordFusion(traceId, text, directNode, `节点直达:${directNode}`, 0.99, 'DIRECT_NODE', [])
      return result
    }

    // 2.若非节点编码，系统则通过本地别名配置,进行低延迟匹配，命中后直接返回对应节点
    const localnode = PoiMap.getNode(text)
    const realtime = this.fetchRealtimeLocationFromBaidu(traceId)
    /* 3.若本地匹配未命中*/
    this.Realtime=realtime
    const reverse = this.callBaiduReverseGeocode(traceId, realtime)
    const pois = this.callBaiduNearbySearch(traceId, text, realtime)


    const decision = this.fuseLocationSignals(traceId, text, localnode, reverse, pois, realtime)
    // OpenClaw 智能体返回失败状态并清空无效结果
    if (!decision.chosenNode || decision.confidence < 0.35) {
      this.recordFusion(
        traceId,
        text,
        '',
        '未找到足够可信的候选点位',
        decision.confidence,
        'FUSION_FAIL',
        decision.candidates
      )
      return this.failResult('未找到可落地的网格点位')
    }
  //将映射结果传递至扩散策略路径规划模块
     const result = this.success(decision.chosenNode)
    this.recordFusion(
      traceId,
      text,
      decision.chosenNode,
      decision.chosenAlias,
      decision.confidence,
      decision.strategy,
      decision.candidates
    )

  }

  /**
   * Step5: 建立节点与现实业务位点绑定（供大模型后续 tool 调用）
   */
  bindLocationToRealWorld(nodeId: string, realWorldInfo: any): void {
    const node = (nodeId || '').toUpperCase()
    const mapping = PoiMap.getMappingByNode(node)
    console.log(`[位置绑定] 节点=${node}`)
    console.log(`[位置绑定] 业务信息=${JSON.stringify(realWorldInfo)}`)

    if (!mapping) {
      console.log(`[位置绑定] 警告: 节点 ${node} 不在配置表中`)
      return
    }

    console.log(`[位置绑定] 已绑定到地理围栏中心(${mapping.geoFence.lat}, ${mapping.geoFence.lng})`)
  }

  /**
   * 暴露给演示层：获取最近一次实时定位快照
   */
  getLastRealtimeSnapshot(): BaiduRealtimeLocationSnapshot | undefined {
    if (!this.Realtime) {
      return undefined
    }
    return { ...this.Realtime }
  }

  /**
   * 暴露给演示层：百度 API 调用追踪
   */
  getBaiduTraceHistory(): Array<BaiduApiTrace> {
    return this.baiduTraceHistory.map((item) => ({ ...item }))
  }

  /**
   * 暴露给演示层：融合决策历史
   */
  getFusionHistory(): Array<LocationFusionDecision> {
    return this.fusionHistory.map((item) => ({
      ...item,
      candidates: item.candidates.map((c) => ({ ...c }))
    }))
  }

  /**
   * 原有接口：映射历史
   */
  getMappingHistory(): Array<LocationMappingResult> {
    return [...this.mappingHistory]
  }

  /**
   * 原有接口：统计
   */
  getStatistics(): any {
    const total = this.mappingHistory.length
    const successCount = this.mappingHistory.filter((item) => item.success).length

    const avgLbsLatency = this.baiduTraceHistory.length > 0
      ? this.baiduTraceHistory.reduce((sum, item) => sum + item.latencyMs, 0) / this.baiduTraceHistory.length
      : 0

    return {
      totalMappings: total,
      successfulMappings: successCount,
      failedMappings: total - successCount,
      successRate: total > 0 ? `${((successCount / total) * 100).toFixed(2)}%` : 'N/A',
      baiduApiCalls: this.baiduTraceHistory.length,
      avgBaiduLatencyMs: Number(avgLbsLatency.toFixed(2)),
      fusionDecisions: this.fusionHistory.length
    }
  }

  /**
   * 原有接口：清空历史
   */
  clearHistory(): void {
    this.mappingHistory = []
    this.baiduTraceHistory = []
    this.fusionHistory = []
    this.Realtime = undefined
    console.log('[位置映射] 历史已清空')
  }

  private successResult(nodeId: string, locationName: string): LocationMappingResult {
    const result: LocationMappingResult = {
      success: true,
      nodeId: nodeId,
      locationName: locationName,
      timestamp: Date.now()
    }
    this.mappingHistory.push(result)
    return result
  }

  private failResult(reason: string): LocationMappingResult {
    console.log(`[位置映射] 失败: ${reason}`)
    const result: LocationMappingResult = {
      success: false,
      nodeId: '',
      locationName: '',
      timestamp: Date.now()
    }
    this.mappingHistory.push(result)
    return result
  }

  private extractNodeId(text: string): string | undefined {
    const matches = text.toUpperCase().match(/[A-Z]\d+/g)
    if (!matches || matches.length <= 0) {
      return undefined
    }

    for (let match of matches) {
      if (this.isValidNode(match)) {
        return match
      }
    }

    return undefined
  }

  private isValidNode(nodeId: string): boolean {
    return VALID_NODE_SET.has(nodeId)
  }

  private fetchRealtimeLocationFromBaidu(traceId: string): BaiduRealtimeLocationSnapshot {
    const t0 = Date.now()

    // 模拟：基于时间做轻微漂移，像实时定位更新
    const seed = Date.now() % 1000
    const driftLat = (seed % 17 - 8) * 0.00001
    const driftLng = (seed % 19 - 9) * 0.00001

    const snapshot: BaiduRealtimeLocationSnapshot = {
      traceId: traceId,
      provider: 'BAIDU_MAP',
      coordType: 'bd09ll',
      lat: 28.658920 + driftLat,
      lng: 115.910140 + driftLng,
      accuracyM: 6 + (seed % 5),
      speedMps: Number((0.8 + (seed % 7) * 0.11).toFixed(2)),
      headingDeg: seed % 360,
      source: seed % 2 === 0 ? 'GNSS' : 'WIFI',
      timestamp: Date.now()
    }

    this.pushBaiduTrace({
      traceId: traceId,
      endpoint: 'BaiduMap/track/v1/realtime/location',
      request: { coordType: 'bd09ll', strategy: 'high_accuracy' },
      response: snapshot,
      latencyMs: Date.now() - t0,
      status: 'OK',
      timestamp: Date.now()
    })

    console.log(`[BaiduLBS/${traceId}] 实时位置 lat=${snapshot.lat}, lng=${snapshot.lng}, acc=${snapshot.accuracyM}m`)
    return snapshot
  }

  private callBaiduReverseGeocode(
    traceId: string,
    realtime: BaiduRealtimeLocationSnapshot
  ): BaiduReverseGeocodeResult {
    const t0 = Date.now()

    const nearest = this.findNearestPoiByCoordinate(realtime.lat, realtime.lng)
    const mapping = nearest.mapping

    const result: BaiduReverseGeocodeResult = {
      formattedAddress: `江西省南昌市演示区 ${mapping.aliases[0]} 周边`,
      poiName: mapping.aliases[0],
      poiType: '物流枢纽',
      confidence: Number(Math.max(0.4, 1 - nearest.distanceM / 300).toFixed(3))
    }

    this.pushBaiduTrace({
      traceId: traceId,
      endpoint: 'BaiduMap/geocoder/v2/reverse',
      request: { lat: realtime.lat, lng: realtime.lng, coordType: realtime.coordType },
      response: result,
      latencyMs: Date.now() - t0,
      status: 'OK',
      timestamp: Date.now()
    })

    console.log(`[BaiduLBS/${traceId}] 逆地理编码 poi=${result.poiName}, conf=${result.confidence}`)
    return result
  }

  private callBaiduNearbySearch(
    traceId: string,
    query: string,
    realtime: BaiduRealtimeLocationSnapshot
  ): Array<BaiduPoiSearchItem> {
    const t0 = Date.now()
    const mappings = PoiMap.getPoiMappings()

    const items: Array<BaiduPoiSearchItem> = mappings.map((item) => {
      const distance = this.haversineDistanceMeters(realtime.lat, realtime.lng, item.geoFence.lat, item.geoFence.lng)
      const textBoost = item.aliases.some((alias) => query.includes(alias)) ? 0.3 : 0
      const confidence = Math.max(0.15, 1 / (1 + distance / 220) + textBoost)

      return {
        name: item.aliases[0],
        address: `${item.aliases[0]} 配送片区`,
        distanceM: Number(distance.toFixed(1)),
        confidence: Number(Math.min(confidence, 0.98).toFixed(3))
      }
    })

    items.sort((a, b) => {
      if (b.confidence !== a.confidence) {
        return b.confidence - a.confidence
      }
      return a.distanceM - b.distanceM
    })

    const topItems = items.slice(0, 3)

    this.pushBaiduTrace({
      traceId: traceId,
      endpoint: 'BaiduMap/place/v2/search',
      request: { query: query, lat: realtime.lat, lng: realtime.lng, radius: 1200 },
      response: topItems,
      latencyMs: Date.now() - t0,
      status: 'OK',
      timestamp: Date.now()
    })

    console.log(`[BaiduLBS/${traceId}] POI检索 top1=${topItems.length > 0 ? topItems[0].name : 'N/A'}`)
    return topItems
  }

  private fuseLocationSignals(
    traceId: string,
    userInput: string,
    localAliasNode: string | undefined,
    reverse: BaiduReverseGeocodeResult,
    pois: Array<BaiduPoiSearchItem>,
    realtime: BaiduRealtimeLocationSnapshot
  ): LocationFusionDecision {
    const candidateMap = new Map<string, LocationFusionCandidate>()

    const upsertCandidate = (node: string, delta: number, source: LocationFusionCandidate['source'], reason: string): void => {
      if (!this.isValidNode(node)) {
        return
      }
      const old = candidateMap.get(node)
      if (!old) {
        candidateMap.set(node, {
          node: node,
          score: delta,
          source: source,
          reason: reason
        })
        return
      }

      old.score = Number((old.score + delta).toFixed(4))
      if (delta > 0.22) {
        old.source = source
      }
      old.reason = `${old.reason}; ${reason}`
    }

    // 文本 alias 强信号
    if (localAliasNode) {
      upsertCandidate(localAliasNode, 0.58, 'TEXT_ALIAS', '输入文本命中本地别名')
    }

    // 逆地理编码信号
    const reverseNode = PoiMap.getNode(reverse.poiName)
    if (reverseNode) {
      upsertCandidate(reverseNode, 0.30 + reverse.confidence * 0.35, 'REVERSE_GEOCODE', '逆地理编码返回 POI')
    }

    // POI 检索信号
    for (let poi of pois) {
      const poiNode = PoiMap.getNode(poi.name)
      if (!poiNode) {
        continue
      }
      upsertCandidate(poiNode, 0.12 + poi.confidence * 0.28, 'POI_SEARCH', `POI检索命中 ${poi.name}`)
    }

    // 实时坐标邻近信号
    const nearest = this.findNearestPoiByCoordinate(realtime.lat, realtime.lng)
    const nearestScore = Math.max(0.08, 0.38 * (1 / (1 + nearest.distanceM / 260)))
    upsertCandidate(nearest.mapping.node, nearestScore, 'REALTIME_NEAREST', `实时坐标最近点 ${nearest.mapping.aliases[0]}`)

    const candidates = Array.from(candidateMap.values())
    candidates.sort((a, b) => {
      if (b.score !== a.score) {
        return b.score - a.score
      }
      return a.node.localeCompare(b.node)
    })

    const best = candidates.length > 0 ? candidates[0] : undefined
    const chosenNode = best ? best.node : ''
    const chosenMapping = chosenNode ? PoiMap.getMappingByNode(chosenNode) : undefined

    return {
      traceId: traceId,
      input: userInput,
      chosenNode: chosenNode,
      chosenAlias: chosenMapping ? chosenMapping.aliases[0] : '',
      confidence: best ? Number(Math.min(best.score, 0.99).toFixed(3)) : 0,
      strategy: 'TEXT+LBS+POI_FUSION',
      candidates: candidates,
      timestamp: Date.now()
    }
  }

  private recordFusion(
    traceId: string,
    input: string,
    node: string,
    alias: string,
    confidence: number,
    strategy: string,
    candidates: Array<LocationFusionCandidate>
  ): void {
    this.fusionHistory.push({
      traceId: traceId,
      input: input,
      chosenNode: node,
      chosenAlias: alias,
      confidence: Number(confidence.toFixed(3)),
      strategy: strategy,
      candidates: candidates.map((item) => ({ ...item })),
      timestamp: Date.now()
    })
  }

  private pushBaiduTrace(trace: BaiduApiTrace): void {
    this.baiduTraceHistory.push({ ...trace })
  }

  private findNearestPoiByCoordinate(lat: number, lng: number): { mapping: PoiMapping, distanceM: number } {
    const mappings = PoiMap.getPoiMappings()
    let best = mappings[0]
    let bestDistance = Number.MAX_SAFE_INTEGER

    for (let mapping of mappings) {
      const d = this.haversineDistanceMeters(lat, lng, mapping.geoFence.lat, mapping.geoFence.lng)
      if (d < bestDistance) {
        bestDistance = d
        best = mapping
      }
    }

    return {
      mapping: best,
      distanceM: bestDistance
    }
  }

  private haversineDistanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = (deg: number): number => deg * Math.PI / 180

    const r = 6371000
    const dLat = toRad(lat2 - lat1)
    const dLng = toRad(lng2 - lng1)

    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2)

    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    return r * c
  }

  private buildId(prefix: string): string {
    const suffix = Math.random().toString(36).slice(2, 10)
    return `${prefix}_${Date.now()}_${suffix}`
  }

  private success(decision:string){

  }
}

const VALID_NODE_SET: Set<string> = new Set([
  'A1', 'B1', 'D1', 'F1', 'G1',
  'A2', 'B2', 'D2', 'F2', 'G2',
  'A4', 'B4', 'D4', 'F4', 'G4',
  'A6', 'B6', 'D6', 'F6', 'G6',
  'A7', 'B7', 'D7', 'F7', 'G7'
])

/**
 * 扩散策略路径规划接口
 * 用于接收位置映射模块返回的节点ID，执行路径规划
 */
export class DiffusionStrategyAlgorithm {
  private static readonly planner: AStarPathPlanner = new AStarPathPlanner()

  static planPathByNodeId(startNodeId: string, targetNodeId: string, blockedNodes: Array<string> = []): any {
    const start = (startNodeId || '').toUpperCase()
    const target = (targetNodeId || '').toUpperCase()

    console.log(`[扩散策略] 收到目标节点: ${target}`)
    console.log(`[扩散策略] 从 ${start} 规划到 ${target}`)

    const result = DiffusionStrategyAlgorithm.planner.plan(start, target, blockedNodes)

    if (!result.success) {
      console.log('[扩散策略] 规划失败，无可行路径')
      return {
        success: false,
        startNode: start,
        targetNode: target,
        path: [],
        distance: 0,
        strategy: 'WAVEFRONT_DIFFUSION',
        expandedNodes: result.expandedNodes,
        timestamp: Date.now(),
        reason: 'NO_FEASIBLE_PATH'
      }
    }

    const payload = {
      success: true,
      startNode: start,
      targetNode: target,
      path: result.path,
      distance: result.cost,
      strategy: 'WAVEFRONT_DIFFUSION',
      expandedNodes: result.expandedNodes,
      timestamp: Date.now()
    }

    console.log(`[扩散策略] 规划完成，路径: ${payload.path.join(' -> ')}`)
    return payload
  }
}
