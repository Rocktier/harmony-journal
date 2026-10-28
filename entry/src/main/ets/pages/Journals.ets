import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ChevronButton } from '../components/ChevronButton';
import {
  JOURNAL_EMOJIS, JOURNAL_MAIN_ID, JOURNAL_MAX, JournalInfo, addJournal, canAddJournal, journalCounts,
  journalEmojiOf, journalNameOf, removeJournal, renameJournal
} from '../data/Journals';
import { NoteMeta } from '../data/NoteMeta';
import { getStore } from '../data/NoteStoreHolder';
import {
  RJ_FS_BODY, RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_HEADING, RJ_FS_META, RJ_RADIUS_MD, RJ_RADIUS_SM,
  RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID_L, RJ_SP_XL, RJ_SP_XS, RJ_SP_XXL
} from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 日记本管理页（1.0.6 多本分册）
 *
 * 用户视角：工作的事、孩子的事、读书的感想，分开记、分开翻。
 * 这个页面就是"分"的那一刀 —— 新建、改名、删除都在这里。
 *
 * ⚠️ 本页最重要的一条纪律：**删本不删日记**。
 *    删掉一个本，里面的日记全部搬进默认本（「生活」），一篇不少。
 *    所以删除必须二次确认，且确认文案要明说"会搬到哪里"——
 *    用户怕的从来不是"少一个本"，是"我的日记没了"。
 *
 * ⚠️ 为什么不放在设置页：本是要经常切的东西，藏在设置里等于没有；
 *    而本的管理（建/改/删）与本的切换是一套心智，放一起最顺。
 */
const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

