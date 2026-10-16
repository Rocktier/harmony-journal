import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { unlockWith, setupVault, unlockWithBiometric, hasBiometric, isFirstRun } from '../data/NoteStoreHolder';
import { RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_DISPLAY, RJ_FS_HEADING, RJ_FS_META, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_TOP_INSET, RJ_SP_VOID, RJ_SP_XL } from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 解锁页（Phase 8 / 决策 4）：替代开发期 DEV_UNLOCK_BYPASS。
 *
 * 流程：
 *  - 启动 → EntryAbility.bootstrap 已备好 salt + 沙箱根 → 进本页
 *  - 首次运行：让用户「设置主密码」（≥6 位，两次一致）→ 生成随机主密钥 + 写两份备份（密码 + 生物）
 *  - 之后运行：优先显示「使用指纹/面容解锁」；生物通过直接进应用，无需再输密码
 *  - 生物不可用/失败/取消 → 降级主密码（永远能解锁）
 *
 * ⚠️ 主密钥随机生成、只存内存；密码与生物各存一份备份互为兜底。忘密码 ≠ 丢数据（可用生物）。
 * ⚠️ 模拟器 / 无生物设备：生物路径会失败并自动降级主密码，不会卡在解锁页。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

@Entry
@Component
struct Unlock {
  /** 运行时色板（深浅切换 = AppStorage 换对象，页面栈不动；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  @State private password: string = '';
  @State private confirm: string = '';
  @State private error: string = '';
  @State private firstRun: boolean = isFirstRun();
  @State private bioAvailable: boolean = false;

  aboutToAppear(): void {
    if (!this.firstRun) {
      hasBiometric().then((ok: boolean) => {
        this.bioAvailable = ok;
      }).catch(() => {
        this.bioAvailable = false;
      });
    }
  }

  private async doBio(): Promise<void> {
    const ok: boolean = await unlockWithBiometric();
    if (ok) {
      router.replaceUrl({ url: 'pages/Index' }).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'replaceUrl failed: %{public}s', JSON.stringify(e));
      });
    } else {
      this.error = '生物解锁失败，请用主密码';
    }
  }

  private async doUnlock(): Promise<void> {
    if (this.firstRun) {
      if (this.password.length < 6) {
        this.error = '主密码至少 6 位';
        return;
      }
      if (this.password !== this.confirm) {
        this.error = '两次输入不一致';
        return;
      }
      const ok: boolean = await setupVault(this.password);
      if (!ok) {
        this.error = '建库失败，请重试';
        return;
      }
      this.goIndex();
      return;
    }
    if (this.password.length === 0) {
      this.error = '请输入主密码';
      return;
    }
    const ok: boolean = await unlockWith(this.password);
    if (ok) {
      this.goIndex();
    } else {
      this.error = '密码不正确，或数据已损坏/不兼容';
    }
  }

  private goIndex(): void {
    router.replaceUrl({ url: 'pages/Index' }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'replaceUrl failed: %{public}s', JSON.stringify(e));
    });
  }

  build() {
    Column() {
      /**
       * 钤印方章（2026-10-13「纸与印」Phase 22）—— **Rock私记 的脸**。
       *
       * 第一性原则：日记 app 的一切围绕"今天"，而这是用户每天打开 app 的第一屏。
       * 原来这屏只有标题 + 密码框：零品牌、零仪式感，中部以下全是空白 —— 用户记不住我们。
       * 印章是中文书写传统里"这篇我钤过了"的意象：古印皆方 + 茶褐描边 +「记」字。
       * ⚠️ 不用圆形笑脸（Daylio 的脸）、不用黄底数字（Day One 的脸）、不用锁
       *    （锁在 Logo 里；印记与锁是两回事：印记 = 我来过，锁 = 它属于我）。
       */
      Stack() {
        Text('记')
          .fontSize(RJ_FS_HEADING)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.brand)
      }
      .width(56)
      .height(56)
      .border({ width: 1.5, color: this.palette.brand, radius: 10 })
      .margin({ top: RJ_SP_TOP_INSET })

      Text('Rock私记')
        .fontSize(RJ_FS_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .letterSpacing(2)
        .margin({ top: RJ_SP_XL, bottom: RJ_SP_SM })

      // 今天：敲密码前先让用户进到"今天"的语境（仪式感）；等宽是家族数码纪律
      Text(this.todayLabel())
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text2)

      // 弹性空间：上（印记/今天）与中（表单）两极拉开，表单落在视觉中心
      Blank()

      Text(this.firstRun ? '设置主密码' : '输入主密码解锁')
        .fontSize(RJ_FS_CALLOUT)
        .fontColor(this.palette.text2)
        .margin({ bottom: RJ_SP_VOID })

      TextInput({ placeholder: '主密码', text: this.password })
        .type(InputType.Password)
        .fontSize(RJ_FS_CALLOUT)
        .backgroundColor(this.palette.card)
        .fontColor(this.palette.text)
        .width('80%')
        .height(44)
        .margin({ bottom: RJ_SP_LG })
        .onChange((v: string) => {
          this.password = v;
          this.error = '';
        })

      if (this.firstRun) {
        TextInput({ placeholder: '再次输入', text: this.confirm })
          .type(InputType.Password)
          .fontSize(RJ_FS_CALLOUT)
          .backgroundColor(this.palette.card)
          .fontColor(this.palette.text)
          .width('80%')
          .height(44)
          .margin({ bottom: RJ_SP_LG })
          .onChange((v: string) => {
            this.confirm = v;
          })
      }

      if (!this.firstRun && this.bioAvailable) {
        // 生物解锁 = **主行动**（首选路径）：墨色实心自绘（纸·墨·茶：chrome 全中性）
        // ⚠️ 不用 buttonStyle(EMPHASIZED)：系统强调样式会覆盖 backgroundColor（墨底被冲白）
        Button('使用指纹 / 面容解锁', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_HEADING)
          .backgroundColor(this.palette.accent)
          .fontColor(this.palette.bg)
          .width('80%')
          .height(46)
          .margin({ top: RJ_SP_MD, bottom: RJ_SP_SM })
          .onClick(() => {
            this.doBio();
          })
      }

      // 主密码按钮的主次**看场景**（见 pwdPrimary）：
      //   有生物可选 → 次要（TEXTUAL 文字态：无底、仅文字，不跟主行动抢视线）
      //   唯一路径   → 主行动（墨色实心自绘）
      // ⚠️ 原来无脑用 `rj_text` 做底：深色下是白底黑字，比主行动按钮还抢眼，主次打架。
      // ⚠️ 主行动分支**不用 EMPHASIZED**：系统强调样式会覆盖 backgroundColor（墨底被冲白、字看不见，
      //   2026-10-14 实测），用 NORMAL + 自绘实心替代。
      Button(this.firstRun ? '设置并进入' : '用主密码解锁', { type: ButtonType.Normal, stateEffect: true })
        .buttonStyle(this.pwdPrimary() ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL)
        .fontSize(RJ_FS_HEADING)
        .fontWeight(this.pwdPrimary() ? FontWeight.Medium : FontWeight.Normal)
        .backgroundColor(this.pwdPrimary() ? this.palette.accent : Color.Transparent)
        .fontColor(this.pwdPrimary() ? this.palette.bg : this.palette.text2)
        .width('80%')
        .height(46)
        .margin({ top: RJ_SP_MD })
        .onClick(() => {
          this.doUnlock();
        })

      if (this.error.length > 0) {
        // 错误提示用警示色（rj_danger），不用强调色 —— 蓝色是"重要"，红色才是"错了"
        Text(this.error)
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.palette.danger)
          .margin({ top: RJ_SP_XL })
      }
      // 弹性空间：把信任锚压到屏幕底部 —— 它原来是半空里飘的一行小字，
      // 而"数据只在这台设备上"是全 App 最重要的信任承诺之一，不该飘着
      Blank()
      Text('数据只在这台设备上 · AES-256-GCM 加密')
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text3)
        .margin({ bottom: RJ_SP_VOID })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .justifyContent(FlexAlign.Start)
  }

  /** 今天：「10 月 13 日 · 星期二」（等宽感由 fontFamily 负责，这里只管文案） */
  private todayLabel(): string {
    const d: Date = new Date();
    const week: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return (d.getMonth() + 1) + ' 月 ' + d.getDate() + ' 日 · 星期' + week[d.getDay()];
  }

  /**
   * 主密码按钮此刻是不是「主行动」：
   *   firstRun（首次设置，页面唯一按钮）        → 是
   *   日常解锁 + 有生物可用                     → 否（生物才是首选，主密码退成文字态）
   *   日常解锁 + 无生物（模拟器/没录指纹）       → 是（唯一路径，不降级）
   */
  private pwdPrimary(): boolean {
    return this.firstRun || !this.bioAvailable;
  }
}
