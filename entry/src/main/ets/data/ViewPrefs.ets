import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 视图偏好（月历 / 时光）的持久化（沙箱 KV，**零权限**）。
 *
 * 2026-10-14 党哥：原来「月/时光」切换**不记偏好** —— 退出重进永远弹回月视图，
 * 用户的视图选择被反复重置。与 AppearancePrefs 同款理由：不用 AppStorage（只活内存）。
 *
 * ⚠️ `getPreferencesSync` 同步版：aboutToAppear 里要立刻定首帧视图，异步会闪一下默认态。
 */
const STORE_NAME: string = 'viewmode';
const KEY_MODE: string = 'mode';

const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

/** 视图模式：月历（俯视一个月）/ 时光（所有日子倒序流淌） */
export type ViewMode = 'month' | 'timeline';

/** 非法值一律回落 'month' —— 默认值必须是"打开就有仪式感"的那个视图 */
export function normalizeViewMode(v: string): ViewMode {
  return v === 'timeline' ? 'timeline' : 'month';
}

export class ViewPrefs {
  private store: preferences.Preferences | null = null;

  /** 必须在读写前调用（页面里传 `getContext(this)`，ability 里传 `this.context`） */
  open(ctx: common.Context): void {
    try {
      this.store = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'open viewmode prefs failed: %{public}s', JSON.stringify(e));
      this.store = null;
    }
  }

  get(): ViewMode {
    if (this.store === null) {
      return 'month';
    }
    try {
      return normalizeViewMode(this.store.getSync(KEY_MODE, 'month') as string);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read viewmode failed: %{public}s', JSON.stringify(e));
      return 'month';
    }
  }

  set(mode: ViewMode): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(KEY_MODE, normalizeViewMode(mode));
      this.store.flush();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save viewmode failed: %{public}s', JSON.stringify(e));
    }
  }
}
