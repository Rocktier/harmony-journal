import { NoteMeta } from './NoteMeta';

/**
 * 日记本（Journals，1.0.6）—— 多本分册（**纯逻辑，不引任何 @kit** —— 单测可跑）
 *
 * 用户视角：人的生活是分层的 —— 工作的事、孩子的事、读书的感想，
 * 塞在一个时间轴里，翻的时候永远在别人的情绪里穿行。
 * 分成本之后，"翻开工作本"只看见工作，"翻开家庭本"只看见家庭，
 * 而每个本各自有自己的连续天数与节奏。
 *
 * ⚠️ 与标签的区别（为什么两个都要）：
 *    标签是**一篇的属性**（一篇可以同时是 #工作 #焦虑），用来横向串联；
 *    日记本是**一篇的归属**（一篇只属于一个本），用来纵向切分。
 *    两者不是替代关系，Day One 也是两套并存。
 *
 * ⚠️ 与本产品定位的关系（2026-10-27 对标 Day One 后的取舍）：
 *    Day One 的"无限日记本"是它的核心组织能力，我们此前只有标签 ⇒ 结构性差距。
 *    本功能与"零联网"无冲突（纯本地存储），不需要任何权限。
 */

/** 一个日记本 */
export interface JournalInfo {
  /** 主键（同时是 NoteMeta.journal 的取值） */
  id: string;
  /** 本的名字（4 个字以内观感最好，上限 12） */
  name: string;
  /** 图标 emoji（空串 = 用默认 📔） */
  emoji: string;
  /** 创建时间戳（毫秒）；默认本恒为 0（排序时自然在最前） */
  createdAt: number;
}

/**
 * 默认本的 id（**永不可删除**）
 *
 * ⚠️ 为什么必须有一个删不掉的本：
 *    删本时里面的日记要有地方去。如果允许把所有本都删掉，
 *    "删最后一个本"就必须连带删日记 —— 那是**用户会因为一次误操作丢全部日记**的设计。
 *    留一个删不掉的本当"回收港"，删本就等价于"把这些日记搬回默认本"，永远不丢一篇。
 */
export const JOURNAL_MAIN_ID: string = 'main';

/** 本名上限（超长会撑破 chip 与标题栏） */
export const JOURNAL_NAME_MAX: number = 12;

/** 自定义本的数量上限（含默认本）—— 太多本就失去切分的意义了 */
export const JOURNAL_MAX: number = 8;

/** 可选图标（固定候选集：避免用户输入 emoji 时出现渲染方块/彩色字不一致） */
export const JOURNAL_EMOJIS: string[] = ['📔', '📘', '📗', '📕', '📙', '📓', '🗂', '🌱'];

/** 默认图标（emoji 为空串时的显示值） */
export const JOURNAL_EMOJI_DEFAULT: string = '📔';

/** 本名清洗：trim、限长、压掉换行（名字里换行会把 UI 撑变形） */
export function sanitizeJournalName(raw: string): string {
  if (typeof raw !== 'string') {
    return '';
  }
  const folded: string = raw.replace(/\s+/g, ' ').trim();
  const chars: string[] = Array.from(folded);
  if (chars.length === 0) {
    return '';
  }
  // ⚠️ 按**字符**截断而不是 substring：emoji 是代理对，切一半会变成乱码方块
  return chars.slice(0, JOURNAL_NAME_MAX).join('');
}

/** 生成一个新本的 id（不当文件名用，只需唯一与可打印） */
export function newJournalId(existing: Set<string>): string {
  let id: string = '';
  let attempt: number = 0;
  do {
    const salt: number = Math.floor(Math.random() * 1000000000);
    id = 'j' + Date.now().toString(36) + salt.toString(36);
    attempt++;
  } while (existing.has(id) && attempt < 100);
  return id;
}

/**
 * 只有默认本时的列表（老数据迁移后的起点）
 *
 * ⚠️ 为什么默认本叫「生活」：老用户升级上来，全部日记都在这一本里，
 *    它承载的就是"我整个人的生活记录"，叫「生活」比叫「默认本」诚实。
 */
