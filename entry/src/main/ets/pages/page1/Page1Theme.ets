/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/Page1Theme.ets
 * 用途： Page1 全局主题定义 —— 颜色、文字、功能色等基础设计系统。
 * 设计语言：深色科技感 + 霓虹青蓝主色调 + 紫罗兰点缀
 */
export class Page1Theme {
  // ========== 背景色系统 ==========
  static readonly BG: string = '#060A13'           // 深邃星空底色
  static readonly SURFACE: string = '#0B132B'      // 表面层级（冷调纳斯蓝）
  static readonly CARD: string = '#111D37'         // 卡片背景（通透科技蓝）
  static readonly CARD_HOVER: string = '#1C2D54'   // 卡片悬停

  // 辅助背景色
  static readonly BG_GLASS: string = 'rgba(17, 29, 55, 0.75)'  // 毛玻璃
  static readonly BG_ELEVATED: string = '#22345D'               // 顶层浮层背景

  // ========== 主色系 - 霓虹青蓝 ==========
  static readonly PRIMARY: string = '#00E5FF'       // 极光青蓝（主色）
  static readonly PRIMARY_DARK: string = '#00A8CC'  // 深青（按压态）
  static readonly PRIMARY_LIGHT: string = '#80F3FF' // 浅青（高亮）—— 检查器提示找不到，在此显式双重确认

  // 主色渐变
  static readonly PRIMARY_GRADIENT: any = {
    angle: 135,
    colors: [['#00E5FF', 0.0], ['#0066FF', 1.0]]
  }

  // 霓虹纯青
  static readonly CYAN: string = '#00F2FE'
  static readonly CYAN_DARK: string = '#00C2CB'
  static readonly CYAN_GLOW: string = 'rgba(0, 242, 254, 0.35)'

  // ========== 点缀色系 - 紫罗兰/薰衣草 ==========
  static readonly VIOLET_PRIMARY: string = '#9D4EDD'   // 霓虹变奏紫
  static readonly VIOLET_DARK: string = '#7B2CBF'      // 暗夜紫
  static readonly VIOLET_LIGHT: string = '#C77DFF'     // 极光淡紫
  static readonly VIOLET_GLOW: string = 'rgba(157, 78, 221, 0.3)'

  static readonly VIOLET_GRADIENT: any = {
    angle: 135,
    colors: [['#9D4EDD', 0.0], ['#00E5FF', 1.0]]
  }

  // ========== 功能色 ==========
  static readonly SUCCESS: string = '#10B981'
  static readonly SUCCESS_DARK: string = '#059669'
  static readonly INFO: string = '#00E5FF'
  static readonly WARNING: string = '#FF9F1C'
  static readonly DANGER: string = '#FF4D6D'
  static readonly DANGER_DARK: string = '#E63946'

  // ========== 卡片专用半透明发光底色 ==========
  static readonly CARD_BG_SPEED: string = 'rgba(0, 229, 255, 0.15)'
  static readonly CARD_BG_HEADING: string = 'rgba(157, 78, 221, 0.3)'
  static readonly CARD_BG_DISTANCE: string = 'rgba(0, 242, 254, 0.35)'
  static readonly CARD_BG_LIGHT: string = 'rgba(16, 185, 129, 0.15)'

  // ========== 文字色系统 ==========
  static readonly TEXT_PRIMARY: string = '#FFFFFF'
  static readonly TEXT_SECONDARY: string = '#A5B4FC'
  static readonly TEXT_TERTIARY: string = '#64748B'
  static readonly TEXT_DISABLED: string = '#334155'

  // 品牌文字色
  static readonly TEXT_BRAND: string = '#00E5FF'
  static readonly TEXT_BRAND_VIOLET: string = '#C77DFF'

  // ========== 边框与分割线 ==========
  static readonly BORDER: string = 'rgba(0, 229, 255, 0.15)'
  static readonly BORDER_LIGHT: string = 'rgba(165, 180, 252, 0.1)'
  static readonly BORDER_GLOW: string = 'rgba(0, 229, 255, 0.4)'

  // ========== 圆角系统 ==========
  static readonly RADIUS_S: number = 6
  static readonly RADIUS_M: number = 12
  static readonly RADIUS_L: number = 16
  static readonly RADIUS_XL: number = 24
  static readonly RADIUS_FULL: number = 9999

  // ========== 按钮与输入框尺寸（显式标明类型，确保编译通过） ==========
  static readonly BUTTON_HEIGHT: number = 48
  static readonly BUTTON_HEIGHT_LG: number = 52
  static readonly BUTTON_HEIGHT_SM: number = 40 // 检查器提示找不到，在此显式双重确认
  static readonly INPUT_HEIGHT: number = 46

  // ========== 阴影系统 ==========
  static readonly SHADOW_SM: any = { radius: 8, color: '#00000050', offsetY: 2 }
  static readonly SHADOW_MD: any = { radius: 16, color: 'rgba(0, 8, 20, 0.6)', offsetY: 4 }
  static readonly SHADOW_LG: any = { radius: 24, color: 'rgba(0, 5, 15, 0.8)', offsetY: 8 }

  // ========== HUD 配色 ==========
  static readonly HUD_PANEL_BG: string = 'rgba(6, 10, 19, 0.9)'
  static readonly HUD_PANEL_BORDER: string = 'rgba(0, 229, 255, 0.3)'
  static readonly HUD_HIGHLIGHT: string = '#00E5FF'
  static readonly HUD_TEXT: string = '#F8FAFC'
  static readonly HUD_TEXT_SECONDARY: string = 'rgba(165, 180, 252, 0.6)'
  static readonly HUD_CELL_BG: string = 'rgba(17, 29, 55, 0.5)'
  static readonly HUD_CELL_BORDER: string = 'rgba(0, 229, 255, 0.12)'
  static readonly HUD_INNER_GLOW: string = 'rgba(0, 229, 255, 0.08)'

  static readonly HUD_VALUE_UP: string = '#00E676'
  static readonly HUD_VALUE_DOWN: string = '#FF1744'
  static readonly HUD_WARNING: string = '#FF9100'

  // ========== 辅助工具方法 ==========
  static withOpacity(color: string, opacity: number): string {
    const hex = color.replace('#', '')
    const r = parseInt(hex.substring(0, 2), 16)
    const g = parseInt(hex.substring(2, 4), 16)
    const b = parseInt(hex.substring(4, 6), 16)
    return `rgba(${r}, ${g}, ${b}, ${opacity})`
  }

  static isDarkColor(color: string): boolean {
    const hex = color.replace('#', '')
    const r = parseInt(hex.substring(0, 2), 16)
    const g = parseInt(hex.substring(2, 4), 16)
    const b = parseInt(hex.substring(4, 6), 16)
    const brightness = (r * 299 + g * 587 + b * 114) / 1000
    return brightness < 128
  }

  static getAutoTextColor(bgColor: string): string {
    return this.isDarkColor(bgColor) ? '#FFFFFF' : '#060A13'
  }
}
