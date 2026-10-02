import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { Block, blocksToJson, jsonToBlocks, wordCountOf } from './NoteBlocks';
import { NoteMeta, isValidDateKey, newNoteId, previewText } from './NoteMeta';
import { encodeIndex, parseIndexStrict, sanitizeTags, sortEntries } from './IndexCodec';
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
/** 记录最近一次导出时刻的小文件（**不含日记内容**，只存一个时间戳） */
const BACKUP_MARK: string = 'last_backup';
/** 摘要长度（列表/时间轴一行显示得下的量；存进索引，避免渲染时再解密） */
const PREVIEW_LEN: number = 42;

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

  /**
   * 正文文件路径（**N2：按 id，不再按 date**）
   *
   * ⚠️ 迁移兼容：老条目的 `id` 就等于它的 `date`，所以老文件 `<date>.rkd` 无需任何改名
   *    依然能被正确寻址 —— 这是"零文件移动"能成立的前提。详见 `IndexCodec`。
   */
  private notePath(id: string): string {
    return this.root + '/' + NOTES_DIR + '/' + id + '.rkd';
  }

  /**
   * 读索引。
   * @returns true  = 成功（含「文件不存在 = 全新用户/首次」这种正常空）；
   *          false = 文件存在但**解密或解析失败**（密码错误 / 数据损坏 / 派生不兼容）。
   *
   * ⚠️ 关键：密码对不对不在 unlock 阶段验证（PBKDF2 永远能派生），
   * 真正验证在解密索引时。所以解密失败必须向上报 false，
   * 否则 unlockWith 会误判成功 → 静默进空主页，用户以为日记全没了。
   */
  loadIndex(): boolean {
    const p: string = this.indexPath();
    if (!fs.accessSync(p)) {
      this.index = [];
      return true;
    }
    const file: fs.File = fs.openSync(p, fs.OpenMode.READ_ONLY);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(p).size);
      fs.readSync(file.fd, buf);
      const plain: Uint8Array | null = this.vault.decrypt(new Uint8Array(buf));
      if (plain === null) {
        hilog.error(DOMAIN, TAG, 'index decrypt failed (wrong password or corrupted data)');
        this.index = [];
        return false;
      }
      const text: string = new util.TextDecoder().decodeToString(plain);
      // ★ 严格解析：认不出来或已损坏 → null → 必须报错拦住（不能当"空库"放行，见 bug 甲）
      const list: NoteMeta[] | null = parseIndexStrict(text);
      if (list === null) {
        hilog.error(DOMAIN, TAG, 'index is not a valid rkindex (corrupted or foreign)');
        this.index = [];
        return false;
      }
      this.index = list;
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadIndex failed: %{public}s', JSON.stringify(e));
      this.index = [];
      return false;
    } finally {
      fs.closeSync(file);
    }
  }

  /** 写索引（整体重写；始终写 v2 格式，见 IndexCodec） */
  saveIndex(): boolean {
    try {
      const json: string = encodeIndex(this.index);
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
  readEntry(id: string): Block[] {
    const p: string = this.notePath(id);
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

  /**
   * 写一篇（**按 id 定位**：没有就新建，有就更新这一篇）
   *
   * ⚠️ 一天多篇之后，写必须是"更新指定的那篇"，不能按 date 覆盖 ——
   * 否则在同一天打开第二篇时，会悄悄把第一篇内容写没了。
   */
  saveEntry(id: string, date: string, blocks: Block[], mood: string, moodText: string,
    favorite: boolean, tags: string[]): boolean {
    try {
      let entryId: string = id;
      if (entryId.length === 0) {
        entryId = this.newEntryId();
      }
      const json: string = blocksToJson(blocks);
      const enc: Uint8Array | null = this.vault.encrypt(this.utf8(json));
      if (enc === null) {
        return false;
      }
      if (!this.writeFileAtomic(this.notePath(entryId), enc)) {
        return false;
      }
      const prev: NoteMeta | null = this.byId(entryId);
      const now: number = Date.now();
      this.upsertMeta({
        id: entryId,
        date: date,
        createdAt: prev !== null ? prev.createdAt : now,
        mood: mood,
        moodText: moodText,
        preview: previewText(this.plainOfBlocks(blocks), PREVIEW_LEN),
        updatedAt: now,
        words: wordCountOf(blocks),
        hasImage: blocks.some((b: Block) => b.type === 'img'),
        imgRef: this.firstImgRef(blocks),
        favorite: favorite,
        tags: sanitizeTags(tags)
      });
      return this.saveIndex();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveEntry failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 删一篇（只删本应用的副本；用户原文件从没进过我们的地盘） */
  deleteEntry(id: string): boolean {
    const p: string = this.notePath(id);
    if (fs.accessSync(p)) {
      fs.unlinkSync(p);
    }
    this.index = this.index.filter((m: NoteMeta) => m.id !== id);
    return this.saveIndex();
  }

  /** 某篇的纯文本（解密 + 块→文本；不存在/解不开 → 空串） */
  textOf(id: string): string {
    return this.plainOfBlocks(this.readEntry(id));
  }

  /**
   * 记下"最近一次导出"的时刻（备份提醒用）
   *
   * 只写一个纯文本小文件 `last_backup`，**不含任何日记内容** ——
   * 提醒逻辑本身不该碰用户数据。
   */
  markBackup(): void {
    const p: string = this.root + '/' + BACKUP_MARK;
    const data: Uint8Array = this.utf8(String(Date.now()));
    try {
      // ⚠️ HarmonyOS 的 fileIo **没有** writeFileSync/readFileSync（别凭记忆写，那是 Node 的 API）
      const file: fs.File = fs.openSync(p, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, data.buffer);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'markBackup failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 最近一次导出的时刻（从未导出 = 0） */
  lastBackupAt(): number {
    const p: string = this.root + '/' + BACKUP_MARK;
    try {
      if (!fs.accessSync(p)) {
        return 0;
      }
      const file: fs.File = fs.openSync(p, fs.OpenMode.READ_ONLY);
      let text: string = '';
      try {
        const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(p).size);
        fs.readSync(file.fd, buf);
        text = new util.TextDecoder().decodeToString(new Uint8Array(buf));
      } finally {
        fs.closeSync(file);
      }
      const n: number = Number(text.trim());
      return Number.isFinite(n) && n > 0 ? n : 0;
    } catch (e) {
      return 0;
    }
  }

  /** 第一张图片的 ref（时间轴缩略图用；没有图返回空串） */
  private firstImgRef(blocks: Block[]): string {
    for (let i: number = 0; i < blocks.length; i++) {
      if (blocks[i].type === 'img' && blocks[i].ref.length > 0) {
        return blocks[i].ref;
      }
    }
    return '';
  }

  /** 块 → 纯文本（块间换行；图片块没有文本，自然被跳过） */
  private plainOfBlocks(blocks: Block[]): string {
    const lines: string[] = [];
    for (let i: number = 0; i < blocks.length; i++) {
      const b: Block = blocks[i];
      let line: string = '';
      for (let j: number = 0; j < b.spans.length; j++) {
        line = line + b.spans[j].text;
      }
      lines.push(line);
    }
    return lines.join('\n');
  }

  /** 按 id 取元数据 */
  byId(id: string): NoteMeta | null {
    for (let i: number = 0; i < this.index.length; i++) {
      if (this.index[i].id === id) {
        return this.index[i];
      }
    }
    return null;
  }

  /** 这一天的全部日记，按**创建时间升序**（切换条按时间顺序更好理解） */
  entriesOfDate(date: string): NoteMeta[] {
    const out: NoteMeta[] = [];
    for (let i: number = 0; i < this.index.length; i++) {
      if (this.index[i].date === date) {
        out.push(this.index[i]);
      }
    }
    out.sort((a: NoteMeta, b: NoteMeta) => a.createdAt < b.createdAt ? -1 : (a.createdAt > b.createdAt ? 1 : 0));
    return out;
  }

  /**
   * 这一天**最新**的一篇（点日历时的默认目标）。
   * 用 `list()` 的顺序找第一个命中 —— index 已是 `date↓, createdAt↓`，第一个就是最新的。
   */
  newestOfDate(date: string): NoteMeta | null {
    for (let i: number = 0; i < this.index.length; i++) {
      if (this.index[i].date === date) {
        return this.index[i];
      }
    }
    return null;
  }

  /** 造一个新 id（保证不与现有冲突） */
  newEntryId(): string {
    const taken: Set<string> = new Set<string>();
    for (let i: number = 0; i < this.index.length; i++) {
      taken.add(this.index[i].id);
    }
    return newNoteId(taken);
  }

  /** 索引列表（日期倒序；同一天按创建时间倒序 —— 最新写的在最上） */
  list(): NoteMeta[] {
    return sortEntries(this.index);
  }

  /**
   * 有日记的日期（月视图打点用）。
   * ⚠️ 一天多篇之后同一个 date 会出现多次 ⇒ **必须去重**，否则未来按它做统计会算重。
   */
  allDates(): string[] {
    const seen: Set<string> = new Set<string>();
    const out: string[] = [];
    for (let i: number = 0; i < this.index.length; i++) {
      if (!seen.has(this.index[i].date)) {
        seen.add(this.index[i].date);
        out.push(this.index[i].date);
      }
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
      const item: BackupItem = { date: m.date, blocks: this.readEntry(m.id), meta: m };
      out.push(item);
    }
    return out;
  }

  /**
   * 导入：把备份内容写回来（**永不覆盖既有内容**）
   *
   * ⚠️ 原来按 date 落盘，同一天第二篇会把第一篇**静默顶掉** ——
   * 现在改为：id 已存在 ⇒ 换一个新 id 追加，**宁可多一篇也不丢一篇**。
   * 全新设备/空库导入时不会撞号 ⇒ 依然是原样恢复。
   */
  importAll(items: BackupItem[]): number {
    let n: number = 0;
    for (let i: number = 0; i < items.length; i++) {
      const it: BackupItem = items[i];
      if (!isValidDateKey(it.date)) {
        continue;
      }
      let id: string = typeof it.meta.id === 'string' && it.meta.id.length > 0 ? it.meta.id : it.date;
      if (this.byId(id) !== null) {
        id = this.newEntryId();
      }
      if (this.saveEntry(id, it.date, it.blocks, it.meta.mood, it.meta.moodText, it.meta.favorite, it.meta.tags)) {
        n++;
      }
    }
    return n;
  }

  private upsertMeta(meta: NoteMeta): void {
    this.index = this.index.filter((m: NoteMeta) => m.id !== meta.id);
    this.index.push(meta);
    // ⚠️ 插入/更新会让顺序失效；`newestOfDate` 依赖"第一个命中即最新"，所以这里必须重排。
    this.index = sortEntries(this.index);
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
