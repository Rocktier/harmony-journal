/**
 * 运行时色板（深浅两套，**不走 setColorMode 运行时切换**）。
 *
 * 为什么要有它（2026-10-16 装机实测的血泪）：
 *   `ApplicationContext.setColorMode()` 在运行中调用会触发 **UIContent 重建**，
 *   页面栈保不住 —— 实测：Editor 里切深色再返回，直接退回桌面（`state change to 4`）；
 *   偶尔栈恢复了，Index 的时光列表也是空的（LazyForEach 的通知在页面不可见时丢失）。
 *   这是框架级行为，绕不过去。
 *
 * 正解（社区公认「不重建换肤」）：颜色值放 **AppStorage**，页面用 `@StorageLink` 绑。
 *   切换 = `AppStorage.Set('palette', new ThemePalette(dark))` ⇒ 所有绑定变量重新赋值
 *   ⇒ 全 UI 重绘，而**页面栈、输入中的文字、滚动位置、焦点全部原样保留**。
 *
 * 与 color.json 的关系：
 *   - `base/` `dark/` 两套 color.json **保留** —— 冷启动首帧前 `EntryAbility` 仍会
 *     `setColorMode` 一次（保系统 UI：状态栏/启动窗口/输入法跟用户选择一致）。
 *   - 运行中**不再调用** setColorMode，深浅完全由本对象驱动。
 *   - 两套值必须与 color.json 保持一致（改色时两边一起改，单测有断言兜底）。
 */

/** token 名清单（单测遍历用，也防两边漏 key） */
export const PALETTE_KEYS: string[] = [
  'bg', 'text', 'text2', 'text3', 'line', 'card', 'g100', 'accent', 'brand',
  'heat1', 'heat2', 'heat3', 'heat4', 'danger', 'sel'
];

/**
 * 当前生效的色板（AppStorage 里的那一个）。
 * ⚠️ ArkTS 不允许对象字面量赋 Record，也不允许 `this as Record<...>` 索引写，
 *    所以字段逐个显式声明 + 构造时逐个赋值（啰嗦，但这是 ArkTS 唯一稳的写法）。
 */
export class ThemePalette {
  /** 是否深色（切换时重建对象的依据） */
  dark: boolean = false;

  bg: string = '#FAF8F3';
  text: string = '#E6000000';
  text2: string = '#99000000';
  text3: string = '#8F000000';
  line: string = '#1F000000';
  card: string = '#FFFFFF';
  g100: string = '#E3E6E8';
  accent: string = '#191919';
  brand: string = '#8A4B1F';
  heat1: string = '#EFE0D2';
  heat2: string = '#D9B894';
  heat3: string = '#B3855C';
  heat4: string = '#8A4B1F';
  danger: string = '#C72B20';
  sel: string = '#30191919';

  constructor(dark: boolean) {
    this.dark = dark;
    if (dark) {
      // 与 resources/dark/element/color.json 逐值对齐（palette.test.ts 兜底）
      this.bg = '#000000';
      this.text = '#DBFFFFFF';
      this.text2 = '#99FFFFFF';
      this.text3 = '#80FFFFFF';
      this.line = '#24FFFFFF';
      this.card = '#303030';
      this.g100 = '#1A1A1A';
      this.accent = '#F0EBE0';
      this.brand = '#C48A5E';
      this.heat1 = '#3D2E24';
      this.heat2 = '#5C4634';
      this.heat3 = '#8A6547';
      this.heat4 = '#C48A5E';
      this.danger = '#FF4A3D';
      this.sel = '#33F0EBE0';
    }
    // 浅色 = 字段默认值（base/color.json）
  }
}

/** 按深浅取色板（每次新对象 —— AppStorage 换引用才能触发 @StorageLink 更新） */
export function paletteFor(dark: boolean): ThemePalette {
  return new ThemePalette(dark);
}
