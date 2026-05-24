import { RecognitionResult } from '../../../services/recognition/RecognitionResult'
import { Page4Keywords } from '../config/Page4Keywords'
import { Page4ReplyText } from '../config/Page4ReplyText'

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
    return Page4ReplyText.queryStatusSummary(
      connStateText,
      realSendEnabled,
      autoFollowEnabled,
      riskText,
      riskScore,
      txFrames,
      rxFrames,
      recogText
    )
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
    if (matched.length <= 0) return Page4ReplyText.orderQueryNoMatch(queryText, statusNeed)
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

    const title: string = Page4ReplyText.orderQueryTitle(mode, statusNeed)
    let body: string = Page4ReplyText.orderQueryHeader(
      title,
      out.length,
      matched.length,
      pendingPick,
      picking,
      pendingCheck,
      shipped
    )
    for (let i: number = 0; i < out.length; i++) {
      const one: OutboundOrder = out[i]
      const idx: number = i + 1
      body += Page4ReplyText.orderQueryLine(
        idx,
        one.orderId,
        one.skuCode,
        one.productName,
        one.quantity,
        one.zone,
        one.status,
        one.createTime
      )
      if (i < out.length - 1) body += '\n'
    }
    return body
  }

  static looksLikeOrderQueryIntent(text: string, lower: string, containsAny: (text: string, keys: Array<string>) => boolean): boolean {
    const hasDomain: boolean = containsAny(lower, Page4Keywords.ORDER_QUERY_DOMAIN)
    if (!hasDomain) return false
    const hasVerb: boolean = containsAny(lower, Page4Keywords.ORDER_QUERY_VERBS)
    if (hasVerb) return true
    if (containsAny(lower, Page4Keywords.ORDER_QUERY_STATUS_SHIPPED)) return true
    if (containsAny(lower, Page4Keywords.ORDER_QUERY_SCOPE_EARLIEST)) return true
    if (containsAny(lower, Page4Keywords.ORDER_QUERY_SCOPE_LATEST)) return true
    if (containsAny(lower, Page4Keywords.ORDER_QUERY_SCOPE_ALL)) return true
    if (text.match(Page4Keywords.buildOrderIdRegex())) return true
    if (text.match(Page4Keywords.buildOrderSkuRegex())) return true
    return false
  }

  static buildVisionSummaryText(lastRecog: RecognitionResult | undefined): string {
    if (!lastRecog) return Page4ReplyText.noVisionResult()
    if (!lastRecog.ok) return Page4ReplyText.visionFailed(lastRecog.errorText)
    let labels: string = ''
    const maxN: number = lastRecog.boxes.length > 3 ? 3 : lastRecog.boxes.length
    for (let i: number = 0; i < maxN; i++) {
      const one = lastRecog.boxes[i]
      const part: string = `${one.label}(${one.score.toFixed(2)})`
      labels = labels.length <= 0 ? part : `${labels}, ${part}`
    }
    if (labels.length <= 0) labels = Page4ReplyText.visionNoBoxes()
    return Page4ReplyText.visionSummary(lastRecog.engine, lastRecog.boxes.length, labels)
  }
}
