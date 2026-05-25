/**
 * 表演文件：高阶路径重规划模块
 * 用途：演示“多策略候选 + 风险评估 + 轨迹稳定化 + 可回放诊断”的重规划流程
 * 注意：这是表演代码，不用于正式生产环境
 */

import { AStarPathPlanner } from './WavefrontDiffusion'

//1.我已专门设置了路径规划的结果对象，用于接收算法返回的规划数据
export interface PathPlanResult {
  success: boolean
  path: Array<string>
  distance: number
  estimatedTime: number
  timestamp: number
  reason: string
}

export interface ReplanContext {
  oldPath: Array<string>
  newPath: Array<string>
  oldTarget: string
  newTarget: string
  currentPosition: string
  blockedNodes: Array<string>
  replanReason: string
  replanTimestamp: number
}

export interface ReplanTelemetry {
  traceId: string
  selectedStrategy: string
  totalLatencyMs: number
  plannerLatencyMs: number
  scoringLatencyMs: number
  blockedNodeCount: number
  blockedEdgeCount: number
  candidateCount: number
}

export interface StrategyScore {
  strategyId: string
  path: Array<string>
  hops: number
  turnCount: number
  riskIndex: number
  continuity: number
  expandedNodes: number
  latencyMs: number
  finalScore: number
}

export interface ReplanDiagnostics {
  telemetry: ReplanTelemetry
  candidates: Array<StrategyScore>
  rejectedReasons: Array<string>
}

export interface ReplanLog {
  id: string
  context: ReplanContext
  status: 'SUCCESS' | 'FAILED'
  executionTime: number
  timestamp: number
  telemetry?: ReplanTelemetry
  diagnostics?: ReplanDiagnostics
}

interface StrategyProfile {
  id: string
  label: string
  turnWeight: number
  riskWeight: number
  continuityWeight: number
  heuristicWeight: number
  beamWidth: number
  riskInflationRadius: number
}

interface BeamState {
  node: string
  path: Array<string>
  turns: number
  risk: number
  continuity: number
  priority: number
}

interface CandidatePath {
  strategyId: string
  strategyLabel: string
  path: Array<string>
  expandedNodes: number
  latencyMs: number
}

interface PlannerOutput {
  selectedPath: Array<string>
  selectedStrategy: string
  diagnostics: ReplanDiagnostics
}

// 重规划执行上下文（用于成功/失败处理参数封装）
interface ReplanExecutionGuard {
  oldPath: Array<string>
  oldTarget: string
  newTarget: string
  currentPos: string
  blockedNodes: Array<string>
  startTime: number
  diagnostics: ReplanDiagnostics
  newPath?: Array<string>
  strategyId?: string
}

export class PathReplanningModule {
  private static readonly GRID_COLS: Array<string> = ['A', 'B', 'D', 'F', 'G']
  private static readonly GRID_ROWS: Array<number> = [1, 2, 4, 6, 7]

  private static readonly STRATEGIES: Array<StrategyProfile> = [
    {
      id: 'DIFFUSION_BASE',
      label: '波前扩散基线',
      turnWeight: 0.30,
      riskWeight: 0.80,
      continuityWeight: 0.35,
      heuristicWeight: 0.25,
      beamWidth: 0,
      riskInflationRadius: 0
    },
    {
      id: 'BEAM_BALANCED',
      label: '平衡型多目标搜索',
      turnWeight: 0.55,
      riskWeight: 1.10,
      continuityWeight: 0.60,
      heuristicWeight: 0.35,
      beamWidth: 8,
      riskInflationRadius: 0
    },
    {
      id: 'BEAM_SAFE',
      label: '安全优先搜索',
      turnWeight: 0.70,
      riskWeight: 1.45,
      continuityWeight: 0.45,
      heuristicWeight: 0.40,
      beamWidth: 10,
      riskInflationRadius: 1
    },
    {
      id: 'BEAM_FAST',
      label: '快速响应搜索',
      turnWeight: 0.25,
      riskWeight: 0.55,
      continuityWeight: 0.20,
      heuristicWeight: 0.70,
      beamWidth: 6,
      riskInflationRadius: 0
    }
  ]

  private currentPath: Array<string> = []
  private currentTarget: string = ''
  private replanHistory: Array<ReplanLog> = []
  private isReplanning: boolean = false
  private lastDiagnostics: ReplanDiagnostics | undefined = undefined

