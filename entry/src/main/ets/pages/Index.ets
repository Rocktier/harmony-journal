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
import { ViewPrefs, ViewMode } from '../data/ViewPrefs';
import { RJ_FS_BODY, RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_META, RJ_FS_TITLE, RJ_RADIUS_LG, RJ_RADIUS_MD, RJ_RADIUS_SM, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID, RJ_SP_VOID_L, RJ_SP_XL, RJ_SP_XS, RJ_SP_XXL, RJ_SP_XXXL } from '../theme/RjTokens';

/**
 * 主页面：月视图日历 + 时光时间轴 + 搜索 + 「那年今日」
 *
 * 家族观感（2026-10-14「纸·墨·茶」）：纸底、墨字，**茶褐**做"有日记"的印记（唯一彩色）。
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
  /**
   * 标签筛选是否展开。
   *
   * ⚠️ 为什么标签默认**收起**：标签是"用户自定义、数量不定"的筛选项，
   * 常驻一整行的后果是 —— ① 白占一行高度（收藏+心情已经占了一行）；
   * ② 有没有标签取决于写过什么，于是这一行**忽隐忽现**，看着很突兀。
   * 收成一个入口后：默认只占一个 chip，展开才占空间。
   * 正在生效时入口会显示"标签 · #xxx"，免得"筛着却看不出来"。
   */
  @State private tagsExpanded: boolean = false;
  /** 距上次备份超过阈值就提醒一次（不自动写文件、只提醒） */
  @State private backupDue: boolean = false;
  private store: NoteStore = getStore();
  private images: ImageStore = new ImageStore();
  /** 时间轴的惰性数据源（换数据必须 reload 才会重画） */
  private dataSource: TimelineDataSource = new TimelineDataSource();
  /** 视图偏好持久化（月/时光；2026-10-14 党哥：原来切换不记偏好，退出重进总弹回月视图） */
  private viewPrefs: ViewPrefs = new ViewPrefs();
  /** 缩略图缓存：ref → 可显示的 uri（解密+落临时文件很贵，一会话内只做一次） */
  private thumbCache: Map<string, string> = new Map<string, string>();

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.images.open(ctx.filesDir);
    // 视图偏好：同步读，首帧就落在用户上次所在（月/时光），不闪默认态
    this.viewPrefs.open(ctx);
    this.mode = this.viewPrefs.get();
    this.reload();
  }

  /**
   * 切视图（分段控件与滑动手势共用）。
   * 落偏好 ⇒ 冷启动回到上次所在（党哥 2026-10-14：用户的视图选择不该被反复重置）。
   */
  private setMode(m: ViewMode): void {
    if (this.mode === m) {
      return;
    }
    this.mode = m;
    this.viewPrefs.set(m);
  }

  /**
   * ⚠️ router.back 回来时 aboutToAppear **不会**重新触发（页面没销毁），
   * 必须用 onPageShow 刷新 —— 不然编辑完回来，标记点和列表都是旧数据（实拍抓到）。
   */
  onPageShow(): void {
    this.reload();
    // **双保险**（2026-10-13 模拟器实测抓到，与 Rock阅读 进度 bug 同构）：
    // router.back 时本页 onPageShow 与 Editor.aboutToDisappear 的 save() **顺序不保证** ——
    // onPageShow 先跑就会读到旧索引（实拍：给今天的日记加标签/收藏后返回，列表不刷新，
    // 重进编辑器却发现数据都在 —— 索引是新的，只是首页读早了）。
    // 短延时再拉一次，确保读库落在 Editor 落库之后。代价：多一次内存索引读取（零 IO）。
    setTimeout(() => {
      hilog.info(DOMAIN, TAG, 'onPageShow deferred reload fired');
      this.reload();
    }, 80);
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

  /**
   * 筛选 chip（收藏 / 心情 / 标签）—— 选中才亮。
   *
   * ⚠️ 用真正的 `Button`，不用 `Text(...).onClick(...)`：伪按钮没有按压反馈、
   * 读屏不报"按钮"、无法聚焦 —— 而筛选是高频操作，这三条都得有。
   * `ButtonType.Normal` **必须显式写**：它的默认值在 **API 18 变过**
   * （<18 是 `Capsule`，≥18 是 `ROUNDED_RECTANGLE`），我们覆盖 API 16+，
   * 不写死的话不同版本设备上形状不一致。
   */
  @Builder
  private chip(label: string, active: boolean, onTap: () => void) {
    Button(label, { type: ButtonType.Normal, stateEffect: true })
      .fontSize(RJ_FS_CAPTION)
      .fontColor(active ? $r('app.color.rj_text') : $r('app.color.rj_text3'))
      .backgroundColor(active ? $r('app.color.rj_g100') : $r('app.color.rj_card'))
      .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
      .margin({ right: RJ_SP_MD })
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
    // 第三参 today：月历上"今天"必须被认出来（第一性原则 —— 日记 app 的一切围绕今天，
    // 而原来今天和其他 30 个格子长得一模一样，用户每天第一眼找不到"今天"）。
    // 第四参 wordsMap：当天总字数 ⇒ 格子茶褐色阶（Booka/GitHub 贡献图模式：深浅=当天量）。
    const wordsMap: Record<string, number> = {};
    for (let i: number = 0; i < this.metas.length; i++) {
      const d: string = this.metas[i].date;
      wordsMap[d] = (wordsMap[d] !== undefined ? wordsMap[d] : 0) + this.metas[i].words;
    }
    return monthGrid(this.monthKey, this.store.allDates(), todayKey(), wordsMap).slice(0, this.calRows() * 7);
  }

  /**
   * 热度色阶填充（2026-10-15 借鉴 Booka/GitHub 贡献图：**颜色深浅 = 当天写作量**）。
   * 茶褐色阶 4 档（全 app 唯一彩色家族）：1-99 淡 / 100-399 中淡 / 400-799 中深 / 800+ 深。
   * 阈值取"努力看得见但不制造焦虑"：80 字一小段也有一格淡印（写了就算），
   * 800+ 长文才拿最深（和 brand 同色，那是"重度倾诉"的一天）。
   */
  private heatFill(cell: MonthCell): ResourceColor {
    if (!cell.hasNote) {
      return Color.Transparent;
    }
    if (cell.words >= 800) {
      return $r('app.color.rj_heat4');
    }
    if (cell.words >= 400) {
      return $r('app.color.rj_heat3');
    }
    if (cell.words >= 100) {
      return $r('app.color.rj_heat2');
    }
    return $r('app.color.rj_heat1');
  }

  /** 热度字色：深底（400+ 的 3/4 档）纸白字、其余墨字；对比度全部 ≥ 4.5:1 */
  private heatText(cell: MonthCell): ResourceColor {
    if (cell.hasNote && cell.words >= 400) {
      return $r('app.color.rj_bg');
    }
    return cell.inMonth ? $r('app.color.rj_text') : $r('app.color.rj_text3');
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
          .fontSize(RJ_FS_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
        if (DEV_SHOW_BADGE) {
          Text('DEV')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text3'))
            .border({ width: 1, color: $r('app.color.rj_text3') })
            .padding({ left: RJ_SP_SM, right: RJ_SP_SM, top: RJ_SP_XS, bottom: RJ_SP_XS })
            .margin({ left: RJ_SP_MD })
        }
        Blank()
        /**
         * 「写今天」—— 这是本应用**唯一一个"创造"动作**，也是一天里最高频的动作，
         * 所以它必须拿最高视觉权重：不该缩在日历和列表下面，也不该只是红字当链接。
         *
         * 用 `ButtonType.Normal` + **自绘实心**（墨底/纸白字/大圆角）。
         * ⚠️ 2026-10-14 实测教训：**不能用 `buttonStyle(EMPHASIZED)`** —— 系统强调样式
         *    会用它自己的背景规则**覆盖**我们的 `backgroundColor`（墨底被冲成白色，
         *    配纸白字 = 整个按钮看不见字，党哥原话"两个三个点"就是指这个）。
         *    自绘同样有按压反馈（stateEffect），样式还完全可控。
         *
         * 填充色取 `rj_accent` = **墨色**（浅 #191919 / 深 #F0EBE0）：最强权重，且纸感统一。
         * （2026-10-14「纸·墨·茶」转向：accent 原为官方系统蓝，因"系统蓝 vs app 蓝分不清"
         *  及"蓝绿同屏发浑"两个问题，chrome 全改中性墨，彩色只留茶褐印记一彩。）
         * 文字色用 `rj_bg`（浅色下纸白字压墨钮 16.9:1、深色下黑字压暖白钮 18:1）。
         *
         * ⚠️ `ButtonType.Normal` 显式写死：默认值在 **API 18 变过**
         *    （<18 = Capsule，≥18 = ROUNDED_RECTANGLE），我们覆盖 API 16+，
         *    不写死则不同版本设备上形状不一致。圆角另外显式给（API 7 的通用属性）。
         */
        Button('写今天', { type: ButtonType.Normal, stateEffect: true })
          .backgroundColor($r('app.color.rj_accent'))
          .fontColor($r('app.color.rj_bg'))
          .fontSize(RJ_FS_CAPTION)
          .fontWeight(FontWeight.Bold)
          .borderRadius(RJ_RADIUS_LG)
          .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .margin({ right: RJ_SP_MD })
          .onClick(() => {
            this.open(todayKey());
          })
        /**
         * 「月历 | 时光」**分段控件**（2026-10-14 党哥：原「月/时光」单按钮"转换奇怪"）。
         *
         * 原方案病根：一个 TEXTUAL 按钮同时承担"显示当前态"和"切换动作"—— 用户看到
         * 「月」会以为"点我去月视图"，实际却是"你已经在月视图，点我离开"，反直觉；
         * 且整页瞬切无空间隐喻、退出重进不记偏好。
         * 分段控件两边都可见、选中态墨色明确 ⇒ 零学习成本；滑动手势见视图区
         * （月历左滑进时光、时光右滑回月历）；偏好落 ViewPrefs 冷启动恢复。
         *
         * 视觉：选中段墨填充（与「写今天」同色的实心=可点），两个按钮各自圆角。
         * ⚠️ **内嵌 Row 不加底槽**（无 backgroundColor/padding/radius）：
         *    2026-10-14 实测，带底槽的内嵌 Row 会让**兄弟节点「写今天」的背景失效**
         *    （墨底被冲白、纸白字看不见 —— 党哥报的"两个三个点"就是它）。
         *    ArkUI 渲染怪癖：同一 Row 内带背景容器疑似干扰兄弟 Button 的背景合成。
         *    规避 = 分段自身无底槽，选中态由按钮自己的墨填充表达。
         */
        Row() {
          // ⚠️ 2026-10-15 实测三层坑（党哥报"两个三个点、没文字说明"就是它）：
          //   ① Button 默认 padding 会挤文字；② 直接给 Button `.height(30)` 与 layoutWeight
          //    冲突会把文字**垂直压扁**（两字只剩 35px，settings 正常 962px）；
          //   ③ 正确解法 = 分段 Row 定高 30vp，按钮 `height('100%')` 撑满、`padding(0)`，
          //    文字垂直居中完整渲染。
          Button('月历', { type: ButtonType.Normal, stateEffect: true })
            .fontSize(RJ_FS_META)
            .fontWeight(this.mode === 'month' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.mode === 'month' ? $r('app.color.rj_bg') : $r('app.color.rj_text3'))
            .backgroundColor(this.mode === 'month' ? $r('app.color.rj_accent') : Color.Transparent)
            .layoutWeight(1)
            .height('100%')
            .padding(0)
            .borderRadius(RJ_RADIUS_SM)
            .onClick(() => {
              this.setMode('month');
            })
          Button('时光', { type: ButtonType.Normal, stateEffect: true })
            .fontSize(RJ_FS_META)
            .fontWeight(this.mode === 'timeline' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.mode === 'timeline' ? $r('app.color.rj_bg') : $r('app.color.rj_text3'))
            .backgroundColor(this.mode === 'timeline' ? $r('app.color.rj_accent') : Color.Transparent)
            .layoutWeight(1)
            .height('100%')
            .padding(0)
            .borderRadius(RJ_RADIUS_SM)
            .onClick(() => {
              this.setMode('timeline');
            })
        }
        .height(30)
        // 96vp ≈ 288px：顶部一行要塞 标题+写今天+分段+设置（党哥屏 1256px @3x）——
        // 实测 148vp 把「设置」挤出屏幕、120vp 把 Blank 压成 0（写今天紧贴标题）。
        // 分段是指示器不是主行动，让位到"不挤且仍有呼吸"的最大宽度。
        // ⚠️ 不加底槽的原因见上方注释（兄弟按钮背景失效的渲染怪癖）。
        .width(96)
        .margin({ right: RJ_SP_MD })
        // 设置（导出备份的生命线入口 —— 藏深了等于没有）
        Button('设置', { type: ButtonType.Normal, stateEffect: true })
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .padding({ left: RJ_SP_SM, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_MD })

      // 坚持写：连续天数 + 今天写没写（今天还没写用强调色，直接推动今天的动作）
      Row() {
        if (this.stats.streak > 0) {
          Text('连续 ' + this.stats.streak + ' 天')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text3'))
        }
        Text('共 ' + this.stats.total + ' 篇')
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .margin({ left: RJ_SP_LG })
        Blank()
        if (!this.stats.wroteToday) {
          // 同理：提示性文字不用 accent（主行动"写今天"才是唯一的蓝）
          Text('今天还没写')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text2'))
        }
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })

      // 备份提醒：生命线靠自觉是不成立的，到期提醒一次（不自动写文件、不重复骚扰）
      // ⚠️ 用 text2 不用 accent：accent 是**主行动专属**（写今天），提醒性文字也抢蓝色
      //    会让"最重要的那个按钮"不再最显眼（2026-10-12 模拟器实测后的收尾）
      if (this.backupDue) {
        Row() {
          Text('距上次备份超过 30 天了 · 去备份')
            .fontSize(RJ_FS_CAPTION)
            .fontColor($r('app.color.rj_text2'))
            .layoutWeight(1)
          Text('去备份 ›')
            .fontSize(RJ_FS_CAPTION)
            .fontColor($r('app.color.rj_text2'))
            .onClick(() => {
              router.pushUrl({ url: 'pages/Settings' });
            })
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })
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
        // 标签入口（默认收起，原因见 `tagsExpanded` 的注释）。
        // 正在生效时把标签名直接写在入口上 —— 否则收起后看不出"正在筛"。
        if (this.allTags.length > 0) {
          this.chip('标签' + (this.filterTag.length > 0 ? ' · ' + this.filterTag : '') +
            (this.tagsExpanded ? ' ▾' : ' ▸'),
            this.tagsExpanded || this.filterTag.length > 0, () => {
            this.tagsExpanded = !this.tagsExpanded;
          })
        }
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_SM })

      if (this.allTags.length > 0 && this.tagsExpanded) {
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
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })
      }

      // 搜索
      TextInput({ placeholder: '搜日记', text: this.query })
        .fontSize(RJ_FS_CALLOUT)
        .backgroundColor($r('app.color.rj_card'))
        .fontColor($r('app.color.rj_text'))
        .placeholderColor($r('app.color.rj_text3'))
        .height(38)
        // 热区补到 44vp（38 的框 + 上下各扩 3，视觉不变、手指好按）
        .responseRegion({ x: 0, y: -3, width: '100%', height: 44 })
        .margin({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })
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
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text3'))
            .width('100%')
            .padding({ bottom: RJ_SP_MD })
          ForEach(this.recall, (card: RecallCard) => {
            Row() {
              Column() {
                Row() {
                  // 「N 年前」是**时光的印记** ⇒ 品牌茶褐（信息标签不是行动，
                  // 但它值得被看见 —— 这是全应用最有"时间复利"感的一行字）
                  Text(card.years)
                    .fontSize(RJ_FS_META)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_brand'))
                  Text(card.meta.date)
                    .fontSize(RJ_FS_META)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                    .margin({ left: RJ_SP_MD })
                  if (this.moodEmoji(card.meta).length > 0) {
                    Text(this.moodEmoji(card.meta))
                      .fontSize(RJ_FS_CAPTION)
                      .margin({ left: RJ_SP_MD })
                  }
                }
                if (card.preview.length > 0) {
                  // 摘要用 serif（2026-10-15 党哥：读的界面要"纸质书信"质感）——
                  // 衬线是纸上阅读的笔画语言；系统无衬线中文字体时自动回退无衬线，不摔。
                  Text(card.preview)
                    .fontSize(RJ_FS_CALLOUT)
                    .fontFamily('serif')
                    .fontColor($r('app.color.rj_text'))
                    .margin({ top: RJ_SP_SM })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: RJ_SP_MD, bottom: RJ_SP_MD })
            .onClick(() => {
              this.open(card.meta.date, card.meta.id);
            })
          }, (card: RecallCard) => card.meta.id)
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_SM, bottom: RJ_SP_LG })
        .border({ width: { bottom: 1 }, color: $r('app.color.rj_line') })
      }

      if (this.query.length > 0) {
        // 搜索结果
        if (this.hits.length === 0) {
          Text('没有找到')
            .fontSize(RJ_FS_CAPTION)
            .fontColor($r('app.color.rj_text3'))
            .margin({ top: RJ_SP_VOID })
        }
        List() {
          ForEach(this.hits, (hit: SearchHit) => {
            ListItem() {
              Column() {
                Text(hit.date)
                  .fontSize(RJ_FS_CAPTION)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text3'))
                Text(hit.snippet)
                  .fontSize(RJ_FS_CALLOUT)
                  .fontColor($r('app.color.rj_text'))
                  .margin({ top: RJ_SP_SM })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })
              .width('100%')
            }
            .onClick(() => {
              this.open(hit.date, hit.id);
            })
          }, (hit: SearchHit) => 'h:' + hit.id)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      } else if (this.mode === 'month') {
        // 月视图
        Row() {
          // 月份切换：真 Button（原来是 Text.onClick 伪按钮 —— 无按压反馈、读屏不报"按钮"、
          // 无法聚焦；这是 A 类无障碍问题）。44vp 热区用 responseRegion 补，不撑高行
          Button('<', { type: ButtonType.Normal, stateEffect: true })
            .fontSize(RJ_FS_BODY)
            .fontColor($r('app.color.rj_text2'))
            .backgroundColor(Color.Transparent)
            .padding({ left: RJ_SP_LG, right: RJ_SP_MD })
            .responseRegion({ x: 0, y: -8, width: '100%', height: 44 })
            .accessibilityText('上一个月')
            .onClick(() => {
              this.monthKey = shiftMonth(this.monthKey, -1);
            })
          Text(this.monthKey)
            .fontSize(RJ_FS_CALLOUT)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text'))
            .letterSpacing(2)
          Button('>', { type: ButtonType.Normal, stateEffect: true })
            .fontSize(RJ_FS_BODY)
            .fontColor($r('app.color.rj_text2'))
            .backgroundColor(Color.Transparent)
            .padding({ left: RJ_SP_MD, right: RJ_SP_LG })
            .responseRegion({ x: 0, y: -8, width: '100%', height: 44 })
            .accessibilityText('下一个月')
            .onClick(() => {
              this.monthKey = shiftMonth(this.monthKey, 1);
            })
        }
        .margin({ bottom: RJ_SP_MD })

        // 6×7 网格
        Grid() {
          ForEach(this.cells(), (cell: MonthCell) => {
            GridItem() {
              /**
               * 「有日记」的标记点：放在数字**正下方**（原来钉在 TopEnd 角上，
               * 正好压住数字 —— 实拍反馈"红点挡住数字"）。
               * 点位占**固定高度**：没日记的日子用透明圆占位，
               * 这样有/没日记的数字保持在同一条水平线上，不会上下跳。
               */
              /**
               * 格子 = 当天写作量的**热度色阶**（茶褐 4 档，2026-10-15 借鉴 Booka/GitHub
               * 贡献图：颜色深浅 = 当天量）。原来的 5px 圆点去掉 —— 色阶底已表达
               * "写过 + 写多少"，圆点是冗余。
               * 今天不抢色阶的戏：**墨色细描边**标识（"待钤印/正在钤印的一天"），
               * 底色仍参与色阶（今天写了也有热度）。日历格管"印记"，
               * 「写今天」蓝钮管"行动"，两个语义不混。
               */
              Column() {
                Text(cell.day.toString())
                  .fontSize(RJ_FS_CALLOUT)
                  .fontFamily('monospace')
                  .fontColor(this.heatText(cell))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .backgroundColor(this.heatFill(cell))
                  // ⚠️ border **所有格子都给**（今天墨色、其余透明）：只给今天加描边会让
                  //    它的文字框比别的格高出一截（1.5vp×2），月历行高不齐会跳（实测抓到）。
                  .border({
                    width: 1.5,
                    color: cell.isToday ? $r('app.color.rj_accent') : Color.Transparent,
                    radius: RJ_RADIUS_SM
                  })
              }
              .justifyContent(FlexAlign.Center)
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
        .padding({ left: RJ_SP_XL, right: RJ_SP_XL })

        // 本月日记列表（**只列这个月** —— 顶部月份导航与列表范围必须一致，见 monthRows）
        if (this.monthRows().length === 0) {
          Text('这个月还没有日记')
            .fontSize(RJ_FS_CAPTION)
            .fontColor($r('app.color.rj_text3'))
            .margin({ top: RJ_SP_XXXL })
        }
        List() {
          ForEach(this.monthRows(), (row: TimelineRow) => {
            ListItem() {
              Column() {
                Row() {
                  Text(row.meta !== null ? row.meta.date : '')
                    .fontSize(RJ_FS_CAPTION)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text2'))
                  if (row.showTime && row.meta !== null) {
                    Text(timeOfDay(row.meta.createdAt))
                      .fontSize(RJ_FS_META)
                      .fontFamily('monospace')
                      .fontColor($r('app.color.rj_text3'))
                      .margin({ left: RJ_SP_MD })
                  }
                  if (row.meta !== null && this.moodEmoji(row.meta).length > 0) {
                    Text(this.moodEmoji(row.meta))
                      .fontSize(RJ_FS_CALLOUT)
                      .margin({ left: RJ_SP_LG })
                  }
                  if (row.meta !== null && row.meta.favorite) {
                    Text('★')
                      .fontSize(RJ_FS_CALLOUT)
                      // 收藏 = 钤印 ⇒ 品牌茶褐（同 Editor 收藏星、同日历日期点，三处一个色）
                      .fontColor($r('app.color.rj_brand'))
                      .margin({ left: RJ_SP_LG })
                  }
                  Blank()
                  Text(row.meta !== null ? row.meta.words + ' 字' : '')
                    .fontSize(RJ_FS_META)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                }
                .width('100%')
                // 标签：用户给的主题词，找得回来的第二条路
                if (row.meta !== null && row.meta.tags.length > 0) {
                  Text('#' + row.meta.tags.join(' #'))
                    .fontSize(RJ_FS_META)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                    .margin({ top: RJ_SP_SM })
                }
                // 摘要来自索引缓存 ⇒ 零额外 IO，月视图也能"看到自己写过的话"
                if (row.meta !== null && row.meta.preview.length > 0) {
                  // serif = 纸上阅读的笔画语言（党哥 2026-10-15：读的界面要纸质书信质感）
                  Text(row.meta.preview)
                    .fontSize(RJ_FS_CALLOUT)
                    .fontFamily('serif')
                    .fontColor($r('app.color.rj_text'))
                    .margin({ top: RJ_SP_SM })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })
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
              .fontSize(RJ_FS_CALLOUT)
              .fontColor($r('app.color.rj_text3'))
            Text('点下面的按钮，写今天')
              .fontSize(RJ_FS_CAPTION)
              .fontColor($r('app.color.rj_text3'))
              .margin({ top: RJ_SP_MD })
          }
          .margin({ top: RJ_SP_VOID_L })
        }
        // ⚠️ 铁律①：长列表必须 LazyForEach（只构建可见区域），且换数据要走 dataSource.reload
        List() {
          LazyForEach(this.dataSource, (row: TimelineRow) => {
            ListItem() {
              if (row.kind === 'header') {
                Text(row.monthKey)
                  .fontSize(RJ_FS_META)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text3'))
                  .width('100%')
                  .padding({ top: RJ_SP_XL, bottom: RJ_SP_MD })
              } else if (row.meta !== null) {
                Row() {
                  Column() {
                    Row() {
                      Text(row.meta.date)
                        .fontSize(RJ_FS_CAPTION)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.rj_text2'))
                      // 同一天多篇时补个时间，否则几行日期一模一样、看不出是几篇
                      if (row.showTime) {
                        Text(timeOfDay(row.meta.createdAt))
                          .fontSize(RJ_FS_META)
                          .fontFamily('monospace')
                          .fontColor($r('app.color.rj_text3'))
                          .margin({ left: RJ_SP_MD })
                      }
                      if (this.moodEmoji(row.meta).length > 0) {
                        Text(this.moodEmoji(row.meta))
                          .fontSize(RJ_FS_CALLOUT)
                          .margin({ left: RJ_SP_MD })
                      }
                      if (row.meta.favorite) {
                        Text('★')
                          .fontSize(RJ_FS_CALLOUT)
                          // 收藏 = 钤印 ⇒ 品牌茶褐（与月视图 ★、Editor 收藏星、日历日期点四处同色）
                          .fontColor($r('app.color.rj_brand'))
                          .margin({ left: RJ_SP_MD })
                      }
                      Blank()
                      Text(row.meta.words + ' 字')
                        .fontSize(RJ_FS_META)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.rj_text3'))
                    }
                    .width('100%')
                    if (row.meta.tags.length > 0) {
                      Text('#' + row.meta.tags.join(' #'))
                        .fontSize(RJ_FS_META)
                        .fontFamily('monospace')
                        .fontColor($r('app.color.rj_text3'))
                        .margin({ top: RJ_SP_SM })
                    }
                    // 摘要来自索引缓存（零额外 IO）；老数据没有 ⇒ 这一行就没有，不硬凑。
                    // serif = 纸上阅读的笔画语言（党哥 2026-10-15：读的界面要纸质书信质感）
                    if (row.meta.preview.length > 0) {
                      Text(row.meta.preview)
                        .fontSize(RJ_FS_CALLOUT)
                        .fontFamily('serif')
                        .fontColor($r('app.color.rj_text'))
                        .margin({ top: RJ_SP_SM })
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
                      .borderRadius(RJ_RADIUS_SM)
                      .margin({ left: RJ_SP_LG })
                  }
                }
                .width('100%')
                .padding({ top: RJ_SP_LG, bottom: RJ_SP_LG })
              }
            }
            .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL })
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
    // 视图切换**滑动手势**（2026-10-14 党哥：「月/时光」整页瞬切"转换奇怪"）：
    // 月历左滑进时光、时光右滑回月历 —— 滑一下给两个视图"并排"的空间隐喻，
    // 与分段控件双通道（点/滑都行，系统记住偏好）。
    // ⚠️ 挂根 Column 而非内层 Stack：横滑方向与 List 的纵向滚动**正交**（系统仲裁互不抢），
    //    与 Button 的 tap 也不冲突（位移超 60vp 才算滑，轻点照常点）。
    // ⚠️ 搜索中禁用：搜索结果是覆盖层，滑它换视图会更懵（"我滑了却没换？"）。
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 60 })
        .onActionEnd((e: GestureEvent) => {
          if (this.query.length > 0) {
            return;
          }
          if (e.offsetX <= -60) {
            this.setMode('timeline');
          } else if (e.offsetX >= 60) {
            this.setMode('month');
          }
        })
    )
  }
}
