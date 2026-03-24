/**
 * 代码指南：
 * 文件： pages/page1/types/SandboxGridTypes.ets
 * 用途： Page1 模块所使用的共享类型定义。
 * 何时修改： 为 Page1 添加或修改 TypeScript 接口、枚举时.
 * 相关文件： pages/page1/ 目录下的 app/、components/、net/*.
 */
export interface GridNode {
  id: string
  xNorm: number // 0~1
  yNorm: number // 0~1
}

export class SandboxGridModel {
  static buildDefaultNodes(): Array<GridNode> {
    const nodes: Array<GridNode> = []

    // 路线拓扑与黑线对齐：
    // rows 1/7 only have B/D/F, rows 2/4/6 have A/B/D/F/G.
    const cols: Array<string> = ['A', 'B', 'D', 'F', 'G']
    // 边缘列保持小的向内偏移以便于交互。
    const xNorms: Array<number> = [0.020, 0.195, 0.504, 0.810, 0.980]
    const yNorms: Array<number> = [0.096, 0.251, 0.499, 0.745, 0.902]
    const rowLabels: Array<number> = [1, 2, 4, 6, 7]

    // 保持边缘列与中心列共线，以便 A/G 起点沿黑线。
    const aeBackShiftNorm: number = 0.0
    const rowCols: Array<Array<string>> = [
      ['B', 'D', 'F'],
      ['A', 'B', 'D', 'F', 'G'],
      ['A', 'B', 'D', 'F', 'G'],
      ['A', 'B', 'D', 'F', 'G'],
      ['B', 'D', 'F']
    ]

    for (let r: number = 0; r < rowCols.length; r++) {
      const colsInRow: Array<string> = rowCols[r]
      for (let c: number = 0; c < colsInRow.length; c++) {
        const col: string = colsInRow[c]
        const colIdx: number = cols.indexOf(col)
        if (colIdx < 0) continue

        let xNorm: number = xNorms[colIdx]
        let yNorm: number = yNorms[r]
        if (col === 'A' || col === 'G') {
          yNorm += aeBackShiftNorm
          if (yNorm > 1.0) yNorm = 1.0
          if (yNorm < 0.0) yNorm = 0.0
        }

        const n: GridNode = {
          id: `${col}${rowLabels[r]}`,
          xNorm: xNorm,
          yNorm: yNorm
        }
        nodes.push(n)
      }
    }

    return nodes
  }
}

