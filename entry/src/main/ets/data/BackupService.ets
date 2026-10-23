/**
 * 备份文件格式（**纯逻辑，单测可跑** —— 加解密由 VaultService 在页面层完成）
 *
 * 为什么备份文件要**再加密一次**：
 *  导出文件会落在用户自选的目录（下载文件夹、网盘同步目录…），
 *  那里不属于应用沙箱 —— 明文躺在那里等于把日记摊开。
 *  所以导出内容 = 「JSON 明文」→ 用同一个主密钥加密 → 写文件。
 *
 * 备份是离线日记唯一的事后悔药（手机丢了/坏了/换机），
 * 所以格式宁可笨一点也要稳：一层 JSON + 一层加密，十年后仍能解释。
 */
import { Block, Span, firstImgRef, jsonToBlocks, blocksToJson, plainOfBlocks, wordCountOf } from './NoteBlocks';
import { NoteMeta, PREVIEW_LEN, isValidDateKey, isValidNoteId, moodById, newNoteId, previewText } from './NoteMeta';
import { sanitizeTags } from './IndexCodec';

export const BACKUP_APP: string = 'rockjournal';
/**
 * v2（N2）：条目带 `id`，支持一天多篇。
 * ⚠️ 读写策略：
 *   - **写**永远 v2
 *   - **读**同时吃 v1 与 v2 —— 用户手里可能还有老版本的备份文件，
 *     读不了 = 他们的后路断了。v1 条目没有 id ⇒ 解析时用 `date` 兜底（与 IndexCodec 同理）。
 */
export const BACKUP_VERSION: number = 2;
export const BACKUP_VERSION_MIN_READABLE: number = 1;
export const BACKUP_EXT: string = '.rkdbak';
/** 可读导出（明文）的扩展名 —— 见 `toPlainText` / `toMarkdown` */
export const EXT_TXT: string = '.txt';
export const EXT_MD: string = '.md';

export interface BackupItem {
  date: string;
  meta: NoteMeta;
  blocks: Block[];
}

/** 备份文件名（带日期，用户一眼知道是哪天的备份） */
export function backupFileName(dateKey: string): string {
  return 'Rock私记-备份-' + dateKey + BACKUP_EXT;
}

/** 可读导出的文件名（明文，名字里就写明"可读"，免得用户和加密备份搞混） */
export function readableFileName(dateKey: string, ext: string): string {
  return 'Rock私记-可读导出-' + dateKey + ext;
}

/**
 * 可读导出：**明文**文本（TXT / Markdown）
 *
 * ⚠️ 为什么要有它（用户视角）：
 *   加密备份 `.rkdbak` 只有本 App 能读 —— 用户想迁移到别的日记软件、或只是想打印/存档，
 *   就**拿不出来**，等于被锁死。一个标榜"数据永远属于你"的隐私应用不该这样。
 *   所以这里导出**明文**，代价是文件不加密 —— 因此设置页必须明确提示用户自行保管。
 *
 * 两者区别：TXT 纯文字（最通用）；Markdown 保留标题/列表/粗斜体结构（可再导入别的编辑器）。
 * ⚠️ 图片不内联（正文里存的是加密文件引用，外部软件也读不懂）⇒ 只留 `[图片]` 占位。
 */
export function toPlainText(items: BackupItem[]): string {
  return renderReadable(items, false);
}

export function toMarkdown(items: BackupItem[]): string {
  return renderReadable(items, true);
}

function renderReadable(items: BackupItem[], markdown: boolean): string {
  const lines: string[] = [];
  lines.push('Rock私记 · 可读导出');
  lines.push('');
  lines.push('共 ' + items.length + ' 篇');
  lines.push('');
  for (let i: number = 0; i < items.length; i++) {
    const it: BackupItem = items[i];
    lines.push(markdown ? '## ' + it.date : '── ' + it.date + ' ──');
    const mood: string = moodLabelOf(it.meta);
    if (mood.length > 0) {
      lines.push(markdown ? '> 心情：' + mood : '心情：' + mood);
    }
    pushBlocks(lines, it.blocks, markdown);
    lines.push('');
  }
  return lines.join('\n');
}

/** 块 → 文本行（两种模式共用，只在标题/列表/样式的记号上不同） */
function pushBlocks(lines: string[], blocks: Block[], markdown: boolean): void {
  for (let i: number = 0; i < blocks.length; i++) {
    const b: Block = blocks[i];
    if (b.type === 'img') {
      lines.push('[图片]');
      continue;
    }
    const text: string = spansToText(b.spans, markdown);
    if (text.length === 0) {
      continue;
    }
    if (b.type === 'h') {
      lines.push(markdown ? '### ' + text : text);
    } else if (b.type === 'li') {
      lines.push(markdown ? '- ' + text : '· ' + text);
    } else {
      lines.push(text);
    }
  }
}