  private readonly planner: AStarPathPlanner = new AStarPathPlanner()

  /**
   * 统一构建重规划结果对象
   */
  private createPlanResult(
    success: boolean,
    path: Array<string>,
    reason: string,
    riskIndex: number = 0
  ): PathPlanResult {
    const hops = path.length > 0 ? path.length - 1 : 0
    const turns = this.countTurns(path)
    const estimatedTime = this.estimateTravelTimeSeconds(hops, turns, riskIndex)

    return {
      success: success,
      path: path,
      distance: hops,
      estimatedTime: estimatedTime,
      timestamp: Date.now(),
      reason: reason
    }
  }

  /**
   * 主入口：执行路径重规划
   */
  replan(
    currentPos: string,
    newTarget: string,
    blockedNodes: Array<string> = [],
    blockedEdges: Array<string> = []
  ): PathPlanResult {
    if (this.isReplanning) {
      return this.createPlanResult(false, [], '重规划进行中，请稍候')
    }

    this.isReplanning = true
    const startTime = Date.now()
    const traceId = this.buildId('TRACE')

    try {
      const oldPath = [...this.currentPath]
      const oldTarget = this.currentTarget
      //1.运行期间临时修改目的地时，自动以当前位置为新起点，结合阻塞信息重新规划并生成最优路线
      const start = this.NodeId(currentPos)
      const end = this.NodeId(newTarget)

      const normalizedBlockedNodes = this.normalizeBlockedNodes(blockedNodes)
      const blockedEdgeSet = this.normalizeBlockedEdges(blockedEdges)

      const edgeTouchNodes = this.extractNodesFromBlockedEdges(blockedEdgeSet)
      const blockedNodesForLog = this.mergeUniqueNodes(normalizedBlockedNodes, edgeTouchNodes)

      console.log(`[Replan/${traceId}] 请求: ${start} -> ${end}`)
      console.log(`[Replan/${traceId}] 阻塞节点: ${normalizedBlockedNodes.length > 0 ? normalizedBlockedNodes.join(', ') : '无'}`)
      console.log(`[Replan/${traceId}] 边关联节点(风险锚点): ${edgeTouchNodes.length > 0 ? edgeTouchNodes.join(', ') : '无'}`)
      console.log(`[Replan/${traceId}] 阻塞边: ${blockedEdgeSet.size > 0 ? blockedEdges.join(', ') : '无'}`)

      const plannerOutput = this.runHybridPlanner(
        traceId,
        start,
        end,
        normalizedBlockedNodes,
        edgeTouchNodes,
        blockedEdgeSet,
        oldPath
      )

      this.lastDiagnostics = plannerOutput.diagnostics

      // 构建统一上下文
      const guard: ReplanExecutionGuard = {
        oldPath,
        oldTarget,
        newTarget: end,
        currentPos: start,
        blockedNodes: blockedNodesForLog,
        startTime,
        diagnostics: plannerOutput.diagnostics
      }

      //2.规划失败时
      if (plannerOutput.selectedPath.length <= 0) {
        return this.guihuaReplanFailure(guard)

      }

      guard.newPath = plannerOutput.selectedPath
      guard.strategyId = plannerOutput.selectedStrategy
      //3.规划成功时
      return this.guihuaReplanFailure(guard)

    } finally {
      this.isReplanning = false
    }
  }

