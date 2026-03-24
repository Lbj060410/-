/**
 * 代码指南：
 * 文件： pages/page3/Page3View.ets
 * 用途： Minimalist page completely filled with a violet gradient.
 */

import { Page1Theme } from '../page1/Page1Theme'

@Component
export struct Page3View {
  build(): void {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient(Page1Theme.VIOLET_GRADIENT)
  }
}
