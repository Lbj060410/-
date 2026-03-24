/**
 * 代码指南：
 * 文件：pages/page1/app/PathPlannerAStar.ets
 * 用途：黑线图上的网格拓扑 + A* 最短路径规划器。
 * 何时修改：更改节点/边图、路径代价策略或最短路径约束时。
 * 相关文件：app/Page1Coordinator.ets（planPath 调用方）和 types/SandboxGridTypes.ets。
 */
export interface GridCoord {
  col: number // 0..4 => A/B/D/F/G
  row: number // 0..4 => 1/2/4/6/7
}

export interface AStarPlanResult {
  ok: boolean
  reason: string
  path: Array<string>
}

export interface RouteSegment {
  a: string
  b: string
}

/**
 * 路段编码工具：
 * - 统一把无向边编码为 A|B（按字典序）；
 * - 这样 blockedEdges 里只需要存一种形式，比较时不会因为方向不同而错过匹配。
 */
export class RouteEdgeCodec {
  static normalize(aId: string, bId: string): string {
    const a: string = aId.trim().toUpperCase()
    const b: string = bId.trim().toUpperCase()
    if (a <= b) return `${a}|${b}`
    return `${b}|${a}`
  }

  static fromSegment(seg: RouteSegment): string {
    return RouteEdgeCodec.normalize(seg.a, seg.b)
  }

  static parse(edgeId: string): RouteSegment | undefined {
    const x: string = edgeId.trim().toUpperCase()
    const parts: Array<string> = x.split('|')
    if (parts.length !== 2) return undefined
    const a: string = parts[0]
    const b: string = parts[1]
    if (!GridIdCodec.isValidId(a)) return undefined
    if (!GridIdCodec.isValidId(b)) return undefined
    return { a: a, b: b }
  }
}

/**
 * 节点 ID 编解码工具（如 D4）：
 * - isValidId: 只允许黑线网络里的合法节点；
 * - parse/encode: 在字符串节点与网格坐标之间转换。
 */
export class GridIdCodec {
  // 列标签与行标签定义了“节点命名空间”，改这里会影响所有节点解析/编码。
  private static readonly COLS: Array<string> = ['A', 'B', 'D', 'F', 'G']
  private static readonly ROW_LABELS: Array<number> = [1, 2, 4, 6, 7]
  // ROUTE_NODE_IDS 是允许参与黑线规划的全部节点白名单。
  // 增删节点时必须同步 ROUTE_EDGES，否则节点会“合法但不可达”。
  private static readonly ROUTE_NODE_IDS: Array<string> = [
          'B1', 'D1', 'F1',
    'A2', 'B2', 'D2', 'F2', 'G2',
    'A4', 'B4', 'D4', 'F4', 'G4',
    'A6', 'B6', 'D6', 'F6', 'G6',
          'B7', 'D7', 'F7'
  ]
  private static readonly ROUTE_NODE_SET: Map<string, boolean> = GridIdCodec.buildRouteNodeSet()

  private static buildRouteNodeSet(): Map<string, boolean> {
    const out: Map<string, boolean> = new Map<string, boolean>()
    for (let i: number = 0; i < GridIdCodec.ROUTE_NODE_IDS.length; i++) {
      out.set(GridIdCodec.ROUTE_NODE_IDS[i], true)
    }
    return out
  }

  static isValidId(id: string): boolean {
    const x: string = id.trim().toUpperCase()
    return GridIdCodec.ROUTE_NODE_SET.get(x) === true
  }

  static parse(id: string): GridCoord | undefined {
    const x: string = id.trim().toUpperCase()
    if (x.length < 2) return undefined
    const c0: string = x[0]
    const col: number = GridIdCodec.COLS.indexOf(c0)
    if (col < 0) return undefined

    const numStr: string = x.slice(1)
    const rowNum: number = Number.parseInt(numStr, 10)
    if (!Number.isFinite(rowNum)) return undefined

    const row: number = GridIdCodec.ROW_LABELS.indexOf(rowNum)
    if (row < 0) return undefined

    return { col: col, row: row }
  }

  static encode(coord: GridCoord): string {
    const colChar: string = GridIdCodec.COLS[coord.col]
    const rowNum: number | undefined = GridIdCodec.ROW_LABELS[coord.row]
    if (!colChar || rowNum === undefined) return ''
    return `${colChar}${String(rowNum)}`
  }
}

class AStarNode {
  id: string
  g: number
  f: number
  parentId: string