  private runHybridPlanner(
    traceId: string,
    start: string,
    goal: string,
    blockedNodes: Array<string>,
    edgeTouchNodes: Array<string>,
    blockedEdgeSet: Set<string>,
    oldPath: Array<string>
  ): PlannerOutput {
    const plannerStartMs = Date.now()

    const hardBlockedSet = new Set(blockedNodes)
    const riskAnchorSet = new Set(this.mergeUniqueNodes(blockedNodes, edgeTouchNodes))
    const candidates: Array<CandidatePath> = []
    const rejectedReasons: Array<string> = []

    // 候选 1：波前扩散基线（稳定）
    const baseline = this.planByDiffusion(start, goal, blockedNodes, blockedEdgeSet)
    if (baseline.path.length > 0) {
      candidates.push(baseline)
    } else {
      rejectedReasons.push('DIFFUSION_BASE 未找到可行路径')
    }

    // 候选 2~N：Beam 多策略搜索（高科技演示）
    for (let profile of PathReplanningModule.STRATEGIES) {
      if (profile.id === 'DIFFUSION_BASE') {
        continue
      }

      const profileBlocked = this.inflateBlockedNodes(hardBlockedSet, profile.riskInflationRadius, start, goal)
      const beam = this.planByBeamSearch(start, goal, profileBlocked, blockedEdgeSet, oldPath, profile)

      if (beam.path.length > 0) {
        candidates.push(beam)
      } else {
        rejectedReasons.push(`${profile.id} 未找到可行路径`)
      }
    }

    const dedupedCandidates = this.deduplicateCandidates(candidates)
    const plannerLatencyMs = Date.now() - plannerStartMs

    const scoringStartMs = Date.now()
    const scores: Array<StrategyScore> = []

    for (let candidate of dedupedCandidates) {
      scores.push(this.scoreCandidate(candidate, riskAnchorSet, oldPath))
    }

    scores.sort((a, b) => a.finalScore - b.finalScore)

    const best = scores.length > 0 ? scores[0] : undefined
    const selectedPath = best ? this.stabilizePath(best.path, oldPath, blockedEdgeSet) : []
    const scoringLatencyMs = Date.now() - scoringStartMs

    const telemetry: ReplanTelemetry = {
      traceId: traceId,
      selectedStrategy: best ? best.strategyId : 'NONE',
      totalLatencyMs: plannerLatencyMs + scoringLatencyMs,
      plannerLatencyMs: plannerLatencyMs,
      scoringLatencyMs: scoringLatencyMs,
      blockedNodeCount: blockedNodes.length,
      blockedEdgeCount: blockedEdgeSet.size,
      candidateCount: scores.length
    }

    const diagnostics: ReplanDiagnostics = {
      telemetry: telemetry,
      candidates: scores,
      rejectedReasons: rejectedReasons
    }

    console.log(`[Replan/${traceId}] 候选路径数: ${scores.length}`)
    if (best) {
      console.log(`[Replan/${traceId}] 选中策略: ${best.strategyId}, score=${best.finalScore.toFixed(3)}`)
    } else {
      console.log(`[Replan/${traceId}] 无可行策略`)
    }

    return {
      selectedPath: selectedPath,
      selectedStrategy: best ? best.strategyId : 'NONE',
      diagnostics: diagnostics
    }
  }

  private planByDiffusion(
    start: string,
    goal: string,
    blockedNodes: Array<string>,
    blockedEdgeSet: Set<string>
  ): CandidatePath {
    const t0 = Date.now()
    const result = this.planner.plan(start, goal, blockedNodes)
    const latency = Date.now() - t0

    if (!result.success || result.path.length <= 0) {
      return {
        strategyId: 'DIFFUSION_BASE',
        strategyLabel: '波前扩散基线',
        path: [],
        expandedNodes: result.expandedNodes,
        latencyMs: latency
      }
    }

    const path = this.pathContainsBlockedEdge(result.path, blockedEdgeSet) ? [] : result.path
    return {
      strategyId: 'DIFFUSION_BASE',
      strategyLabel: '波前扩散基线',
      path: path,
      expandedNodes: result.expandedNodes,
      latencyMs: latency
    }
  }

