/**
 * 日记元数据与日期/搜索逻辑（**纯逻辑，不引任何 @kit** —— 单测可跑）
 *
 * 一天一篇：日期键 `yyyy-MM-dd` 既是文件名也是主键。
 * 心情：5 个封闭选项 + 1 个自定义（评估文档 MVP 范围第 6 条）。
 */

/** 心情：id / emoji / 中文标签（自定义款 id = 'custom'，标签由用户输入） */
export interface Mood {
  id: string;
  emoji: string;
  label: string;
}

export const MOODS: Mood[] = [
  { id: 'happy', emoji: '😄', label: '开心' },
  { id: 'calm', emoji: '😌', label: '平静' },
  { id: 'sad', emoji: '😔', label: '难过' },
  { id: 'angry', emoji: '😤', label: '生气' },
  { id: 'tired', emoji: '😪', label: '疲惫' }
];

export const MOOD_CUSTOM_ID: string = 'custom';

export function moodById(id: string): Mood | null {
  for (let i: number = 0; i < MOODS.length; i++) {
    if (MOODS[i].id === id) {
      return MOODS[i];
    }
  }
  return null;
}

/**
 * 一篇日记的元数据（索引里存的东西，正文单独一个加密文件）
 *
 * ⚠️ **N2（一天多篇）：`id` 才是主键，`date` 只是属性。**
 * 历史上 date 兼主键兼文件名，导致"同一天再写会覆盖"。
 * 现在正文文件 = `notes/<id>.rkd`，同一天可以有任意多篇。
 */
export interface NoteMeta {
  /** 主键：一条日记一个 id（同时是正文文件名） */
  id: string;
  /** 归属日期键 yyyy-MM-dd（**不再是主键**，同一天可多篇） */
  date: string;
  /** 创建时间戳（毫秒）—— 同一天多篇的排序依据 */
  createdAt: number;
  /** 心情 id；未选则空串 */
  mood: string;
  /** 自定义心情的文案（mood === 'custom' 时有效） */
  moodText: string;
  /**
   * 摘要（**缓存进索引**的一小段正文，供列表/时间轴直接显示）
   *
   * ⚠️ 为什么缓存而不是"渲染时再解密"：索引本来整块在内存里，带一个字符串 = **零额外 IO**；
   *    而渲染时解密 = 每行一个文件 IO + 解密，几百行必崩（冷启动铁律①）。
   *    用户视角：时间轴里能看到"自己写过的话"，隧道才成立，光有日期只是张表。
   * ⚠️ 老数据没有这个字段 ⇒ 空串（下次编辑该篇才补上），显示时优雅降级。
   */
  preview: string;
  /** 最后更新时间戳（毫秒） */
  updatedAt: number;
  /** 字数 */
  words: number;
  /** 是否含图片 */
  hasImage: boolean;
  /**
   * 第一张图片的相对路径（`img/<id>.enc`），没有图则空串。
   * ⚠️ 与 preview 同理：**缓存进索引**，时间轴才能只解图片、不必解密整篇 ——
   *    否则想显示缩略图就得 readEntry 一遍，又是每行一次 IO（铁律①）。
   */
  imgRef: string;
}

/**
 * 生成一篇新日记的 id（纯逻辑，可单测）
 *
 * 照 `ImageStore.newRef()` 的套路：时间戳 base36 + 随机 base36。
 * ⚠️ 它会被直接拿去做**文件名**，所以必须：
 *  ① 纯 base36 字符（天然不含 `/` `\` `:` 等路径危险字符）
 *  ② 与现有 id 集合不冲突（冲突就重 roll）
 */
export function newNoteId(existing: Set<string>): string {
  let id: string = '';
  let attempt: number = 0;
  do {
    const salt: number = Math.floor(Math.random() * 1000000000);
    id = Date.now().toString(36) + salt.toString(36);
    attempt++;
  } while (existing.has(id) && attempt < 100);
  return id;
}

/**
 * id 是否"能安全当文件名用"（纯逻辑，可单测）
 *
 * ⚠️ 校验的边界是**路径安全**，不是"是不是新版格式"：
 * 迁移时老条目的 id 就是日期串 `2026-09-30`（含连字符），它必须算合法 ——
 * 否则老数据在迁移中会被当成脏数据丢掉（离线日记丢不起）。
 * 所以这里拦的只有：空 / 超长 / `..` 路径穿越 / 非 [0-9a-z-_] 字符（路径分隔符等）。
 */
export function isValidNoteId(id: string): boolean {
  if (typeof id !== 'string' || id.length === 0 || id.length > 64) {
    return false;
  }
  if (id === '.' || id === '..') {
    return false;
  }
  for (let i: number = 0; i < id.length; i++) {
    const c: string = id.charAt(i);
    const ok: boolean = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || c === '-' || c === '_';
    if (!ok) {
      return false;
    }
  }
  return true;
}

