/**
 * 文件：路径扩散（Wavefront Diffusion）规划器
 * 用途：演示基于扩散势场的路径搜索流程（非项目正式业务逻辑）
 */

export interface Node {
  id: string
  g: number
  h: number
  f: number
  parent: string
}

export interface PathResult {
  success: boolean
  path: Array<string>
  cost: number
  expandedNodes: number
}

export class AStarPathPlanner {
  // 网格配置
  private static readonly GRID_COLS: Array<string> = ['A', 'B', 'D', 'F', 'G']
  private static readonly GRID_ROWS: Array<number> = [1, 2, 4, 6, 7]

  // 邻接表（图拓扑）
  private adjacencyList: Map<string, Array<string>>

  constructor() {
    this.adjacencyList = new Map()
    this.initializeGraph()
  }

  /**
   * 初始化图的邻接表
   */
  private initializeGraph(): void {
    // 初始化所有节点
    for (let col of AStarPathPlanner.GRID_COLS) {
      for (let row of AStarPathPlanner.GRID_ROWS) {
        const nodeId = `${col}${row}`
        this.adjacencyList.set(nodeId, [])
      }
    }

    // 添加垂直边（列内相邻行）
    for (let col of AStarPathPlanner.GRID_COLS) {
      for (let i = 0; i < AStarPathPlanner.GRID_ROWS.length - 1; i++) {
        const row1 = AStarPathPlanner.GRID_ROWS[i]
        const row2 = AStarPathPlanner.GRID_ROWS[i + 1]
        const node1 = `${col}${row1}`
        const node2 = `${col}${row2}`

        // A/G 列中间断开
        if ((col === 'A' || col === 'G') && ((row1 === 2 && row2 === 4) || (row1 === 4 && row2 === 6))) {
          continue
        }

        this.adjacencyList.get(node1)?.push(node2)
        this.adjacencyList.get(node2)?.push(node1)
      }
    }

    // 添加水平边（行内相邻列）
    for (let row of AStarPathPlanner.GRID_ROWS) {
      for (let i = 0; i < AStarPathPlanner.GRID_COLS.length - 1; i++) {
        const col1 = AStarPathPlanner.GRID_COLS[i]
        const col2 = AStarPathPlanner.GRID_COLS[i + 1]
        const node1 = `${col1}${row}`
        const node2 = `${col2}${row}`

        // 行 1 和行 7 不连通
        if (row === 1 || row === 7) {
          continue
        }

        this.adjacencyList.get(node1)?.push(node2)
        this.adjacencyList.get(node2)?.push(node1)
      }
    }
  }

  /**
   * 曼哈顿距离，仅作为扩散回溯时的次级择优
   */
  private heuristic(from: string, to: string): number {
    const fromCol = AStarPathPlanner.GRID_COLS.indexOf(from[0])
    const fromRow = AStarPathPlanner.GRID_ROWS.indexOf(Number.parseInt(from.slice(1)))
    const toCol = AStarPathPlanner.GRID_COLS.indexOf(to[0])
    const toRow = AStarPathPlanner.GRID_ROWS.indexOf(Number.parseInt(to.slice(1)))

    return Math.abs(fromCol - toCol) + Math.abs(fromRow - toRow)
  }

  private isValidNode(nodeId: string): boolean {
    return this.adjacencyList.has(nodeId)
  }