  private planByBeamSearch(
    start: string,
    goal: string,
    blockedSet: Set<string>,
    blockedEdgeSet: Set<string>,
    oldPath: Array<string>,
    profile: StrategyProfile
  ): CandidatePath {
    const t0 = Date.now()

    if (blockedSet.has(start) || blockedSet.has(goal)) {
      return {
        strategyId: profile.id,
        strategyLabel: profile.label,
        path: [],
        expandedNodes: 0,
        latencyMs: Date.now() - t0
      }
    }

    const adjacency = this.planner.getAdjacencyList()
    let frontier: Array<BeamState> = [{
      node: start,
      path: [start],
      turns: 0,
      risk: 0,
      continuity: this.computeContinuity([start], oldPath),
      priority: 0
    }]

    const goalStates: Array<BeamState> = []
    let expanded = 0
    const maxExpanded = 640
    const maxCandidates = 4

    while (frontier.length > 0 && expanded < maxExpanded && goalStates.length < maxCandidates) {
      frontier.sort((a, b) => a.priority - b.priority)
      const wave = frontier.slice(0, profile.beamWidth)
      const nextFrontier: Array<BeamState> = []

      for (let state of wave) {
        if (state.node === goal) {
          goalStates.push(state)
          continue
        }

        const neighbors = adjacency.get(state.node) || []
        for (let neighbor of neighbors) {
          expanded += 1
          if (expanded > maxExpanded) {
            break
          }

          if (blockedSet.has(neighbor)) {
            continue
          }

          if (this.isBlockedEdge(state.node, neighbor, blockedEdgeSet)) {
            continue
          }

          if (state.path.includes(neighbor)) {
            continue
          }

          const newPath = [...state.path, neighbor]
          const turns = this.countTurns(newPath)
          const risk = state.risk + this.computeNodeRisk(neighbor, blockedSet)
          const continuity = this.computeContinuity(newPath, oldPath)
          const hops = newPath.length - 1
          const h = this.gridDistance(neighbor, goal)

          const priority =
            hops +
              turns * profile.turnWeight +
              risk * profile.riskWeight +
              (1 - continuity) * profile.continuityWeight +
              h * profile.heuristicWeight

          nextFrontier.push({
            node: neighbor,
            path: newPath,
            turns: turns,
            risk: risk,
            continuity: continuity,
            priority: priority
          })
        }
      }

      nextFrontier.sort((a, b) => a.priority - b.priority)
      frontier = nextFrontier.slice(0, profile.beamWidth * 3)
    }

    if (goalStates.length <= 0) {
      return {
        strategyId: profile.id,
        strategyLabel: profile.label,
        path: [],
        expandedNodes: expanded,
        latencyMs: Date.now() - t0
      }
    }

    goalStates.sort((a, b) => a.priority - b.priority)

    return {
      strategyId: profile.id,
      strategyLabel: profile.label,
      path: goalStates[0].path,
      expandedNodes: expanded,
      latencyMs: Date.now() - t0
    }
  }

  private deduplicateCandidates(candidates: Array<CandidatePath>): Array<CandidatePath> {
    const map = new Map<string, CandidatePath>()
    for (let candidate of candidates) {
      if (candidate.path.length <= 0) {
        continue
      }
      const key = candidate.path.join('>')
      const old = map.get(key)
      if (!old || candidate.expandedNodes < old.expandedNodes) {
        map.set(key, candidate)
      }
    }
    return Array.from(map.values())
  }

  private scoreCandidate(
    candidate: CandidatePath,
    blockedSet: Set<string>,
    oldPath: Array<string>
  ): StrategyScore {
    const hops = candidate.path.length - 1
    const turns = this.countTurns(candidate.path)
    const risk = this.computePathRisk(candidate.path, blockedSet)
    const continuity = this.computeContinuity(candidate.path, oldPath)

    const finalScore =
      hops * 1.00 +
        turns * 0.58 +
        risk * 1.30 +
        (1 - continuity) * 0.85 +
        candidate.expandedNodes * 0.002

    return {
      strategyId: candidate.strategyId,
      path: candidate.path,
      hops: hops,
      turnCount: turns,
      riskIndex: Number(risk.toFixed(3)),
      continuity: Number(continuity.toFixed(3)),
      expandedNodes: candidate.expandedNodes,
      latencyMs: candidate.latencyMs,
      finalScore: Number(finalScore.toFixed(3))
    }
  }

  private stabilizePath(
    path: Array<string>,
    oldPath: Array<string>,
    blockedEdgeSet: Set<string>
  ): Array<string> {
    if (path.length <= 2 || oldPath.length <= 1) {
      return path
    }

    // 抑制“局部来回抖动”：A->B->A 这种模式直接剔除中间点
    const stabilized: Array<string> = []
    for (let i = 0; i < path.length; i++) {
      const cur = path[i]
      const prev = stabilized.length >= 1 ? stabilized[stabilized.length - 1] : ''
      const prevPrev = stabilized.length >= 2 ? stabilized[stabilized.length - 2] : ''

      if (prevPrev.length > 0 && prev.length > 0 && prevPrev === cur) {
        stabilized.pop()
        continue
      }

      stabilized.push(cur)
    }

    // 兜底：平滑后不能引入阻塞边
    if (this.pathContainsBlockedEdge(stabilized, blockedEdgeSet)) {
      return path
    }

    return stabilized
  }

