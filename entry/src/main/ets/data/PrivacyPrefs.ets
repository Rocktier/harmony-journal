import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 「已同意隐私政策」的持久化（沙箱 KV，**零权限**）。
 *
 * 为什么需要它：华为《审核指南》7.5 要求**首次启动时以显著方式提示用户阅读隐私政策**
 * （弹窗 / 注册登录页展示）。2026-10-20 Rock私记 1.0.0 就栽在这一条 —— 原来政策
 * 只放在「设置 → 隐私政策」里，不主动弹 = 不合规。
 *
 * 为什么不用 AppStorage：AppStorage 只活在内存里，杀进程后标记就没了 ⇒
 * 每次冷启动都重新弹一次同意框，那是骚扰不是合规。所以必须落 preferences。
 *
 * ⚠️ 与 AppearancePrefs 同款用 `getPreferencesSync`（同步）：解锁页首帧就要据此
 *    决定"渲染隐私门还是渲染解锁表单"，异步读会让第一屏闪一下错误内容。
 */
const STORE_NAME: string = 'privacy';
const KEY_AGREED: string = 'agreed';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

export class PrivacyPrefs {
  private store: preferences.Preferences | null = null;

  /** 必须在读写前调用（页面里传 `getContext(this)`） */
  open(ctx: common.Context): void {
    try {
      this.store = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'open privacy prefs failed: %{public}s', JSON.stringify(e));
      this.store = null;
    }
  }

  /**
   * 是否已同意。
   * ⚠️ 读不到一律按**未同意**（默认值是"再问一次"而不是"放行"）：
   *    合规项宁肯多弹一次，不能漏弹一次。
   */
  isAgreed(): boolean {
    if (this.store === null) {
      return false;
    }
    try {
      return this.store.getSync(KEY_AGREED, false) as boolean;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read privacy flag failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 记下同意（写完立即 flush，别等系统调度） */
  setAgreed(): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(KEY_AGREED, true);
      this.store.flush();
      hilog.info(DOMAIN, TAG, 'privacy agreed, persisted');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save privacy flag failed: %{public}s', JSON.stringify(e));
    }
  }
}
