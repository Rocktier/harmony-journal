import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { DEV_SHOW_BADGE } from '../common/DevFlags';
import { TimelineDataSource } from '../common/TimelineDataSource';
import { ImageStore } from '../data/ImageStore';
import {
  JournalStats, MOODS, MonthCell, Mood, NoteMeta, NoteText, SearchHit, TimelineRow, collectTags,
  computeStats, filterMetas, moodById, monthGrid, monthOf, monthRowCount, needsBackupReminder,
  onThisDayDates, previewText, searchNotes, shiftMonth, timeOfDay, timelineRows, todayKey, yearsAgoLabel
} from '../data/NoteMeta';
import { NoteStore } from '../data/NoteStore';
import { getStore } from '../data/NoteStoreHolder';

/**
 * 主页面：月视图日历 + 时光时间轴 + 搜索 + 「那年今日」
 *
 * 家族观感：纯黑底、白字、红点做"有日记"的标记（与图标红点同源）。
 *
 * ⚠️ Phase 10b（回头看）的用户视角：
 *   写完之后内容大概率再也不会被打开 —— 所以主页要**让过去自己出现**：
 *   ① 那年今日：今天打开就有往年同日的内容撞进来
 *   ② 时光时间轴：能看到"自己写过的话"（摘要缓存进索引，零额外 IO）+ 照片缩略图
 *   —— 光有日期和字数的列表是张表，不是隧道。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
/**
 * 那年今日最多展示几条。
 * ⚠️ 从 3 提到 5：这一栏的价值在**连续性**（1 年前 / 2 年前 / 3 年前…），
 * 只给一条就只是"一条往年记录"，给到 5 条才是"这几年这一天我都在做什么"。
 */
const RECALL_MAX: number = 5;
/** 卡片里摘要的字数（比索引里的 42 稍短，卡片空间有限） */
const RECALL_PREVIEW_LEN: number = 40;

/** 传给编辑器的参数：带 id 就精确打开那篇；没有就按 date 取这天最新的一篇 */
interface EntryParamPayload {
  date: string;
  id: string;
}

/** 「那年今日」的一张卡片（预先算好，渲染时不再做任何 IO） */
interface RecallCard {
  meta: NoteMeta;
  /** `3 年前` */
  years: string;
  /** 摘要（老数据没有缓存 ⇒ 这里回退到解密取，但最多 RECALL_MAX 条，成本封顶） */
  preview: string;
}

