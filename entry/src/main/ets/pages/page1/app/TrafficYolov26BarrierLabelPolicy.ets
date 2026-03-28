/**
 * 代码指南：
 * 文件： 
pages/page1/app/TrafficYolov26BarrierLabelPolicy.ets
 * 用途： 
Page1 coordination/scheduling helper logic.
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/TrafficYolov26BarrierLabelPolicy.ets
 * 用途： 定义交通障碍标签策略，将视觉标签映射到交通管控语义。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * TrafficYolov26BarrierLabelPolicy
 * Pure functions for yolov26barrier label normalization and semantic mapping.
 */
export function normalizeYolov26BarrierLabelKey(label: string): string {
  const x: string = label.trim().toLowerCase()
  let out: string = ''
  for (let i: number = 0; i < x.length; i++) {
    const ch: string = x[i]
    const code: number = ch.charCodeAt(0)
    const isNum: boolean = code >= 48 && code <= 57
    const isLower: boolean = code >= 97 && code <= 122
    if (isNum || isLower) out += ch
  }
  return out
}

export function isTrafficLightYolov26BarrierLabelKey(labelKey: string): boolean {
  return labelKey === 'trafficlight' || labelKey === 'trafficlights'
}

export function isShigongYolov26BarrierLabelKey(labelKey: string): boolean {
  return labelKey === 'shigong'
}

export function isGetOffTheCarYolov26BarrierLabelKey(labelKey: string): boolean {
  return labelKey === 'getoffthecar' || labelKey === 'getoffcar'
}