export function defaultJournals(): JournalInfo[] {
  const main: JournalInfo = { id: JOURNAL_MAIN_ID, name: '生活', emoji: JOURNAL_EMOJIS[0], createdAt: 0 };
  return [main];
}

/**
 * 洗白本列表（**迁移的入口**，老索引没有 journals 字段 ⇒ 得到 [默认本]）
 *
 * 保证三条不变量（下游 UI 依赖它们，不许破坏）：
 *  ① **默认本一定存在，且排在第一位**（删不掉的回收港 + chip 条的首项）
 *  ② id 唯一（重名的本会让切换失效）
 *  ③ 名字非空的本才有意义 —— 空名字退回「未命名」，绝不丢本
 *
 * ⚠️ 幂等：normalize(normalize(x)) === normalize(x)（迁移可能被跑多次）
 */
export function normalizeJournals(raw: JournalInfo[] | undefined): JournalInfo[] {
  const out: JournalInfo[] = [];
  const seen: Set<string> = new Set<string>();
  if (Array.isArray(raw)) {
    // ⚠️ 上限是**总数**（含默认本）⇒ 这里必须给默认本留一个位置，
    //    否则能存到 JOURNAL_MAX + 1 个，"上限"就成了摆设。
    for (let i: number = 0; i < raw.length && out.length < JOURNAL_MAX - 1; i++) {
      const it: JournalInfo = raw[i];
      if (it === null || it === undefined) {
        continue;
      }
      // 默认本单独处理（它必须存在且 id 固定）
      if (it.id === JOURNAL_MAIN_ID) {
        continue;
      }
      if (typeof it.id !== 'string' || !isValidJournalId(it.id) || seen.has(it.id)) {
        continue;
      }
      const name: string = sanitizeJournalName(it.name);
      const emoji: string = typeof it.emoji === 'string' ? it.emoji : '';
      const createdAt: number = typeof it.createdAt === 'number' && it.createdAt > 0 ? it.createdAt : 0;
      const info: JournalInfo = {
        id: it.id,
        name: name.length > 0 ? name : '未命名',
        emoji: emoji,
        createdAt: createdAt
      };
      seen.add(it.id);
      out.push(info);
    }
  }
  // 默认本的名号可被用户改（保留用户起的名字），但 id 与"排第一"不变
  const rawMain: JournalInfo | null = findRawMain(raw);
  const mainName: string = rawMain === null ? '生活' : (sanitizeJournalName(rawMain.name) || '生活');
  const mainEmoji: string = rawMain !== null && typeof rawMain.emoji === 'string' && rawMain.emoji.length > 0
    ? rawMain.emoji
    : JOURNAL_EMOJIS[0];
  const main: JournalInfo = { id: JOURNAL_MAIN_ID, name: mainName, emoji: mainEmoji, createdAt: 0 };
  out.sort((a: JournalInfo, b: JournalInfo) => a.createdAt - b.createdAt);
  const result: JournalInfo[] = [main];
  for (let i: number = 0; i < out.length; i++) {
    result.push(out[i]);
  }
  return result;
}

/** 在原始列表里找默认本（已被改名也要认出来） */
function findRawMain(raw: JournalInfo[] | undefined): JournalInfo | null {
  if (!Array.isArray(raw)) {
    return null;
  }
  for (let i: number = 0; i < raw.length; i++) {
    const it: JournalInfo = raw[i];
    if (it !== null && it !== undefined && it.id === JOURNAL_MAIN_ID) {
      return it;
    }
  }
  return null;
}