  constructor(id: string, g: number, f: number, parentId: string) {
    this.id = id
    this.g = g
    this.f = f
    this.parentId = parentId
  }
}

export class PathPlannerAStar {
  // 黑线网络拓扑（唯一真实路网）：
  // 修改”允许怎么走”必须改这里，A* 只会在这张图上搜索。
  private static readonly ROUTE_EDGES: Array<RouteSegment> = [
    // 三条主要垂直干线
    { a: 'B1', b: 'B2' }, { a: 'B2', b: 'B4' }, { a: 'B4', b: 'B6' }, { a: 'B6', b: 'B7' },
    { a: 'D1', b: 'D2' }, { a: 'D2', b: 'D4' }, { a: 'D4', b: 'D6' }, { a: 'D6', b: 'D7' },
    { a: 'F1', b: 'F2' }, { a: 'F2', b: 'F4' }, { a: 'F4', b: 'F6' }, { a: 'F6', b: 'F7' },

    // 第 2/4/6 行的水平连接
    // A/G 是每行的侧端点，不跨行垂直连接
    { a: 'A2', b: 'B2' }, { a: 'B2', b: 'D2' }, { a: 'D2', b: 'F2' }, { a: 'F2', b: 'G2' },
    { a: 'A4', b: 'B4' }, { a: 'B4', b: 'D4' }, { a: 'D4', b: 'F4' }, { a: 'F4', b: 'G4' },
    { a: 'A6', b: 'B6' }, { a: 'B6', b: 'D6' }, { a: 'D6', b: 'F6' }, { a: 'F6', b: 'G6' }
  ]
  private static readonly ROUTE_ADJ: Map<string, Array<string>> = PathPlannerAStar.buildRouteAdj()

  // 由边表生成邻接表，供 A* 高频查询 neighbors 使用
  private static buildRouteAdj(): Map<string, Array<string>> {
    const out: Map<string, Array<string>> = new Map<string, Array<string>>()

    for (let i: number = 0; i < PathPlannerAStar.ROUTE_EDGES.length; i++) {
      const e: RouteSegment = PathPlannerAStar.ROUTE_EDGES[i]
      const a: string = e.a
      const b: string = e.b

      let an: Array<string> | undefined = out.get(a)
      if (!an) {
        an = []
        out.set(a, an)
      }
      an.push(b)

      let bn: Array<string> | undefined = out.get(b)
      if (!bn) {
        bn = []
        out.set(b, bn)
      }
      bn.push(a)
    }
    return out
  }

  // 对外导出边列表的副本，避免调用方修改内部常量
  static routeEdges(): Array<RouteSegment> {
    const out: Array<RouteSegment> = []
    for (let i: number = 0; i < PathPlannerAStar.ROUTE_EDGES.length; i++) {
      const e: RouteSegment = PathPlannerAStar.ROUTE_EDGES[i]
      out.push({ a: e.a, b: e.b })
    }
    return out
  }

