/**
 * 时间胶囊的解锁日期选择对话框（@CustomDialog + DatePicker）
 *
 * 为什么用自定义 Dialog 而不是 promptAction.showDialog：后者只能摆
 * 标题/正文/按钮，**内嵌不了 DatePicker** —— 选日期必须走 CustomDialog。
 *
 * 为什么限定「明天 ~ 十年后」：
 *   - 下限明天：当天就解锁的胶囊没有意义（earliestUnlock 同一口径，见 NoteMeta）；
 *   - 上限十年：再往上走，用户早就忘了这回事，解锁时只会一脸茫然
 *     （且 DatePicker 的 selected 值过远，首帧定位也会怪）。
 */
import { ThemePalette } from '../theme/ThemePalette';
import { RJ_FS_BODY, RJ_FS_CAPTION, RJ_FS_META, RJ_RADIUS_LG, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM } from '../theme/RjTokens';

/** 可选范围上限：从今天算起往后十年（用户改不动这个边界，见 selected 的钳制） */
const MAX_YEARS_AHEAD: number = 10;

/**
 * ⚠️ 必须是 `@CustomDialog` 而不是 `@Component`：CustomDialogController 的 builder
 *    只收 @CustomDialog 装饰的 struct —— 漏了这个装饰器，运行期 new controller
 *    时报 "class constructor cannot called without 'new'" 直接崩（2026-10-20 实测）。
 */
@CustomDialog
export struct CapsuleDateDialog {
  /**
   * @CustomDialog 的硬性约定：struct 里必须有一个 CustomDialogController 属性
   * （框架用它回填控制器；编译期 10905211 强制检查，漏了过不了）。
   * 声明为**可选** —— 创建方不传，框架自己回填（官方示例同款写法）。
   */
  controller?: CustomDialogController;
  /** 运行时色板（与全局同一份 @StorageLink） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  /** 当前选中的解锁时刻（毫秒，本地零点） */
  unlockAt: number = 0;
  /** 确认回调（把选中的 unlockAt 交出去） */
  onConfirm: (unlockAt: number) => void = () => {};
  /** 取消回调：必须由调用方提供 —— @CustomDialog 的关闭要经 controller */
  onCancel: () => void = () => {};

  /** 今天（零点）—— 供 DatePicker 做 selected 的兜底钳制 */
  private today(): Date {
    const now: Date = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }

  /**
   * 可选范围的**下限 = 明天**零点。
   *
   * ⚠️ 与 Editor.openCapsuleDialog 的 earliestUnlock 同口径（2026-10-20 修）：
   *    原来这里 start 传的是今天，用户能选到"当天解锁"的胶囊 —— 与产品承诺
   *    「最早明天」自相矛盾，且当天解锁的胶囊没有意义（建完就能看，锁了个寂寞）。
   */
  private startDate(): Date {
    const t: Date = this.today();
    return new Date(t.getFullYear(), t.getMonth(), t.getDate() + 1);
  }

  build() {
    Column() {
      Text('什么时候能打开？')
        .fontSize(RJ_FS_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .margin({ top: RJ_SP_LG })
      Text('最早明天 · 最晚十年后')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .margin({ top: RJ_SP_SM })

      /**
       * DatePicker：type 'date'，本地时区。
       * selected 传入前由调用方保证 ≥ 明天零点；这里再兜底钳一次，
       * 防止调用方传了 0 或过去时刻导致首帧定位错乱。
       */
      DatePicker({
        start: this.startDate(),
        end: new Date(new Date().getFullYear() + MAX_YEARS_AHEAD, 11, 31),
        selected: this.unlockAt > 0 ? new Date(this.unlockAt) : new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate() + 1)
      })
        .layoutWeight(1)
        .onChange((res: DatePickerResult) => {
          // res.year/month/day 是选中值；month 从 0 起（SDK 语义）
          if (res.year !== undefined && res.month !== undefined && res.day !== undefined) {
            this.unlockAt = new Date(res.year, res.month, res.day).getTime();
          }
        })

      Row() {
        Button('取消', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.palette.text2)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel();
          })
        Button('就定这天', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.bg)
          .backgroundColor(this.palette.accent)
          .borderRadius(RJ_RADIUS_LG)
          .layoutWeight(1)
          .margin({ left: RJ_SP_MD })
          .onClick(() => {
            this.onConfirm(this.unlockAt);
          })
      }
      .width('100%')
      .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_MD, bottom: RJ_SP_LG })
    }
    .width('100%')
    .backgroundColor(this.palette.card)
  }
}
