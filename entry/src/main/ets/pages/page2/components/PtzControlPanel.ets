/**
 * 代码指南：
 * 文件： pages/page2/components/PtzControlPanel.ets
 * 用途：Page2 可复用 UI 控件（云台及相关组件）.
 * 何时修改： 添加云台按钮、控制面板或进行样式更新时.
 * 相关文件： services/control/CameraPtzService.ets 以及 Page2 协调器.
 */
import { CameraPtzService, PtzResult } from '../../../services/control/CameraPtzService'
import { videoStore } from '../../../state/VideoStore'
import { Page1Theme } from '../../page1/Page1Theme'

@Component
export struct PtzControlPanel {
  cameraHost: string = ''
  cameraUser: string = ''
  cameraPass: string = ''
  svc?: CameraPtzService

  private getService(): CameraPtzService {
    return this.svc ? this.svc : new CameraPtzService()
  }

  private async run(
    op: (svc: CameraPtzService, host: string, user: string, pass: string) => Promise<PtzResult>
  ): Promise<void> {
    const host: string = this.cameraHost
    if (!host) {
      videoStore.setError('Camera host is empty')
      return
    }

    const user: string = this.cameraUser
    const pass: string = this.cameraPass
    try {
      const r: PtzResult = await op(this.getService(), host, user, pass)
      if (r.ok) videoStore.setStatus(`PTZ ok ${r.costMs}ms`)
      else videoStore.setError(`PTZ failed ${r.costMs}ms`)
    } catch (_) {
      videoStore.setError('PTZ exception')
    }
  }

  build() {
    Column({ space: 16 }) {
      Column({ space: 16 }) {
        // D-Pad
        Grid() {
          GridItem() {}
          GridItem() { this.ptzBtn('↑', () => this.run((svc, h, u, p) => svc.up(h, u, p))) }
          GridItem() {}

          GridItem() { this.ptzBtn('←', () => this.run((svc, h, u, p) => svc.left(h, u, p))) }
          GridItem() {
            Column().width('100%').height('100%').backgroundColor('#F3F4F6').borderRadius(12).border({ width: 1, color: '#E5E7EB' })
          }
          GridItem() { this.ptzBtn('→', () => this.run((svc, h, u, p) => svc.right(h, u, p))) }

          GridItem() {}
          GridItem() { this.ptzBtn('↓', () => this.run((svc, h, u, p) => svc.down(h, u, p))) }
          GridItem() {}
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width(144)
        .height(144)

        // 缩放滑块占位符
        Row({ space: 12 }) {
          Text('ZOOM').fontSize(10).fontWeight(FontWeight.Bold).fontColor(Page1Theme.TEXT_TERTIARY)
          Slider({ value: 50, min: 1, max: 100, step: 1, style: SliderStyle.OutSet })
            .layoutWeight(1)
            .selectedColor(Page1Theme.PRIMARY)
            .trackColor('#E5E7EB')
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F9FAFB')
      .borderRadius(16)
      .border({ width: 1, color: '#F3F4F6' })
    }
  }

  @Builder
  private ptzBtn(label: string, action: () => void): void {
    Button() {
      Text(label).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Page1Theme.TEXT_SECONDARY)
    }
    .width('100%')
    .height('100%')
    .borderRadius(12)
    .backgroundColor(Page1Theme.CARD)
    .border({ width: 1, color: '#E5E7EB' })
    .shadow({ radius: 4, color: '#0000000A', offsetX: 0, offsetY: 2 })
    .onClick(action)
  }
}