  /**
   * A* 最短路径规划入口。
   * 输入：
   * - startId/goalId：起终点；
   * - blocked：禁用节点；
   * - blockedEdges：禁用边（统一为 A|B）。
   * 输出：
   * - ok=true: path 为可执行节点序列；
   * - ok=false: reason 说明失败原因。
   */
  static plan(startId: string, goalId: string, blocked: Array<string>, blockedEdges: Array<string> = []): AStarPlanResult {
    if (!GridIdCodec.isValidId(startId)) {
      return { ok: false, reason: `bad start=${startId}`, path: [] }
    }
    if (!GridIdCodec.isValidId(goalId)) {
      return { ok: false, reason: `bad goal=${goalId}`, path: [] }
    }
    if (startId === goalId) {
      return { ok: true, reason: 'same', path: [startId] }
    }

    // blockedSet/blockedEdgeSet：
    // - blockedSet 直接封节点
    // - blockedEdgeSet 只封节点之间的特定连线
    // 若你要让“某段黑线不可走”，优先改 blockedEdges，而不是删节点。
    const blockedSet: Map<string, boolean> = new Map<string, boolean>()
    for (let i: number = 0; i < blocked.length; i++) {
      blockedSet.set(blocked[i], true)
    }
    const blockedEdgeSet: Map<string, boolean> = new Map<string, boolean>()
    for (let i: number = 0; i < blockedEdges.length; i++) {
      const e: string = blockedEdges[i].trim().toUpperCase()
      if (e.length <= 0) continue
      blockedEdgeSet.set(e, true)
    }

    if (blockedSet.get(startId) === true) {
      return { ok: false, reason: `start blocked=${startId}`, path: [] }
    }
    if (blockedSet.get(goalId) === true) {
      return { ok: false, reason: `goal blocked=${goalId}`, path: [] }
    }

    // 标准 A* 四件套：
    // - open: 待扩展节点（用数组 + popMinF 选 f 最小）
    // - bestG: 每个点当前最优代价
    // - parent: 回溯路径
    // - closed: 已完成扩展
    const open: Array<AStarNode> = []
    const bestG: Map<string, number> = new Map<string, number>()
    const parent: Map<string, string> = new Map<string, string>()
    const closed: Map<string, boolean> = new Map<string, boolean>()

    const h0: number = PathPlannerAStar.heuristic(startId, goalId)
    open.push(new AStarNode(startId, 0, h0, ''))
    bestG.set(startId, 0)

    while (open.length > 0) {
      const current: AStarNode = PathPlannerAStar.popMinF(open)
      if (closed.get(current.id) === true) continue

      // 终点出队时即得到最优路径（启发函数一致时）
      if (current.id === goalId) {
        const path: Array<string> = PathPlannerAStar.reconstruct(goalId, parent)
        return { ok: true, reason: 'ok', path: path }
      }

      closed.set(current.id, true)

      const nbrs: Array<string> = PathPlannerAStar.neighbors(current.id)
      for (let i: number = 0; i < nbrs.length; i++) {
        const nb: string = nbrs[i]
        // 节点阻塞直接跳过
        if (blockedSet.get(nb) === true) continue

        // 边阻塞也跳过（例如 G4-G2 问题就依赖这里的边定义与屏蔽）
        const edgeId: string = RouteEdgeCodec.normalize(current.id, nb)
        if (blockedEdgeSet.get(edgeId) === true) continue
        if (closed.get(nb) === true) continue

        // 单步代价统一按 1 处理，当前路网属于“边权一致最短跳数”
        const tentativeG: number = current.g + 1
        const oldG: number | undefined = bestG.get(nb)
        if (oldG !== undefined && tentativeG >= oldG) continue

        parent.set(nb, current.id)
        bestG.set(nb, tentativeG)
        const h: number = PathPlannerAStar.heuristic(nb, goalId)
        const f: number = tentativeG + h
        open.push(new AStarNode(nb, tentativeG, f, current.id))
      }
    }

    return { ok: false, reason: 'no path', path: [] }
  }

  private static heuristic(aId: string, bId: string): number {
    const a: GridCoord | undefined = GridIdCodec.parse(aId)
    const b: GridCoord | undefined = GridIdCodec.parse(bId)
    if (!a || !b) return 999
    // 当前启发函数是曼哈顿距离（按网格列/行差）：
    // - 适用于本项目“每条可走边代价相同”场景
    // - 若未来引入不同边权重，这里和 tentativeG 都要一起调整
    const dx: number = Math.abs(a.col - b.col)
    const dy: number = Math.abs(a.row - b.row)
    return dx + dy
  }

  private static neighbors(id: string): Array<string> {
    const x: string = id.trim().toUpperCase()
    const n: Array<string> | undefined = PathPlannerAStar.ROUTE_ADJ.get(x)
    if (!n) return []
    const out: Array<string> = []
    for (let i: number = 0; i < n.length; i++) out.push(n[i])
    return out
  }

  // 线性扫描取 open 中 f 最小节点；节点规模很小，足够稳定且实现简单
  private static popMinF(open: Array<AStarNode>): AStarNode {
    let bestIdx: number = 0
    let bestF: number = open[0].f

    for (let i: number = 1; i < open.length; i++) {
      const f: number = open[i].f
      if (f < bestF) {
        bestF = f
        bestIdx = i
      }
    }

    const node: AStarNode = open[bestIdx]
    open.splice(bestIdx, 1)
    return node
  }

  // 从 goal 沿 parent 逆向回溯，再反转为 start->goal
  private static reconstruct(goalId: string, parent: Map<string, string>): Array<string> {
    const out: Array<string> = []
    let cur: string = goalId
    out.push(cur)

    // 路由图很小，防止错误的父节点循环
    for (let guard: number = 0; guard < 32; guard++) {
      const p: string | undefined = parent.get(cur)
      if (!p || p.length === 0) break
      out.push(p)
      cur = p
    }

    out.reverse()
    return out
  }
}