/** 补零：1 → '01' */
function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

/** 由 Date 生成日期键 */
export function dateKeyOf(d: Date): string {
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

export function todayKey(): string {
  return dateKeyOf(new Date());
}

/** 日期键是否合法（形如 2026-09-28，且月日合理） */
export function isValidDateKey(key: string): boolean {
  if (typeof key !== 'string' || key.length !== 10) {
    return false;
  }
  if (key.charAt(4) !== '-' || key.charAt(7) !== '-') {
    return false;
  }
  const y: number = Number(key.substring(0, 4));
  const m: number = Number(key.substring(5, 7));
  const d: number = Number(key.substring(8, 10));
  if (!isFinite(y) || !isFinite(m) || !isFinite(d) || y < 1970 || m < 1 || m > 12 || d < 1) {
    return false;
  }
  return d <= daysInMonth(y, m);
}

/** 某年某月的天数（闰年 2 月 = 29） */
export function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    return isLeapYear(year) ? 29 : 28;
  }
  const big: number[] = [1, 3, 5, 7, 8, 10, 12];
  for (let i: number = 0; i < big.length; i++) {
    if (big[i] === month) {
      return 31;
    }
  }
  return 30;
}

export function isLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

/** 取月份键 yyyy-MM */
export function monthOf(dateKey: string): string {
  return dateKey.substring(0, 7);
}

/** 年月（ArkTS 不允许"对象字面量当类型"，必须显式声明接口） */
export interface YearMonth {
  year: number;
  month: number;
}

/** 月份键 → 年月 */
export function parseMonth(monthKey: string): YearMonth {
  const ym: YearMonth = { year: Number(monthKey.substring(0, 4)), month: Number(monthKey.substring(5, 7)) };
  return ym;
}

/** 上一个 / 下一个月份键 */
export function shiftMonth(monthKey: string, delta: number): string {
  const p: YearMonth = parseMonth(monthKey);
  let total: number = p.year * 12 + (p.month - 1) + delta;
  const y: number = Math.floor(total / 12);
  const m: number = total - y * 12 + 1;
  return y + '-' + pad2(m);
}

/**
 * 月视图的一格
 * `inMonth=false` 表示是补齐的那几天（上月尾/下月头），界面上要画成灰色
 */
export interface MonthCell {
  /** 该格对应的日期键 */
  date: string;
  /** 日号（1~31） */
  day: number;
  /** 是否属于当前月 */
  inMonth: boolean;
  /** 这天有没有日记（打点用） */
  hasNote: boolean;
}

/**
 * 生成月视图网格（**周一为一周开头**，6 行 × 7 列 = 42 格，行数固定）：
 * 行数固定才能保证切换月份时日历不跳动（高度变化会让界面抖）。
 */
export function monthGrid(monthKey: string, dates: string[]): MonthCell[] {
  const p: YearMonth = parseMonth(monthKey);
  const set: Set<string> = new Set<string>(dates);
  const first: Date = new Date(p.year, p.month - 1, 1);
  // JS 的 getDay()：周日=0；换算成周一=0
  const leading: number = (first.getDay() + 6) % 7;
  const cells: MonthCell[] = [];
  const total: number = daysInMonth(p.year, p.month);
  for (let i: number = 0; i < 42; i++) {
    const dayNum: number = i - leading + 1;
    const inMonth: boolean = dayNum >= 1 && dayNum <= total;
    const date: string = inMonth
      ? monthKey + '-' + pad2(dayNum)
      : shiftedDateKey(p.year, p.month, dayNum);
    const cell: MonthCell = {
      date: date,
      day: inMonth ? dayNum : new Date(date + 'T00:00:00').getDate(),
      inMonth: inMonth,
      hasNote: set.has(date)
    };
    cells.push(cell);
  }
  return cells;
}

/** 越界的日号换算成真实日期键（1 之前是上月，total 之后是下月） */
function shiftedDateKey(year: number, month: number, dayNum: number): string {
  const base: Date = new Date(year, month - 1, dayNum);
  return dateKeyOf(base);
}

// ── 搜索（Phase 6 的纯逻辑部分）────────────────────────────────────────
export interface SearchHit {
  /** 《N2》：命中条目的 id —— 点结果要能精确打开"那篇"，而不是那天的默认一篇 */
  id: string;
  date: string;
  /** 命中位置附近的一段正文（给用户看"为什么命中"） */
  snippet: string;
}

/** 搜索输入：一篇日记的 id + 日期 + 纯文本 */
export interface NoteText {
  id: string;
  date: string;
  text: string;
}

