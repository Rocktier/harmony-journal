import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

import { APPEARANCE_DARK, APPEARANCE_LIGHT, AppearanceMode, resolveDark } from './Appearance';
import { ThemePalette } from '../theme/ThemePalette';

const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

/**
 * 启动时定系统色板（**只准在 onCreate / loadContent 之前调一次**）。
 *
 * ⚠️ 运行中不要再调 `setColorMode`：它触发 UIContent 重建，页面栈保不住 ——
 * 2026-10-16 装机实测：Editor 里切深色再返回直接退回桌面；栈偶尔恢复了，
 * Index 时光列表也是空的。详见 ThemePalette 头注。
 * 这里保留它只为：启动窗口 / 状态栏 / 输入法等**系统 UI** 与用户选择一致。
 */
/**
 * 系统当前是否深色（**跟随系统模式的唯一依据**）。
 *
 * `ctx.config.colorMode` 在 `onCreate` 与 `onConfigurationUpdate` 里都可用；
 * 读不到（undefined / NOT_SET）一律当浅色 —— 与修复前的行为一致，不会更差。
 */
export function systemIsDark(ctx: common.Context): boolean {
  try {
    const cfg = (ctx as common.UIAbilityContext).config;
    const cm = cfg === undefined ? undefined : cfg.colorMode;
    return cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read system colorMode failed: %{public}s', JSON.stringify(e));
    return false;
  }
}

export function applyAppearanceAtStartup(ctx: common.Context, mode: AppearanceMode): void {
  try {
    const app: common.ApplicationContext = (ctx as common.UIAbilityContext).getApplicationContext();
    if (mode === APPEARANCE_DARK) {
      app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === APPEARANCE_LIGHT) {
      app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      app.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'startup setColorMode failed: %{public}s', JSON.stringify(e));
  }
  // 色板进 AppStorage（页面 @StorageLink 绑它）—— 首帧前就位，不闪默认色。
  // 跟随系统 ⇒ 按系统**当前**深浅定（旧代码在这里恒给浅色，见 resolveDark 注释）
  AppStorage.SetOrCreate('palette', new ThemePalette(resolveDark(mode, systemIsDark(ctx))));
}

/**
 * 运行时切色（用户点按钮/设置页 chip）—— **换色板对象，不动页面栈**。
 *
 * 所有页面/组件用 `@StorageLink('palette') palette: ThemePalette` 绑色，
 * 这里 Set 新对象 ⇒ 全 UI 重绘，栈/输入/滚动/焦点全保留。
 * 系统栏不再由 setColorMode 带，手动补（不补的话状态栏还是旧色的字）。
 */
export function applyPaletteMode(ctx: common.Context, mode: AppearanceMode): void {
  const dark: boolean = resolveDark(mode, systemIsDark(ctx));
  AppStorage.Set('palette', new ThemePalette(dark));
  syncSystemBars(ctx, dark);
}

/** 状态栏文字/底色手动跟随（不再有 setColorMode 代劳） */
export function syncSystemBars(ctx: common.Context, dark: boolean): void {
  window.getTopWindow(ctx as common.UIAbilityContext).then((win: window.Window) => {
    try {
      win.setWindowSystemBarProperties({
        statusBarColor: dark ? '#000000' : '#FAF8F3',
        statusBarContentColor: dark ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(e));
    }
  }).catch((e: Error) => {
    hilog.warn(DOMAIN, TAG, 'getTopWindow failed: %{public}s', JSON.stringify(e));
  });
}