/** id 是否能安全使用（路径安全同款思路：只要可打印的 base36 字符） */
export function isValidJournalId(id: string): boolean {
  if (typeof id !== 'string' || id.length === 0 || id.length > 64) {
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

/** 按 id 找本；找不到返回 null（**默认本不在列表里也要能返回** —— 容错靠它） */
export function journalById(journals: JournalInfo[], id: string): JournalInfo | null {
  for (let i: number = 0; i < journals.length; i++) {
    if (journals[i].id === id) {
      return journals[i];
    }
  }
  return null;
}

/**
 * 取一个本该显示的图标（空串 → 默认 📔）
 *
 * ⚠️ 为什么容忍空串：老数据与外部导入都可能没有 emoji 字段，
 *    每个读取处都写一遍 `|| '📔'` 会漏 ⇒ 收敛成一个函数。
 */
export function journalEmojiOf(info: JournalInfo | null): string {
  if (info === null || typeof info.emoji !== 'string' || info.emoji.length === 0) {
    return JOURNAL_EMOJI_DEFAULT;
  }
  return info.emoji;
}

/** 本名（拿不到本时给个可读的兜底，界面上不出现空白 chip） */
export function journalNameOf(info: JournalInfo | null): string {
  if (info === null) {
    return '生活';
  }
  const n: string = sanitizeJournalName(info.name);
  return n.length > 0 ? n : '未命名';
}

/**
 * 按本过滤日记（**空 id = 全部**，与筛选"不筛选"同义）
 *
 * ⚠️ 归属不可信时的处理：NoteMeta.journal 缺失/指向一个已被删掉的本
 *    ⇒ 一律归到默认本显示，而不是让这篇"消失"。
 *    这是删本操作不丢日记的另一半保证（前半在 removeJournal 里）。
 */
export function journalOf(metas: NoteMeta[], journalId: string): NoteMeta[] {
  if (journalId.length === 0) {
    return metas;
  }
  const out: NoteMeta[] = [];
  for (let i: number = 0; i < metas.length; i++) {
    const j: string = normalizeJournalRef(metas[i].journal);
    if (j === journalId) {
      out.push(metas[i]);
    }
  }
  return out;
}

/**
 * 一篇日记归属哪个本（缺字段/空 ⇒ 默认本）
 *
 * ⚠️ 只认"非空字符串"，不认别的：老数据根本没有 journal 字段 ⇒ 默认本。
 */
export function normalizeJournalRef(raw: string | undefined): string {
  if (typeof raw !== 'string' || raw.length === 0) {
    return JOURNAL_MAIN_ID;
  }
  return raw;
}

/** 每个本各有多少篇（chip 上的计数；默认本兜底收容所有无归属的篇） */
export function journalCounts(journals: JournalInfo[], metas: NoteMeta[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (let i: number = 0; i < journals.length; i++) {
    counts[journals[i].id] = 0;
  }
  for (let i: number = 0; i < metas.length; i++) {
    const j: string = normalizeJournalRef(metas[i].journal);
    if (counts[j] === undefined) {
      counts[j] = 0;
    }
    counts[j] += 1;
  }
  return counts;
}

/** 新本能不能再建（超出上限要给 UI 一个明确答复，而不是静默失败） */
export function canAddJournal(journals: JournalInfo[]): boolean {
  return journals.length < JOURNAL_MAX;
}

/** 默认本不能删（删了就没有回收港了） */
export function canRemoveJournal(info: JournalInfo): boolean {
  return info.id !== JOURNAL_MAIN_ID;
}

/**
 * 新建一个本（返回新列表 + 新本；满了/名字空 ⇒ 返回 null）
 *
 * ⚠️ 为什么不直接 push 修改入参：ArkTS 里 @State 数组被就地改可能不触发刷新
 *    （家族老坑：数据变了 UI 不更新）⇒ 一律返回新数组交给调用方赋值。
 */
export interface AddJournalResult {
  list: JournalInfo[];
  created: JournalInfo;
}

export function addJournal(journals: JournalInfo[], name: string, emoji: string, nowMs: number): AddJournalResult | null {
  if (!canAddJournal(journals)) {
    return null;
  }
  const clean: string = sanitizeJournalName(name);
  if (clean.length === 0) {
    return null;
  }
  const taken: Set<string> = new Set<string>();
  for (let i: number = 0; i < journals.length; i++) {
    taken.add(journals[i].id);
  }
  const created: JournalInfo = {
    id: newJournalId(taken),
    name: clean,
    emoji: emoji,
    createdAt: nowMs > 0 ? nowMs : 1
  };
  const list: JournalInfo[] = journals.slice();
  list.push(created);
  return { list: list, created: created };
}

/** 给某个本改名/换图标（默认本也可以改 —— 用户有权叫它「我的日记」） */
export function renameJournal(journals: JournalInfo[], id: string, name: string, emoji: string): JournalInfo[] {
  const clean: string = sanitizeJournalName(name);
  if (clean.length === 0) {
    return journals;
  }
  let createdAt: number = 1;
  const out: JournalInfo[] = [];
  for (let i: number = 0; i < journals.length; i++) {
    const it: JournalInfo = journals[i];
    if (it.id === id) {
      createdAt = it.createdAt > 0 ? it.createdAt : 1;
      const next: JournalInfo = { id: it.id, name: clean, emoji: emoji, createdAt: createdAt };
      out.push(next);
    } else {
      out.push(it);
    }
  }
  return out;
}

/**
 * 删除一个本（**删本不删日记**：篇目搬回默认本）
 *
 * ⚠️ 这是本功能唯一可能导致"日记看不见"的操作，必须两边同时保证：
 *    ① 这里返回 `movedIds` 给调用方去改 NoteMeta.journal（存储侧）
 *    ② `normalizeJournalRef` 把所有不可信归属兜到默认本（读取侧）
 *    ⇒ 即使第 ① 步因为崩溃没做成，第 ② 步也能让日记还在默认本里出现。
 */
export interface RemoveJournalResult {
  list: JournalInfo[];
  /** 被删本里原本有哪些篇（调用方要把它们改挂到默认本） */
  movedIds: string[];
}

export function removeJournal(journals: JournalInfo[], id: string, metas: NoteMeta[]): RemoveJournalResult | null {
  if (id === JOURNAL_MAIN_ID) {
    return null; // 默认本删不掉
  }
  const list: JournalInfo[] = [];
  let found: boolean = false;
  for (let i: number = 0; i < journals.length; i++) {
    if (journals[i].id === id) {
      found = true;
      continue;
    }
    list.push(journals[i]);
  }
  if (!found) {
    return null;
  }
  const movedIds: string[] = [];
  for (let i: number = 0; i < metas.length; i++) {
    if (normalizeJournalRef(metas[i].journal) === id) {
      movedIds.push(metas[i].id);
    }
  }
  return { list: list, movedIds: movedIds };
}

/**
 * 把一批日记改挂到某个本（删本后的实际搬运动作）
 *
 * ⚠️ 返回新数组 + 只改命中的那几篇：整表重建会丢掉并发保存的改动，
 *    而且几百篇时重建的开销没必要。
 */
export function moveEntries(metas: NoteMeta[], ids: string[], journalId: string): NoteMeta[] {
  const set: Set<string> = new Set<string>(ids);
  const out: NoteMeta[] = [];
  for (let i: number = 0; i < metas.length; i++) {
    const m: NoteMeta = metas[i];
    if (set.has(m.id)) {
      const next: NoteMeta = copyWithJournal(m, journalId);
      out.push(next);
    } else {
      out.push(m);
    }
  }
  return out;
}

/** 改一篇的归属（复制而非就地改：@State 数组就地改不触发刷新） */
export function copyWithJournal(m: NoteMeta, journalId: string): NoteMeta {
  return {
    id: m.id,
    date: m.date,
    createdAt: m.createdAt,
    mood: m.mood,
    moodText: m.moodText,
    preview: m.preview,
    updatedAt: m.updatedAt,
    words: m.words,
    hasImage: m.hasImage,
    favorite: m.favorite,
    tags: m.tags,
    imgRef: m.imgRef,
    unlockAt: m.unlockAt,
    journal: journalId
  };
}

/**
 * 一条 NoteMeta 的归属本 id（**永远有值**，缺字段 ⇒ 默认本）
 *
 * ⚠️ 与 `normalizeJournalRef` 的分工：那个吃原始字段（可能 undefined），
 *    这个吃 NoteMeta，是 UI 里真正该用的那个。
 */
export function journalIdOf(m: NoteMeta): string {
  return normalizeJournalRef(m.journal);
}
