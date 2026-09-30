import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { unlockWith, isFirstRun } from '../data/NoteStoreHolder';
import { ensureBioKey, tryBioUnlock } from '../common/BioUnlock';

/**
 * 解锁页（Phase 8 / 决策 4）：替代开发期 DEV_UNLOCK_BYPASS。
 *
 * 流程：
 *  - 启动 → EntryAbility.bootstrap 已备好 salt → 进本页
 *  - 首次运行：让用户「设置主密码」（≥6 位，两次一致）→ 派生主密钥 + 落 salt
 *  - 之后运行：输入主密码解锁
 *  - 优先尝试生物（HUKS 绑生物）→ 通过即放行；无生物/失败降级主密码
 *
 * ⚠️ 主密钥 = PBKDF2(密码, 固定 salt)，只存内存；忘密码 = 无法派生 = 数据不可恢复。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

@Entry
@Component
struct Unlock {
  @State private password: string = '';
  @State private confirm: string = '';
  @State private error: string = '';
  @State private bioMsg: string = '';
  @State private firstRun: boolean = isFirstRun();

  aboutToAppear(): void {
    ensureBioKey();
    this.attemptBio();
  }

  private async attemptBio(): Promise<void> {
    const ok: boolean = await tryBioUnlock();
    if (ok) {
      // 真机：生物通过 → 此处应解封主密钥到内存（HUKS 主密钥保管专项，待实现）。
      // 当前 HUKS 仅做认证层，主密钥仍需密码派生 → 提示用密码。
      this.bioMsg = '生物已通过，请输入主密码解锁数据';
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
    } else {
      if (this.password.length === 0) {
        this.error = '请输入主密码';
        return;
      }
    }
    const ok: boolean = await unlockWith(this.password);
    if (ok) {
      router.replaceUrl({ url: 'pages/Index' }).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'replaceUrl failed: %{public}s', JSON.stringify(e));
      });
    } else {
      this.error = '密码不正确，或数据已损坏/不兼容';
    }
  }

  build() {
    Column() {
      Text('Rock私记')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rj_text'))
        .letterSpacing(2)
        .margin({ top: 80, bottom: 8 })
      Text(this.firstRun ? '设置主密码' : '输入主密码解锁')
        .fontSize(13)
        .fontColor($r('app.color.rj_text2'))
        .margin({ bottom: 40 })

      TextInput({ placeholder: '主密码', text: this.password })
        .type(InputType.Password)
        .fontSize(14)
        .backgroundColor($r('app.color.rj_card'))
        .fontColor($r('app.color.rj_text'))
        .width('80%')
        .height(44)
        .margin({ bottom: 12 })
        .onChange((v: string) => {
          this.password = v;
          this.error = '';
        })

      if (this.firstRun) {
        TextInput({ placeholder: '再次输入', text: this.confirm })
          .type(InputType.Password)
          .fontSize(14)
          .backgroundColor($r('app.color.rj_card'))
          .fontColor($r('app.color.rj_text'))
          .width('80%')
          .height(44)
          .margin({ bottom: 12 })
          .onChange((v: string) => {
            this.confirm = v;
          })
      }

      Button(this.firstRun ? '设置并进入' : '解锁')
        .fontSize(15)
        .backgroundColor($r('app.color.rj_text'))
        .fontColor($r('app.color.rj_bg'))
        .width('80%')
        .height(46)
        .margin({ top: 8 })
        .onClick(() => {
          this.doUnlock();
        })

      if (this.bioMsg.length > 0) {
        Text(this.bioMsg)
          .fontSize(12)
          .fontColor($r('app.color.rj_text3'))
          .margin({ top: 16 })
      }
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(12)
          .fontColor($r('app.color.rj_red'))
          .margin({ top: 16 })
      }
      Text('数据只在这台设备上 · AES-256-GCM 加密')
        .fontSize(10)
        .fontColor($r('app.color.rj_text3'))
        .margin({ bottom: 40, top: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
    .justifyContent(FlexAlign.Start)
  }
}
