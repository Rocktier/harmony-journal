import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { Block, blocksToJson, jsonToBlocks, wordCountOf } from './NoteBlocks';
import { NoteMeta, isValidDateKey } from './NoteMeta';
import { BackupItem } from './BackupService';
import { VaultService } from './VaultService';

/**
 * 日记存储（设备端：沙箱文件 + 加密）
 *
 * 布局（全在应用沙箱，系统别的 app 读不到；导出必须用户主动走文件选择器）：
 *   filesDir/notes/<yyyy-MM-dd>.rkd   一篇日记一个加密文件
 *   filesDir/index.rkd                索引（日期/心情/字数/时间戳），同样加密
 *   filesDir/img/<id>.enc             图片（Phase 4，正文只存 ref）
 *
 * 为什么一篇一个文件而不是一个库文件：
 *  ① 写日记是高频小改动，整库重写会随着日记变多越来越慢（大文件反复加密）；
 *  ② 单篇损坏只丢一篇，不会连累全部（离线日记丢不起，这是兜底设计）；
 *  ③ 索引单独存，打开列表不必解密全部正文 —— 冷启动快（家族铁律 1）。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
const NOTES_DIR: string = 'notes';
const INDEX_FILE: string = 'index.rkd';

export class NoteStore {
  private root: string = '';
  private vault: VaultService = new VaultService();
  private index: NoteMeta[] = [];

  /** 初始化目录（不解密任何东西） */
  open(ctx: common.UIAbilityContext): void {
    this.root = ctx.filesDir;
    const dir: string = this.root + '/' + NOTES_DIR;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    hilog.info(DOMAIN, TAG, 'store root=%{public}s', this.root);
  }

  getVault(): VaultService {
    return this.vault;
  }

  /** 索引是否已载入 */
  indexLoaded(): boolean {
    return this.index.length > 0;
  }

  private indexPath(): string {
    return this.root + '/' + INDEX_FILE;
  }

  private notePath(date: string): string {
    return this.root + '/' + NOTES_DIR + '/' + date + '.rkd';
  }

  /** 读索引（文件不存在 = 全新用户，返回空列表而不是失败） */
  loadIndex(): NoteMeta[] {
    const p: string = this.indexPath();
    if (!fs.accessSync(p)) {
      this.index = [];
      return this.index;
    }
    const file: fs.File = fs.openSync(p, fs.OpenMode.READ_ONLY);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(p).size);
      fs.readSync(file.fd, buf);
      const plain: Uint8Array | null = this.vault.decrypt(new Uint8Array(buf));
      if (plain === null) {
        hilog.error(DOMAIN, TAG, 'index decrypt failed');
        this.index = [];
        return this.index;
      }
      const text: string = new util.TextDecoder().decodeToString(plain);
      const parsed: object = JSON.parse(text) as object;
      const holder: IndexHolder = parsed as IndexHolder;
      const list: NoteMeta[] = holder.items !== undefined ? holder.items : [];
      this.index = Array.isArray(list) ? list.filter((m: NoteMeta) => isValidDateKey(m.date)) : [];
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadIndex failed: %{public}s', JSON.stringify(e));
      this.index = [];
    } finally {
      fs.closeSync(file);
    }
    return this.index;
  }

  /** 写索引（整体重写：条目数 = 日记篇数，一年也就 365 条，代价可接受） */
  saveIndex(): boolean {
    try {
      const holder: IndexHolder = { v: 1, items: this.index };
      const json: string = JSON.stringify(holder);
      const bytes: Uint8Array = this.utf8(json);
      const enc: Uint8Array | null = this.vault.encrypt(bytes);
      if (enc === null) {
        return false;
      }
      return this.writeFileAtomic(this.indexPath(), enc);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveIndex failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 读一篇（返回块数组；不存在/解不开 → 空数组） */
  readNote(date: string): Block[] {
    const p: string = this.notePath(date);
    if (!fs.accessSync(p)) {
      return [];
    }
    const file: fs.File = fs.openSync(p, fs.OpenMode.READ_ONLY);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(p).size);
      fs.readSync(file.fd, buf);
      const plain: Uint8Array | null = this.vault.decrypt(new Uint8Array(buf));
      if (plain === null) {
        return [];
      }
      return jsonToBlocks(new util.TextDecoder().decodeToString(plain));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readNote failed: %{public}s', JSON.stringify(e));
      return [];
    } finally {
      fs.closeSync(file);
    }
  }

  /** 写一篇（同时更新索引里的字数与时间戳） */
  writeNote(date: string, blocks: Block[], mood: string, moodText: string): boolean {
    try {
      const json: string = blocksToJson(blocks);
      const enc: Uint8Array | null = this.vault.encrypt(this.utf8(json));
      if (enc === null) {
        return false;
      }
      if (!this.writeFileAtomic(this.notePath(date), enc)) {
        return false;
      }
      this.upsertMeta({
        date: date,
        mood: mood,
        moodText: moodText,
        updatedAt: Date.now(),
        words: wordCountOf(blocks),
        hasImage: blocks.some((b: Block) => b.type === 'img')
      });
      return this.saveIndex();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'writeNote failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 删一篇（只删本应用的副本；用户原文件从没进过我们的地盘） */
  deleteNote(date: string): boolean {
    const p: string = this.notePath(date);
    if (fs.accessSync(p)) {
      fs.unlinkSync(p);
    }
    this.index = this.index.filter((m: NoteMeta) => m.date !== date);
    return this.saveIndex();
  }

  /** 索引列表（按日期倒序：最新在上） */
  list(): NoteMeta[] {
    return this.index.slice().sort((a: NoteMeta, b: NoteMeta) => a.date < b.date ? 1 : (a.date > b.date ? -1 : 0));
  }

  metaOf(date: string): NoteMeta | null {
    for (let i: number = 0; i < this.index.length; i++) {
      if (this.index[i].date === date) {
        return this.index[i];
      }
    }
    return null;
  }

  /** 有日记的日期（月视图打点用） */
  allDates(): string[] {
    const out: string[] = [];
    for (let i: number = 0; i < this.index.length; i++) {
      out.push(this.index[i].date);
    }
    return out;
  }

  /**
   * 导出用：把所有日记读成明文 JSON（**只在用户主动导出时调用**，
   * 且导出文件仍会用同一个密码再加密一次 —— 见 BackupService）
   */
  /**
   * 导出用：把所有日记读成明文结构（**只在用户主动导出时调用**，
   * 且导出文件仍会用同一个密码再加密一次 —— 见 BackupService）
   *
   * 复用 `BackupItem` 而不是另起一个同名接口：ArkTS **不支持结构化类型兼容**，
   * 两个字段一样的接口互不兼容，另起一个就传不进 `buildBackup()`。
   */
  exportAll(): BackupItem[] {
    const out: BackupItem[] = [];
    const list: NoteMeta[] = this.list();
    for (let i: number = 0; i < list.length; i++) {
      const m: NoteMeta = list[i];
      const item: BackupItem = { date: m.date, blocks: this.readNote(m.date), meta: m };
      out.push(item);
    }
    return out;
  }

  /** 导入：把导出的内容写回来（覆盖同名日期） */
  importAll(items: BackupItem[]): number {
    let n: number = 0;
    for (let i: number = 0; i < items.length; i++) {
      const it: BackupItem = items[i];
      if (!isValidDateKey(it.date)) {
        continue;
      }
      if (this.writeNote(it.date, it.blocks, it.meta.mood, it.meta.moodText)) {
        n++;
      }
    }
    return n;
  }

  private upsertMeta(meta: NoteMeta): void {
    this.index = this.index.filter((m: NoteMeta) => m.date !== meta.date);
    this.index.push(meta);
  }

  /**
   * 原子写：先写 .tmp 再 rename。
   * 写到一半被杀掉不会留下"半个文件"——半个加密文件 = 这篇日记彻底没了。
   */
  private writeFileAtomic(path: string, bytes: Uint8Array): boolean {
    const tmp: string = path + '.tmp';
    try {
      if (fs.accessSync(tmp)) {
        fs.unlinkSync(tmp);
      }
      const file: fs.File = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes.buffer);
      } finally {
        fs.closeSync(file);
      }
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      fs.renameSync(tmp, path);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'writeFileAtomic failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  private utf8(s: string): Uint8Array {
    return new util.TextEncoder().encodeInto(s);
  }
}

interface IndexHolder {
  v?: number;
  items?: NoteMeta[];
}
