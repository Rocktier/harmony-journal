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
import { Block, jsonToBlocks, blocksToJson } from './NoteBlocks';
import { NoteMeta, isValidDateKey, isValidNoteId } from './NoteMeta';

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

export interface BackupItem {
  date: string;
  meta: NoteMeta;
  blocks: Block[];
}

/** 备份文件名（带日期，用户一眼知道是哪天的备份） */
export function backupFileName(dateKey: string): string {
  return 'Rock私记-备份-' + dateKey + BACKUP_EXT;
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
      imgRef: src !== undefined && typeof src.imgRef === 'string' ? src.imgRef : ''
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
