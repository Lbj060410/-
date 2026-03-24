/**
 * 代码指南：
 * 文件： entryability/EntryAbility.ts
 * 用途： HarmonyOS entry ability bootstrap lifecycle.
 * 何时修改： app startup/ability lifecycle integration changes.
 * 相关文件： pages/Index.ets app root.
 */
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 保存 context 到 globalThis，供页面组件访问 resourceManager
    globalThis.abilityContext = this.context
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        console.error(`loadContent failed: ${err.code}`);
      }
    });
  }

  onDestroy(): void {
    // no-op
  }
}