  /**
   * 规划失败处理
   */
  private guihuaReplanFailure(guard: ReplanExecutionGuard): PathPlanResult {
    console.log(`[重规划失败] 无法规划到 ${guard.newTarget}`)

    this.currentPath = []
    this.currentTarget = ''

    this.recordReplanLog(
      guard.oldPath,
      [],
      guard.oldTarget,
      guard.newTarget,
      guard.currentPos,
      guard.blockedNodes,
      'FAILED',
      guard.startTime,
      guard.diagnostics
    )

    return this.createPlanResult(
      false,
      [],
      `无法规划到目标 ${guard.newTarget}，已清空路径列表`
    )
  }

  /**
   * 规划成功处理
   */
  private guihuaReplanSuccess(guard: ReplanExecutionGuard): PathPlanResult {
    const newPath = guard.newPath!
    const strategyId = guard.strategyId!

    console.log(`[重规划成功] 策略=${strategyId}, 新路径: ${newPath.join(' -> ')}`)

    this.currentPath = [...newPath]
    this.currentTarget = guard.newTarget

    this.recordReplanLog(
      guard.oldPath,
      newPath,
      guard.oldTarget,
      guard.newTarget,
      guard.currentPos,
      guard.blockedNodes,
      'SUCCESS',
      guard.startTime,
      guard.diagnostics
    )

    this.logPathTransition(guard.oldPath, newPath, guard.oldTarget, guard.newTarget, guard.currentPos, guard.blockedNodes, strategyId)

    const riskIndex = guard.diagnostics.candidates.length > 0
      ? guard.diagnostics.candidates[0].riskIndex
      : 0

    return this.createPlanResult(
      true,
      newPath,
      `成功重规划到 ${guard.newTarget}（策略=${strategyId}）`,
      riskIndex
    )
  }

  /**
   * 记录重规划日志（包含遥测与诊断）
   */
  private recordReplanLog(
    oldPath: Array<string>,
    newPath: Array<string>,
    oldTarget: string,
    newTarget: string,
    currentPos: string,
    blockedNodes: Array<string>,
    status: 'SUCCESS' | 'FAILED',
    startTime: number,
    diagnostics: ReplanDiagnostics
  ): void {
    const executionTime = Date.now() - startTime

    const log: ReplanLog = {
      id: this.buildId('REPLAN'),
      context: {
        oldPath: [...oldPath],
        newPath: [...newPath],
        oldTarget: oldTarget,
        newTarget: newTarget,
        currentPosition: currentPos,
        blockedNodes: [...blockedNodes],
        replanReason: `目标从 ${oldTarget} 调整为 ${newTarget}`,
        replanTimestamp: Date.now()
      },
      status: status,
      executionTime: executionTime,
      timestamp: Date.now(),
      telemetry: diagnostics.telemetry,
      diagnostics: diagnostics
    }

    this.replanHistory.push(log)
    console.log(`[日志] 重规划记录已保存: ${log.id}`)
  }

  /**
   * 打印路径切换信息
   */
  private logPathTransition(
    oldPath: Array<string>,
    newPath: Array<string>,
    oldTarget: string,
    newTarget: string,
    currentPos: string,
    blockedNodes: Array<string>,
    strategyId: string
  ): void {
    console.log('=== 路径切换详情 ===')
    console.log(`当前位置: ${currentPos}`)
    console.log(`旧目标: ${oldTarget}`)
    console.log(`新目标: ${newTarget}`)
    console.log(`旧路径: ${oldPath.join(' -> ')}`)
    console.log(`新路径: ${newPath.join(' -> ')}`)
    console.log(`阻塞节点: ${blockedNodes.length > 0 ? blockedNodes.join(', ') : '无'}`)
    console.log(`执行策略: ${strategyId}`)
    console.log('状态: 当前路径可中断，下一路径可接管')
    console.log('====================')
  }

  private normalizeBlockedNodes(nodes: Array<string>): Array<string> {
    const out: Array<string> = []
    for (let node of nodes) {
      const normalized = this.NodeId(node)
      if (this.isValidNode(normalized) && !out.includes(normalized)) {
        out.push(normalized)
      }
    }
    return out
  }

  private normalizeBlockedEdges(edges: Array<string>): Set<string> {
    const out = new Set<string>()
    for (let edge of edges) {
      const parsed = this.parseEdge(edge)
      if (!parsed) {
        continue
      }
      const a = parsed[0]
      const b = parsed[1]
      if (!this.isValidNode(a) || !this.isValidNode(b)) {
        continue
      }
      out.add(this.edgeKey(a, b))
    }
    return out
  }

