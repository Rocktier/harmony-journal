import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { curves, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { DEV_SHOW_BADGE } from '../common/DevFlags';
import { ChevronButton } from '../components/ChevronButton';
import { TimelineDataSource } from '../common/TimelineDataSource';
import { ImageStore } from '../data/ImageStore';
import {
  JournalStats, MOODS, MonthCell, Mood, NoteMeta, NoteText, SearchHit, TimelineRow, collectTags,
  capsuleBadge, capsuleLocked, computeStats, countsForStats, filterMetas, isCapsule, moodById,
  monthGrid, monthOf, monthRowCount, onThisDayDates, previewText, searchNotes, shiftMonth, timeOfDay,
  timelineRows, todayKey, yearsAgoLabel
} from '../data/NoteMeta';
import { NoteStore } from '../data/NoteStore';
import { getStore } from '../data/NoteStoreHolder';
import { ViewPrefs, ViewMode } from '../data/ViewPrefs';
import { RJ_FS_BODY, RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_META, RJ_FS_TITLE, RJ_RADIUS_LG, RJ_RADIUS_MD, RJ_RADIUS_SM, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID, RJ_SP_VOID_L, RJ_SP_XL, RJ_SP_XS, RJ_SP_XXL, RJ_SP_XXXL } from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

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
const DOMAIN: number = 0xD002;
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
  /** 运行时色板（深浅切换 = AppStorage 换对象，页面栈不动；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  @State private metas: NoteMeta[] = [];
  /**
   * 日期 → 当天总字数（月历热力色阶的数据源）。
   *
   * ⚠️ 为什么必须是 @State 而不是 cells() 里现算：ArkUI 的 `ForEach` 按 **key**
   *    判定"这一项变没变"（我们用的是 `cell.date`）。保存一篇新日记后，那天格子的
   *    key 和保存前一模一样 ⇒ ForEach 认为该项未变、**不重新执行 item builder**，
   *    于是闭包里那个旧的 `cell.words` 原样留着 —— 表现就是"保存完日历不染色，
   *    切到时光再切回来（组件重建）才正常"（2026-10-20 华为审核实测报的同一个 bug）。
   *    把数据源提成 @State，builder 里读 `this.heatByDate[...]` 才会建立响应依赖，
   *    reload 时换个新对象即触发重渲染 —— 这是正解；比"key 里塞版本号强制全量重建"
   *    干净（那个方案会白重建 42 个格子）。
   */
  @State private heatByDate: Record<string, number> = {};
  /**
   * 已收藏的 id 集合（与 heatByDate 同一个理由提成 @State）
   *
   * ⚠️ 收藏星在时光轴行里，而 LazyForEach 按 key（`n:`+id）判定要不要重建 item ——
   *    翻转收藏后 key 不变 ⇒ itemGenerator 不重新执行 ⇒ 星还是原来那颗。
   *    实测踩到（2026-10-20 修完第一个 bug 后当场抓到，日志里 toggleFavorite
   *    已经成功、界面却没反应）。builder 里读 `this.favIds.has(...)` 才能建立
   *    响应依赖，reload 换个新 Set 即重渲染。
   */
  @State private favIds: Set<string> = new Set<string>();
  /** 哪一篇的 ★ 正在跳（收藏脉冲，2026-10-23 复评整改：与 Editor ★ 的 spring 弹跳同语言） */
  @State private favKickId: string = '';
  /** 有日记的日期（与 heatByDate 同批更新）—— 判"这天写没写过"用它，见 wordsOf */
  @State private markedDates: string[] = [];
  /**
   * 有**时间胶囊**的日期（月历锁点用，与 heatByDate 同批更新）。
   * 只存"这天有胶囊"，不存锁没锁 —— 锁点表达的是"这有天写的信"，
   * 到期后锁点自然消失（reload 时按当前时间重算）。
   */
  @State private capsuleDates: string[] = [];
  @State private mode: string = 'month';
  @State private monthKey: string = monthOf(todayKey());
  @State private query: string = '';
  /**
   * 搜索的解密会话缓存（2026-10-22 评审 P1-6）：
   * 原实现每次按键都逐篇"文件 IO + AES 解密"构建 texts —— 几百篇后每键必卡。
   * 现在把「构建 texts」（贵）与「按 query 过滤」（纯内存）分离：
   * 同一批数据（metas 未变）只解密一次，后续按键只重跑 searchNotes。
   * reload() 会把 searchSessionValid 置 false（数据变了必须重建）。
   */
  private searchSessionTexts: NoteText[] = [];
  private searchSessionValid: boolean = false;
  /** 搜索防抖定时器（300ms；键盘每键一次 onChange，逐篇解密扛不住连击） */
  private searchTimer: number = -1;
  @State private hits: SearchHit[] = [];
  @State private loaded: boolean = false;
  /**
   * 月历空态开关（2026-10-24 修复，独立布尔而不是 if 里现算 this.metas.length）。
   *
   * ⚠️ 原来在 build 的 if 里直接写 `this.loaded && this.metas.length === 0`：
   *    解锁进首页后 metas 有 1 篇，**空态却一直显示**（模拟器实拍 + 双探针证实
   *    metas/heatByDate/loaded 三值全对、渲染不更新）。ArkTS 对 if 条件里
   *    数组 .length 的响应追踪不可靠 ⇒ 抽成 @State 布尔，reload 里显式赋值。
   */
  @State private monthEmpty: boolean = false;
  // P0-5 平板适配决策记录（2026-10-22）：月视图不做断点分栏。
  // 月历是 7 列周结构（列数不可变）；日记列表行是"日期 + 短摘要"，全宽拉伸
  // 不产生 Reader/Editor 那种"一行 40+ 字"的可读性问题；宽屏分栏（月历|列表）
  // 属大改，收益不抵回归风险。编辑器侧的版心封顶已做（Editor.ets maxWidth 560）。
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
    const nowMs: number = Date.now();
    // 热力数据源必须与 metas 同批更新（换新对象才会触发依赖它的 Grid 重渲染）
    const heat: Record<string, number> = {};
    const marked: string[] = [];
    const capsule: string[] = [];
    for (let i: number = 0; i < this.metas.length; i++) {
      const d: string = this.metas[i].date;
      // 未到期胶囊不计入热度（从格子颜色深浅能反推信写了多长 —— 封存纪律的统计侧对应物）
      if (countsForStats(this.metas[i], nowMs)) {
        heat[d] = (heat[d] !== undefined ? heat[d] : 0) + this.metas[i].words;
      }
      if (!marked.includes(d)) {
        marked.push(d);
      }
      if (capsuleLocked(this.metas[i], nowMs) && !capsule.includes(d)) {
        capsule.push(d);
      }
    }
    this.heatByDate = heat;
    this.markedDates = marked;
    this.capsuleDates = capsule;
    // 收藏集合同批更新（新 Set ⇒ 依赖它的时光轴收藏星才会重渲染）
    const fav: Set<string> = new Set<string>();
    for (let i: number = 0; i < this.metas.length; i++) {
      if (this.metas[i].favorite) {
        fav.add(this.metas[i].id);
      }
    }
    this.favIds = fav;
    this.loaded = true;
    // 月历空态显式赋值（2026-10-24：if 里现算 .length 不可靠，见 monthEmpty 声明处注释）
    this.monthEmpty = this.metas.length === 0;
    this.allTags = collectTags(this.metas);
    this.stats = computeStats(this.metas, todayKey(), nowMs);
    // 数据变了 ⇒ 搜索的解密缓存失效（见 runSearch 的会话缓存说明）
    this.searchSessionValid = false;
    this.refreshData();
    this.buildRecall();
    hilog.info(DOMAIN, TAG, 'index loaded: %{public}d notes, recall %{public}d', this.metas.length, this.recall.length);
  }

  /** 把筛选后的结果灌进时间轴（换数据必须走 reload，否则 LazyForEach 不重画） */
  private refreshData(): void {
    const shown: NoteMeta[] = filterMetas(this.metas, this.onlyFavorite, this.filterMood, this.filterTag);
    // nowMs 必须传：胶囊行的 key 带锁定/倒计时标签（见 noteRowKey）——
    // 普通日记设为胶囊后 key 会变，LazyForEach 才会重建那一行
    // （2026-10-21 实测：不传的话列表继续剧透胶囊的前 42 字摘要）
    this.dataSource.reload(timelineRows(shown, Date.now()));
    hilog.info(DOMAIN, TAG, 'refreshData: metas=%{public}d shown=%{public}d rows=%{public}d fav=%{public}s mood=[%{public}s]',
      this.metas.length, shown.length, this.dataSource.totalCount(),
      this.onlyFavorite ? 'y' : 'n', this.filterMood);
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
    // ⚠️ 选中态必须一眼可见（2026-10-25 华为反馈：「收藏/心情筛选没有高亮变化」）。
    //    原写法是 g100(#E3E6E8) vs card(#FFF) —— 浅灰 vs 白，在真机上几乎看不出差别。
    //    改成本家族既有的「选中 = 墨底反白」（与外观 chip 选中态同一语言）：
    //    墨色 accent 底 + 反白字 + 加粗，未选中仍是纸面底 + 次级字色。
    Button(label, { type: ButtonType.Normal, stateEffect: true })
      .fontSize(RJ_FS_CAPTION)
      .fontColor(active ? this.palette.bg : this.palette.text3)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
      .backgroundColor(active ? this.palette.accent : this.palette.card)
      .border({ width: active ? 0 : 1, color: this.palette.line })
      .borderRadius(RJ_RADIUS_MD)
      .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
      .margin({ right: RJ_SP_MD })
      .accessibilityText(label + (active ? '，已选中' : ''))
      .onClick(() => {
        onTap();
      })
  }

  /** 「那年今日」：把往年同日的日记预先算成卡片（渲染时零 IO） */
  private buildRecall(): void {
    const today: string = todayKey();
    const nowMs: number = Date.now();
    const dates: string[] = onThisDayDates(this.store.allDates(), today);
    const cards: RecallCard[] = [];
    for (let i: number = 0; i < dates.length && cards.length < RECALL_MAX; i++) {
      const list: NoteMeta[] = this.store.entriesOfDate(dates[i]);
      for (let j: number = 0; j < list.length && cards.length < RECALL_MAX; j++) {
        const m: NoteMeta = list[j];
        // 未到期胶囊不进「那年今日」：这一栏的看点就是摘要，而胶囊的摘要
        // 不允许被任何人（包括明年的自己）提前看到（封存纪律，与搜索同理）
        if (capsuleLocked(m, nowMs)) {
          continue;
        }
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
    return monthGrid(this.monthKey, this.store.allDates(), todayKey(), this.heatByDate).slice(0, this.calRows() * 7);
  }

  /**
   * 这天写了多少字；`-1` = 这天没有日记（热力色阶与字色共用）。
   *
   * ⚠️ 不能用 `Object.prototype.hasOwnProperty.call(...)` 判 key 在不在 ——
   *    ArkTS 禁 Function.apply/call 与 prototype 赋值（arkts-no-func-apply-call），
   *    编译直接报错。改用并行的日期数组（markedDates）判存在，语义也更直白。
   * ⚠️ `0` = 这天只有未到期的胶囊（有日记但不计热度）⇒ 色阶走透明，
   *    由锁点单独表达 —— 颜色深浅=字数是会泄密的（见 reload 的 countsForStats）。
   */
  private wordsOf(date: string): number {
    if (!this.markedDates.includes(date)) {
      return -1;
    }
    const w: number = this.heatByDate[date];
    return w === undefined ? 0 : w;
  }

  /**
   * 热度色阶填充（2026-10-15 借鉴 Booka/GitHub 贡献图：**颜色深浅 = 当天写作量**）。
   * 茶褐色阶 4 档（全 app 唯一彩色家族）：1-99 淡 / 100-399 中淡 / 400-799 中深 / 800+ 深。
   * 阈值取"努力看得见但不制造焦虑"：80 字一小段也有一格淡印（写了就算），
   * 800+ 长文才拿最深（和 brand 同色，那是"重度倾诉"的一天）。
   *
   * ⚠️ 读的是 `this.heatByDate` 而不是 `cell.words` —— 后者是闭包里的旧对象，
   *    ForEach 不重建就拿它没法刷新（保存日记不染色的根因，见 heatByDate 注释）。
   */
  private heatFill(cell: MonthCell): ResourceColor {
    const w: number = this.wordsOf(cell.date);
    // -1 = 没日记；0 = 纯胶囊日（无色阶，只给锁点 —— 防从颜色反推信的长短）
    if (w <= 0) {
      return Color.Transparent;
    }
    if (w >= 800) {
      return this.palette.heat4;
    }
    if (w >= 400) {
      return this.palette.heat3;
    }
    if (w >= 100) {
      return this.palette.heat2;
    }
    return this.palette.heat1;
  }

  /** 热度字色：深底（400+ 的 3/4 档）纸白字、其余墨字；对比度全部 ≥ 4.5:1 */
  private heatText(cell: MonthCell): ResourceColor {
    if (this.wordsOf(cell.date) >= 400) {
      return this.palette.bg;
    }
    return cell.inMonth ? this.palette.text : this.palette.text3;
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
    const rows: TimelineRow[] = timelineRows(inMonth, Date.now());
    const notes: TimelineRow[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      if (rows[i].kind === 'note') {
        notes.push(rows[i]);
      }
    }
    return notes;
  }

  /**
   * 打开一篇：`id` 有值就精确打开那篇（搜索结果），否则交给编辑器按 date 取这天最新的一篇
   *
   * ⚠️ 时间胶囊路由拦截（2026-10-20）：**未到期的胶囊不进编辑器** ——
   *    编辑器整页"可编辑"的暗示会让人以为锁坏了，且多一分误触泄密的面。
   *    统一先去 pages/Capsule（只读详情：倒计时 + 解锁日）；到期的正常进编辑器。
   */
  private open(date: string, id: string = ''): void {
    if (id.length > 0) {
      const m: NoteMeta | null = this.store.byId(id);
      if (m !== null && capsuleLocked(m, Date.now())) {
        router.pushUrl({ url: 'pages/Capsule', params: { id: id } }).catch((e: Error) => {
          hilog.error(DOMAIN, TAG, 'pushUrl Capsule failed: %{public}s', JSON.stringify(e));
        });
        return;
      }
    }
    const payload: EntryParamPayload = { date: date, id: id };
    router.pushUrl({ url: 'pages/Editor', params: payload }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pushUrl failed: %{public}s', JSON.stringify(e));
    });
  }

  /**
   * 时光轴行内的收藏切换（2026-10-20 修华为审核实测 bug：列表里点 ★ 没反应）。
   *
   * 只翻索引里的 `favorite` 位、不重写正文密文 —— 收藏是索引级元数据，
   * 解密+重加密整篇正文只为改一个布尔值，纯属浪费（且多一次 IO 失败面）。
   * 改完必须 reload：`NoteMeta` 不是 @Observed，属性变了不会自己重渲染。
   */
  private toggleFavorite(id: string): void {
    const ok: boolean = this.store.toggleFavorite(id);
    if (!ok) {
      hilog.error(DOMAIN, TAG, 'toggleFavorite failed: %{public}s', id);
      return;
    }
    // 收藏脉冲：跳 320ms（spring 归位）—— 时光轴里点星要有"钤下去"的一拍
    this.favKickId = id;
    setTimeout(() => {
      if (this.favKickId === id) {
        this.favKickId = '';
      }
    }, 320);
    this.reload();
  }

  private runSearch(): void {
    const nowMs: number = Date.now();
    // 会话缓存未命中才解密（数据变了/首次搜索）；命中则直接复用上次的明文
    if (!this.searchSessionValid) {
      const texts: NoteText[] = [];
      for (let i: number = 0; i < this.metas.length; i++) {
        const m: NoteMeta = this.metas[i];
        // 未到期的胶囊不进搜索 —— 命中片段的 snippet 会剧透内容（封存纪律的搜索侧对应物）
        if (capsuleLocked(m, nowMs)) {
          continue;
        }
        const item: NoteText = {
          id: m.id,
          date: m.date,
          text: this.store.textOf(m.id),
          tags: m.tags
        };
        texts.push(item);
      }
      this.searchSessionTexts = texts;
      this.searchSessionValid = true;
    }
    this.hits = searchNotes(this.searchSessionTexts, this.query);
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

  /**
   * 页面转场（2026-10-22 评审 P0-1 动效包）：与 Editor/Settings/Capsule 统一的推栈语言。
   * 主页作为栈底，被 push 时的退出是"让位"（轻微左移+压暗），回来时反向复位。
   */
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
    Column() {
      // 顶部：视图切换 + 月份
      Row() {
        Text('Rock私记')
          .fontSize(RJ_FS_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .letterSpacing(2)
        if (DEV_SHOW_BADGE) {
          Text('DEV')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .border({ width: 1, color: this.palette.text3 })
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
          .backgroundColor(this.palette.accent)
          .fontColor(this.palette.bg)
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
            .fontColor(this.mode === 'month' ? this.palette.bg : this.palette.text3)
            .backgroundColor(this.mode === 'month' ? this.palette.accent : Color.Transparent)
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
            .fontColor(this.mode === 'timeline' ? this.palette.bg : this.palette.text3)
            .backgroundColor(this.mode === 'timeline' ? this.palette.accent : Color.Transparent)
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
          .fontColor(this.palette.text3)
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
            .fontColor(this.palette.text3)
        }
        Text('共 ' + this.stats.total + ' 篇')
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .margin({ left: RJ_SP_LG })
        Blank()
        if (!this.stats.wroteToday) {
          // 同理：提示性文字不用 accent（主行动"写今天"才是唯一的蓝）
          Text('今天还没写')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text2)
        }
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })

      // 筛选条：数据全在索引里 ⇒ 零 IO 成本；几百篇之后这是"还能不能用"的分界线
      Row() {
        // ⚠️ 收藏 chip 走 **if 分支**而不是直接把 @State 当参数传（2026-10-25 实测）：
        //    直接 `this.chip('★ 收藏', this.onlyFavorite, ...)` 时，点了收藏
        //    **列表筛了、chip 却不变色** —— @Builder 的值参数没跟着 @State 重跑
        //    （同一行里 ForEach 里的心情 chip 因 key 带 :on 会重建，所以它是好的）。
        //    拆成 if/else ⇒ 选中态变化时整段重建 ⇒ 高亮一定跟上。
        if (this.onlyFavorite) {
          this.chip('★ 收藏', true, () => {
            this.onlyFavorite = !this.onlyFavorite;
            this.refreshData();
          })
        } else {
          this.chip('★ 收藏', false, () => {
            this.onlyFavorite = !this.onlyFavorite;
            this.refreshData();
          })
        }
        ForEach(MOODS, (m: Mood) => {
          this.chip(m.emoji, this.filterMood === m.id, () => {
            this.filterMood = this.filterMood === m.id ? '' : m.id;
            this.refreshData();
          })
          // key 带选中态（2026-10-25 华为反馈：「选了标签要点第二次才亮」同源）：
          // key 不变 ⇒ ForEach 不重建 item ⇒ chip 的高亮可能停在旧值。
        }, (m: Mood) => m.id + (this.filterMood === m.id ? ':on' : ''))
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
              // 同上：key 带选中态，选中变化必换 key ⇒ chip 一定重建、高亮一定跟上
            }, (t: string) => t + (this.filterTag === t ? ':on' : ''))
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
        .backgroundColor(this.palette.card)
        .fontColor(this.palette.text)
        .placeholderColor(this.palette.text3)
        .height(38)
        // 热区补到 44vp（38 的框 + 上下各扩 3，视觉不变、手指好按）
        .responseRegion({ x: 0, y: -3, width: '100%', height: 44 })
        .margin({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })
        .onChange((v: string) => {
          this.query = v;
          // 防抖 300ms（P1-6）：停止输入半秒才真搜 —— 逐篇解密的成本不该付在每次按键上
          if (this.searchTimer >= 0) {
            clearTimeout(this.searchTimer);
            this.searchTimer = -1;
          }
          if (v.length === 0) {
            this.hits = [];
            return;
          }
          this.searchTimer = setTimeout(() => {
            this.searchTimer = -1;
            this.runSearch();
          }, 300);
        })

      // 那年今日：搜索时不打扰；没有往年内容就**完全不渲染**（不留空壳）
      if (this.query.length === 0 && this.recall.length > 0) {
        Column() {
          Text('那年今日')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
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
                    .fontColor(this.palette.brand)
                  Text(card.meta.date)
                    .fontSize(RJ_FS_META)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
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
                    .fontColor(this.palette.text)
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
            // A 类容器伪按钮：整卡可点但读屏无标签（2026-10-23 复评整改）
            .accessibilityText('那年今日：打开 ' + card.meta.date + ' 的日记')
          }, (card: RecallCard) => card.meta.id)
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_SM, bottom: RJ_SP_LG })
        .border({ width: { bottom: 1 }, color: this.palette.line })
      }

      if (this.query.length > 0) {
        // 搜索结果
        if (this.hits.length === 0) {
          Text('没有找到')
            .fontSize(RJ_FS_CAPTION)
            .fontColor(this.palette.text3)
            .margin({ top: RJ_SP_VOID })
        }
        List() {
          ForEach(this.hits, (hit: SearchHit) => {
            ListItem() {
              Column() {
                Text(hit.date)
                  .fontSize(RJ_FS_CAPTION)
                  .fontFamily('monospace')
                  .fontColor(this.palette.text3)
                Text(hit.snippet)
                  .fontSize(RJ_FS_CALLOUT)
                  .fontColor(this.palette.text)
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
            // A 类容器伪按钮：搜索结果行整行可点但读屏无标签（2026-10-23 复评整改）
            .accessibilityText('打开 ' + hit.date + ' 的日记')
          }, (hit: SearchHit) => 'h:' + hit.id)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: this.palette.line })
      } else if (this.mode === 'month') {
        // 月视图
        // ⚠️ 2026-10-23 复评（横屏/矮屏）：整段外包 Scroll —— 顶部双 Row +
        //    筛选条 + 搜索框 + 月历（最高 300vp）挤在不可滚的父 Column 里，
        //    横屏矮屏时月历区溢出且无滚动手权（内容不可达 = 功能坏）。
        //    月历 Grid 自身高度仍按行数固定（月内不滚），整页才滚。
        //    缩进暂未重排（语法无关，先保正确；整洁化见后续格式化轮）。
        Scroll() {
        Column() {
        Row() {
          // 月份切换：圆形 chevron 图标按钮（2026-10-15 替换裸 `<` `>` 字符按钮）
          ChevronButton({
            side: 'left',
            label: '上一个月',
            onClickHandler: () => {
              this.monthKey = shiftMonth(this.monthKey, -1);
            }
          })
          Text(this.monthKey)
            .fontSize(RJ_FS_CALLOUT)
            .fontFamily('monospace')
            .fontColor(this.palette.text)
            .letterSpacing(2)
          ChevronButton({
            side: 'right',
            label: '下一个月',
            onClickHandler: () => {
              this.monthKey = shiftMonth(this.monthKey, 1);
            }
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
                    color: cell.isToday ? this.palette.accent : Color.Transparent,
                    radius: RJ_RADIUS_SM
                  })
                // 时间胶囊锁点（2026-10-20）：这天有一封还没到期的信。
                // ⚠️ 读 @State 的 capsuleDates 而不是 cell 上的字段 —— 与热度同源的
                //    ForEach 不重建坑（见 heatByDate 头注）；且占位固定高度，
                //    没有胶囊的日子用同高度透明文本占位，数字不下沉。
                Text(this.capsuleDates.includes(cell.date) ? '⏳' : ' ')
                  .fontSize(RJ_FS_META)
                  .fontColor(this.palette.brand)
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .height('100%')
              // 切月浮现（P0-1）：月份切换时全部格子 key 更新 ⇒ 新格子淡入+微缩放，
              // 旧格子淡出 —— "翻到另一页"而不是"瞬间替换"
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
                .animation({ duration: 180, curve: Curve.EaseOut }))
            }
            .onClick(() => {
              this.open(cell.date);
            })
          // A 类容器伪按钮（2026-10-23 复评整改）：GridItem 本身不是 Button，
          // 读屏不报"按钮"也不报哪天 —— 显式补标签（42 格月历全靠它导航）
          .accessibilityText(cell.date + (cell.isToday ? '，今天' : '')
            + (this.capsuleDates.includes(cell.date) ? '，有一封没到期的信' : ''))
          // ⚠️ 2026-10-24 修复：key 必须带 words —— ForEach 按 key 复用 item，
          //    key 不变则 item 里的热度表达式（heatFill 经 wordsOf 读 @State）永驻
          //    首次值（实拍：保存日记后月历格子不着色）。words 进 key 后热度变化
          //    即换 key ⇒ item 重建 ⇒ 重新求值。（cell.words 由 cells() 每次 build
          //    经 monthGrid 现算，本身就是最新的。）
        }, (cell: MonthCell) => cell.date + ':' + cell.words)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        // 行数按当月实际需要（10 月只有 5 行，固定 6 行会白占 1/3 屏）
        .rowsTemplate(this.rowTemplate())
        .height(this.calRows() * 50)
        .padding({ left: RJ_SP_XL, right: RJ_SP_XL })

        // 新用户引导（P2-8，2026-10-22 整改）：月视图原来没有任何空态 ——
        // 第一个月全是空格子，不知道从哪开始。给一句方向明确的引导。
        // ⚠️ 2026-10-24：条件改读 @State monthEmpty（reload 显式赋值）——
        //    原来 if 里现算 this.metas.length，实测有数据也不消失（见声明处注释）。
        if (this.monthEmpty) {
          Column() {
            Text('从今天开始')
              .fontSize(RJ_FS_CALLOUT)
              .fontColor(this.palette.text3)
            Text('点上面的「写今天」，写下第一篇')
              .fontSize(RJ_FS_CAPTION)
              .fontColor(this.palette.text3)
              .margin({ top: RJ_SP_SM })
          }
          .width('100%')
          .margin({ top: RJ_SP_VOID_L })
        }
        }
        .width('100%')
        }
      } else {
        // 时光时间轴（全部，按年月分块，倒序）
        if (!this.loaded || this.metas.length === 0) {
          Column() {
            // ⏳ !loaded = reload() 还没跑完（loaded 在 reload 末尾**同步**置 true，
            //    正常不可见；只有极端慢盘会闪一两帧）：显示骨架占位而不是"还没有日记"
            //    （否则冷启动先闪一帧空态再闪数据，空态说谎——P1-2/P1-1，2026-10-22 整改）
            if (!this.loaded) {
              Text('···')
                .fontSize(RJ_FS_TITLE)
                .fontColor(this.palette.text3)
            } else {
              Text('还没有日记')
                .fontSize(RJ_FS_CALLOUT)
                .fontColor(this.palette.text3)
              // ⚠️ 2026-10-22 修正（P1-2）：「写今天」按钮早已提到头部（891 行注释），
              //    文案还指向不存在的"下面" —— 空态必须指对地方
              Text('点上面的「写今天」，记下第一篇')
                .fontSize(RJ_FS_CAPTION)
                .fontColor(this.palette.text3)
                .margin({ top: RJ_SP_MD })
            }
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
                  .fontColor(this.palette.text3)
                  .width('100%')
                  .padding({ top: RJ_SP_XL, bottom: RJ_SP_MD })
              } else if (row.meta !== null) {
                // ⚠️ 为什么日记行要抽成 @Builder 还多传一个 meta（2026-10-20 编译踩坑）：
                //   ① itemGenerator 的函数体**只能写 UI 组件**，塞一句
                //      `const meta = row.meta` 直接报 "Only UI component syntax can be written here"；
                //   ② 而收藏按钮的 onClick 闭包里，ArkTS 对 `row.meta` 的 null 收窄会失效
                //      （报 'row.meta' is possibly 'null'）。
                //   解法：让收窄在**调用点**生效 —— `row.meta` 作实参传进 @Builder，
                //   形参声明为非空 `NoteMeta`，整行都基于它渲染，闭包里也能安全用。
                this.noteRow(row, row.meta);
              }
            }
            .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL })
            .onClick(() => {
              if (row.meta !== null) {
                this.open(row.meta.date, row.meta.id);
              }
            })
            // A 类容器伪按钮：时光轴整行可点但读屏无标签（2026-10-23 复评整改）。
            // 月份头行（meta 为 null）不可点，不给标签
            .accessibilityText(row.meta !== null ? '打开 ' + row.meta.date + ' 的日记' : row.monthKey)
          }, (row: TimelineRow) => row.key)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: this.palette.line })
      }

      // ⚠️ 原来这里还有一个底部大按钮「写今天」，现已提到头部 ——
      //    同一意图两个入口会让人犹豫该点哪个，而且底部那个要滚过日历+列表才看得到。
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
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

  /**
   * 时光轴的一行日记（2026-10-20 从 build 内联抽成 @Builder）
   *
   * 抽出来的原因见 LazyForEach 里的注释：itemGenerator 不能写语句声明，
   * 而收藏按钮的 onClick 需要非空 meta —— 把 row.meta 作实参传进来，
   * 形参声明非空，整行（含闭包）都基于它。
   *
   * `row` 只为 showTime 保留（同日多篇才补 HH:mm）。
   */
  @Builder
  private noteRow(row: TimelineRow, meta: NoteMeta) {
    Row() {
      Column() {
        Row() {
          Text(meta.date)
            .fontSize(RJ_FS_CAPTION)
            .fontFamily('monospace')
            .fontColor(this.palette.text2)
          // 同一天多篇时补个时间，否则几行日期一模一样、看不出是几篇
          if (row.showTime) {
            Text(timeOfDay(meta.createdAt))
              .fontSize(RJ_FS_META)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .margin({ left: RJ_SP_MD })
          }
          if (this.moodEmoji(meta).length > 0) {
            Text(this.moodEmoji(meta))
              .fontSize(RJ_FS_CALLOUT)
              .margin({ left: RJ_SP_MD })
          }
          /**
           * 收藏星（2026-10-20 从"只读展示"改为**可直接点**）
           *
           * ⚠️ 原来只有收藏后才渲染一个 ★、且不带点击 —— 华为审核实测报：
           *    「首页-时光-收藏：点击收藏图标未高亮显示」。用户看到列表里的 ★
           *    理所当然认为能点，点了没反应 = 功能坏了。
           * 现在未收藏显示空心 ☆（可点）、收藏显示实心 ★（茶褐），
           * 点一下就地切换并重载 —— 不必再进编辑器（编辑器那颗星保留，
           * 写的时候顺手标）。
           * 收藏 = 钤印 ⇒ 品牌茶褐（与月视图 ★、Editor 收藏星、日历日期点四处同色）
           *
           * ⚠️ 读 `this.favIds.has(...)` 而不是 `meta.favorite`：后者是闭包里的
           *    旧对象，LazyForEach 不重建 item 就拿它没法刷新（与日历染色同源的坑）。
           */
          Button(this.favIds.has(meta.id) ? '★' : '☆', { type: ButtonType.Normal, stateEffect: true })
            .fontSize(RJ_FS_CALLOUT)
            .fontColor(this.favIds.has(meta.id) ? this.palette.brand : this.palette.text3)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .margin({ left: RJ_SP_MD })
            .accessibilityText(this.favIds.has(meta.id) ? '取消收藏' : '收藏这一篇')
            // 收藏脉冲（2026-10-23 复评整改）：放大 1.3，spring 归位并过冲
            .scale({ x: this.favKickId === meta.id ? 1.3 : 1.0, y: this.favKickId === meta.id ? 1.3 : 1.0 })
            .animation({ duration: 320, curve: curves.springMotion(0.3, 0.7) })
            .onClick(() => {
              this.toggleFavorite(meta.id);
            })
          /**
           * 时间胶囊徽标（2026-10-20）：锁定态显示倒计时，已解锁显示角标。
           * 位置在收藏星之后 —— 与 ★ 同属"这篇的状态"，且都是行内小字。
           */
          if (isCapsule(meta)) {
            Text(capsuleBadge(meta, Date.now()))
              .fontSize(RJ_FS_META)
              .fontFamily('monospace')
              .fontColor(this.palette.brand)
              .margin({ left: RJ_SP_MD })
          }
          Blank()
          /**
           * 字数：锁定态胶囊**不显示** —— 数字大小会剧透"信写了多长"
           * （封存纪律在列表侧的对应物；保存路径 preview 等字段同理全空）。
           */
          if (!capsuleLocked(meta, Date.now())) {
            Text(meta.words + ' 字')
              .fontSize(RJ_FS_META)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
          }
        }
        .width('100%')
        if (meta.tags.length > 0) {
          Text('#' + meta.tags.join(' #'))
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .margin({ top: RJ_SP_SM })
        }
        // 摘要来自索引缓存（零额外 IO）；老数据没有 ⇒ 这一行就没有，不硬凑。
        // serif = 纸上阅读的笔画语言（党哥 2026-10-15：读的界面要纸质书信质感）
        if (meta.preview.length > 0) {
          Text(meta.preview)
            .fontSize(RJ_FS_CALLOUT)
            .fontFamily('serif')
            .fontColor(this.palette.text)
            .margin({ top: RJ_SP_SM })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 二次调用走缓存，很便宜；这里多判一次是为了解密失败时不留空白方块
      if (meta.imgRef.length > 0 && this.thumbOf(meta).length > 0) {
        Image(this.thumbOf(meta))
          .width(48)
          .height(48)
          .objectFit(ImageFit.Cover)
          .borderRadius(RJ_RADIUS_SM)
          .margin({ left: RJ_SP_LG })
      }
    }
    .width('100%')
    .padding({ top: RJ_SP_LG, bottom: RJ_SP_LG })
    // 行的进出过渡（2026-10-23 复评整改）：新增/删除的日记淡入淡出+轻位移，
    // 不再是瞬现瞬消失（插入才播；reload 的全量重画不播，见 TimelineDataSource）
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .animation({ duration: 200, curve: Curve.EaseOut }))
  }
}
