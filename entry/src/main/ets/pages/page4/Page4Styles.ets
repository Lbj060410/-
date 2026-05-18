import { Page1Theme } from '../page1/Page1Theme'
import { INPUT } from '../page1/Page1Styles'

export const PAGE4_BUTTON = {
  HEIGHT_LG: 48,
  HEIGHT_MD: 44,
  HEIGHT_SM: 40,
  RADIUS: Page1Theme.RADIUS_M,
  FONT_SIZE_LG: 14,
  FONT_SIZE_MD: 13,
  FONT_SIZE_SM: 12,
  BG_IDLE: '#121926',
  BG_ACTIVE: '#00F5D4',
  BORDER_IDLE: 'rgba(0, 245, 212, 0.08)',
  BORDER_ACTIVE: '#80FFEC',
  FG_IDLE: Page1Theme.TEXT_SECONDARY,
  FG_ACTIVE: '#020408'
}

export const PAGE4_PANEL = {
  NAV_BG: Page1Theme.BG,
  NAV_BORDER: Page1Theme.BORDER,
  SIDEBAR_BG: Page1Theme.SURFACE,
  SIDEBAR_BORDER: Page1Theme.BORDER,
  CHAT_ASSIST_BG: Page1Theme.CARD,
  CHAT_ASSIST_BORDER: Page1Theme.BORDER,
  CHAT_BUSY_BG: Page1Theme.CARD,
  INPUT_BG: Page1Theme.SURFACE,
  INPUT_BORDER: Page1Theme.BORDER
}

// Keep page4 input exactly aligned with page1 input tokens.
export const PAGE4_INPUT = {
  HEIGHT: INPUT.HEIGHT,
  RADIUS: INPUT.RADIUS,
  BG: INPUT.BG,
  TEXT_COLOR: INPUT.TEXT_COLOR,
  PLACEHOLDER_COLOR: INPUT.PLACEHOLDER_COLOR,
  BORDER_COLOR: INPUT.BORDER_COLOR,
  BORDER_FOCUS: INPUT.BORDER_FOCUS
}

export function page4BtnBg(active: boolean): string {
  return active ? PAGE4_BUTTON.BG_ACTIVE : PAGE4_BUTTON.BG_IDLE
}

export function page4BtnBorder(active: boolean): string {
  return active ? PAGE4_BUTTON.BORDER_ACTIVE : PAGE4_BUTTON.BORDER_IDLE
}

export function page4BtnFg(active: boolean): string {
  return active ? PAGE4_BUTTON.FG_ACTIVE : PAGE4_BUTTON.FG_IDLE
}
