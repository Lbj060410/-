/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/Page1Styles.ets
 * 用途： Page1 组件样式集中管理 —— 按钮、卡片、输入框、面板等组件的尺寸、间距、阴影。
 */

import { Page1Theme } from './Page1Theme'

type ThemeCompat = {
  BUTTON_HEIGHT: number
  BUTTON_HEIGHT_SM: number
  INPUT_HEIGHT: number
  RADIUS_S: number
  RADIUS_M: number
  RADIUS_L: number
  RADIUS_XL: number
  SURFACE: string
  BORDER: string
  TEXT_SECONDARY: string
  PRIMARY: string
  PRIMARY_LIGHT: string
  CARD_HOVER: string
  SHADOW_MD: { radius: number; color: string; offsetY: number }
  CARD: string
  TEXT_PRIMARY: string
  TEXT_TERTIARY: string
  SUCCESS: string
  WARNING: string
  DANGER: string
  VIOLET_PRIMARY: string
  CARD_BG_SPEED: string
  CARD_BG_HEADING: string
  CYAN: string
  CARD_BG_DISTANCE: string
  CARD_BG_LIGHT: string
}

const THEME: ThemeCompat = Page1Theme as unknown as ThemeCompat

const BUTTON_HEIGHT_LG_FALLBACK: number = 52
const VIOLET_LIGHT_FALLBACK: string = '#C77DFF'

// ========== 💡 重塑核心：极光霓虹与赛博暗黑矩阵 ==========
// 彻底干掉土气和沉闷的普通蓝色
const BRAND_NEON_CYAN: string = '#00F5D4'        // 终极痛点修复：激活态改用明亮、通透的荧光极光青（赛博跑车仪表盘色）
const BRAND_NEON_GLOW: string = '#80FFEC'       // 极光青边框高亮
const APERTURE_DARK_INPUT: string = '#020408'   // 输入框痛点修复：彻底切断蓝色，改用深邃纯净的夜视黑
const APERTURE_DARK_BTN: string = '#121926'     // 空闲按钮：带微弱冷调的黑曜石色

// ========== 按钮样式 ==========
export const BUTTON = {
  HEIGHT_LG: BUTTON_HEIGHT_LG_FALLBACK,
  HEIGHT_MD: THEME.BUTTON_HEIGHT,
  HEIGHT_SM: THEME.BUTTON_HEIGHT_SM,
  HEIGHT_XS: 32,
  RADIUS: THEME.RADIUS_M,
  FONT_SIZE: 13,

  BG_IDLE: APERTURE_DARK_BTN,
  BORDER_IDLE: 'rgba(0, 245, 212, 0.12)',
  FG_IDLE: THEME.TEXT_SECONDARY,

  // 修复：点击/激活后变成酷炫的极光荧光青，配合深色底座上的反差白字
  BG_ACTIVE: BRAND_NEON_CYAN,
  BORDER_ACTIVE: BRAND_NEON_GLOW,
  FG_ACTIVE: '#020408', // 荧光底色上配纯黑字，是高端电竞外设和HUD的经典做法，极其锐利清晰
  BG_HOVER: THEME.CARD_HOVER,
}

// ========== 卡片样式 ==========
export const CARD = {
  RADIUS: THEME.RADIUS_M,
  PADDING: 16,
  ACCENT_HEIGHT: 3,
  ICON_SIZE: 32,

  VALUE_FONT: 24,
  LABEL_FONT: 11,

  SHADOW: THEME.SHADOW_MD,

  BG: THEME.CARD,
  TEXT_COLOR: THEME.TEXT_PRIMARY,
  TEXT_MUTED: THEME.TEXT_SECONDARY,
}

// ========== 输入框样式（彻底重构：完全去蓝色化，纯黑晶体化） ==========
export const INPUT = {
  HEIGHT: THEME.INPUT_HEIGHT,
  RADIUS: THEME.RADIUS_M,

  // 彻底修复：使用全黑底座，像一块光滑无暇的黑色全面屏玻璃，彻底告别丑蓝
  BG: APERTURE_DARK_INPUT,

  // 纯白字体，黑底白字，绝不拖泥带水
  TEXT_COLOR: '#FFFFFF',

  // 占位符改为半透明雾白
  PLACEHOLDER_COLOR: 'rgba(255, 255, 255, 0.25)',

  // 未聚焦时是极具克制的半透明细线，若隐若现
  BORDER_COLOR: 'rgba(255, 255, 255, 0.05)',

  // 聚焦一瞬间，整个输入框边缘亮起一圈耀眼的极光青细窄微光，仪式感拉满
  BORDER_FOCUS: BRAND_NEON_CYAN,
}

