import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { APPEARANCE_DARK, APPEARANCE_LIGHT, AppearanceMode } from './Appearance';

/**
 * 把"用户选的外观"落到系统（`ApplicationContext.setColorMode`）。
 *
 * 为什么走系统而不是自己换色板：本应用深浅色是**资源限定符**（`base/` 与 `dark/` 两套
 * `color.json`），系统一改 colorMode，资源自动跟着换 —— 一处生效、全应用一致，
 * 也天然满足"适配深/浅色模式"的审核要求。
 *
 * ⚠️ `COLOR_MODE_NOT_SET` = 跟随系统（默认档）。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

export function applyAppearance(ctx: common.Context, mode: AppearanceMode): void {
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
    hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(e));
  }
}
