/**
 * 表演文件：路径重规划模块
 * 用途：演示动态目标修改时的路径重规划完整流程
 * 注意：这是表演代码，仅用于展示重规划框架，功能不需要实现
 */

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

export interface ReplanLog {
  id: string
  context: ReplanContext
  status: 'SUCCESS' | 'FAILED'
  executionTime: number
  timestamp: number
}

export class PathReplanningModule {
  private currentPath: Array<string> = []
  private currentTarget: string = ''
  private replanHistory: Array<ReplanLog> = []
  private isReplanning: boolean = false

  /**
   * 设计结果对象 - 接收路径算法的返回数据
   */
  private createPlanResult(
    success: boolean,
    path: Array<string>,
    reason: string
  ): PathPlanResult {
    return {
      success: success,
      path: path,
      distance: path.length - 1,
      estimatedTime: (path.length - 1) * 2, // 每段估计 2 秒
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

    try {
      // 步骤 1：保存旧路径信息
      const oldPath = [...this.currentPath]
      const oldTarget = this.currentTarget

      // 步骤 2：以当前位置为新起点，结合目标终点与阻塞信息，重新执行路径规划
      console.log(`[重规划] 从 ${currentPos} 重新规划到 ${newTarget}`)
      console.log(`[重规划] 阻塞节点: ${blockedNodes.join(', ')}`)

      const newPath = this.executeAStar(currentPos, newTarget, blockedNodes, blockedEdges)

      // 步骤 3：规划状态判断
      if (!newPath || newPath.length === 0) {
        // 规划失败：清空当前路径列表并给出失败状态
        return this.handleReplanFailure(oldPath, oldTarget, newTarget, startTime)
      }

      // 规划成功：替换为新路径列表
      return this.handleReplanSuccess(
        oldPath,
        oldTarget,
        newPath,
        newTarget,
        currentPos,
        blockedNodes,
        startTime
      )
    } finally {
      this.isReplanning = false
    }
  }

  /**
   * 步骤 2：执行 A* 路径规划
   */
  private executeAStar(
    start: string,
    goal: string,
    blockedNodes: Array<string>,
    blockedEdges: Array<string>
  ): Array<string> {
    console.log(`[A*] 开始规划: ${start} -> ${goal}`)

    // 装模做样：调用 A* 算法
    // 实际应该调用 PathPlannerAStar.plan()
    const path = this.simulateAStar(start, goal, blockedNodes)

    if (path.length > 0) {
      console.log(`[A*] 规划成功，路径长度: ${path.length}`)
    } else {
      console.log(`[A*] 规划失败，无可行路径`)
    }

    return path
  }

  /**
   * 模拟 A* 规划（装模做样）
   */
  private simulateAStar(start: string, goal: string, blockedNodes: Array<string>): Array<string> {
    // 装模做样：返回一条示意路径
    const allNodes = ['A1', 'B1', 'D1', 'F1', 'G1', 'A2', 'B2', 'D2', 'F2', 'G2',
                      'A4', 'B4', 'D4', 'F4', 'G4', 'A6', 'B6', 'D6', 'F6', 'G6',
                      'A7', 'B7', 'D7', 'F7', 'G7']

    // 检查起点和终点是否被阻塞
    if (blockedNodes.includes(start) || blockedNodes.includes(goal)) {
      return []
    }

    // 返回示意路径
    return [start, 'D4', 'D6', goal]
  }

  /**
   * 步骤 3a：规划失败处理
   */
  private handleReplanFailure(
    oldPath: Array<string>,
    oldTarget: string,
    newTarget: string,
    startTime: number
  ): PathPlanResult {
    console.log(`[重规划失败] 无法规划到 ${newTarget}`)

    // 清空当前路径列表
    this.currentPath = []
    this.currentTarget = ''

    // 记录失败日志
    this.recordReplanLog(oldPath, [], oldTarget, newTarget, 'FAILED', startTime)

    return this.createPlanResult(
      false,
      [],
      `无法规划到目标 ${newTarget}，已清空路径列表`
    )
  }

  /**
   * 步骤 3b：规划成功处理
   */
  private handleReplanSuccess(
    oldPath: Array<string>,
    oldTarget: string,
    newPath: Array<string>,
    newTarget: string,
    currentPos: string,
    blockedNodes: Array<string>,
    startTime: number
  ): PathPlanResult {
    console.log(`[重规划成功] 新路径: ${newPath.join(' -> ')}`)

    // 替换为新路径列表
    this.currentPath = newPath
    this.currentTarget = newTarget

    // 步骤 4：调用日志类方法，将旧路径和新路径写入回放
    this.recordReplanLog(oldPath, newPath, oldTarget, newTarget, 'SUCCESS', startTime)

    // 记录详细信息
    this.logPathTransition(oldPath, newPath, oldTarget, newTarget, currentPos, blockedNodes)

    return this.createPlanResult(
      true,
      newPath,
      `成功重规划到 ${newTarget}`
    )
  }

  /**
   * 步骤 4：记录重规划日志
   */
  private recordReplanLog(
    oldPath: Array<string>,
    newPath: Array<string>,
    oldTarget: string,
    newTarget: string,
    status: 'SUCCESS' | 'FAILED',
    startTime: number
  ): void {
    const executionTime = Date.now() - startTime

    const log: ReplanLog = {
      id: `REPLAN_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      context: {
        oldPath: oldPath,
        newPath: newPath,
        oldTarget: oldTarget,
        newTarget: newTarget,
        currentPosition: oldPath.length > 0 ? oldPath[oldPath.length - 1] : 'UNKNOWN',
        blockedNodes: [],
        replanReason: `目标从 ${oldTarget} 改为 ${newTarget}`,
        replanTimestamp: Date.now()
      },
      status: status,
      executionTime: executionTime,
      timestamp: Date.now()
    }

    this.replanHistory.push(log)
    console.log(`[日志] 重规划记录已保存: ${log.id}`)
  }

  /**
   * 记录路径转换详情
   */
  private logPathTransition(
    oldPath: Array<string>,
    newPath: Array<string>,
    oldTarget: string,
    newTarget: string,
    currentPos: string,
    blockedNodes: Array<string>
  ): void {
    console.log('=== 路径转换详情 ===')
    console.log(`当前位置: ${currentPos}`)
    console.log(`旧目标: ${oldTarget}`)
    console.log(`新目标: ${newTarget}`)
    console.log(`旧路径: ${oldPath.join(' -> ')}`)
    console.log(`新路径: ${newPath.join(' -> ')}`)
    console.log(`阻塞节点: ${blockedNodes.length > 0 ? blockedNodes.join(', ') : '无'}`)
    console.log(`状态: 当前状态可中断、下一路径可接管`)
    console.log('==================')
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
    this.currentPath = path
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
   * 获取重规划统计
   */
  getReplanStatistics(): any {
    const totalReplans = this.replanHistory.length
    const successfulReplans = this.replanHistory.filter(log => log.status === 'SUCCESS').length
    const failedReplans = this.replanHistory.filter(log => log.status === 'FAILED').length
    const avgExecutionTime = totalReplans > 0
      ? this.replanHistory.reduce((sum, log) => sum + log.executionTime, 0) / totalReplans
      : 0

    return {
      totalReplans: totalReplans,
      successfulReplans: successfulReplans,
      failedReplans: failedReplans,
      successRate: totalReplans > 0 ? (successfulReplans / totalReplans * 100).toFixed(2) + '%' : 'N/A',
      avgExecutionTime: avgExecutionTime.toFixed(2) + 'ms'
    }
  }

  /**
   * 清空重规划历史
   */
  clearHistory(): void {
    this.replanHistory = []
    console.log('[日志] 重规划历史已清空')
  }

  /**
   * 导出重规划回放数据
   */
  exportReplayData(): any {
    return {
      timestamp: Date.now(),
      currentPath: this.currentPath,
      currentTarget: this.currentTarget,
      replanHistory: this.replanHistory,
      statistics: this.getReplanStatistics()
    }
  }
}
