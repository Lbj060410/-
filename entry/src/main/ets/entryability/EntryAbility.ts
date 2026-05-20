/**
 * 代码指南：
 * 文件： entryability/EntryAbility.ts
 * 用途： 鸿蒙 OS 入口 Ability 启动生命周期.
 * 何时修改： 应用启动 / Ability 生命周期集成发生变更时.
 * 相关文件： pages/Index.ets（应用根节点）.
 */
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { page1Coordinator } from '../pages/page1/app/Page1Coordinator'
import { page2Coordinator } from '../pages/page2/Page2Coordinator'
import { shutdownRecognitionCenter } from '../services/recognition/RecognitionCenter'
import { bengkuiMasterError } from '../utils/BengkuiMasterLogger'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 保存 context 到 globalThis，供页面组件访问 resourceManager
    globalThis.abilityContext = this.context
    void want
    void launchParam
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        console.error(`loadContent failed: ${err.code}`);
        bengkuiMasterError('EntryAbility.onWindowStageCreate.loadContent', err)
      }
    });
  }

  onDestroy(): void {
    page1Coordinator.stop().catch((e: Object): void => {
      bengkuiMasterError('EntryAbility.onDestroy.page1Coordinator.stop', e)
    })
    try {
      page2Coordinator.stop()
    } catch (e) {
      bengkuiMasterError('EntryAbility.onDestroy.page2Coordinator.stop', e)
    }
    try {
      shutdownRecognitionCenter()
    } catch (e) {
      bengkuiMasterError('EntryAbility.onDestroy.shutdownRecognitionCenter', e)
    }
  }

  onBackground(): void {
    // App enters background: promptly stop heavy loops/inference to avoid lifecycle timeout freeze.
    try {
      page1Coordinator.pausePage()
    } catch (e) {
      bengkuiMasterError('EntryAbility.onBackground.page1Coordinator.pausePage', e)
    }
    try {
      page2Coordinator.stop()
    } catch (e) {
      bengkuiMasterError('EntryAbility.onBackground.page2Coordinator.stop', e)
    }
    try {
      shutdownRecognitionCenter()
    } catch (e) {
      bengkuiMasterError('EntryAbility.onBackground.shutdownRecognitionCenter', e)
    }
  }

  onForeground(): void {
    // Views will re-arm their own loops in onPageShow/aboutToAppear; keep ability hook lightweight.
  }
}