// ========== 间距规格 ==========
export const SPACING = {
  XS: 4,
  S: 8,
  M: 12,
  L: 16,
  XL: 20,
  XXL: 24,
}

// ========== 圆角规格 ==========
export const RADIUS = {
  S: THEME.RADIUS_S,
  M: THEME.RADIUS_M,
  L: THEME.RADIUS_L,
  XL: THEME.RADIUS_XL,
}

// ========== 字号规格 ==========
export const FONT_SIZE = {
  XS: 10,
  S: 11,
  M: 12,
  L: 13,
  XL: 14,
  XXL: 16,
  TITLE: 18,
  LARGE: 24,
  XLARGE: 30,
}

// ========== 状态指示色 ==========
export const STATUS = {
  ACTION: BRAND_NEON_GLOW,
  PATH_QUEUE: VIOLET_LIGHT_FALLBACK,
  SUCCESS: THEME.SUCCESS,
  WARNING: THEME.WARNING,
  DANGER: THEME.DANGER,
}

// ========== 卡片数据色 ==========
export const CARD_ACCENT = {
  SPEED: BRAND_NEON_CYAN,
  SPEED_BG: THEME.CARD_BG_SPEED,

  HEADING: THEME.VIOLET_PRIMARY,
  HEADING_BG: THEME.CARD_BG_HEADING,

  DISTANCE: THEME.CYAN,
  DISTANCE_BG: THEME.CARD_BG_DISTANCE,

  LIGHT: THEME.SUCCESS,
  LIGHT_BG: THEME.CARD_BG_LIGHT,
}

// ========== 控制面板按钮色 ==========
export const CONTROL_PANEL = {
  MODE_BTN_HEIGHT: 44,
  MODE_BTN_RADIUS: THEME.RADIUS_M,
  MODE_BTN_FONT_SIZE: 13,

  ACTION_BTN_HEIGHT: BUTTON_HEIGHT_LG_FALLBACK,
  ACTION_BTN_RADIUS: THEME.RADIUS_M,

  DIAG_BTN_HEIGHT: 32,
  DIAG_BTN_RADIUS: THEME.RADIUS_M,

  SEND_BTN_HEIGHT: THEME.BUTTON_HEIGHT_SM,
  SEND_BTN_RADIUS: THEME.RADIUS_M,

  BG_IDLE: APERTURE_DARK_BTN,
  // 修复：面板上的按钮激活态同步换装为极光荧光青加黑字，拒绝暗底死蓝
  BG_ACTIVE: BRAND_NEON_CYAN,
  BORDER_IDLE: 'rgba(0, 245, 212, 0.08)',
  BORDER_ACTIVE: BRAND_NEON_GLOW,
  FG_IDLE: THEME.TEXT_SECONDARY,
  FG_ACTIVE: '#020408',
}

// ========== 更多面板按钮 ==========
export const MORE_PANEL = {
  BTN_HEIGHT: THEME.BUTTON_HEIGHT_SM,
  BTN_RADIUS: THEME.RADIUS_M,
  BG: APERTURE_DARK_BTN,
  BORDER: 'rgba(0, 245, 212, 0.08)',
  FG: THEME.TEXT_PRIMARY,
}

// ========== 对话框/模态 ==========
export const MODAL = {
  OVERLAY_BG: 'rgba(2, 4, 8, 0.85)', // 更加纯粹的夜视黑遮罩
  CLOSE_BTN_HEIGHT: 32,
  CLOSE_BTN_RADIUS: 16,
  CLOSE_BTN_BG: THEME.CARD,
  CLOSE_BTN_FG: THEME.TEXT_PRIMARY,
}

// ========== 路径队列卡片 ==========
export const PATH_CARD = {
  TEXT_COLOR: BRAND_NEON_CYAN,
  BG: 'rgba(0, 245, 212, 0.06)', // 极光青微弱呼吸透底
  PADDING: 12,
  RADIUS: THEME.RADIUS_S,
  BORDER_COLOR: 'rgba(0, 245, 212, 0.2)',
}