  private extractNodesFromBlockedEdges(edgeSet: Set<string>): Array<string> {
    const out: Array<string> = []
    for (let edgeKey of edgeSet) {
      const parts = edgeKey.split('|')
      if (parts.length !== 2) {
        continue
      }
      if (!out.includes(parts[0])) {
        out.push(parts[0])
      }
      if (!out.includes(parts[1])) {
        out.push(parts[1])
      }
    }
    return out
  }

  private mergeUniqueNodes(a: Array<string>, b: Array<string>): Array<string> {
    const out: Array<string> = [...a]
    for (let node of b) {
      if (!out.includes(node)) {
        out.push(node)
      }
    }
    return out
  }

  private inflateBlockedNodes(
    blocked: Set<string>,
    radius: number,
    start: string,
    goal: string
  ): Set<string> {
    if (radius <= 0 || blocked.size <= 0) {
      return new Set(blocked)
    }

    const adjacency = this.planner.getAdjacencyList()
    const inflated = new Set<string>(blocked)

    for (let root of blocked) {
      let frontier: Array<string> = [root]
      const visited = new Set<string>([root])

      for (let depth = 0; depth < radius; depth++) {
        const nextFrontier: Array<string> = []

        for (let node of frontier) {
          const neighbors = adjacency.get(node) || []
          for (let neighbor of neighbors) {
            if (visited.has(neighbor)) {
              continue
            }
            visited.add(neighbor)
            nextFrontier.push(neighbor)
            inflated.add(neighbor)
          }
        }

        frontier = nextFrontier
      }
    }

    inflated.delete(start)
    inflated.delete(goal)
    return inflated
  }

  private computePathRisk(path: Array<string>, blockedSet: Set<string>): number {
    if (path.length <= 0 || blockedSet.size <= 0) {
      return 0
    }

    let risk = 0
    for (let node of path) {
      risk += this.computeNodeRisk(node, blockedSet)
    }

    return risk / path.length
  }

  private computeNodeRisk(node: string, blockedSet: Set<string>): number {
    if (blockedSet.size <= 0) {
      return 0
    }

    let minDist = Number.MAX_SAFE_INTEGER
    for (let blocked of blockedSet) {
      const d = this.gridDistance(node, blocked)
      if (d < minDist) {
        minDist = d
      }
    }

    if (minDist <= 1) {
      return 1
    }
    if (minDist === 2) {
      return 0.45
    }
    if (minDist === 3) {
      return 0.15
    }
    return 0
  }

  private computeContinuity(path: Array<string>, oldPath: Array<string>): number {
    if (path.length <= 0 && oldPath.length <= 0) {
      return 1
    }

    if (oldPath.length <= 0) {
      return 0.5
    }

    const oldSet = new Set(oldPath)
    let overlap = 0
    for (let node of path) {
      if (oldSet.has(node)) {
        overlap += 1
      }
    }

    return overlap / Math.max(path.length, oldPath.length)
  }

  private countTurns(path: Array<string>): number {
    if (path.length < 3) {
      return 0
    }

    let turns = 0
    for (let i = 2; i < path.length; i++) {
      const a = this.nodeToCoord(path[i - 2])
      const b = this.nodeToCoord(path[i - 1])
      const c = this.nodeToCoord(path[i])

      if (!a || !b || !c) {
        continue
      }

      const v1x = b.c - a.c
      const v1y = b.r - a.r
      const v2x = c.c - b.c
      const v2y = c.r - b.r

      if (v1x !== v2x || v1y !== v2y) {
        turns += 1
      }
    }

    return turns
  }

  private estimateTravelTimeSeconds(hops: number, turns: number, riskIndex: number): number {
    const base = hops * 1.8
    const turnPenalty = turns * 0.45
    const riskPenalty = riskIndex * hops * 0.60
    return Number((base + turnPenalty + riskPenalty).toFixed(2))
  }

  private pathContainsBlockedEdge(path: Array<string>, blockedEdgeSet: Set<string>): boolean {
    if (path.length < 2 || blockedEdgeSet.size <= 0) {
      return false
    }

    for (let i = 1; i < path.length; i++) {
      if (this.isBlockedEdge(path[i - 1], path[i], blockedEdgeSet)) {
        return true
      }
    }

    return false
  }

  private isBlockedEdge(a: string, b: string, blockedEdgeSet: Set<string>): boolean {
    return blockedEdgeSet.has(this.edgeKey(a, b))
  }

