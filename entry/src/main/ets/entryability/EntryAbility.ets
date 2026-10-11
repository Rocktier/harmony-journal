import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

import { applyAppearance } from '../common/AppearanceApply';
import { AppearancePrefs } from '../data/AppearancePrefs';
import { bootstrap } from '../data/NoteStoreHolder';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

export default class EntryAbility extends UIAbility {
  /**
   * 应用用户选的外观（**默认跟随系统**）。
   *
   * ⚠️ 原来这里写死 `COLOR_MODE_DARK`（"Journal 默认深色"），代价是：
   *   ① `resources/dark/` 限定符**永远不会生效**（系统浅色时我们仍强制深色）；
   *   ② 上架审核要求"适配深/浅色模式"，强制单色属于高风险项。
   * 深色观感一点没丢 —— 深色值搬进了 `resources/dark/element/color.json`，
   * 系统在深色模式下走的仍是原来那套 `#000000` / `#FFFFFF`。
   *
   * 2026-10-12 起：读用户偏好（沙箱 KV）—— 没选过就是"跟随系统"（不打扰）；
   * 用户显式选了深/浅色就按他的来。必须在 loadContent **之前**定下来，
   * 否则首帧会先闪一下浅色再变深（晚上被窝里写日记 = 一次刺眼）。
   */
  private applyColorMode(): void {
    try {
      const prefs: AppearancePrefs = new AppearancePrefs();
      prefs.open(this.context);
      applyAppearance(this.context, prefs.get());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'apply appearance failed: %{public}s', JSON.stringify(e));
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyColorMode();
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