// ── 回头看（Phase 10b：那年今日 + 时光时间轴）—— 纯逻辑，全部带单测 ──────────

/**
 * 「那年今日」：取出与 today **同月同日**的、过去的日期键（倒序，不含今天）。
 *
 * ⚠️ 闰日 `02-29` 只在历史闰年命中，**不降级到 `02-28`** ——
 * 用户的心智是"这一天的往年"，不是"月底附近"，降级会给人看错的错觉。
 */
export function onThisDayDates(dates: string[], today: string): string[] {
  if (!isValidDateKey(today)) {
    return [];
  }
  const md: string = today.substring(5);
  const out: string[] = [];
  for (let i: number = 0; i < dates.length; i++) {
    const d: string = dates[i];
    if (!isValidDateKey(d)) {
      continue;
    }
    if (d === today) {
      continue;
    }
    if (d >= today) {
      continue; // 只看过去（"未来的自己"留给以后）
    }
    if (d.substring(5) !== md) {
      continue;
    }
    out.push(d);
  }
  out.sort((a: string, b: string) => a < b ? 1 : (a > b ? -1 : 0));
  return out;
}

/** `N 年前`（MM-DD 已相同 ⇒ 年份差即精确年数）；入参不合法返回空串 */
export function yearsAgoLabel(past: string, today: string): string {
  if (!isValidDateKey(past) || !isValidDateKey(today)) {
    return '';
  }
  if (past >= today) {
    return '';
  }
  const diff: number = Number(today.substring(0, 4)) - Number(past.substring(0, 4));
  return diff > 0 ? diff + ' 年前' : '';
}

/** 时间轴的一行：要么是年月标题，要么是一篇日记 */
export interface TimelineRow {
  /** 'header' | 'note' */
  kind: string;
  /** 稳定唯一 key（标题 'h:'+monthKey，日记 'n:'+id）—— LazyForEach 强依赖它 */
  key: string;
  /** 所属月份 '2026-09' */
  monthKey: string;
  /** kind==='note' 时有值；标题行为 null */
  meta: NoteMeta | null;
  /** 这一天是否多篇 ⇒ 行内要不要补显示 HH:mm，否则同日多篇看着会重复 */
  showTime: boolean;
}

/**
 * 把日记列表压成"扁平"时间轴行（月份变化处插入标题行）。
 *
 * ⚠️ 前置：metas 必须是 `store.list()` 的顺序（date↓, createdAt↓），本函数不排序 ——
 *    排序是索引的职责，重复排两处容易不一致。
 */
export function timelineRows(metas: NoteMeta[]): TimelineRow[] {
  const perDay: Map<string, number> = new Map<string, number>();
  for (let i: number = 0; i < metas.length; i++) {
    const key: string = metas[i].date;
    const cur: number | undefined = perDay.get(key);
    perDay.set(key, cur === undefined ? 1 : cur + 1);
  }
  const rows: TimelineRow[] = [];
  let lastMonth: string = '';
  for (let i: number = 0; i < metas.length; i++) {
    const m: NoteMeta = metas[i];
    const mk: string = monthOf(m.date);
    if (mk !== lastMonth) {
      const header: TimelineRow = { kind: 'header', key: 'h:' + mk, monthKey: mk, meta: null, showTime: false };
      rows.push(header);
      lastMonth = mk;
    }
    const n: number | undefined = perDay.get(m.date);
    const many: boolean = n !== undefined && n > 1;
    const row: TimelineRow = { kind: 'note', key: 'n:' + m.id, monthKey: mk, meta: m, showTime: many };
    rows.push(row);
  }
  return rows;
}

/** 摘要：折叠空白 → 按**字符**截断 → 超长补 `…`（emoji 安全） */
export function previewText(text: string, maxChars: number): string {
  if (maxChars <= 0) {
    return '';
  }
  const folded: string = text.replace(/\s+/g, ' ').trim();
  const chars: string[] = Array.from(folded);
  if (chars.length <= maxChars) {
    return folded;
  }
  return chars.slice(0, maxChars).join('') + '…';
}

/** 前一天的日期键（跨月/跨年/闰年都要对）；入参不合法返回空串 */
export function prevDateKey(key: string): string {
  if (!isValidDateKey(key)) {
    return '';
  }
  const y: number = Number(key.substring(0, 4));
  const m: number = Number(key.substring(5, 7));
  const d: number = Number(key.substring(8, 10));
  if (d > 1) {
    return key.substring(0, 8) + pad2(d - 1);
  }
  if (m > 1) {
    const pm: number = m - 1;
    return y + '-' + pad2(pm) + '-' + pad2(daysInMonth(y, pm));
  }
  return (y - 1) + '-12-31';
}

