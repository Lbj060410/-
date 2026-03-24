/**
 * 代码指南：
 * 文件：pages/Index.ets
 * 用途：带浮动底部导航的应用外壳。
 * 何时修改：切换顶级页面或导航行为时。
 * 相关文件：pages/page1/*、pages/page2/*、pages/page3/*、pages/page4/*。
 */
import { Page1View } from './page1/Page1View'
import { Page2View } from './page2/Page2View'
import { Page3View } from './page3/Page3View'
import { Page4View } from './page4/Page4View'
import { Page1Theme } from './page1/Page1Theme'

@Entry
@Component
struct Index {
  @State private currentIndex: number = 0
  @State private showFloatingNav: boolean = false

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.buildCurrentPage()

      if (this.showFloatingNav) {
        this.buildNavPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Page1Theme.BG)
    .onClick((): void => {
      this.showFloatingNav = !this.showFloatingNav
    })
  }

  @Builder
  private buildCurrentPage(): void {
    if (this.currentIndex === 0) {
      Page1View()
    } else if (this.currentIndex === 1) {
      Page2View()
    } else if (this.currentIndex === 2) {
      Page3View()
    } else {
      Page4View()
    }
  }

  @Builder
  private buildNavPanel(): void {
    Row() {
      Row({ space: 80 }) {
        this.navItem('地图', 0)
        this.navItem('视频', 1)
        this.navItem('3D', 2)
        this.navItem('助手', 3)
      }
      .padding({ left: 80, right: 80, top: 14, bottom: 14 })
      .borderRadius(32)
      .backgroundColor('#4DFFFFFF')
      .backgroundBlurStyle(BlurStyle.Thin)
      .backdropBlur(40)
      .shadow({ radius: 40, color: '#00000012', offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: 44 })
    .transition({ type: TransitionType.All, opacity: 0, scale: { x: 0.95, y: 0.95 } })
    .onClick((): void => {}) // 拦截点击事件
  }

  @Builder
  private navItem(label: string, index: number): void {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (index === 0) {
          Image(this.currentIndex === index ? $rawfile('icon/地图.png') : $rawfile('icon/地图未选择.png'))
            .width(26)
            .height(26)
            .translate({ x: 0, y: this.currentIndex === index ? -4 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        } else if (index === 1) {
          Image(this.currentIndex === index ? $rawfile('icon/视频.png') : $rawfile('icon/视频未选择.png'))
            .width(26)
            .height(26)
            .translate({ x: 0, y: this.currentIndex === index ? -4 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        } else if (index === 2) {
          Image(this.currentIndex === index ? $rawfile('icon/3d.png') : $rawfile('icon/3d未选择.png'))
            .width(26)
            .height(26)
            .translate({ x: 0, y: this.currentIndex === index ? -4 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        } else {
          Image(this.currentIndex === index ? $rawfile('icon/智能体.png') : $rawfile('icon/智能体未选择.png'))
            .width(26)
            .height(26)
            .translate({ x: 0, y: this.currentIndex === index ? -4 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        }
      }
      .width(44)
      .height(44)

      Text(label)
        .fontSize(12)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentIndex === index ? Page1Theme.VIOLET_PRIMARY : Page1Theme.TEXT_SECONDARY)
        .opacity(this.currentIndex === index ? 1.0 : 0.6)
    }
    .onClick((): void => {
      animateTo({ duration: 300, curve: Curve.EaseOut }, (): void => {
        this.currentIndex = index
      })
    })
  }
}
