/**
 * 圆形图标按钮（Chevron） —— 2026-10-15 党哥：全局替换裸的 `<` `>` 字符按钮。
 *
 * 为什么是它（第一性原则 + 鸿蒙最新 UI 建议）：
 *  - 裸 `<` `>` 是字符、无按压反馈、读屏不报"按钮"，是 A 类无障碍问题，且"太随意"。
 *  - 查 HarmonyOS NEXT 设计规范：导航/返回用 **chevron（V 形线条箭头）**，图标按钮用
 *    **`ButtonType.Circle`**（圆形图标按钮，鸿蒙官方推荐的"有质感"形态），按压态自带高亮（stateEffect）。
 *  - chevron **自绘 Path**（两条线 V 形，Material/Apple 同款），不依赖系统 Symbol 资源
 *    （`sys.symbol.chevron_*` 在部分模拟器运行时不显示，实测踩过）；线条圆角端点更优雅。
 *  - chrome 全中性（纸·墨·茶）：箭头用 rj_text 墨色，背景透明（不抢视线，符合"墨是 chrome"）。
 *
 * ⚠️ 2026-10-15 修尺寸 bug（像素实锤）：
 *    `Path.commands` 的坐标单位是**物理像素 px**（path.d.ts："The unit is px"），
 *    不是随组件缩放的逻辑坐标 —— 首版按 22 单位直接写，3.5x 屏上箭头只渲染成
 *    **16×24px**（40vp 按钮里一个小点，视觉上根本不像"返回按钮"）。
 *    昨天验收只数了"有没有墨色像素"（252px）就判通过，**没量尺寸**，所以漏了。
 *    修法：坐标乘 `display.getDefaultDisplaySync().densityPixels`，任何密度下都占满视口。
 *    ⚠️ 同类教训：图标类改动**必须量尺寸**，不能只量"有没有像素"。
 */
import { display } from '@kit.ArkUI';

/** 图标视口（vp） */
const ICON_SIZE: number = 22;

@Component
export struct ChevronButton {
  /** 'left' = 左 chevron（返回/上一月）；'right' = 右 chevron（下一月） */
  side: string = 'left';
  /** 无障碍标签（如"上一个月""返回"） */
  label: string = '';
  /** 点击回调 */
  onClickHandler: () => void = () => {};

  /** 22 单位逻辑坐标 → 物理像素（build 里不能写局部函数，故提为方法） */
  private s(n: number): number {
    const d: number = display.getDefaultDisplaySync().densityPixels;
    return Math.round(n * d * 10) / 10;
  }

  /** V 形线条箭头（22×22 坐标系）：左=顶点在左，右=顶点在右 */
  private commands(): string {
    if (this.side === 'right') {
      return 'M' + this.s(7) + ' ' + this.s(4) + ' L' + this.s(15) + ' ' + this.s(12)
        + ' L' + this.s(7) + ' ' + this.s(20);
    }
    return 'M' + this.s(15) + ' ' + this.s(4) + ' L' + this.s(7) + ' ' + this.s(12)
      + ' L' + this.s(15) + ' ' + this.s(20);
  }

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Path()
        .width(ICON_SIZE)
        .height(ICON_SIZE)
        .commands(this.commands())
        .stroke($r('app.color.rj_text'))
        .strokeWidth(2.4)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        .fill('none')
    }
    .width(40)
    .height(40)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.label)
    .onClick(() => {
      this.onClickHandler();
    })
  }
}