/** span → 文本（Markdown 下加粗斜体记号；纯文本下只留字） */
function spansToText(spans: Span[], markdown: boolean): string {
  let out: string = '';
  for (let i: number = 0; i < spans.length; i++) {
    const s = spans[i];
    if (!markdown) {
      out = out + s.text;
      continue;
    }
    let piece: string = s.text;
    if (s.bold) {
      piece = '**' + piece + '**';
    }
    if (s.italic) {
      piece = '*' + piece + '*';
    }
    out = out + piece;
  }
  return out;
}

/** 心情 → 人类可读（`😄 开心`；自定义心情用它的文案） */
function moodLabelOf(meta: NoteMeta): string {
  if (meta.mood.length === 0) {
    return '';
  }
  if (meta.mood === 'custom') {
    return meta.moodText.length > 0 ? meta.moodText : '';
  }
  const m = moodById(meta.mood);
  return m === null ? '' : m.emoji + ' ' + m.label;
}

/** 明文 → 备份字节（页面层拿它去加密再写文件） */
export function buildBackup(items: BackupItem[]): Uint8Array {
  // 同 NoteBlocks：JSON.stringify 的参数不能直接是裸对象字面量
  const holder: BackupHolder = { app: BACKUP_APP, v: BACKUP_VERSION, items: items };
  const json: string = JSON.stringify(holder);
  return utf8Encode(json);
}

/**
 * 备份字节 → 条目（解密后调用）。
 * 容错优先：单篇坏掉跳过，不影响其余（丢一篇比全丢好）。
 */
export function parseBackup(plain: Uint8Array): BackupItem[] {
  const text: string = utf8Decode(plain);
  if (text.length === 0) {
    return [];
  }
  // 同样：空对象字面量 `{}` 也不给初值（ArkTS 10605038）
  let holder: BackupHolder | null = null;
  try {
    holder = JSON.parse(text) as BackupHolder;
  } catch (e) {
    return [];
  }
  if (holder === null) {
    return [];
  }
  if (holder.app !== BACKUP_APP) {
    return [];
  }
  if (holder.v === undefined || typeof holder.v !== 'number' ||
      holder.v < BACKUP_VERSION_MIN_READABLE || holder.v > BACKUP_VERSION) {
    return [];
  }
  const list: BackupItem[] = holder.items !== undefined && Array.isArray(holder.items) ? holder.items : [];
  const out: BackupItem[] = [];
  for (let i: number = 0; i < list.length; i++) {
    const it: BackupItem = list[i];
    if (it === null || it === undefined || !isValidDateKey(it.date)) {
      continue;
    }
    const src: NoteMeta | undefined = it.meta;
    // v1 条目没有 id ⇒ 兜底成 date（导入侧再做冲突处理，这里只保证字段齐全）
    let id: string = src !== undefined && typeof src.id === 'string' && isValidNoteId(src.id) ? src.id : it.date;
    const updatedAt: number = src !== undefined && typeof src.updatedAt === 'number' ? src.updatedAt : 0;
    // 老备份（1.0.1 及以前）的 meta 没有 unlockAt ⇒ undefined ⇒ 当普通日记恢复
    const unlockAt: number = src !== undefined && typeof src.unlockAt === 'number' && src.unlockAt > 0
      ? src.unlockAt : 0;
    const meta: NoteMeta = {
      id: id,
      date: it.date,
      createdAt: src !== undefined && typeof src.createdAt === 'number' ? src.createdAt : updatedAt,
      mood: src !== undefined && typeof src.mood === 'string' ? src.mood : '',
      moodText: src !== undefined && typeof src.moodText === 'string' ? src.moodText : '',
      preview: src !== undefined && typeof src.preview === 'string' ? src.preview : '',
      updatedAt: updatedAt,
      words: src !== undefined && typeof src.words === 'number' ? src.words : 0,
      hasImage: src !== undefined && src.hasImage === true,
      imgRef: src !== undefined && typeof src.imgRef === 'string' ? src.imgRef : '',
      favorite: src !== undefined && src.favorite === true,
      tags: sanitizeTags(src !== undefined ? src.tags : undefined),
      unlockAt: unlockAt
    };
    const kept: BackupItem = {
      date: it.date,
      meta: meta,
      blocks: jsonToBlocks(blocksToJson(it.blocks !== undefined ? it.blocks : []))
    };
    out.push(kept);
  }
  return out;
}

