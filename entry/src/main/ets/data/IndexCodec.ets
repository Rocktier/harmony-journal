import { isValidDateKey, isValidNoteId, NoteMeta } from './NoteMeta';

/**
 * 索引的解析与写入（**纯逻辑，不引任何 @kit** —— 可被单测直接跑）
 *
 * 为什么从 `NoteStore` 里抽出来：
 *   `NoteStore` 引了 `fileIo / @kit.AbilityKit` 等，Node 里跑不了 ⇒
 *   迁移逻辑写在那儿就**永远没法自动验证**。而 v1→v2 迁移是本次改造**唯一可能丢数据的地方**，
 *   必须有单测兜底 —— 所以落在无 @kit 的模块里（与 `BackupService` 同一套路）。
 *
 * ## v1 → v2 迁移要义（**零文件移动**）
 *
 * | | |
 * |---|---|
 * | v1 条目 | 没有 `id`，主键是 `date`，文件名 `<date>.rkd` |
 * | v2 条目 | 主键是 `id`，文件名 `<id>.rkd` |
 * | 遷移手法 | 老条目直接取 **`id = date`** |
 * | 结果 | 文件名 `<date>.rkd` **天然仍然有效，一个都不用改名** |
 *
 * ⚠️ 为什么不批量 rename：改名是多步 IO，**中途失败/断电 ⇒ 用户丢日记**。
 *    取 `id = date` 让老数据原地不动就满足新模型的全部不变量，这是唯一不能省的谨慎。
 */
export const INDEX_APP: string = 'rockjournal';
export const INDEX_VERSION: number = 2;

/** 索引文件的容器（导出是为了能构造测试数据，写在私处就测不了） */
export interface IndexHolder {
  app?: string;
  v?: number;
  items?: NoteMeta[];
}

/**
 * 排序规则：**日期倒序 → 同日按创建时间倒序**（最新写的在最前）。
 * 一天多篇之后，同日内部必须有稳定次序，否则第二天再来一篇会串位。
 */
export function sortEntries(items: NoteMeta[]): NoteMeta[] {
  const copy: NoteMeta[] = items.slice();
  copy.sort((a: NoteMeta, b: NoteMeta) => {
    if (a.date !== b.date) {
      return a.date < b.date ? 1 : -1;
    }
    if (a.createdAt !== b.createdAt) {
      return a.createdAt < b.createdAt ? 1 : -1;
    }
    return 0;
  });
  return copy;
}

/**
 * **严格版**：区分「合法空索引」与「索引坏了」（bug 甲教训的直接产物）
 *
 * - `null` = 这段根本不是我们能认的索引（JSON 坏了 / 是别家的容器）⇒ **上层必须报错拦住**，
 *           绝不能当成"空库"放行，否则用户进空主页会以为日记全没了。
 * - `[]`   = 认得出来，只是确实没条目（新库的正常状态）。
 */
export function parseIndexStrict(plain: string): NoteMeta[] | null {
  if (plain.length === 0) {
    return [];
  }
  let holder: IndexHolder | null = null;
  try {
    holder = JSON.parse(plain) as IndexHolder;
  } catch (e) {
    return null;
  }
  if (holder === null) {
    return null;
  }
  if (holder.app !== undefined && holder.app !== INDEX_APP) {
    return null;
  }
  if (holder.items === undefined) {
    return null;
  }
  const raw: NoteMeta[] = Array.isArray(holder.items) ? holder.items : [];
  // v1 = 没有版本号（老格式压根没写 v 字段）或显式 1
  const legacy: boolean = holder.v === undefined || holder.v === 1;
  return normalizeEntries(raw, legacy);
}

/**
 * 索引明文 → 条目列表（**同时吃 v1 与 v2**），坏数据降级为空数组。
 *
 * 容错方式：单条脏/日期非法 → **跳过这一条**，其余照常（丢一篇优于全库报废）。
 * ⚠️ 幂等：同一份输入解析两次必须结果完全一致。
 */
