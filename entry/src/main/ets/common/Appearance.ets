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

/** 是否"当前是深色"—— 用于按钮图标（☀ / ☾）。跟随系统时**不知道**系统当前深浅，返回 null。 */
export function isDarkMode(mode: AppearanceMode): boolean | null {
  if (mode === APPEARANCE_DARK) {
    return true;
  }
  if (mode === APPEARANCE_LIGHT) {
    return false;
  }
  return null;
}

/** 图标（一段文本，避免引入图标资源，符合"极致小"） */
export function appearanceIcon(mode: AppearanceMode): string {
  const dark: boolean | null = isDarkMode(mode);
  if (dark === null) {
    return '半';
  }
  return dark ? '☾' : '☀';
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
