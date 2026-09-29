import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

import { bootstrap } from '../data/NoteStoreHolder';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Journal 默认深色（家族 Nothing OS 风格）
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(e));
    }
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 启动准备（建目录 + 取/建 salt，不解锁）→ 进解锁页：
    // 解锁在 pages/Unlock 完成（主密码 / 生物），解锁后才进 Index。
    bootstrap(this.context).then((ok: boolean) => {
      hilog.info(DOMAIN, TAG, 'bootstrap ok=%{public}s', ok);
      if (ok) {
        windowStage.loadContent('pages/Unlock', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
            return;
          }
          hilog.info(DOMAIN, TAG, 'loadContent succeeded');
        });
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
