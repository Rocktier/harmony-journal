import { CARD_INTENT_WRITE_TODAY } from '../../data/JournalCardData';

/**
 * Journal 桌面服务卡片 UI（**零泄漏版**，2026-10-26 党哥拍板）
 *
 * 一个布局通吃 2×2 / 2×4：应用名 / 今天的日期 / 「写今天」按钮 / 隐私承诺小字。
 *
 * **卡片里不会出现任何日记内容**（正文与索引全加密，Form 进程没有密钥，
 * 结构上也读不出来 —— 详见 data/JournalCardData.ets 头注）。
 *
 * 交互：整卡可点 → postCardAction('router') 拉起 EntryAbility 并带
 * `intent=writeToday` → 应用若已解锁直接进编辑器；若在锁屏则先解锁、
 * 解锁成功后自动续跳编辑器（见 EntryAbility / Unlock / Index 三处）。
 *
 * 配色：底与文字走 sys.color（卡片配置 colorMode=auto，深浅色由系统托管，零维护）；
 * 按钮用 Journal 品牌橘（#C48A5E，浅/深两套色板里都是这个色系，深浅下都压得住）。
 *
 * ⚠️ **为什么不做"两种规格两套排版"**（2026-10-26 连续踩坑后的定稿）：
 *   ① form 页面**不支持 @StorageLink**（ArkTS 编译报 11706006
 *      "can't support form application"），只能用 @LocalStorageProp；
 *   ② @LocalStorageProp 在 2×4 实例上读到的是**默认值**（绑定数据被后到的实例覆盖）
 *      ⇒ 想按 dimension 分支出不同排版，**在 form 页面里根本做不到**；
 *   ③ onAreaChange（按实际宽度自适应）同样被 form 限制挡掉（11706006）。
 *   ⇒ 结论：form 页面拿不到可靠尺寸 ⇒ **统一布局**。2×2 实测高约 146vp，
 *     四行内容放得下；2×4 高约 307vp，同一套内容留白多一些，但整洁统一。
 */
const BRAND: string = '#C48A5E';

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('weekdayText') weekdayText: string = '';

  private readonly appLabel: string = 'Rock私记';

  build() {
    Column() {
      Text(this.appLabel)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .width('100%');

      Text(`${this.dateText} ${this.weekdayText}`)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 });

      this.writeButton();

      Text('数据只在这台设备上')
        .fontSize(9)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .width('100%');
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(20)
    // 整卡点击 = 「写今天」：router 动作带 intent 拉起应用
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { intent: CARD_INTENT_WRITE_TODAY }
      });
    });
  }

  /** 「写今天」按钮（品牌橘底白字；深浅色下对比度都够） */
  @Builder
  writeButton() {
    Row() {
      Text('写今天')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .fontWeight(FontWeight.Medium);
      Text('→')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .fontWeight(FontWeight.Medium)
        .margin({ left: 6 });
    }
    .height(30)
    .padding({ left: 14, right: 14 })
    .borderRadius(15)
    .backgroundColor(BRAND)
    .width('100%')
    .justifyContent(FlexAlign.Center);
  }
}
