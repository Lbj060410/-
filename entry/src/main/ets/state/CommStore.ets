/**
 * 代码指南：
 * 文件： state/CommStore.ets
 * 用途： Shared app-level store/state module.
 * 何时修改： adding cross-page state or adjusting global data shape.
 * 相关文件： page views/coordinators and services that read/write store values.
 */
// entry/src/main/ets/state/CommStore.ets

export interface DiagKeyTxFrame {
  tsMs: number
  cmdHex: string
  actionText: string
  modeText: string
  hex: string
}

export interface DiagKeyRxFrame {
  tsMs: number
  cmdHex: string
  summary: string
  frameKind: string
  hex: string
}

export interface DiagWebTxLog {
  tsMs: number
  status: string
  line: string
}

@Observed
export class CommStore {
  // ==== 通信状态 ====
  commConnected: boolean = false
  commStateText: string = 'IDLE'
  commReconnectCount: number = 0
  commLastErrorText: string = ''

  txPackets: number = 0
  rxPackets: number = 0

  // ==== PPS 统计 ====
  diagTxPps: number = 0
  diagRxPps: number = 0
  private diagPpsWindowStartMs: number = 0
  private diagPpsTxBase: number = 0
  private diagPpsRxBase: number = 0

  // ==== WiFi IP ====
  wifiIp: string = ''

  // ==== 路径规划/避障计数 ====
  diagReplanCount: number = 0
  diagAvoidCount: number = 0
  diagEStopCount: number = 0

  // ==== 帧日志 ====
  diagLogEnabled: boolean = false
  diagLogPath: string = '-'
  diagLogLines: number = 0
  diagLogFileSizeBytes: number = 0

  // ==== 关键指令帧日志（仅动作控制）====
  diagKeyTxFrames: Array<DiagKeyTxFrame> = []
  private readonly diagKeyTxFramesMax: number = 120
  diagKeyRxFrames: Array<DiagKeyRxFrame> = []
  private readonly diagKeyRxFramesMax: number = 120
  diagWebTxLogs: Array<DiagWebTxLog> = []
  private readonly diagWebTxLogsMax: number = 120

  // ==== Getter 别名（供 DiagnosticsPanel 使用）====
  get diagCommStateText(): string { return this.commStateText }
  get diagCommConnected(): boolean { return this.commConnected }
  get diagCommReconnectCount(): number { return this.commReconnectCount }
  get diagCommLastError(): string { return this.commLastErrorText }

  // ==== 通信方法 ====
  setCommState(connected: boolean, text: string): void {
    this.commConnected = connected
    this.commStateText = text
  }

  setCommReconnectCount(v: number): void { this.commReconnectCount = v }

  setCommLastError(text: string): void { this.commLastErrorText = text }

  setWifiIp(ip: string): void { this.wifiIp = ip }

  bumpTxPacket(): void {
    this.txPackets += 1
    this.updateDiagPpsIfNeeded()
  }

  bumpRxPacket(): void {
    this.rxPackets += 1
    this.updateDiagPpsIfNeeded()
  }

  private updateDiagPpsIfNeeded(): void {
    const now: number = Date.now()
    if (this.diagPpsWindowStartMs <= 0) {
      this.diagPpsWindowStartMs = now
      this.diagPpsTxBase = this.txPackets
      this.diagPpsRxBase = this.rxPackets
      return
    }
    if (now - this.diagPpsWindowStartMs >= 1000) {
      this.diagTxPps = this.txPackets - this.diagPpsTxBase
      this.diagRxPps = this.rxPackets - this.diagPpsRxBase
      this.diagPpsWindowStartMs = now
      this.diagPpsTxBase = this.txPackets
      this.diagPpsRxBase = this.rxPackets
    }
  }

  // ==== 规划/避障/急停 ====
  bumpReplan(): void { this.diagReplanCount += 1 }
  bumpAvoid(): void { this.diagAvoidCount += 1 }
  bumpEStop(): void { this.diagEStopCount += 1 }

  // ==== 日志 ====
  setLogEnabled(enabled: boolean): void { this.diagLogEnabled = enabled }
  setLogInfo(path: string, lines: number, sizeBytes: number): void {
    this.diagLogPath = path
    this.diagLogLines = lines
    this.diagLogFileSizeBytes = sizeBytes
  }

  appendDiagKeyTxFrame(frame: DiagKeyTxFrame): void {
    const next: Array<DiagKeyTxFrame> = []
    const cap: number = this.diagKeyTxFramesMax
    const keepFrom: number = this.diagKeyTxFrames.length >= cap ? 1 : 0
    for (let i: number = keepFrom; i < this.diagKeyTxFrames.length; i++) {
      next.push(this.diagKeyTxFrames[i])
    }
    next.push(frame)
    this.diagKeyTxFrames = next
  }

  clearDiagKeyTxFrames(): void {
    this.diagKeyTxFrames = []
  }

  appendDiagKeyRxFrame(frame: DiagKeyRxFrame): void {
    const next: Array<DiagKeyRxFrame> = []
    const cap: number = this.diagKeyRxFramesMax
    const keepFrom: number = this.diagKeyRxFrames.length >= cap ? 1 : 0
    for (let i: number = keepFrom; i < this.diagKeyRxFrames.length; i++) {
      next.push(this.diagKeyRxFrames[i])
    }
    next.push(frame)
    this.diagKeyRxFrames = next
  }

  clearDiagKeyRxFrames(): void {
    this.diagKeyRxFrames = []
  }

  appendDiagWebTxLog(item: DiagWebTxLog): void {
    const next: Array<DiagWebTxLog> = []
    const cap: number = this.diagWebTxLogsMax
    const keepFrom: number = this.diagWebTxLogs.length >= cap ? 1 : 0
    for (let i: number = keepFrom; i < this.diagWebTxLogs.length; i++) {
      next.push(this.diagWebTxLogs[i])
    }
    next.push(item)
    this.diagWebTxLogs = next
  }

  clearDiagWebTxLogs(): void {
    this.diagWebTxLogs = []
  }
}

export const commStore: CommStore = new CommStore()