/** UTF-8 编解码（不引 @kit，单测可用；设备端有更快的 util.TextEncoder，但这里数据量不大） */
export function utf8Encode(s: string): Uint8Array {
  const bytes: number[] = [];
  for (let i: number = 0; i < s.length; i++) {
    const code: number = s.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length) {
      const next: number = s.charCodeAt(i + 1);
      const cp: number = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00);
      bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
      i++;
    } else {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  }
  return new Uint8Array(bytes);
}

export function utf8Decode(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b: number = bytes[i];
    if (b < 0x80) {
      out += String.fromCharCode(b);
      i += 1;
    } else if (b >= 0xC0 && b < 0xE0) {
      out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if (b >= 0xE0 && b < 0xF0) {
      out += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
      i += 3;
    } else {
      const cp: number = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      out += String.fromCodePoint(cp);
      i += 4;
    }
  }
  return out;
}

interface BackupHolder {
  app?: string;
  v?: number;
  items?: BackupItem[];
}

/**
 * 批量导入规划（**纯逻辑，无 IO，可单测** —— 2026-10-23 复评新增）
 *
 * 背景：NoteStore.importAll 原来逐篇调 saveEntry，而 saveEntry 每篇结尾都
 * 全量重写 + 加密 + 原子写**整个索引** ⇒ N 篇 = N 次全量写（O(N²)）。
 * 这不是"十年后一万篇"的远期问题 —— 几百篇的备份今天就能卡到用户。
 *
 * 修法是把「决策」与「IO」分离：
 *  ① 本函数在内存里完成 id 分配 + 元数据构造（纯函数 ⇒ 语义进 CI 守着）；
 *  ② NoteStore.importAll 只逐篇写正文密文 + **一次** saveIndex（IO 结构肉眼可审）。
 *
 * 语义与旧逐篇版逐字一致（不许悄悄改行为）：
 *  - date 非法 ⇒ 跳过；
 *  - id 与现有索引冲突 ⇒ 换新 id（**宁可多一篇也不丢一篇**，绝不静默顶掉）；
 *  - 胶囊（unlockAt > 0）⇒ mood/moodText/preview/hasImage/imgRef/tags 一律封存
 *    （索引整块可读，任何内容字段漏进索引，锁就形同虚设）；
 *  - createdAt/updatedAt 取注入的 now —— 对齐旧 saveEntry 对新篇目的行为
 *    （prev 不存在 ⇒ now；备份里的原时间戳不保留，与旧行为一致）。
 */
export interface PlannedNote {
  /** 要落的正文 id（与现有冲突时已换成新号） */
  id: string;
  blocks: Block[];
  meta: NoteMeta;
}

export function planImport(existing: NoteMeta[], items: BackupItem[], now: number): PlannedNote[] {
  const taken: Set<string> = new Set<string>();
  for (let i: number = 0; i < existing.length; i++) {
    taken.add(existing[i].id);
  }
  const out: PlannedNote[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const it: BackupItem = items[i];
    if (!isValidDateKey(it.date)) {
      continue;
    }
    // 老备份（1.0.1 及以前）的 meta 没有 id ⇒ 回退用 date（老条目 id 本就等于 date）
    let id: string = typeof it.meta.id === 'string' && it.meta.id.length > 0 ? it.meta.id : it.date;
    if (taken.has(id)) {
      id = newNoteId(taken);
    }
    taken.add(id);
    // 老备份的 meta 没有 unlockAt ⇒ undefined ⇒ 当普通日记恢复
    const savedUnlockAt: number = typeof it.meta.unlockAt === 'number' ? it.meta.unlockAt : 0;
    const sealed: boolean = savedUnlockAt > 0;
    out.push({
      id: id,
      blocks: it.blocks,
      meta: {
        id: id,
        date: it.date,
        createdAt: now,
        mood: sealed ? '' : it.meta.mood,
        moodText: sealed ? '' : it.meta.moodText,
        preview: sealed ? '' : previewText(plainOfBlocks(it.blocks), PREVIEW_LEN),
        updatedAt: now,
        words: wordCountOf(it.blocks),
        hasImage: sealed ? false : it.blocks.some((b: Block) => b.type === 'img'),
        imgRef: sealed ? '' : firstImgRef(it.blocks),
        favorite: it.meta.favorite,
        tags: sealed ? [] : sanitizeTags(it.meta.tags),
        unlockAt: savedUnlockAt
      }
    });
  }
  return out;
}
