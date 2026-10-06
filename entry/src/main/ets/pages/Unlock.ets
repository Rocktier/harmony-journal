import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { unlockWith, setupVault, unlockWithBiometric, hasBiometric, isFirstRun } from '../data/NoteStoreHolder';
import { RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_DISPLAY, RJ_FS_HEADING, RJ_FS_META, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_TOP_INSET, RJ_SP_VOID, RJ_SP_XL } from '../theme/RjTokens';

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
      Text('Rock私记')
        .fontSize(RJ_FS_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rj_text'))
        .letterSpacing(2)
        .margin({ top: RJ_SP_TOP_INSET, bottom: RJ_SP_MD })
      Text(this.firstRun ? '设置主密码' : '输入主密码解锁')
        .fontSize(RJ_FS_CALLOUT)
        .fontColor($r('app.color.rj_text2'))
        .margin({ bottom: RJ_SP_VOID })

      TextInput({ placeholder: '主密码', text: this.password })
        .type(InputType.Password)
        .fontSize(RJ_FS_CALLOUT)
        .backgroundColor($r('app.color.rj_card'))
        .fontColor($r('app.color.rj_text'))
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
          .backgroundColor($r('app.color.rj_card'))
          .fontColor($r('app.color.rj_text'))
          .width('80%')
          .height(44)
          .margin({ bottom: RJ_SP_LG })
          .onChange((v: string) => {
            this.confirm = v;
          })
      }

      if (!this.firstRun && this.bioAvailable) {
        Button('使用指纹 / 面容解锁')
          .fontSize(RJ_FS_HEADING)
          .backgroundColor($r('app.color.rj_accent'))
          .fontColor($r('app.color.rj_bg'))
          .width('80%')
          .height(46)
          .margin({ top: RJ_SP_MD, bottom: RJ_SP_SM })
          .onClick(() => {
            this.doBio();
          })
      }

      Button(this.firstRun ? '设置并进入' : '用主密码解锁')
        .fontSize(RJ_FS_HEADING)
        .backgroundColor($r('app.color.rj_text'))
        .fontColor($r('app.color.rj_bg'))
        .width('80%')
        .height(46)
        .margin({ top: RJ_SP_MD })
        .onClick(() => {
          this.doUnlock();
        })

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(RJ_FS_CAPTION)
          .fontColor($r('app.color.rj_red'))
          .margin({ top: RJ_SP_XL })
      }
      Text('数据只在这台设备上 · AES-256-GCM 加密')
        .fontSize(RJ_FS_META)
        .fontColor($r('app.color.rj_text3'))
        .margin({ bottom: RJ_SP_VOID, top: RJ_SP_VOID })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
    .justifyContent(FlexAlign.Start)
  }
}
