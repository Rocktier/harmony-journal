import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { APPEARANCE_SYSTEM, AppearanceMode, normalizeAppearance } from '../common/Appearance';

/**
 * 外观偏好的持久化（沙箱 KV，**零权限**）。
 *
 * 为什么不用 AppStorage：AppStorage 只活在内存里，杀进程后"我选的深色"就没了
 * ⇒ 每次冷启动都退回跟随系统，对"晚上写日记"的人是反复打扰。
 *
 * ⚠️ 用 `getPreferencesSync`（同步）：启动时要在 loadContent 之前把模式定下来，
 *   异步版会让首帧先闪一下浅色再变深（夜间场景下就是一次刺眼）。
 */
const STORE_NAME: string = 'appearance';
const KEY_MODE: string = 'mode';

const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

export class AppearancePrefs {
  private store: preferences.Preferences | null = null;

  /** 必须在读写前调用（页面里传 `getContext(this)`，ability 里传 `this.context`） */
  open(ctx: common.Context): void {
    try {
      this.store = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'open appearance prefs failed: %{public}s', JSON.stringify(e));
      this.store = null;
    }
  }

  /** 读不到（或没 open）一律按"跟随系统" —— 默认值必须是"不打扰" */
  get(): AppearanceMode {
    if (this.store === null) {
      return APPEARANCE_SYSTEM;
    }
    try {
      return normalizeAppearance(this.store.getSync(KEY_MODE, APPEARANCE_SYSTEM) as string);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read appearance failed: %{public}s', JSON.stringify(e));
      return APPEARANCE_SYSTEM;
    }
  }

  set(mode: AppearanceMode): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(KEY_MODE, normalizeAppearance(mode));
      this.store.flush();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save appearance failed: %{public}s', JSON.stringify(e));
    }
  }
}
