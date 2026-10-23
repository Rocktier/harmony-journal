import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { unlockWith, setupVault, unlockWithBiometric, hasBiometric, isFirstRun } from '../data/NoteStoreHolder';
import { PrivacyPrefs } from '../data/PrivacyPrefs';
import { RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_DISPLAY, RJ_FS_HEADING, RJ_FS_META, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_TOP_INSET, RJ_SP_VOID, RJ_SP_XL } from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 解锁页（Phase 8 / 决策 4）：替代开发期 DEV_UNLOCK_BYPASS。
 *
 * 流程：
 *  - 启动 → EntryAbility.bootstrap 已备好 salt + 沙箱根 → 进本页
 *  - **隐私门**（2026-10-20 新增，华为审核指南 7.5）：未同意过隐私政策时，
 *    本页只渲染隐私门 —— 用户点「同意并继续」之后才看得到解锁表单
 *  - 首次运行：让用户「设置主密码」（≥6 位，两次一致）→ 生成随机主密钥 + 写两份备份（密码 + 生物）
 *  - 之后运行：优先显示「使用指纹/面容解锁」；生物通过直接进应用，无需再输密码
 *  - 生物不可用/失败/取消 → 降级主密码（永远能解锁）
 *
 * ⚠️ 主密钥随机生成、只存内存；密码与生物各存一份备份互为兜底。忘密码 ≠ 丢数据（可用生物）。
 * ⚠️ 模拟器 / 无生物设备：生物路径会失败并自动降级主密码，不会卡在解锁页。
 */
const DOMAIN: number = 0xD002;
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
  /** 隐私政策是否已同意（未同意 ⇒ 先过隐私门，见 build） */
  @State private agreed: boolean = false;
  private privacy: PrivacyPrefs = new PrivacyPrefs();

  aboutToAppear(): void {
    this.privacy.open(getContext(this) as common.UIAbilityContext);
    this.agreed = this.privacy.isAgreed();
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

  /** 页面转场（2026-10-22 P0-1 动效包）：与全家族统一的推栈语言（见 Editor.pageTransition） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 280, curve: Curve.Friction })
      .translate({ x: 200 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 280, curve: Curve.Friction })
      .translate({ x: -80 })
      .opacity(0.8)
    PageTransitionEnter({ type: RouteType.Pop, duration: 280, curve: Curve.Friction })
      .translate({ x: -80 })
      .opacity(0.8)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.Friction })
      .translate({ x: 200 })
      .opacity(0.6)
  }

  build() {
    Stack() {
      // 隐私门没过 ⇒ 只渲染隐私门，解锁表单根本不出现（不是"弹一下能绕过"的那种）
      if (!this.agreed) {
        this.privacyGate();
      } else {
        this.unlockForm();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }

  /** 解锁表单（隐私门通过后才渲染） */
  @Builder
  private unlockForm() {
    // ⚠️ 2026-10-23 复评（横屏/矮屏）：外包 Scroll —— 原不可滚容器在横屏矮屏下
    //    把「同意并继续」挤出屏幕底部且无任何滚动途径（内容不可达 = 功能坏）。
    //    代价：Blank 的压底语义在 Scroll 内不再生效（信任锚贴在内容下方）——
    //    可用性优先于竖屏压底美学。缩进暂未重排（语法无关，先保正确）。
    Scroll() {
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
    .padding({ bottom: RJ_SP_VOID })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }

  /**
   * 隐私门（2026-10-20 新增 —— 华为审核指南 7.5 硬性要求）
   *
   * 「应用在首次启动时未显著提示用户阅读隐私政策」= Rock私记 1.0.0 的拒因之一。
   * 放在**解锁表单之前**：第一屏就是它，不存在"绕过去"的路径。
   *
   * 设计口径：
   *  - 摘要必须自己说清三件事（不收集 / 不联网 / 只存本机加密），
   *    不能只丢一个「同意」按钮让人盲点 —— 那不是提示，是胁迫；
   *  - 「阅读隐私政策」进应用内 Privacy 页（断网也能看，且与博客 `#privacy` 章逐字一致）；
   *  - 「不同意」= 退出应用（terminateSelf），不提供"不同意但继续用"的选项。
   */
  @Builder
  private privacyGate() {
    Column() {
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

      Text('欢迎使用 Rock私记')
        .fontSize(RJ_FS_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .letterSpacing(2)
        .margin({ top: RJ_SP_XL, bottom: RJ_SP_SM })

      Text('开始之前，请读一遍我们怎么对待你的数据')
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text2)

      Blank()

      Column() {
        Text('· 不收集任何个人信息 —— 没有账号、没有登录、没有云端同步')
          .fontSize(RJ_FS_META)
          .fontColor(this.palette.text2)
          .margin({ bottom: RJ_SP_MD })
        Text('· 不联网 —— 不申请网络权限，功能全部在你的设备上完成')
          .fontSize(RJ_FS_META)
          .fontColor(this.palette.text2)
          .margin({ bottom: RJ_SP_MD })
        Text('· 只存在这台设备 —— 日记经 AES-256-GCM 加密，密钥由你的主密码派生')
          .fontSize(RJ_FS_META)
          .fontColor(this.palette.text2)
          .margin({ bottom: RJ_SP_MD })
        Text('· 我们无法读取、也无法找回 —— 主密码遗忘，内容无法恢复')
          .fontSize(RJ_FS_META)
          .fontColor(this.palette.text2)
      }
      .width('80%')

      Blank()

      // 完整政策：应用内页（断网可看）—— 摘要只是摘要，真源在这里
      Button('阅读《隐私政策》', { type: ButtonType.Normal, stateEffect: true })
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text2)
        .margin({ bottom: RJ_SP_LG })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Privacy' }).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'pushUrl privacy failed: %{public}s', JSON.stringify(e));
          });
        })

      Button('同意并继续', { type: ButtonType.Normal, stateEffect: true })
        .fontSize(RJ_FS_HEADING)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.palette.accent)
        .fontColor(this.palette.bg)
        .width('80%')
        .height(46)
        .margin({ bottom: RJ_SP_SM })
        .onClick(() => {
          this.privacy.setAgreed();
          this.agreed = true;
        })

      Button('不同意', { type: ButtonType.Normal, stateEffect: true })
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text3)
        .width('80%')
        .height(40)
        .onClick(() => {
          (getContext(this) as common.UIAbilityContext).terminateSelf();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: RJ_SP_XL, right: RJ_SP_XL, bottom: RJ_SP_VOID })
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