export function parseIndex(plain: string): NoteMeta[] {
  const parsed: NoteMeta[] | null = parseIndexStrict(plain);
  return parsed === null ? [] : parsed;
}

/** 把任意来源的条目列表洗成"字段齐全、排序确定、id 唯一"的安全列表 */
export function normalizeEntries(raw: NoteMeta[], legacy: boolean): NoteMeta[] {
  const out: NoteMeta[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i: number = 0; i < raw.length; i++) {
    const it: NoteMeta = raw[i];
    if (it === null || it === undefined) {
      continue;
    }
    if (!isValidDateKey(it.date)) {
      continue;
    }
    // ★ 迁移核心：老条目 id = date（于是老文件名无需任何改动）
    let id: string = legacy ? it.date : (typeof it.id === 'string' ? it.id : '');
    if (!isValidNoteId(id)) {
      id = it.date;
    }
    if (seen.has(id)) {
      // 同名 id 会让后写的覆盖先写的 —— 宁可重编号也不丢这一篇
      id = rehash(id, seen);
    }
    seen.add(id);
    const updatedAt: number = typeof it.updatedAt === 'number' ? it.updatedAt : 0;
    /**
     * ⚠️ 这里必须判 `> 0`，不能只判"是不是数字"：
     * `typeof 0 === 'number'` 成立，于是 `createdAt: 0` 会被当成有效值保留，
     * 结果是时间轴里老条目**不显示 HH:mm**（`timeOfDay(0)` 返回空串）——
     * 真机实拍发现的观感缺陷。0 不是有效时间戳，一律退回 `updatedAt`。
     */
    const rawCreated: number = typeof it.createdAt === 'number' ? it.createdAt : 0;
    const entry: NoteMeta = {
      id: id,
      date: it.date,
      createdAt: rawCreated > 0 ? rawCreated : updatedAt,
      mood: typeof it.mood === 'string' ? it.mood : '',
      moodText: typeof it.moodText === 'string' ? it.moodText : '',
      preview: typeof it.preview === 'string' ? it.preview : '', // 老数据没有 ⇒ 空串，展示时降级
      updatedAt: updatedAt,
      words: typeof it.words === 'number' ? it.words : 0,
      hasImage: it.hasImage === true,
      imgRef: typeof it.imgRef === 'string' ? it.imgRef : '',
      favorite: it.favorite === true,
      tags: sanitizeTags(it.tags)
    };
    out.push(entry);
  }
  return sortEntries(out);
}

/** 条目 → 索引明文（**永远写 v2**） */
export function encodeIndex(items: NoteMeta[]): string {
  const holder: IndexHolder = { app: INDEX_APP, v: INDEX_VERSION, items: sortEntries(items) };
  return JSON.stringify(holder);
}

/**
 * 标签清洗（脏标签会让"只搜标签"全是噪声）：
 * 只保留非空字符串、去重、去掉 `#` 前缀（用户常顺手打上）、限长防把索引撑爆。
 */
export function sanitizeTags(raw: string[] | undefined): string[] {
  if (raw === undefined || !Array.isArray(raw)) {
    return [];
  }
  const out: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i: number = 0; i < raw.length && out.length < 12; i++) {
    // ⚠️ 不能用 `unknown` 类型（ArkTS 10605008 arkts-no-any-unknown）—— 用 string + typeof 校验
    const one: string = raw[i];
    if (typeof one !== 'string') {
      continue;
    }
    let t: string = one.trim();
    while (t.length > 0 && t.charAt(0) === '#') {
      t = t.substring(1);
    }
    t = t.trim();
    if (t.length === 0 || t.length > 16 || seen.has(t)) {
      continue;
    }
    seen.add(t);
    out.push(t);
  }
  return out;
}

/** id 冲突时换个后缀（确定性重编号，方便单测与排错） */
function rehash(id: string, taken: Set<string>): string {
  let n: number = 1;
  let candidate: string = id + '-' + n;
  while (taken.has(candidate) && n < 1000) {
    n++;
    candidate = id + '-' + n;
  }
  return candidate;
}
