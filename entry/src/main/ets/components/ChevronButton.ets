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
 */
@Component
export struct ChevronButton {
  /** 'left' = 左 chevron（返回/上一月）；'right' = 右 chevron（下一月） */
  side: string = 'left';
  /** 无障碍标签（如"上一个月""返回"） */
  label: string = '';
  /** 点击回调 */
  onClickHandler: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      // V 形线条箭头（22×22 坐标系）：左=顶点在左，右=顶点在右
      Path()
        .width(22)
        .height(22)
        .commands(this.side === 'right' ? 'M7 4 L15 12 L7 20' : 'M15 4 L7 12 L15 20')
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
