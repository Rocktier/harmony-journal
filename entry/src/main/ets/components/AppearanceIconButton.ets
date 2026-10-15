/**
 * 外观切换图标按钮（编辑器头部快捷三态：跟随系统 / 深色 / 浅色）
 *
 * 为什么是自绘 Path（2026-10-15，"字体字形当图标"三连败后定的纪律）：
 *  - ☾/☀ Unicode 符号：模拟器字体缺字形 → 渲染成残缺图形（findings §9.3）
 *  - 汉字 随/夜/昼：Button 固定 40×40 的内容区把字形裁掉一角（像素实锤"夜"右下缺损）
 *  - 官方 SymbolGlyph：编译通过、运行时不显示（findings §9.1）
 *  - iconfont（自带字体文件）：为一个按钮拖几十 KB 字体违背极致小，
 *    而且"交给字体渲染"正是三次翻车的共同根因 —— 图标不再走任何字体路线。
 *
 * ⚠️ Path.commands 的坐标单位是**物理像素 px**（查过 path.d.ts："The unit is px"），
 *    不是随组件缩放的逻辑坐标 —— 首版按 24 单位逻辑坐标写，月亮只渲染出 12×12px
 *    （40vp 按钮的 1/10，像素实锤）。所以所有坐标先乘 `iconScale()`（屏幕密度），
 *    组件视口仍用 vp，任何密度下图标都精确占满。
 * 造型取自通用图形语言（Feather 风格，22 单位坐标空间）：
 * 月亮 = 实心新月，太阳 = 圆 + 八射线，跟随系统 = 左半填充圆。
 */
import { display } from '@kit.ArkUI';
import { AppearanceMode, appearanceLabel, isDarkMode } from '../common/Appearance';
import { RJ_RADIUS_SM } from '../theme/RjTokens';

/** 图标视口（vp）—— 与坐标空间同尺寸，commands 乘密度后正好填满 */
const ICON_SIZE: number = 22;

@Component
export struct AppearanceIconButton {
  /** 当前外观模式（决定画哪个图标） */
  mode: AppearanceMode = 'system';
  /** 点击回调（三态轮转由调用方负责） */
  onToggle: () => void = () => {};

  /** 22 单位逻辑坐标 → 物理像素（build 里不能写局部函数，故提为方法） */
  private s(n: number): number {
    const d: number = display.getDefaultDisplaySync().densityPixels;
    return Math.round(n * d * 10) / 10;
  }

  /** 深色：实心新月（Feather moon 缩放到 22 空间） */
  private moonCmd(): string {
    return 'M' + this.s(19.26) + ' ' + this.s(11.73)
      + ' A' + this.s(8.25) + ' ' + this.s(8.25) + ' 0 1 1 ' + this.s(10.28) + ' ' + this.s(2.75)
      + ' A' + this.s(6.42) + ' ' + this.s(6.42) + ' 0 0 0 ' + this.s(19.26) + ' ' + this.s(11.73) + ' Z';
  }

  /** 浅色：太阳 = 圆 + 八条射线（描边） */
  private sunCmd(): string {
    return 'M' + this.s(6.6) + ' ' + this.s(11)
      + ' A' + this.s(4.4) + ' ' + this.s(4.4) + ' 0 1 1 ' + this.s(15.4) + ' ' + this.s(11)
      + ' A' + this.s(4.4) + ' ' + this.s(4.4) + ' 0 1 1 ' + this.s(6.6) + ' ' + this.s(11)
      + ' M' + this.s(11) + ' ' + this.s(2) + ' L' + this.s(11) + ' ' + this.s(4)
      + ' M' + this.s(11) + ' ' + this.s(18) + ' L' + this.s(11) + ' ' + this.s(20)
      + ' M' + this.s(2) + ' ' + this.s(11) + ' L' + this.s(4) + ' ' + this.s(11)
      + ' M' + this.s(18) + ' ' + this.s(11) + ' L' + this.s(20) + ' ' + this.s(11)
      + ' M' + this.s(8.17) + ' ' + this.s(8.17) + ' L' + this.s(6.76) + ' ' + this.s(6.76)
      + ' M' + this.s(13.83) + ' ' + this.s(13.83) + ' L' + this.s(15.24) + ' ' + this.s(15.24)
      + ' M' + this.s(8.17) + ' ' + this.s(13.83) + ' L' + this.s(6.76) + ' ' + this.s(15.24)
      + ' M' + this.s(13.83) + ' ' + this.s(8.17) + ' L' + this.s(15.24) + ' ' + this.s(6.76);
  }

  /** 跟随系统：左半填充圆（一半明一半暗） */
  private autoFillCmd(): string {
    return 'M' + this.s(11) + ' ' + this.s(2.75)
      + ' A' + this.s(8.25) + ' ' + this.s(8.25) + ' 0 0 0 ' + this.s(11) + ' ' + this.s(19.25) + ' Z';
  }

  /** 跟随系统：外圈描边 */
  private autoRingCmd(): string {
    return 'M' + this.s(2.75) + ' ' + this.s(11)
      + ' A' + this.s(8.25) + ' ' + this.s(8.25) + ' 0 1 1 ' + this.s(19.25) + ' ' + this.s(11)
      + ' A' + this.s(8.25) + ' ' + this.s(8.25) + ' 0 1 1 ' + this.s(2.75) + ' ' + this.s(11);
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Stack() {
        if (isDarkMode(this.mode) === true) {
          Path()
            .width(ICON_SIZE)
            .height(ICON_SIZE)
            .commands(this.moonCmd())
            .fill($r('app.color.rj_text2'))
        } else if (isDarkMode(this.mode) === false) {
          Path()
            .width(ICON_SIZE)
            .height(ICON_SIZE)
            .commands(this.sunCmd())
            .fill('none')
            .stroke($r('app.color.rj_text2'))
            .strokeWidth(1.8)
            .strokeLineCap(LineCapStyle.Round)
        } else {
          Stack() {
            Path()
              .width(ICON_SIZE)
              .height(ICON_SIZE)
              .commands(this.autoFillCmd())
              .fill($r('app.color.rj_text2'))
            Path()
              .width(ICON_SIZE)
              .height(ICON_SIZE)
              .commands(this.autoRingCmd())
              .fill('none')
              .stroke($r('app.color.rj_text2'))
              .strokeWidth(1.8)
          }
        }
      }
    }
    .backgroundColor($r('app.color.rj_card'))
    .borderRadius(RJ_RADIUS_SM)
    .width(40)
    .height(40)
    // 40×40 视觉 + 热区补足 44（与全 app 触控纪律一致）
    .responseRegion({ x: -2, y: -2, width: 44, height: 44 })
    .accessibilityText('外观：' + appearanceLabel(this.mode))
    .onClick(() => {
      this.onToggle();
    })
  }
}
