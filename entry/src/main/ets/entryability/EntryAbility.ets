import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

import { APPEARANCE_SYSTEM, AppearanceMode, isSystemDarkColorMode, paletteNeedsRefresh } from '../common/Appearance';
import {
  applyAppearanceAtStartup, applySystemDark, currentPaletteDark, systemIsDark
} from '../common/AppearanceApply';
import { AppearancePrefs } from '../data/AppearancePrefs';
import { CARD_INTENT_WRITE_TODAY } from '../data/JournalCardData';
import { bootstrap } from '../data/NoteStoreHolder';

const DOMAIN: number = 0xD002;
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
   *
   * 2026-10-26 再改：app 层面的 colorMode 一律 NOT_SET（跟随系统），
   * 深/浅偏好只体现在色板（palette）上 —— 详见 applyAppearanceAtStartup 的注释。
   * 原因：app 一旦被钉死成 DARK/LIGHT，系统主题变化就不再回调 onConfigurationUpdate，
   * "跟随系统"就永远跟不上系统（华为复评实测）。
   */
  private applyColorMode(): void {
    try {
      const prefs: AppearancePrefs = new AppearancePrefs();
      prefs.open(this.context);
      applyAppearanceAtStartup(this.context, prefs.get());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'apply appearance failed: %{public}s', JSON.stringify(e));
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureIntent(want);
    this.applyColorMode();
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  /**
   * 桌面卡片点「写今天」→ postCardAction('router') 拉起本应用时带 `intent`。
   *
   * 两种进入路径都要接住：
   *  - 应用没运行：onCreate 的 want 里就有 ⇒ 存进 AppStorage，
   *    用户解锁后 Index 页消费 → 直达编辑器；
   *  - 应用在运行（singleton）：走 onNewWant ⇒ 存进 AppStorage，
   *    Index 页的 @Watch 立刻消费 → 直达编辑器。
   *
   * ⚠️ 这里**只存意图，不存任何内容**（卡片那边本来也没有内容可传）。
   */
  onNewWant(want: Want): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.captureIntent(want);
  }

  /**
   * 把卡片传来的意图存进 AppStorage（供 Index 页消费）
   *
   * ⚠️⚠️ **卡片参数不能按自定义键名取**（2026-10-26 实测，日志实证）：
   *    卡片里写 `params: { intent: 'writeToday' }`，系统拉起 ability 时传过来的
   *    want.parameters 变成：
   *      { "a9": "writeToday", "formID": 906329980, "params": "{\"a9\":\"writeToday\"}", ... }
   *    —— **自定义键被重命名成 a0/a1/a2…（按位置排，本例排到了 a9）**，
   *    并且原样塞进 `params` 字段的 JSON 字符串里。
   *    ⇒ 只认 `params['intent']` 必然读不到（症状：点了卡片应用起来了，但什么也没发生）。
   *    ⇒ 正确姿势：**按"值"找，不按"键"找**（意图值是唯一语义标记）。
   */
  private captureIntent(want: Want): void {
    try {
      const params: Record<string, Object> | undefined = want.parameters;
      if (params === undefined) {
        hilog.info(DOMAIN, TAG, 'want params undefined');
        return;
      }
      const intent: string = this.pickIntent(params);
      if (intent.length === 0) {
        hilog.info(DOMAIN, TAG, 'no card intent in want');
        return;
      }
      if (intent !== CARD_INTENT_WRITE_TODAY) {
        hilog.warn(DOMAIN, TAG, 'unknown card intent ignored: %{public}s', intent);
        return;
      }
      AppStorage.setOrCreate<string>('pendingIntent', intent);
      hilog.info(DOMAIN, TAG, 'card intent captured: %{public}s', intent);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'capture intent failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 从卡片 want 的参数里取出意图（不依赖键名） */
  private pickIntent(params: Record<string, Object>): string {
    // (a) 系统把卡片自定义参数塞在 params 字段里（JSON 字符串）
    const nested: Object | undefined = params['params'];
    if (typeof nested === 'string') {
      const hit: string = this.findInJson(nested);
      if (hit.length > 0) {
        return hit;
      }
    }
    // (b) 扁平键：自定义键被系统重命名成 a0/a1/…（实测 'intent' → 'a9'）
    for (let i: number = 0; i < 32; i++) {
      const v: Object | undefined = params['a' + i];
      if (typeof v === 'string' && v === CARD_INTENT_WRITE_TODAY) {
        return v;
      }
    }
    return '';
  }

  /** JSON 字符串里找意图值（找不到返回空串） */
  private findInJson(json: string): string {
    try {
      const obj = JSON.parse(json) as Record<string, Object>;
      const keys: string[] = Object.keys(obj);
      for (const k of keys) {
        const v: Object = obj[k];
        if (typeof v === 'string' && v === CARD_INTENT_WRITE_TODAY) {
          return v;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'parse card params failed: %{public}s', JSON.stringify(e));
    }
    return '';
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

  /**
   * 系统深浅变了（用户在控制中心切了深色）。
   *
   * 只在用户选了**跟随系统**时才动色板 —— 显式选了深/浅的人不该被系统覆盖。
   * 走 `applyPaletteMode`（换 AppStorage 里的 palette 对象）而不是 `setColorMode`：
   * 后者会重建 UIContent、页面栈保不住（2026-10-16 实测：切完直接退回桌面）。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    // ⚠️ 不调 super：UIAbility 基类未实现该方法，ArkTS 能编译但运行时抛错，
    //    实测（2026-10-25）表现为应用窗口存在但内容全空（黑屏）。
    try {
      const prefs: AppearancePrefs = new AppearancePrefs();
      prefs.open(this.context);
      const mode: AppearanceMode = prefs.get();
      if (mode !== APPEARANCE_SYSTEM) {
        return;
      }
      // ⚠️ 必须用**回调参数** newConfig.colorMode，不能读 ctx.config.colorMode ——
      //    回调触发那一刻 ctx.config 可能还是旧值，那就会算出"系统没变"，
      //    应用纹丝不动（华为 2026-10-26 复评实测：跟随系统 + 开系统深色 → 不变色）。
      const systemDark: boolean = isSystemDarkColorMode(newConfig.colorMode);
      const cur: boolean | null = currentPaletteDark();
      if (cur !== null && !paletteNeedsRefresh(mode, systemDark, cur)) {
        return;
      }
      applySystemDark(this.context, systemDark);
      hilog.info(DOMAIN, TAG, 'appearance follows system, colorMode=%{public}d dark=%{public}s',
        newConfig.colorMode, systemDark ? 'yes' : 'no');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'follow system failed: %{public}s', JSON.stringify(e));
    }
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    // 兜底：极少数情况下系统主题变化没走到 onConfigurationUpdate（应用在后台时切深色），
    // 回到前台对一次账 —— 跟随系统档下色板必须与系统一致。
    this.syncFollowSystem();
  }

  /** 对账：用户选「跟随系统」时，色板深浅必须等于系统当前深浅。 */
  private syncFollowSystem(): void {
    try {
      const prefs: AppearancePrefs = new AppearancePrefs();
      prefs.open(this.context);
      const mode: AppearanceMode = prefs.get();
      if (mode !== APPEARANCE_SYSTEM) {
        return;
      }
      const systemDark: boolean = systemIsDark(this.context);
      const cur: boolean | null = currentPaletteDark();
      if (cur === null || !paletteNeedsRefresh(mode, systemDark, cur)) {
        return;
      }
      applySystemDark(this.context, systemDark);
      hilog.info(DOMAIN, TAG, 'foreground sync appearance, dark=%{public}s', systemDark ? 'yes' : 'no');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'foreground sync failed: %{public}s', JSON.stringify(e));
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
