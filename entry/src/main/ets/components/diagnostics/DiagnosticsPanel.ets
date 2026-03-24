/**
 * 代码指南：
 * 文件： components/diagnostics/DiagnosticsPanel.ets
 * 用途： Reusable diagnostics UI panel.
 * 何时修改： diagnostics display fields/actions are changed.
 * 相关文件： services/diagnostics/FrameLogService.ets and page1 view.
 */
// entry/src/main/ets/components/diagnostics/DiagnosticsPanel.ets
import wifi from '@ohos.wifi'

import { commStore, DiagKeyRxFrame, DiagKeyTxFrame, DiagWebTxLog } from '../../state/CommStore'
import { deviceNetworkResolver } from '../../services/network/DeviceNetworkResolver'

@Component
export struct DiagnosticsPanel {
  aboutToAppear(): void {
    const gatewayIp: string = deviceNetworkResolver.resolveGatewayIp()
    if (gatewayIp.length > 0) {
      commStore.setWifiIp(gatewayIp)
      return
    }

    try {
      const ipNum: number = wifi.getIpInfo().ipAddress
      const a: number = ipNum & 0xFF
      const b: number = (ipNum >>> 8) & 0xFF
      const c: number = (ipNum >>> 16) & 0xFF
      const d: number = (ipNum >>> 24) & 0xFF
      commStore.setWifiIp(`${a}.${b}.${c}.${d}`)
    } catch (_) {
      commStore.setWifiIp('未知')
    }
  }

  private fmtTime(tsMs: number): string {
    const d: Date = new Date(tsMs)
    const hh: string = `${d.getHours()}`.padStart(2, '0')
    const mm: string = `${d.getMinutes()}`.padStart(2, '0')
    const ss: string = `${d.getSeconds()}`.padStart(2, '0')
    const ms: string = `${d.getMilliseconds()}`.padStart(3, '0')
    return `${hh}:${mm}:${ss}.${ms}`
  }

  build() {
    Column({ space: 12 }) {
      Text('Diagnostics / 工程模式')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Column({ space: 6 }) {
        Text('通信')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)

        Text(`连接IP：${commStore.wifiIp}`)
          .fontSize(12)

        Text(`状态：${commStore.diagCommStateText} ${commStore.diagCommConnected ? '(connected)' : ''}`)
          .fontSize(12)

        Text(`RX: ${commStore.diagRxPps} pkt/s   TX: ${commStore.diagTxPps} pkt/s`)
          .fontSize(12)

        Text(`重连次数: ${commStore.diagCommReconnectCount}`)
          .fontSize(12)

        if (commStore.diagCommLastError.length > 0) {
          Text(`最后错误: ${commStore.diagCommLastError}`)
            .fontSize(12)
        }
      }
      .padding(12)
      .borderRadius(12)
      .backgroundColor('#F3F5F7')

      Column({ space: 8 }) {
        Text('关键日志')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)

        Row({ space: 8 }) {
          Text('发送控制指令日志')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#475467')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('接收数据帧日志')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#475467')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('网页端上报日志')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#475467')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }
        .width('100%')

        Row({ space: 8 }) {
          Column({ space: 6 }) {
            if (commStore.diagKeyTxFrames.length <= 0) {
              Text('暂无日志')
                .fontSize(12)
                .fontColor('#667085')
            } else {
              Scroll() {
                Column({ space: 6 }) {
                  ForEach(commStore.diagKeyTxFrames, (item: DiagKeyTxFrame): void => {
                    Text(`[${this.fmtTime(item.tsMs)}] ${item.cmdHex} ${item.actionText} (${item.modeText})`)
                      .fontSize(11)
                      .fontColor('#101828')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .padding(8)
                      .borderRadius(8)
                      .backgroundColor('#FFFFFF')
                  }, (item: DiagKeyTxFrame): string => `${item.tsMs}-${item.cmdHex}-${item.hex}`)
                }
                .width('100%')
              }
              .width('100%')
              .height(420)
              .edgeEffect(EdgeEffect.None)
            }
          }
          .layoutWeight(1)

          Column({ space: 6 }) {
            if (commStore.diagKeyRxFrames.length <= 0) {
              Text('暂无日志')
                .fontSize(12)
                .fontColor('#667085')
            } else {
              Scroll() {
                Column({ space: 6 }) {
                  ForEach(commStore.diagKeyRxFrames, (item: DiagKeyRxFrame): void => {
                    Text(`[${this.fmtTime(item.tsMs)}] ${item.cmdHex} ${item.summary}`)
                      .fontSize(11)
                      .fontColor('#101828')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .padding(8)
                      .borderRadius(8)
                      .backgroundColor('#FFFFFF')
                  }, (item: DiagKeyRxFrame): string => `${item.tsMs}-${item.cmdHex}-${item.hex}`)
                }
                .width('100%')
              }
              .width('100%')
              .height(420)
              .edgeEffect(EdgeEffect.None)
            }
          }
          .layoutWeight(1)

          Column({ space: 6 }) {
            if (commStore.diagWebTxLogs.length <= 0) {
              Text('暂无日志')
                .fontSize(12)
                .fontColor('#667085')
            } else {
              Scroll() {
                Column({ space: 6 }) {
                  ForEach(commStore.diagWebTxLogs, (item: DiagWebTxLog): void => {
                    Scroll() {
                      Text(`[${this.fmtTime(item.tsMs)}] ${item.status} ${item.line}`)
                        .fontSize(11)
                        .fontColor('#101828')
                        .maxLines(1)
                    }
                    .scrollable(ScrollDirection.Horizontal)
                    .edgeEffect(EdgeEffect.None)
                    .width('100%')
                    .padding(8)
                    .borderRadius(8)
                    .backgroundColor('#FFFFFF')
                  }, (item: DiagWebTxLog): string => `${item.tsMs}-${item.status}-${item.line}`)
                }
                .width('100%')
              }
              .width('100%')
              .height(420)
              .edgeEffect(EdgeEffect.None)
            }
          }
          .layoutWeight(1)
        }
        .width('100%')
      }
      .padding(12)
      .borderRadius(12)
      .backgroundColor('#F3F5F7')
    }
    .width('100%')
    .padding(16)
  }
}

