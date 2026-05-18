import { RecognitionResult } from '../../../services/recognition/RecognitionResult'

export interface OutboundOrder {
  orderId: string
  skuCode: string
  productName: string
  quantity: number
  zone: string
  status: string
  createTime: string
}

export class Page4RuntimeDiagnosticsModule {
  static errorToText(e: Object): string {
    if (e instanceof Error) {
      const msg: string = e.message.trim()
      return msg.length > 0 ? msg : 'unknown error'
    }
    const anyObj: Record<string, Object | string | number | boolean> = e as Record<string, Object | string | number | boolean>
    const code: string = String(anyObj['code'] ?? '')
    const msg: string = String(anyObj['message'] ?? '')
    const details: string = String(anyObj['details'] ?? '')
    const out: string = `${code} ${msg} ${details}`.trim()
    if (out.length > 0 && out !== 'undefined undefined undefined') return out
    try {
      const asJson: string = JSON.stringify(e)
      if (asJson.length > 0 && asJson !== '{}') return asJson
    } catch (_) {}
    return 'unknown error'
  }

  static buildStatusSummaryText(
    connStateText: string,
    realSendEnabled: boolean,
    autoFollowEnabled: boolean,
    riskText: string,
    riskScore: number,
    txFrames: number,
    rxFrames: number,
    recogText: string
  ): string {
    const mode: string = realSendEnabled ? 'REAL_SEND' : 'DRY_RUN'
    const recText: string = recogText.length > 0 ? recogText : '-'
    return `链路=${connStateText} | 模式=${mode} | 自动跟随=${autoFollowEnabled ? 'ON' : 'OFF'} | 风险=${riskText}(${riskScore}) | TX/RX=${txFrames}/${rxFrames} | Recog=${recText}`
  }

  static buildOrderQueryText(
    outboundOrders: Array<OutboundOrder>,
    queryText: string,
    mode: 'all' | 'earliest' | 'latest' = 'all',
    statusFilter: string = ''
  ): string {
    const q: string = queryText.trim().toUpperCase()
    const statusNeed: string = statusFilter.trim()
    const matched: Array<OutboundOrder> = []
    for (let i: number = 0; i < outboundOrders.length; i++) {
      const one: OutboundOrder = outboundOrders[i]
      if (statusNeed.length > 0 && one.status !== statusNeed) continue
      if (q.length <= 0) { matched.push(one); continue }
      const idUp: string = one.orderId.toUpperCase()
      const skuUp: string = one.skuCode.toUpperCase()
      const productUp: string = one.productName.toUpperCase()
      if (idUp.indexOf(q) >= 0 || skuUp.indexOf(q) >= 0 || productUp.indexOf(q) >= 0) matched.push(one)
    }
    if (matched.length <= 0) {
      if (statusNeed.length > 0) return `订单查询：未找到匹配记录（状态=${statusNeed}，关键词=${queryText}）`
      return `订单查询：未找到匹配记录（关键词=${queryText}）`
    }
    const parseRecordTimeMs = (x: OutboundOrder): number => {
      const recordIso: string = x.createTime.replace(' ', 'T')
      const recordMs: number = Date.parse(recordIso)
      return Number.isFinite(recordMs) ? recordMs : 0
    }
    const sorted: Array<OutboundOrder> = []
    for (let i: number = 0; i < matched.length; i++) sorted.push(matched[i])
    sorted.sort((a: OutboundOrder, b: OutboundOrder): number => parseRecordTimeMs(a) - parseRecordTimeMs(b))
    let out: Array<OutboundOrder> = []
    if (mode === 'earliest') out = [sorted[0]]
    else if (mode === 'latest') out = [sorted[sorted.length - 1]]
    else out = sorted

    let pendingPick: number = 0
    let picking: number = 0
    let pendingCheck: number = 0
    let shipped: number = 0
    for (let i: number = 0; i < matched.length; i++) {
      const s: string = matched[i].status
      if (s === '待拣货') pendingPick += 1
      if (s === '拣货中') picking += 1
      if (s === '待复核') pendingCheck += 1
      if (s === '已出库' || s === '已发货') shipped += 1
    }

    let title: string = '订单查询结果'
    if (mode === 'earliest') title = '订单查询结果（最早）'
    if (mode === 'latest') title = '订单查询结果（最新）'
    if (statusNeed.length > 0) title = `${title}（状态=${statusNeed}）`
    let body: string = `${title}(${out.length}条，匹配总数=${matched.length})：待拣货=${pendingPick}，拣货中=${picking}，待复核=${pendingCheck}，已出库/已发货=${shipped}\n`
    for (let i: number = 0; i < out.length; i++) {
      const one: OutboundOrder = out[i]
      const idx: number = i + 1
      body += `${idx}. ${one.orderId} | SKU=${one.skuCode} | ${one.productName} | 数量=${one.quantity} | 区域=${one.zone} | 状态=${one.status} | 创建=${one.createTime}`
      if (i < out.length - 1) body += '\n'
    }
    return body
  }

  static looksLikeOrderQueryIntent(text: string, lower: string, containsAny: (text: string, keys: Array<string>) => boolean): boolean {
    const hasDomain: boolean = containsAny(lower, ['订单', '出库单', '订单记录', '拣货', '复核', '发货', '出库'])
    if (!hasDomain) return false
    const hasVerb: boolean = containsAny(lower, ['查', '查询', '查找', '查看', '看看', '给我', '列出', '统计', '记录'])
    if (hasVerb) return true
    if (containsAny(lower, ['已发货'])) return true
    if (containsAny(lower, ['最早', '最晚', '最新', '全部', '所有'])) return true
    if (text.match(/OUT-\d{8}-\d{3}/i)) return true
    if (text.match(/[A-Z]{2}-\d{4}/i)) return true
    return false
  }

  static buildVisionSummaryText(lastRecog: RecognitionResult | undefined): string {
    if (!lastRecog) return '暂无识别结果。'
    if (!lastRecog.ok) return `识别失败: ${lastRecog.errorText}`
    let labels: string = ''
    const maxN: number = lastRecog.boxes.length > 3 ? 3 : lastRecog.boxes.length
    for (let i: number = 0; i < maxN; i++) {
      const one = lastRecog.boxes[i]
      const part: string = `${one.label}(${one.score.toFixed(2)})`
      labels = labels.length <= 0 ? part : `${labels}, ${part}`
    }
    if (labels.length <= 0) labels = '无检测框'
    return `识别引擎=${lastRecog.engine} | boxes=${lastRecog.boxes.length} | ${labels}`
  }
}
