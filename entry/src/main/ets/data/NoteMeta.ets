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

/** 一篇日记的元数据（索引里存的东西，正文单独一个加密文件） */
export interface NoteMeta {
  /** 日期键 yyyy-MM-dd */
  date: string;
  /** 心情 id；未选则空串 */
  mood: string;
  /** 自定义心情的文案（mood === 'custom' 时有效） */
  moodText: string;
  /** 最后更新时间戳（毫秒） */
  updatedAt: number;
  /** 字数 */
  words: number;
  /** 是否含图片 */
  hasImage: boolean;
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
    cells.push({
      date: date,
      day: inMonth ? dayNum : new Date(date + 'T00:00:00').getDate(),
      inMonth: inMonth,
      hasNote: set.has(date)
    });
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
  date: string;
  /** 命中位置附近的一段正文（给用户看"为什么命中"） */
  snippet: string;
}

/** 搜索输入：一篇日记的日期 + 纯文本 */
export interface NoteText {
  date: string;
  text: string;
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
    hits.push({ date: item.date, snippet: snippet });
  }
  return hits;
}
