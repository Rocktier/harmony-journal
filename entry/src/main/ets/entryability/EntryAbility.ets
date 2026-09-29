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
    //
    // ⚠️ 白屏防线（实拍教训）：bootstrap 一旦 reject，`then` 不执行，
    // loadContent 就永远不被调用 —— ability 停在 FOREGROUND 却 window attached #0，
    // 用户看到的是桌面/黑屏，连报错都出不来。所以：**任何分支都必须 loadContent**。
    let loaded: boolean = false;
    const load = (reason: string): void => {
      if (loaded) {
        return;
      }
      loaded = true;
      windowStage.loadContent('pages/Unlock', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'loadContent succeeded, via %{public}s', reason);
      });
    };
    // 兜底：bootstrap 迟迟不回头也先把页面立起来
    const timer: number = setTimeout(() => {
      hilog.warn(DOMAIN, TAG, 'bootstrap timeout, load anyway');
      load('timeout');
    }, 3000);
    bootstrap(this.context).then((ok: boolean) => {
      clearTimeout(timer);
      hilog.info(DOMAIN, TAG, 'bootstrap ok=%{public}s', ok);
      load('resolved');
    }).catch((e: Error) => {
      clearTimeout(timer);
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', JSON.stringify(e));
      load('rejected');
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