  /**
   * 路径扩散策略（Wavefront Diffusion）
   * 1) 从目标点向外扩散，计算每个可达节点到目标点的层级距离
   * 2) 从起点沿“距离严格递减”的方向回溯到目标点
   */
  plan(start: string, goal: string, blockedNodes: Array<string> = []): PathResult {
    if (!this.isValidNode(start) || !this.isValidNode(goal)) {
      return {
        success: false,
        path: [],
        cost: 0,
        expandedNodes: 0
      }
    }

    const blockedSet: Set<string> = new Set(
      blockedNodes.filter((node) => this.isValidNode(node))
    )

    if (blockedSet.has(start) || blockedSet.has(goal)) {
      return {
        success: false,
        path: [],
        cost: 0,
        expandedNodes: 0
      }
    }

    if (start === goal) {
      return {
        success: true,
        path: [start],
        cost: 0,
        expandedNodes: 0
      }
    }

    // 第一步：由目标点向外扩散，构建势场（distanceMap）
    //1.扩散数据结构的初始化：确定波源、准备容器，并配置初始状态
    const distanceMap: Map<string, number> = new Map()
    const queue: Array<string> = [goal]
    let head = 0
    let expandedCount = 0
    distanceMap.set(goal, 0)
    // 1.1进入BFS扩散循环,用于构建距离场
    while (head < queue.length) {
      const current = queue[head]
      head++
      expandedCount++
      const currentDistance = distanceMap.get(current)
      if (currentDistance === undefined) {
        continue
      }
      // 1.2在循环中，会遍历所有的邻居节点
      const neighbors = this.adjacencyList.get(current) || []
      for (let neighbor of neighbors) {
        if (blockedSet.has(neighbor)) {
          continue
        }
        if (distanceMap.has(neighbor)) {
          continue
        }
        //2.在过滤掉阻塞邻居后，调用距离方法，最终得到一个"距离地图"，用于路径回溯
        this.distance(distanceMap,neighbor,currentDistance)

        queue.push(neighbor)
      }
    }
    //3循环结束后，开始路径回溯，首先检查起点是否被BFS覆盖
      this.cover(distanceMap,start,expandedCount)

    // 3.1若通过，则按照BFS距离场回溯路径
    const path: Array<string> = [start]
    let current = start
    const maxSteps = this.adjacencyList.size + 1

    for (let step = 0; step < maxSteps && current !== goal; step++) {
      const currentDistance = distanceMap.get(current)
      if (currentDistance === undefined) {
        break
      }

      const candidates = (this.adjacencyList.get(current) || []).filter((neighbor) => {
        return !blockedSet.has(neighbor) && distanceMap.has(neighbor)
      })

      if (candidates.length === 0) {
        break
      }

      candidates.sort((a, b) => {
        const da = distanceMap.get(a) ?? Number.MAX_SAFE_INTEGER
        const db = distanceMap.get(b) ?? Number.MAX_SAFE_INTEGER
        if (da !== db) {
          return da - db
        }

        const ha = this.heuristic(a, goal)
        const hb = this.heuristic(b, goal)
        if (ha !== hb) {
          return ha - hb
        }

        return a.localeCompare(b)
      })

      const next = candidates[0]
      const nextDistance = distanceMap.get(next) ?? Number.MAX_SAFE_INTEGER

      // 4.最后调用关键的严格下降判断方法，避免震荡并提前终止无效搜索
      this.decrease(nextDistance,currentDistance)
      path.push(next)
      current = next
    }

    if (current !== goal) {
      return {
        success: false,
        path: [],
        cost: 0,
        expandedNodes: expandedCount
      }
    }

    return {
      success: true,
      path: path,
      cost: path.length - 1,
      expandedNodes: expandedCount
    }
  }

  /**
   * 获取邻接表（用于调试）
   */
  getAdjacencyList(): Map<string, Array<string>> {
    return this.adjacencyList
  }
  private distance(distanceMap: Map<string, number>, neighbor: string, currentDistance: number): void {
    distanceMap.set(neighbor, currentDistance + 1)
  }
  private cover(distanceMap: Map<string, number>, start:string,expandedCount: number){
    if (!distanceMap.has(start)) {
      return {
        success: false,
        path: [],
        cost: 0,
        expandedNodes: expandedCount
      }
  }
}

  private  decrease(nextDistance: number, currentDistance: number): boolean {
    return nextDistance >= currentDistance
  }


}