  private edgeKey(a: string, b: string): string {
    return a < b ? `${a}|${b}` : `${b}|${a}`
  }

  private parseEdge(rawEdge: string): Array<string> | undefined {
    const s = (rawEdge || '').toUpperCase()
    const matches = s.match(/[A-Z]\d+/g)
    if (!matches || matches.length < 2) {
      return undefined
    }
    return [matches[0], matches[1]]
  }

  private NodeId(nodeId: string): string {
    return (nodeId || '').trim().toUpperCase()
  }

  private isValidNode(nodeId: string): boolean {
    return this.planner.getAdjacencyList().has(nodeId)
  }

  private gridDistance(from: string, to: string): number {
    const a = this.nodeToCoord(from)
    const b = this.nodeToCoord(to)
    if (!a || !b) {
      return Number.MAX_SAFE_INTEGER / 16
    }
    return Math.abs(a.c - b.c) + Math.abs(a.r - b.r)
  }

  private nodeToCoord(nodeId: string): { c: number, r: number } | undefined {
    if (!nodeId || nodeId.length < 2) {
      return undefined
    }

    const col = nodeId[0]
    const row = Number.parseInt(nodeId.slice(1))

    const c = PathReplanningModule.GRID_COLS.indexOf(col)
    const r = PathReplanningModule.GRID_ROWS.indexOf(row)

    if (c < 0 || r < 0) {
      return undefined
    }

    return { c: c, r: r }
  }

  private buildId(prefix: string): string {
    const suffix = Math.random().toString(36).slice(2, 10)
    return `${prefix}_${Date.now()}_${suffix}`
  }

  /**
   * 获取当前路径
   */
  getCurrentPath(): Array<string> {
    return [...this.currentPath]
  }

  /**
   * 获取当前目标
   */
  getCurrentTarget(): string {
    return this.currentTarget
  }

  /**
   * 设置初始路径
   */
  setInitialPath(path: Array<string>, target: string): void {
    this.currentPath = [...path]
    this.currentTarget = target
    console.log(`[初始化] 路径已设置: ${path.join(' -> ')}, 目标: ${target}`)
  }

  /**
   * 获取重规划历史
   */
  getReplanHistory(): Array<ReplanLog> {
    return [...this.replanHistory]
  }

  /**
   * 获取最新一次诊断信息
   */
  getLastDiagnostics(): ReplanDiagnostics | undefined {
    if (!this.lastDiagnostics) {
      return undefined
    }

    return {
      telemetry: { ...this.lastDiagnostics.telemetry },
      candidates: this.lastDiagnostics.candidates.map((item) => ({ ...item, path: [...item.path] })),
      rejectedReasons: [...this.lastDiagnostics.rejectedReasons]
    }
  }

  /**
   * 获取重规划统计
   */
  getReplanStatistics(): any {
    const totalReplans = this.replanHistory.length
    const successfulReplans = this.replanHistory.filter((log) => log.status === 'SUCCESS').length
    const failedReplans = this.replanHistory.filter((log) => log.status === 'FAILED').length

    const avgExecutionTime = totalReplans > 0
      ? this.replanHistory.reduce((sum, log) => sum + log.executionTime, 0) / totalReplans
      : 0

    const avgCandidateCount = totalReplans > 0
      ? this.replanHistory.reduce((sum, log) => sum + (log.telemetry?.candidateCount ?? 0), 0) / totalReplans
      : 0

    return {
      totalReplans: totalReplans,
      successfulReplans: successfulReplans,
      failedReplans: failedReplans,
      successRate: totalReplans > 0 ? `${((successfulReplans / totalReplans) * 100).toFixed(2)}%` : 'N/A',
      avgExecutionTime: `${avgExecutionTime.toFixed(2)}ms`,
      avgCandidateCount: Number(avgCandidateCount.toFixed(2))
    }
  }

  /**
   * 清空历史
   */
  clearHistory(): void {
    this.replanHistory = []
    this.lastDiagnostics = undefined
    console.log('[日志] 重规划历史已清空')
  }

  /**
   * 导出重规划回放数据
   */
  exportReplayData(): any {
    return {
      timestamp: Date.now(),
      currentPath: [...this.currentPath],
      currentTarget: this.currentTarget,
      replanHistory: [...this.replanHistory],
      lastDiagnostics: this.getLastDiagnostics(),
      statistics: this.getReplanStatistics()
    }
  }
}
