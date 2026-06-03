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
import { page2Coordinator } from './page2/Page2Coordinator'
import { page1Store } from './page1/app/Page1UiStore'
import fs from '@ohos.file.fs'
import util from '@ohos.util'
import { bengkuiMasterError, bengkuiMasterErrText } from '../utils/BengkuiMasterLogger'

const PAGE4_PLACE_BINDING_FILE: string = 'page4_place_bindings.json'
const SPLASH_VIDEO_TIMEOUT_MS: number = 20000
interface Page4PlaceBindingPayload {
  homeNodeId?: string
  companyNodeId?: string
}

@Entry
@Component
struct Index {
  @State private currentIndex: number = 0
  @State private showFloatingNav: boolean = false
  @State private showSplash: boolean = true
  private splashHardTimeoutId: number = -1
  private splashFinishDelayId: number = -1

  aboutToAppear(): void {
    try {
      this.restorePlaceConfiguredOnAppEnter()
    } catch (e) {
      bengkuiMasterError('Index.aboutToAppear.restorePlaceConfiguredOnAppEnter', e)
    }
    // Page2 识别链路需要在非 Page2 页面也持续工作；入口页先以后台低频模式拉起。
    try {
      page2Coordinator.enterBackgroundMode()
    } catch (e) {
      bengkuiMasterError('Index.aboutToAppear.page2Coordinator.enterBackgroundMode', e)
    }
    void page2Coordinator.start()
      .catch((e: Object): void => {
        bengkuiMasterError('Index.aboutToAppear.page2Coordinator.start', e)
      })
    this.clearSplashHardTimeout()
    this.showSplash = true
    // 兜底：避免视频组件异常或媒体回调缺失时，开屏长期停留。
    this.splashHardTimeoutId = setTimeout((): void => {
      this.splashHardTimeoutId = -1
      if (!this.showSplash) return
      this.showSplash = false
    }, SPLASH_VIDEO_TIMEOUT_MS) as number
  }

  aboutToDisappear(): void {
    this.clearSplashHardTimeout()
    this.clearSplashFinishDelay()
  }

  private restorePlaceConfiguredOnAppEnter(): void {
    let home: string = ''
    let company: string = ''
    let f: fs.File | undefined = undefined
    try {
      const bindingPath: string = `${getContext(this).filesDir}/${PAGE4_PLACE_BINDING_FILE}`
      f = fs.openSync(bindingPath, fs.OpenMode.READ_ONLY)
      const st: fs.Stat = fs.statSync(bindingPath)
      const size: number = Number(st.size)
      if (Number.isFinite(size) && size > 0 && size <= 4096) {
        const buf: ArrayBuffer = new ArrayBuffer(Math.trunc(size))
        const readLen: number = fs.readSync(f.fd, buf)
        if (readLen > 0) {
          const bytes: Uint8Array = new Uint8Array(buf, 0, readLen)
          const txt: string = new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeWithStream(bytes, { stream: false })
          const parsed: Page4PlaceBindingPayload = JSON.parse(txt) as Page4PlaceBindingPayload
          home = String(parsed.homeNodeId ?? '').trim().toUpperCase()
          company = String(parsed.companyNodeId ?? '').trim().toUpperCase()
        }
      }
    } catch (e) {
      home = ''
      company = ''
      const msg: string = this.errText(e).toLowerCase()
      const notFound: boolean =
        msg.indexOf('no such file or directory') >= 0 ||
        msg.indexOf('enoent') >= 0 ||
        msg.indexOf('file not found') >= 0
      if (!notFound) {
        bengkuiMasterError(
          'Index.restorePlaceConfiguredOnAppEnter',
          e,
          `bindingPath=${getContext(this).filesDir}/${PAGE4_PLACE_BINDING_FILE}`
        )
      }
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
    page1Store.setPlaceConfigured(home, company)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (!this.showSplash) {
        this.buildCurrentPage()

        if (this.showFloatingNav) {
          this.buildNavPanel()
        }
      }

      if (this.showSplash) {
        Stack() {
          Video({
            src: $rawfile('开屏动画.mp4'),
          })
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .controls(false)
            .autoPlay(true)
            .onFinish((): void => {
              try {
                this.clearSplashHardTimeout()
                this.clearSplashFinishDelay()
                this.splashFinishDelayId = setTimeout((): void => {
                  this.splashFinishDelayId = -1
                  this.showSplash = false
                }, 500) as number
              } catch (e) {
                bengkuiMasterError('Index.splash.onFinish', e)
                this.showSplash = false
              }
            })
            .onError((): void => {
              try {
                this.skipSplashNow()
              } catch (e) {
                bengkuiMasterError('Index.splash.onError', e)
                this.showSplash = false
              }
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .zIndex(999)
        .onClick((): void => {
          try {
            this.skipSplashNow()
          } catch (e) {
            bengkuiMasterError('Index.splash.onClick', e)
            this.showSplash = false
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Page1Theme.BG)
    .onClick((): void => {
      if (this.showSplash) return
      this.showFloatingNav = !this.showFloatingNav
    })
  }

  private skipSplashNow(): void {
    if (!this.showSplash) return
    this.clearSplashHardTimeout()
    this.clearSplashFinishDelay()
    this.showSplash = false
  }

  private clearSplashHardTimeout(): void {
    if (this.splashHardTimeoutId >= 0) {
      clearTimeout(this.splashHardTimeoutId)
      this.splashHardTimeoutId = -1
    }
  }

  private clearSplashFinishDelay(): void {
    if (this.splashFinishDelayId >= 0) {
      clearTimeout(this.splashFinishDelayId)
      this.splashFinishDelayId = -1
    }
  }

  private errText(e: Object): string {
    return bengkuiMasterErrText(e)
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