@Entry
@Component
struct JournalsPage {
  /** 运行时色板（深浅切换 = AppStorage 换对象，页面栈不动；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  @State private journals: JournalInfo[] = [];
  /** 各本的篇数（删本确认文案要靠它告诉用户"会搬走多少篇"） */
  @State private counts: Record<string, number> = {};
  /** 新建区：名字与选中的图标 */
  @State private newName: string = '';
  @State private newEmoji: string = JOURNAL_EMOJIS[0];
  /** 正在改名的本（空串 = 没有） */
  @State private renamingId: string = '';
  @State private renameName: string = '';
  @State private renameEmoji: string = JOURNAL_EMOJIS[0];
  /** 正在确认删除的本（空串 = 没有） */
  @State private confirmId: string = '';
  /** 操作后的即时反馈（清空靠定时器，不常驻） */
  @State private hint: string = '';
  private store = getStore();

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    // ⚠️ counts 必须基于**全量**日记算（本页面不按本过滤，它是管本的）
    this.journals = this.store.journalList();
    this.counts = journalCounts(this.journals, this.store.list());
  }

  /** 落盘：本列表与条目归属在同一次 saveIndex 里写（分开写会留下不一致的中间态） */
  private persist(): boolean {
    const ok: boolean = this.store.saveIndex();
    if (!ok) {
      hilog.error(DOMAIN, TAG, 'saveIndex failed in Journals page');
    }
    return ok;
  }

  private countOf(id: string): number {
    const n: number | undefined = this.counts[id];
    return n === undefined ? 0 : n;
  }

  private showHint(text: string): void {
    this.hint = text;
    setTimeout(() => {
      this.hint = '';
    }, 2600);
  }

  // ── 新建 ────────────────────────────────────────────────────────

  private doAdd(): void {
    const r = addJournal(this.journals, this.newName, this.newEmoji, Date.now());
    if (r === null) {
      // 分不出是"名字空"还是"本满了"就说个准话，别让用户猜
      if (!canAddJournal(this.journals)) {
        this.showHint('最多 ' + JOURNAL_MAX + ' 个本，先删掉一些吧');
      } else {
        this.showHint('先给它起个名字');
      }
      return;
    }
    this.store.setJournals(r.list);
    if (this.persist()) {
      this.showHint('已新建「' + r.created.name + '」');
    }
    this.newName = '';
    this.newEmoji = JOURNAL_EMOJIS[0];
    this.refresh();
  }

  // ── 改名（默认本也允许改 —— 用户有权叫它「我的日记」） ──────────────

  private doRename(id: string): void {
    const before: JournalInfo | null = this.journalById(id);
    this.store.setJournals(renameJournal(this.journals, id, this.renameName, this.renameEmoji));
    if (this.persist() && before !== null) {
      this.showHint('已改名为「' + this.renameName + '」');
    }
    this.renamingId = '';
    this.refresh();
  }

  private startRename(j: JournalInfo): void {
    this.renamingId = j.id;
    this.renameName = journalNameOf(j);
    this.renameEmoji = journalEmojiOf(j);
    this.confirmId = '';
  }

  // ── 删除（搬走篇目，二次确认） ───────────────────────────────────

  private doRemove(id: string): void {
    const metas: NoteMeta[] = this.store.list();
    const r = removeJournal(this.journals, id, metas);
    if (r === null) {
      this.confirmId = '';
      return;
    }
    // ★ 先搬日记再删本：顺序反了就会出现"本没了、日记也没归属"的中间态
    this.store.setJournals(r.list);
    this.store.moveEntriesTo(r.movedIds, JOURNAL_MAIN_ID);
    if (this.persist()) {
      this.showHint('已删除，' + r.movedIds.length + ' 篇移到「生活」');
    }
    this.confirmId = '';
    this.refresh();
  }

  private journalById(id: string): JournalInfo | null {
    for (let i: number = 0; i < this.journals.length; i++) {
      if (this.journals[i].id === id) {
        return this.journals[i];
      }
    }
    return null;
  }

  // ── 界面 ────────────────────────────────────────────────────────

  build() {
    // ⚠️ 根 Column 必须给确定高度（'100%'），否则下面 Scroll 的 layoutWeight 无解
    //    （家族老坑：高度不确定的父链会把内容压成 0，表现为整页空白）
    Column() {
      Row() {
        ChevronButton({
          side: 'left',
          label: '返回',
          onClickHandler: () => {
            router.back();
          }
        })
        Text('日记本')
          .fontSize(RJ_FS_HEADING)
          .fontColor(this.palette.text)
          .letterSpacing(2)
        Blank()
        Text(this.journals.length + '/' + JOURNAL_MAX)
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_SM })

      Text('分开记，分开翻。删掉一个本，里面的日记会搬进「生活」，一篇不会少。')
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.palette.brand)
          .width('100%')
          .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_SM })
      }

      Scroll() {
        Column() {
          ForEach(this.journals, (j: JournalInfo) => {
            this.journalRow(j)
            // ⚠️ key 必须带"展开/确认"状态（家族第 4 次同型坑）：
            //    @Builder 值参数不随 @State 重跑，只改 @State 而 key 不变
            //    ⇒ 行内不重建 ⇒ 点了"改名"却看不到输入框。
          }, (j: JournalInfo) => j.id + (this.renamingId === j.id ? ':edit' : '') +
            (this.confirmId === j.id ? ':confirm' : ''))
          this.addSection()
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_VOID_L })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }

  /** 一个本的一行（含改名/删除的内嵌展开区） */
  @Builder
  private journalRow(j: JournalInfo) {
    Column() {
      Row() {
        Text(journalEmojiOf(j))
          .fontSize(RJ_FS_BODY)
        Text(journalNameOf(j))
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
          .margin({ left: RJ_SP_MD })
        Text(this.countOf(j.id) + ' 篇')
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .margin({ left: RJ_SP_MD })
        Blank()
        Button('改名', { type: ButtonType.Normal, stateEffect: true })
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.palette.text3)
          .padding({ left: RJ_SP_SM, right: RJ_SP_SM, top: RJ_SP_XS, bottom: RJ_SP_XS })
          .onClick(() => {
            this.startRename(j);
          })
        // 默认本不给删除按钮（它是回收港，删了就没地方搬了）
        if (j.id !== JOURNAL_MAIN_ID) {
          Button('删除', { type: ButtonType.Normal, stateEffect: true })
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontSize(RJ_FS_CAPTION)
            .fontColor(this.palette.text3)
            .padding({ left: RJ_SP_SM, right: RJ_SP_SM, top: RJ_SP_XS, bottom: RJ_SP_XS })
            .onClick(() => {
              this.confirmId = j.id;
              this.renamingId = '';
            })
        }
      }
      .width('100%')
      .padding({ top: RJ_SP_MD, bottom: RJ_SP_MD })

      // 改名展开区
      if (this.renamingId === j.id) {
        Column() {
          TextInput({ placeholder: '本的名字', text: this.renameName })
            .fontSize(RJ_FS_CALLOUT)
            .backgroundColor(this.palette.card)
            .fontColor(this.palette.text)
            .placeholderColor(this.palette.text3)
            .height(38)
            .onChange((v: string) => {
              this.renameName = v;
            })
          this.emojiRow(this.renameEmoji, (e: string) => {
            this.renameEmoji = e;
          })
          Row() {
            Button('取消', { type: ButtonType.Normal, stateEffect: true })
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .fontSize(RJ_FS_CAPTION)
              .fontColor(this.palette.text3)
              .onClick(() => {
                this.renamingId = '';
              })
            Button('保存', { type: ButtonType.Normal, stateEffect: true })
              .backgroundColor(this.palette.accent)
              .fontColor(this.palette.bg)
              .fontSize(RJ_FS_CAPTION)
              .borderRadius(RJ_RADIUS_MD)
              .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
              .margin({ left: RJ_SP_MD })
              .onClick(() => {
                this.doRename(j.id);
              })
          }
          .margin({ top: RJ_SP_SM })
        }
        .width('100%')
        .padding({ bottom: RJ_SP_MD })
      }

      /**
       * 删除确认区（**必须说清搬到哪去** —— 用户怕的是日记没了，不是本没了）
       */
      if (this.confirmId === j.id) {
        Column() {
          Text('删除「' + journalNameOf(j) + '」？里面 ' + this.countOf(j.id) + ' 篇日记会移到「生活」，不会删除。')
            .fontSize(RJ_FS_CAPTION)
            .fontColor(this.palette.text2)
            .width('100%')
          Row() {
            Button('取消', { type: ButtonType.Normal, stateEffect: true })
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .fontSize(RJ_FS_CAPTION)
              .fontColor(this.palette.text3)
              .onClick(() => {
                this.confirmId = '';
              })
            Button('确认删除', { type: ButtonType.Normal, stateEffect: true })
              .backgroundColor(this.palette.accent)
              .fontColor(this.palette.bg)
              .fontSize(RJ_FS_CAPTION)
              .borderRadius(RJ_RADIUS_MD)
              .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
              .margin({ left: RJ_SP_MD })
              .onClick(() => {
                this.doRemove(j.id);
              })
          }
          .margin({ top: RJ_SP_SM })
        }
        .width('100%')
        .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_MD })
        .backgroundColor(this.palette.card)
        .borderRadius(RJ_RADIUS_SM)
      }
    }
    .width('100%')
    .padding({ top: RJ_SP_XS })
  }

  /** 图标选择行（固定候选集，避免用户输入 emoji 时渲染不一致） */
  @Builder
  private emojiRow(selected: string, onPick: (e: string) => void) {
    Row() {
      ForEach(JOURNAL_EMOJIS, (e: string) => {
        Button(e, { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_BODY)
          .backgroundColor(selected === e ? this.palette.accent : Color.Transparent)
          .border({
            width: selected === e ? 0 : 1,
            color: this.palette.text3
          })
          .width(34)
          .height(34)
          .padding(0)
          .borderRadius(RJ_RADIUS_SM)
          .margin({ right: RJ_SP_SM })
          .onClick(() => {
            onPick(e);
          })
      }, (e: string) => e + (selected === e ? ':on' : ''))
    }
    .margin({ top: RJ_SP_SM })
  }

  /** 新建本（最后一个卡片，与列表同构但常驻） */
  @Builder
  private addSection() {
    Column() {
      Text('新建')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ bottom: RJ_SP_SM })
      TextInput({ placeholder: '给它起个名字，比如「工作」', text: this.newName })
        .fontSize(RJ_FS_CALLOUT)
        .backgroundColor(this.palette.card)
        .fontColor(this.palette.text)
        .placeholderColor(this.palette.text3)
        .height(38)
        .onChange((v: string) => {
          this.newName = v;
        })
      this.emojiRow(this.newEmoji, (e: string) => {
        this.newEmoji = e;
      })
      Button('新建本', { type: ButtonType.Normal, stateEffect: true })
        .backgroundColor(this.palette.accent)
        .fontColor(this.palette.bg)
        .fontSize(RJ_FS_CAPTION)
        .fontWeight(FontWeight.Bold)
        .borderRadius(RJ_RADIUS_MD)
        .padding({ left: RJ_SP_XL, right: RJ_SP_XL, top: RJ_SP_SM, bottom: RJ_SP_SM })
        .margin({ top: RJ_SP_MD })
        .onClick(() => {
          this.doAdd();
        })
    }
    .width('100%')
    .padding({ top: RJ_SP_LG })
  }
}
