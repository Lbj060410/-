/**
 * 表演文件：A* 路径规划算法实现
 * 用途：演示 A* 最短路径搜索在网格图上的完整实现
 */

export interface Node {
  id: string
  g: number  // 从起点到该节点的代价
  h: number  // 启发值（到终点的估计代价）
  f: number  // f = g + h
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

  // 邻接表（网络拓扑）
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
   * 曼哈顿距离启发函数
   */
  private heuristic(from: string, to: string): number {
    const fromCol = AStarPathPlanner.GRID_COLS.indexOf(from[0])
    const fromRow = AStarPathPlanner.GRID_ROWS.indexOf(Number.parseInt(from.slice(1)))
    const toCol = AStarPathPlanner.GRID_COLS.indexOf(to[0])
    const toRow = AStarPathPlanner.GRID_ROWS.indexOf(Number.parseInt(to.slice(1)))

    return Math.abs(fromCol - toCol) + Math.abs(fromRow - toRow)
  }

  /**
   * A* 主算法
   */
  plan(start: string, goal: string, blockedNodes: Array<string> = []): PathResult {
    const openSet: Array<Node> = []
    const closedSet: Map<string, boolean> = new Map()
    const gScore: Map<string, number> = new Map()
    const parent: Map<string, string> = new Map()
    let expandedCount = 0

    // 初始化起点
    const h0 = this.heuristic(start, goal)
    openSet.push({
      id: start,
      g: 0,
      h: h0,
      f: h0,
      parent: ''
    })
    gScore.set(start, 0)

    // 主循环
    while (openSet.length > 0) {
      // 找 f 值最小的节点
      let minIdx = 0
      for (let i = 1; i < openSet.length; i++) {
        if (openSet[i].f < openSet[minIdx].f) {
          minIdx = i
        }
      }

      const current = openSet[minIdx]
      openSet.splice(minIdx, 1)

      // 跳过已处理节点
      if (closedSet.get(current.id)) {
        continue
      }

      expandedCount++

      // 到达目标
      if (current.id === goal) {
        const path = this.reconstructPath(goal, parent)
        return {
          success: true,
          path: path,
          cost: current.g,
          expandedNodes: expandedCount
        }
      }

      closedSet.set(current.id, true)

      // 扩展邻居
      const neighbors = this.adjacencyList.get(current.id) || []
      for (let neighbor of neighbors) {
        if (closedSet.get(neighbor)) {
          continue
        }

        if (blockedNodes.includes(neighbor)) {
          continue
        }

        const tentativeG = current.g + 1
        const oldG = gScore.get(neighbor)

        if (oldG !== undefined && tentativeG >= oldG) {
          continue
        }

        parent.set(neighbor, current.id)
        gScore.set(neighbor, tentativeG)
        const h = this.heuristic(neighbor, goal)
        const f = tentativeG + h

        openSet.push({
          id: neighbor,
          g: tentativeG,
          h: h,
          f: f,
          parent: current.id
        })
      }
    }

    return {
      success: false,
      path: [],
      cost: 0,
      expandedNodes: expandedCount
    }
  }

  /**
   * 路径回溯
   */
  private reconstructPath(goal: string, parent: Map<string, string>): Array<string> {
    const path: Array<string> = []
    let current = goal

    while (current) {
      path.unshift(current)
      current = parent.get(current) || ''
    }

    return path
  }

  /**
   * 获取邻接表（用于调试）
   */
  getAdjacencyList(): Map<string, Array<string>> {
    return this.adjacencyList
  }
}