/** 写日记的统计（全部从内存里的索引算，零 IO） */
export interface JournalStats {
  /** 总篇数（一天多篇时按篇算） */
  total: number;
  /** 有日记的天数（去重 —— 一天 3 篇算 1 天） */
  days: number;
  /** 总字数 */
  words: number;
  /** 当前连续天数 */
  streak: number;
  /** 历史最长连续天数 */
  longest: number;
  /** 今天写没写 */
  wroteToday: boolean;
}

/**
 * 统计 + 连续天数（纯逻辑，可单测）
 *
 * ⚠️ 连续天数的判定（用户视角，两个关键点）：
 *  ① **今天还没写时，连续天数仍然算活着** —— 从昨天往回数。
 *     否则一到凌晨用户的"连续 30 天"就归零，那是惩罚不是激励。
 *     是否断在今天，由 `wroteToday` 单独表达（界面上再提示"今天还没写"）。
 *  ② 昨天也没写 ⇒ 链已经断了 ⇒ 连续 = 0（不粉饰）。
 */
export function computeStats(metas: NoteMeta[], today: string): JournalStats {
  const seen: Set<string> = new Set<string>();
  let words: number = 0;
  for (let i: number = 0; i < metas.length; i++) {
    seen.add(metas[i].date);
    words = words + metas[i].words;
  }
  const dates: string[] = [];
  seen.forEach((d: string) => {
    if (isValidDateKey(d)) {
      dates.push(d);
    }
  });
  dates.sort((a: string, b: string) => a < b ? -1 : (a > b ? 1 : 0)); // 升序
  const wroteToday: boolean = isValidDateKey(today) && seen.has(today);
  const empty: JournalStats = { total: metas.length, days: dates.length, words: words, streak: 0, longest: 0, wroteToday: wroteToday };
  if (dates.length === 0 || !isValidDateKey(today)) {
    return empty;
  }
  // 历史最长连续（正着扫一遍）
  let longest: number = 1;
  let run: number = 1;
  for (let i: number = 1; i < dates.length; i++) {
    if (prevDateKey(dates[i]) === dates[i - 1]) {
      run = run + 1;
    } else {
      run = 1;
    }
    if (run > longest) {
      longest = run;
    }
  }
  // 当前连续：锚点 = 今天（写了）或昨天（没写但链还活着）
  const anchor: string = wroteToday ? today : prevDateKey(today);
  if (anchor.length === 0 || !seen.has(anchor)) {
    return { total: metas.length, days: dates.length, words: words, streak: 0, longest: longest, wroteToday: wroteToday };
  }
  let streak: number = 0;
  let cursor: string = anchor;
  while (seen.has(cursor)) {
    streak = streak + 1;
    const prev: string = prevDateKey(cursor);
    if (prev.length === 0) {
      break;
    }
    cursor = prev;
  }
  return { total: metas.length, days: dates.length, words: words, streak: streak, longest: longest, wroteToday: wroteToday };
}

/** 时间戳 → `HH:mm`（同日多篇时用来区分） */
export function timeOfDay(ts: number): string {
  if (!Number.isFinite(ts) || ts <= 0) {
    return '';
  }
  const d: Date = new Date(ts);
  const hh: number = d.getHours();
  const mm: number = d.getMinutes();
  return (hh < 10 ? '0' + hh : '' + hh) + ':' + (mm < 10 ? '0' + mm : '' + mm);
}

/**
 * 全文搜索：大小写不敏感，命中处前后各取 12 个字符做摘要。
 *
 * ⚠️ 用 `Array.from` 切片再 join —— 直接 `substring` 可能把 emoji 的代理对切成两半，
 *    摘要里出现乱码方块（日记里 emoji 很多，这个坑必须绕）。
 */
export function searchNotes(texts: NoteText[], query: string): SearchHit[] {
  const q: string = query.trim().toLowerCase();
  if (q.length === 0) {
    return [];
  }
  const hits: SearchHit[] = [];
  for (let i: number = 0; i < texts.length; i++) {
    const item: NoteText = texts[i];
    const lower: string = item.text.toLowerCase();
    const at: number = lower.indexOf(q);
    if (at < 0) {
      continue;
    }
    const chars: string[] = Array.from(item.text);
    const atChars: number = Array.from(item.text.substring(0, at)).length;
    const from: number = Math.max(0, atChars - 12);
    const to: number = Math.min(chars.length, atChars + q.length + 12);
    let snippet: string = chars.slice(from, to).join('');
    if (from > 0) {
      snippet = '…' + snippet;
    }
    if (to < chars.length) {
      snippet = snippet + '…';
    }
    const hit: SearchHit = { id: item.id, date: item.date, snippet: snippet };
    hits.push(hit);
  }
  return hits;
}
