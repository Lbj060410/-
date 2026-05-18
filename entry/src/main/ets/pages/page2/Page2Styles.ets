import { Page1Theme } from '../page1/Page1Theme'

export const PAGE2_BUTTON = {
  HEIGHT_LG: 48,
  HEIGHT_MD: 44,
  HEIGHT_SM: 40,
  HEIGHT_XS: 32,
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

export const PAGE2_MODAL = {
  CLOSE_HEIGHT: 32,
  CLOSE_RADIUS: Page1Theme.RADIUS_M,
  CLOSE_BG: PAGE2_BUTTON.BG_IDLE,
  CLOSE_BORDER: PAGE2_BUTTON.BORDER_IDLE,
  CLOSE_FG: PAGE2_BUTTON.FG_IDLE,
  CLOSE_FONT_SIZE: PAGE2_BUTTON.FONT_SIZE_SM
}

export const PAGE2_REPLAY = {
  PANEL_BG: Page1Theme.SURFACE,
  CARD_BG: Page1Theme.CARD,
  CARD_BORDER: Page1Theme.BORDER,
  EMPTY_BG: Page1Theme.CARD_HOVER,
  DETAIL_BG: Page1Theme.CARD,
  DETAIL_BORDER: Page1Theme.BORDER
}

export function page2BtnBg(active: boolean): string {
  return active ? PAGE2_BUTTON.BG_ACTIVE : PAGE2_BUTTON.BG_IDLE
}

export function page2BtnBorder(active: boolean): string {
  return active ? PAGE2_BUTTON.BORDER_ACTIVE : PAGE2_BUTTON.BORDER_IDLE
}

export function page2BtnFg(active: boolean): string {
  return active ? PAGE2_BUTTON.FG_ACTIVE : PAGE2_BUTTON.FG_IDLE
}
