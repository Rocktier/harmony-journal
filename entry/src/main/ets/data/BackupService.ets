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
import { NoteMeta, isValidDateKey } from './NoteMeta';

export const BACKUP_APP: string = 'rockjournal';
export const BACKUP_VERSION: number = 1;
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
  if (holder.app !== BACKUP_APP || holder.v !== BACKUP_VERSION) {
    return [];
  }
  const list: BackupItem[] = holder.items !== undefined && Array.isArray(holder.items) ? holder.items : [];
  const out: BackupItem[] = [];
  for (let i: number = 0; i < list.length; i++) {
    const it: BackupItem = list[i];
    if (it === null || it === undefined || !isValidDateKey(it.date)) {
      continue;
    }
    const fallback: NoteMeta = { date: it.date, mood: '', moodText: '', updatedAt: 0, words: 0, hasImage: false };
    const kept: BackupItem = {
      date: it.date,
      meta: it.meta !== undefined ? it.meta : fallback,
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
