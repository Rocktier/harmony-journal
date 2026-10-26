/**
 * 外观模式（日 / 夜 / 跟随系统）—— **纯逻辑，零设备 API**，便于 CI 单测。
 *
 * 为什么单独抽这一层：
 *   存储（preferences）与系统设置（setColorMode）都是设备 API，CI 上跑不了；
 *   而"模式有哪些、未知值怎么回落、显示名叫什么"是纯判断，必须能测。
 *
 * ⚠️ 与 `Theme`（若有）不同：本应用深浅色走**资源限定符**（`base/` 与 `dark/` 两套 color.json），
 *   切换靠 `ApplicationContext.setColorMode` —— 所以模式值只是"用户意图"，不自己管色板。
 */

/** 'system' | 'light' | 'dark'（不用字面量联合类型，保证 ArkTS 各版本都能编译） */
export type AppearanceMode = string;

/** 跟随系统（默认） */
export const APPEARANCE_SYSTEM: string = 'system';
/** 始终浅色 */
export const APPEARANCE_LIGHT: string = 'light';
/** 始终深色（夜间模式） */
export const APPEARANCE_DARK: string = 'dark';

/** 未知值一律回落「跟随系统」（脏数据 / 老版本不会渲染出 undefined 行为） */
export function normalizeAppearance(value: string): AppearanceMode {
  if (value === APPEARANCE_LIGHT || value === APPEARANCE_DARK) {
    return value;
  }
  return APPEARANCE_SYSTEM;
}

/** 显示名（设置页三态用） */
export function appearanceLabel(mode: AppearanceMode): string {
  if (mode === APPEARANCE_LIGHT) {
    return '浅色';
  }
  if (mode === APPEARANCE_DARK) {
    return '深色';
  }
  return '跟随系统';
}

/** 是否"当前是深色"—— 用于图标选择（AppearanceIconButton 画月亮还是太阳）。跟随系统时**不知道**系统当前深浅，返回 null。 */
export function isDarkMode(mode: AppearanceMode): boolean | null {
  if (mode === APPEARANCE_DARK) {
    return true;
  }
  if (mode === APPEARANCE_LIGHT) {
    return false;
  }
  return null;
}

/**
 * 结合「用户意图」与「系统当前深浅」解出**该用哪套色板**（2026-10-25 华为反馈修复）。
 *
 * 为什么必须有它：之前直接用 `isDarkMode(mode) === true` 定色板，而
 * `isDarkMode('system')` 返回 **null** ⇒ `null === true` 为 **false**
 * ⇒ **跟随系统时色板恒为浅色**，系统切深色应用毫无反应（审核员实测：
 * 「设置-深浅跟随系统无变化」）。
 *
 * 纯逻辑：系统深浅由调用方（`AppearanceApply` 读 `ctx.config.colorMode`）传入，
 * 本函数不碰设备 API ⇒ CI 可测。
 */
export function resolveDark(mode: AppearanceMode, systemDark: boolean): boolean {
  if (mode === APPEARANCE_DARK) {
    return true;
  }
  if (mode === APPEARANCE_LIGHT) {
    return false;
  }
  return systemDark;
}

/**
 * 系统 `Configuration.colorMode` 的取值（来自 `ConfigurationConstant.ColorMode`）。
 *
 * 抄成常量是为了让「判定系统深浅」能留在**纯逻辑层**——CI 上跑不了
 * `@kit.AbilityKit` 的 ConfigurationConstant，但可以测这个数值映射。
 * ⚠️ 改前先对一眼 SDK：
 *   `NOT_SET = -1, DARK = 0, LIGHT = 1`（DARK 是 0 不是 1，别记反）。
 */
export const COLOR_MODE_NOT_SET: number = -1;
export const COLOR_MODE_DARK: number = 0;
export const COLOR_MODE_LIGHT: number = 1;

/**
 * 系统当前是否深色（由 `Configuration.colorMode` 数值判定）。
 *
 * 只有 DARK 算深色；NOT_SET / LIGHT 都算浅色（读不到时回落浅色，
 * 与修复前行为一致，不会更差）。
 */
export function isSystemDarkColorMode(colorMode: number | undefined): boolean {
  return colorMode !== undefined && colorMode === COLOR_MODE_DARK;
}

/**
 * 色板要不要跟着系统重算（**跟随系统**档的守门）。
 *
 * 2026-10-26 华为复评反馈：「选择跟随系统，打开系统深色模式后，
 * 需切换其他模式重新选择跟随系统才可变为深色」——
 * 根因是系统深浅只在**切模式那一刻**读一次，系统主题变化后没人重算色板。
 *
 * @param mode 用户选的外观档
 * @param systemDark 系统当前是否深色
 * @param currentDark 当前色板是否深色
 * @returns true = 需要重算并替换 palette
 */
export function paletteNeedsRefresh(mode: AppearanceMode, systemDark: boolean, currentDark: boolean): boolean {
  // 显式选了深/浅的人不该被系统覆盖
  if (mode !== APPEARANCE_SYSTEM) {
    return false;
  }
  return systemDark !== currentDark;
}

/**
 * 点一下切到哪一档（编辑器那个快捷按钮用）。
 *
 * 顺序：跟随系统 → 深色 → 浅色 → 跟随系统。
 * 为什么深色排在浅色前面：这是**夜间写日记**的高频动作
 * （党哥 2026-10-12：很多人晚上在被窝里写，不能太亮）⇒ 从"跟随"点一下就直接到深色。
 */
export function nextAppearance(mode: AppearanceMode): AppearanceMode {
  if (mode === APPEARANCE_SYSTEM) {
    return APPEARANCE_DARK;
  }
  if (mode === APPEARANCE_DARK) {
    return APPEARANCE_LIGHT;
  }
  return APPEARANCE_SYSTEM;
}
