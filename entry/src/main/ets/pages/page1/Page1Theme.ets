/**
 * 代码指南：
 * 文件：pages/page1/Page1Theme.ets
 * 用途：Page1 UI 主题或页面级组合。
 * 何时修改：相关行为或契约变化时。
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/Page1Theme.ets
 * 用途： 集中定义 page1 主题色、渐变与 UI 视觉常量。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
export class Page1Theme {
  // 主背景色
  static readonly BG: string = '#EEF1F8' // 来自 linear-gradient(160deg, #EEF1F8 0%, #F4F6FA 50%, #EDF0F8 100%)

  static readonly SURFACE: string = '#FFFFFF'
  static readonly CARD: string = '#FFFFFF'
  static readonly CARD_HOVER: string = '#F1F5F9'

  // 紫罗兰/薰衣草渐变色
  static readonly VIOLET_PRIMARY: string = '#7C3AED'
  static readonly VIOLET_DARK: string = '#6D28D9'
  static readonly VIOLET_GRADIENT: any = {
    angle: 180,
    colors: [['#A78BFA', 0.0], ['#7C3AED', 1.0]]
  }

  // 蓝色/主色渐变（从 React UI 引入）
  static readonly PRIMARY: string = '#2F6BFF'
  static readonly PRIMARY_DARK: string = '#1E4ED8'
  static readonly PRIMARY_GRADIENT: any = {
    angle: 155,
    colors: [['#4a7fff', 0.0], ['#1e4ed8', 1.0]]
  }

  static readonly SUCCESS: string = '#059669' // 来自 UI 的绿色
  static readonly INFO: string = '#0891B2'    // 来自 UI 的青色
  static readonly WARNING: string = '#F59E0B' // 来自 UI 的橙色
  static readonly DANGER: string = '#EF4444'

  static readonly TEXT_PRIMARY: string = '#1A1F36'
  static readonly TEXT_SECONDARY: string = '#475569'
  static readonly TEXT_TERTIARY: string = '#9CA3AF'
  static readonly BORDER: string = '#F3F4F6' // rgba(0,0,0,0.05) 近似值

  static readonly RADIUS_S: number = 8
  static readonly RADIUS_M: number = 12
  static readonly RADIUS_L: number = 16
  static readonly RADIUS_XL: number = 24 // tailwind 中的 2xl

  static readonly BUTTON_HEIGHT: number = 52
  static readonly INPUT_HEIGHT: number = 46
}



