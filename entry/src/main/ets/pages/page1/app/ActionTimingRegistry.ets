/**
 * 代码指南：
 * 文件：pages/page1/app/ActionTimingRegistry.ets
 * 用途：Page1 协调/调度辅助逻辑。
 * 何时修改：相关行为或契约变化时。
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/pages/page1/app/ActionTimingRegistry.ets
 * 用途： 维护动作时序配置与动作持续时长映射，为调度器和运动播放提供统一时序基线。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
/**
 * ActionTimingRegistry
 * 动作窗口和命令节奏的纯数据时序注册表。
 */
import { Page1Action } from '../types/Page1Types'

export interface MotionTimingProfile {
  preMs: number
  activeMs: number
  postMs: number
  sendGapMs: number
}

export class ActionTimingRegistry {
  timingForAction(action: Page1Action): MotionTimingProfile {
    if (action === Page1Action.GO) {
      return { preMs: 2000, activeMs: 1500, postMs: 500, sendGapMs: 4000 }
    }
    if (action === Page1Action.LEFT || action === Page1Action.RIGHT || action === Page1Action.UTURN) {
      return { preMs: 1000, activeMs: 500, postMs: 500, sendGapMs: 2000 }
    }
    if (action === Page1Action.BACK) {
      return { preMs: 2000, activeMs: 1500, postMs: 500, sendGapMs: 4000 }
    }
    return { preMs: 0, activeMs: 0, postMs: 0, sendGapMs: 2000 }
  }

  gateDepartTiming(): MotionTimingProfile {
    // 离开后，车辆侧闸门+前进比正常前进需要更长时间。
    // 保持更大间隔以避免下一个前进命令被立即忽略。
    return { preMs: 3000, activeMs: 1500, postMs: 500, sendGapMs: 7000 }
  }
}