@Entry
@Component
struct Index {
  @State private metas: NoteMeta[] = [];
  @State private mode: string = 'month';
  @State private monthKey: string = monthOf(todayKey());
  @State private query: string = '';
  @State private hits: SearchHit[] = [];
  @State private loaded: boolean = false;
  @State private recall: RecallCard[] = [];
  @State private stats: JournalStats = {
    total: 0, days: 0, words: 0, streak: 0, longest: 0, wroteToday: false
  };
  /** 筛选（数据全在索引里 ⇒ 零 IO 成本）：仅收藏 / 心情 / 标签 */
  @State private onlyFavorite: boolean = false;
  @State private filterMood: string = '';
  @State private filterTag: string = '';
  @State private allTags: string[] = [];
  /** 距上次备份超过阈值就提醒一次（不自动写文件、只提醒） */
  @State private backupDue: boolean = false;
  private store: NoteStore = getStore();
  private images: ImageStore = new ImageStore();
  /** 时间轴的惰性数据源（换数据必须 reload 才会重画） */
  private dataSource: TimelineDataSource = new TimelineDataSource();
  /** 缩略图缓存：ref → 可显示的 uri（解密+落临时文件很贵，一会话内只做一次） */
  private thumbCache: Map<string, string> = new Map<string, string>();

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.images.open(ctx.filesDir);
    this.reload();
  }

  /**
   * ⚠️ router.back 回来时 aboutToAppear **不会**重新触发（页面没销毁），
   * 必须用 onPageShow 刷新 —— 不然编辑完回来，红点和列表都是旧数据（实拍抓到）。
   */
  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    this.metas = this.store.list();
    this.loaded = true;
    this.allTags = collectTags(this.metas);
    this.stats = computeStats(this.metas, todayKey());
    // 备份提醒：生命线靠自觉是不成立的，到期提醒一次（阈值 30 天）
    this.backupDue = needsBackupReminder(this.store.lastBackupAt(), Date.now(), this.metas.length > 0, 30);
    this.refreshData();
    this.buildRecall();
    hilog.info(DOMAIN, TAG, 'index loaded: %{public}d notes, recall %{public}d', this.metas.length, this.recall.length);
  }

  /** 把筛选后的结果灌进时间轴（换数据必须走 reload，否则 LazyForEach 不重画） */
  private refreshData(): void {
    const shown: NoteMeta[] = filterMetas(this.metas, this.onlyFavorite, this.filterMood, this.filterTag);
    this.dataSource.reload(timelineRows(shown));
  }

  /** 筛选条上的一枚按钮（选中才亮） */
  @Builder
  private chip(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(11)
      .fontColor(active ? $r('app.color.rj_text') : $r('app.color.rj_text3'))
      .backgroundColor(active ? $r('app.color.rj_g100') : $r('app.color.rj_card'))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .margin({ right: 8 })
      .onClick(() => {
        onTap();
      })
  }

  /** 「那年今日」：把往年同日的日记预先算成卡片（渲染时零 IO） */
  private buildRecall(): void {
    const today: string = todayKey();
    const dates: string[] = onThisDayDates(this.store.allDates(), today);
    const cards: RecallCard[] = [];
    for (let i: number = 0; i < dates.length && cards.length < RECALL_MAX; i++) {
      const list: NoteMeta[] = this.store.entriesOfDate(dates[i]);
      for (let j: number = 0; j < list.length && cards.length < RECALL_MAX; j++) {
        const m: NoteMeta = list[j];
        // 老数据没缓存摘要 ⇒ 解密补一次（上限 RECALL_MAX 条，成本封顶）
        const text: string = m.preview.length > 0 ? m.preview : previewText(this.store.textOf(m.id), RECALL_PREVIEW_LEN);
        const card: RecallCard = { meta: m, years: yearsAgoLabel(m.date, today), preview: text };
        cards.push(card);
      }
    }
    this.recall = cards;
  }

  /**
   * 缩略图：解密 → 临时文件 → `getUriFromPath`
   * ⚠️ findings §8 的血坑：直接把路径给 Image 会**渲染空白**，必须过 `fileUri`。
   */
  private thumbOf(meta: NoteMeta): string {
    if (meta.imgRef.length === 0) {
      return '';
    }
    const hit: string | undefined = this.thumbCache.get(meta.imgRef);
    if (hit !== undefined) {
      return hit;
    }
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const path: string = this.images.load(meta.imgRef, this.store.getVault(), ctx.cacheDir);
    const uri: string = path.length > 0 ? fileUri.getUriFromPath(path) : '';
    this.thumbCache.set(meta.imgRef, uri);
    return uri;
  }

  /**
   * 月视图的格子。
   *
   * ⚠️ `monthGrid` 固定返回 42 格（6 行 × 7，"切月不跳动"的老约定，单测也锁着 42）。
   *    但 10 月只有 5 行 —— 若照 42 格全渲染、只把 rowsTemplate 收成 5 行，
   *    多出的 7 格没有轨道，**整个 Grid 会不渲染**（实拍抓到：日历一个日子都不见了）。
   *    所以这里**只渲染实际存在的行**：模型不变，界面不浪费那一行空间。
   */
  private cells(): MonthCell[] {
    return monthGrid(this.monthKey, this.store.allDates()).slice(0, this.calRows() * 7);
  }

  /**
   * 月视图下方的列表 —— **只显示当前所选月份**。
   *
   * ⚠️ N1 的取舍（按第一性原则，不是观感洁癖）：
   *  ① **一致性**：日历和列表共享顶部那对 `‹ 月份 ›`，范围就必须一致 ——
   *     否则"翻到九月但列表还是全部历史"是两个窗格在打架，用户的"我在哪"会崩。
   *  ② **去重**：10b 之后"全部历史倒序"已由**时光时间轴**专职负责（还带摘要和缩略图），
   *     月视图里再放一份全量列表 = 同一需求两份更差的实现。
   *  ③ 复用 `timelineRows` 只取 note 行 ⇒ `showTime` 的判断与时间轴完全同源（同日多篇才补 HH:mm）。
   */
  /**
   * 当月日历要几行。
   * ⚠️ 必须是**普通方法**而不是 getter：ArkUI 的 build 里对 getter 求值不可靠
   *    （实测高度算成 NaN ⇒ Grid 一个格子都不渲染）。
   */
  private calRows(): number {
    return monthRowCount(this.monthKey);
  }

  private rowTemplate(): string {
    let t: string = '';
    const n: number = this.calRows();
    for (let i: number = 0; i < n; i++) {
      t = i === 0 ? '1fr' : t + ' 1fr';
    }
    return t;
  }

  private monthRows(): TimelineRow[] {
    const inMonth: NoteMeta[] = [];
    for (let i: number = 0; i < this.metas.length; i++) {
      if (monthOf(this.metas[i].date) === this.monthKey) {
        inMonth.push(this.metas[i]);
      }
    }
    const rows: TimelineRow[] = timelineRows(inMonth);
    const notes: TimelineRow[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      if (rows[i].kind === 'note') {
        notes.push(rows[i]);
      }
    }
    return notes;
  }

  /** 打开一篇：`id` 有值就精确打开那篇（搜索结果），否则交给编辑器按 date 取这天最新的一篇 */
  private open(date: string, id: string = ''): void {
    const payload: EntryParamPayload = { date: date, id: id };
    router.pushUrl({ url: 'pages/Editor', params: payload }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pushUrl failed: %{public}s', JSON.stringify(e));
    });
  }

  private runSearch(): void {
    const texts: NoteText[] = [];
    for (let i: number = 0; i < this.metas.length; i++) {
      const m: NoteMeta = this.metas[i];
      const item: NoteText = {
        id: m.id,
        date: m.date,
        text: this.store.textOf(m.id),
        tags: m.tags
      };
      texts.push(item);
    }
    this.hits = searchNotes(texts, this.query);
  }

  private moodEmoji(m: NoteMeta): string {
    if (m.mood.length === 0) {
      return '';
    }
    if (m.mood === 'custom') {
      return m.moodText.length > 0 ? m.moodText.substring(0, 2) : '·';
    }
    const found = moodById(m.mood);
    return found === null ? '' : found.emoji;
  }

  build() {
    Column() {
      // 顶部：视图切换 + 月份
      Row() {
        Text('Rock私记')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
        if (DEV_SHOW_BADGE) {
          Text('DEV')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_red'))
            .border({ width: 1, color: $r('app.color.rj_red') })
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ left: 8 })
        }
        Blank()
        // 「写今天」提到头部：一天里最高频的动作不该要滚过日历和列表才看得到
        Text('写今天')
          .fontSize(12)
          .fontColor($r('app.color.rj_red'))
          .fontWeight(FontWeight.Bold)
          .margin({ right: 16 })
          .onClick(() => {
            this.open(todayKey());
          })
        Text(this.mode === 'month' ? '月' : '时光')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .margin({ right: 14 })
          .onClick(() => {
            this.mode = this.mode === 'month' ? 'timeline' : 'month';
          })
        // 设置（导出备份的生命线入口 —— 藏深了等于没有）
        Text('设置')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      // 坚持写：连续天数 + 今天写没写（今天还没写用红色，直接推动今天的动作）
      Row() {
        if (this.stats.streak > 0) {
          Text('连续 ' + this.stats.streak + ' 天')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text3'))
        }
        Text('共 ' + this.stats.total + ' 篇')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .margin({ left: 12 })
        Blank()
        if (!this.stats.wroteToday) {
          Text('今天还没写')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_red'))
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })

      // 备份提醒：生命线靠自觉是不成立的，到期提醒一次（不自动写文件、不重复骚扰）
      if (this.backupDue) {
        Row() {
          Text('距上次备份超过 30 天了 · 去备份')
            .fontSize(11)
            .fontColor($r('app.color.rj_red'))
            .layoutWeight(1)
          Text('去备份 ›')
            .fontSize(11)
            .fontColor($r('app.color.rj_red'))
            .onClick(() => {
              router.pushUrl({ url: 'pages/Settings' });
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })
      }

      // 筛选条：数据全在索引里 ⇒ 零 IO 成本；几百篇之后这是"还能不能用"的分界线
      Row() {
        this.chip('★ 收藏', this.onlyFavorite, () => {
          this.onlyFavorite = !this.onlyFavorite;
          this.refreshData();
        })
        ForEach(MOODS, (m: Mood) => {
          this.chip(m.emoji, this.filterMood === m.id, () => {
            this.filterMood = this.filterMood === m.id ? '' : m.id;
            this.refreshData();
          })
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 4 })

      if (this.allTags.length > 0) {
        Scroll() {
          Row() {
            ForEach(this.allTags, (t: string) => {
              this.chip('#' + t, this.filterTag === t, () => {
                this.filterTag = this.filterTag === t ? '' : t;
                this.refreshData();
              })
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 6 })
      }

      // 搜索
      TextInput({ placeholder: '搜日记', text: this.query })
        .fontSize(13)
        .backgroundColor($r('app.color.rj_card'))
        .fontColor($r('app.color.rj_text'))
        .placeholderColor($r('app.color.rj_text3'))
        .height(38)
        .margin({ left: 20, right: 20, bottom: 8 })
        .onChange((v: string) => {
          this.query = v;
          if (v.length > 0) {
            this.runSearch();
          } else {
            this.hits = [];
          }
        })

      // 那年今日：搜索时不打扰；没有往年内容就**完全不渲染**（不留空壳）
      if (this.query.length === 0 && this.recall.length > 0) {
        Column() {
          Text('那年今日')
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text3'))
            .width('100%')
            .padding({ bottom: 6 })
          ForEach(this.recall, (card: RecallCard) => {
            Row() {
              Column() {
                Row() {
                  Text(card.years)
                    .fontSize(10)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_red'))
                  Text(card.meta.date)
                    .fontSize(10)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                    .margin({ left: 8 })
                  if (this.moodEmoji(card.meta).length > 0) {
                    Text(this.moodEmoji(card.meta))
                      .fontSize(12)
                      .margin({ left: 8 })
                  }
                }
                if (card.preview.length > 0) {
                  Text(card.preview)
                    .fontSize(13)
                    .fontColor($r('app.color.rj_text'))
                    .margin({ top: 3 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .onClick(() => {
              this.open(card.meta.date, card.meta.id);
            })
          }, (card: RecallCard) => card.meta.id)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4, bottom: 10 })
        .border({ width: { bottom: 1 }, color: $r('app.color.rj_line') })
      }

      if (this.query.length > 0) {
        // 搜索结果
        if (this.hits.length === 0) {
          Text('没有找到')
            .fontSize(12)
            .fontColor($r('app.color.rj_text3'))
            .margin({ top: 40 })
        }
        List() {
          ForEach(this.hits, (hit: SearchHit) => {
            ListItem() {
              Column() {
                Text(hit.date)
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text3'))
                Text(hit.snippet)
                  .fontSize(14)
                  .fontColor($r('app.color.rj_text'))
                  .margin({ top: 4 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
              .width('100%')
            }
            .onClick(() => {
              this.open(hit.date, hit.id);
            })
          }, (hit: SearchHit) => hit.date)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      } else if (this.mode === 'month') {
        // 月视图
        Row() {
          Text('<')
            .fontSize(16)
            .fontColor($r('app.color.rj_text2'))
            .onClick(() => {
              this.monthKey = shiftMonth(this.monthKey, -1);
            })
            .padding(8)
          Text(this.monthKey)
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text'))
            .letterSpacing(2)
          Text('>')
            .fontSize(16)
            .fontColor($r('app.color.rj_text2'))
            .onClick(() => {
              this.monthKey = shiftMonth(this.monthKey, 1);
            })
            .padding(8)
        }
        .margin({ bottom: 8 })

        // 6×7 网格
        Grid() {
          ForEach(this.cells(), (cell: MonthCell) => {
            GridItem() {
              Stack({ alignContent: Alignment.TopEnd }) {
                Text(cell.day.toString())
                  .fontSize(13)
                  .fontFamily('monospace')
                  .fontColor(cell.inMonth ? $r('app.color.rj_text') : $r('app.color.rj_text3'))
                if (cell.hasNote) {
                  Circle({ width: 8, height: 8 })
                    .fill($r('app.color.rj_red'))
                    .margin({ top: 3, right: 8 })
                }
              }
              .width('100%')
              .height('100%')
            }
            .onClick(() => {
              this.open(cell.date);
            })
          }, (cell: MonthCell) => cell.date)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        // 行数按当月实际需要（10 月只有 5 行，固定 6 行会白占 1/3 屏）
        .rowsTemplate(this.rowTemplate())
        .height(this.calRows() * 50)
        .padding({ left: 16, right: 16 })

        // 本月日记列表（**只列这个月** —— 顶部月份导航与列表范围必须一致，见 monthRows）
        if (this.monthRows().length === 0) {
          Text('这个月还没有日记')
            .fontSize(12)
            .fontColor($r('app.color.rj_text3'))
            .margin({ top: 24 })
        }
        List() {
          ForEach(this.monthRows(), (row: TimelineRow) => {
            ListItem() {
              Column() {
                Row() {
                  Text(row.meta !== null ? row.meta.date : '')
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text2'))
                  if (row.showTime && row.meta !== null) {
                    Text(timeOfDay(row.meta.createdAt))
                      .fontSize(10)
                      .fontFamily('monospace')
                      .fontColor($r('app.color.rj_text3'))
                      .margin({ left: 8 })
                  }
                  if (row.meta !== null && this.moodEmoji(row.meta).length > 0) {
                    Text(this.moodEmoji(row.meta))
                      .fontSize(14)
                      .margin({ left: 10 })
                  }
                  if (row.meta !== null && row.meta.favorite) {
                    Text('★')
                      .fontSize(14)
                      .fontColor($r('app.color.rj_red'))
                      .margin({ left: 10 })
                  }
                  Blank()
                  Text(row.meta !== null ? row.meta.words + ' 字' : '')
                    .fontSize(10)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                }
                .width('100%')
                // 标签：用户给的主题词，找得回来的第二条路
                if (row.meta !== null && row.meta.tags.length > 0) {
                  Text('#' + row.meta.tags.join(' #'))
                    .fontSize(10)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                    .margin({ top: 3 })
                }
                // 摘要来自索引缓存 ⇒ 零额外 IO，月视图也能"看到自己写过的话"
                if (row.meta !== null && row.meta.preview.length > 0) {
                  Text(row.meta.preview)
                    .fontSize(13)
                    .fontColor($r('app.color.rj_text'))
                    .margin({ top: 4 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            }
            .onClick(() => {
              if (row.meta !== null) {
                this.open(row.meta.date, row.meta.id);
              }
            })
          }, (row: TimelineRow) => row.key)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      } else {
        // 时光时间轴（全部，按年月分块，倒序）
        if (!this.loaded || this.metas.length === 0) {
          Column() {
            Text('还没有日记')
              .fontSize(14)
              .fontColor($r('app.color.rj_text3'))
            Text('点下面的按钮，写今天')
              .fontSize(11)
              .fontColor($r('app.color.rj_text3'))
              .margin({ top: 6 })
          }
          .margin({ top: 60 })
        }
        // ⚠️ 铁律①：长列表必须 LazyForEach（只构建可见区域），且换数据要走 dataSource.reload
        List() {
          LazyForEach(this.dataSource, (row: TimelineRow) => {
            ListItem() {
              if (row.kind === 'header') {
                Text(row.monthKey)
                  .fontSize(10)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text3'))
                  .width('100%')
                  .padding({ top: 14, bottom: 6 })
              } else if (row.meta !== null) {
                Row() {
                  Column() {
                    Row() {
                      Text(row.meta.date)
                        .fontSize(12)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.rj_text2'))
                      // 同一天多篇时补个时间，否则几行日期一模一样、看不出是几篇
                      if (row.showTime) {
                        Text(timeOfDay(row.meta.createdAt))
                          .fontSize(10)
                          .fontFamily('monospace')
                          .fontColor($r('app.color.rj_text3'))
                          .margin({ left: 8 })
                      }
                      if (this.moodEmoji(row.meta).length > 0) {
                        Text(this.moodEmoji(row.meta))
                          .fontSize(13)
                          .margin({ left: 8 })
                      }
                      if (row.meta.favorite) {
                        Text('★')
                          .fontSize(13)
                          .fontColor($r('app.color.rj_red'))
                          .margin({ left: 8 })
                      }
                      Blank()
                      Text(row.meta.words + ' 字')
                        .fontSize(10)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.rj_text3'))
                    }
                    .width('100%')
                    if (row.meta.tags.length > 0) {
                      Text('#' + row.meta.tags.join(' #'))
                        .fontSize(10)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.rj_text3'))
                        .margin({ top: 3 })
                    }
                    // 摘要来自索引缓存（零额外 IO）；老数据没有 ⇒ 这一行就没有，不硬凑
                    if (row.meta.preview.length > 0) {
                      Text(row.meta.preview)
                        .fontSize(13)
                        .fontColor($r('app.color.rj_text'))
                        .margin({ top: 4 })
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  // 二次调用走缓存，很便宜；这里多判一次是为了解密失败时不留空白方块
                  if (row.meta.imgRef.length > 0 && this.thumbOf(row.meta).length > 0) {
                    Image(this.thumbOf(row.meta))
                      .width(48)
                      .height(48)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(2)
                      .margin({ left: 10 })
                  }
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
            }
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              if (row.meta !== null) {
                this.open(row.meta.date, row.meta.id);
              }
            })
          }, (row: TimelineRow) => row.key)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      }

      // ⚠️ 原来这里还有一个底部大按钮「写今天」，现已提到头部 ——
      //    同一意图两个入口会让人犹豫该点哪个，而且底部那个要滚过日历+列表才看得到。
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
  }
}
