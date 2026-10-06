import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ImageStore } from '../data/ImageStore';

import { Block, Span, UNDO_LIMIT, blocksToJson, jsonToBlocks, popSnapshot, pushSnapshot, wordCountOf } from '../data/NoteBlocks';
import { blocksToLines, linesToBlocks } from '../data/NoteBridge';
import {
  MOODS, Mood, NoteMeta, isValidDateKey, parseTags, tagsToText, timeOfDay, todayKey
} from '../data/NoteMeta';
import { NoteStore } from '../data/NoteStore';
import { getStore } from '../data/NoteStoreHolder';
import { RawSpan } from '../data/NoteBlocks';
import { mergeSpans } from '../data/NoteBlocks';
import { RJ_FS_BODY, RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_HEADING, RJ_FS_META, RJ_FS_TITLE, RJ_RADIUS_LG, RJ_RADIUS_SM, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_XL, RJ_SP_XS, RJ_SP_XXL } from '../theme/RjTokens';

/**
 * 编辑页（Phase 4）：所见即所得
 *
 * 关键技术点（评估文档六¾ 实测）：
 *  - RichEditor **没有** fontSize/lineHeight 属性 → 字号走 `setTypingStyle`（onReady 里先设，否则第一段用默认样式）
 *  - 内置 `placeholder`；深色主题要配 `caretColor` / `selectedBackgroundColor`
 *  - 块类型靠**行前缀**：`# ` 标题、`- ` 列表（Markdown 仅作输入快捷键，不占工具栏）
 *  - `getSpans()` 碎片化 → 交给 `mergeSpans` 合并后再转块（数据层职责，不在这里做）
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
/**
 * ⚠️ RichEditor 没有 fontSize 属性，正文字号只能在 `addTextSpan` 的 span style 与
 *    `setTypingStyle` 上给（查过 SDK d.ts）。日记是**长文阅读**，13~16 在 6 寸屏偏弱
 *    ⇒ 正文取 token `RJ_FS_BODY`(=17)，行高靠系统默认。
 * ⚠️ 此前这里另有一份局部 `const RJ_FS_BODY = 17`，与 token 同名冲突
 *    （`arkts-unique-names` 编译不过）—— 已删，正文只剩token 一个来源。
 */

@Entry
@Component
struct Editor {
  /** 这一篇的主键（新建时先占位，首次保存才真正落盘） */
  @State private entryId: string = '';
  @State private date: string = '';
  @State private mood: string = '';
  @State private moodText: string = '';
  @State private words: number = 0;
  @State private saved: boolean = true;
  @State private lines: string[] = [];
  @State private imgRefs: string[] = [];
  @State private imgPaths: string[] = [];
  /** 这**一天**的全部日记（切换条用；只有 >1 篇才显示） */
  @State private dayEntries: NoteMeta[] = [];
  @State private dayIndex: number = -1;
  /** 收藏（★） */
  @State private favorite: boolean = false;
  /** 标签输入串（逗号分隔；保存时才解析成数组） */
  @State private tagsText: string = '';
  /** 最近一次成功保存的时刻（HH:mm）—— 给"真的存上了"一个确定感 */
  @State private savedAt: string = '';
  /** 撤销/重做是否可用（块级快照；本 SDK 的 RichEditor 无 undo API） */
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  private pendingLines: string[] = [];
  private store: NoteStore = getStore();
  private images: ImageStore = new ImageStore();
  private controller: RichEditorController = new RichEditorController();
  private options: RichEditorOptions = { controller: this.controller };
  /** 自动保存防抖计时器（-1 = 没有待保存的定时器） */
  private saveTimer: number = -1;
  /** 上一次落盘的内容（撤销栈的基准，也是"有没有变化"的判据） */
  private lastJson: string = '';
  private undoStack: string[] = [];
  private redoStack: string[] = [];
  /**
   * 灌入后的抑制窗口（毫秒时间戳）。
   * ⚠️ `restore()` 会触发 `onDidChange`，若不抑制，刚打开一篇就立刻把内容存一遍。
   *    用"时间窗"而不是布尔标志，是因为 onDidChange 是异步回调，比 restore 晚到。
   */
  private suppressUntil: number = 0;

  aboutToDisappear(): void {
    // 离开页面（返回键/切走）前把待保存的内容立刻落盘，别只靠防抖定时器
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    if (!this.saved) {
      this.save();
    }
  }

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.images.open(ctx.filesDir);
    const params: object = router.getParams() as object;
    const holder: EntryParam = params as EntryParam;
    const reqId: string = holder.id !== undefined ? holder.id : '';
    const rawDate: string = holder.date !== undefined ? holder.date : '';
    // ⚠️ N3 修复：原来用 `toISOString()`（UTC）回退 —— 与 `todayKey()`（本地时区）不一致，
    //    导致每天 00:00~08:00 之间新建会锁到**前一天**。"今天"只能有一个定义。
    const fallbackDate: string = isValidDateKey(rawDate) ? rawDate : todayKey();

    // 打开目标：**优先认 id**（点搜索结果要精确命中那篇），否则打开这天最新的一篇
    let target: NoteMeta | null = reqId.length > 0 ? this.store.byId(reqId) : null;
    if (target === null && isValidDateKey(rawDate)) {
      target = this.store.newestOfDate(rawDate);
    }
    if (target !== null) {
      this.date = target.date;
      this.entryId = target.id;
      this.loadEntry(target.id, ctx);
    } else {
      // 这天还没有任何一篇 ⇒ 新建（先占位 id，写了才会真正落盘）
      this.date = fallbackDate;
      this.entryId = this.store.newEntryId();
      this.imgRefs = [];
      this.refreshImagePreviews(ctx);
      this.pendingLines = [];
      this.words = 0;
      // ⚠️ 撤销基准也要初始化（空文档）：否则新建日记的**第一次**保存不会入栈，
      //    撤销按钮全程是灰的 —— 恰好是最需要撤销的场景（刚写了一大段想全删）。
      this.lastJson = blocksToJson([]);
      this.canUndo = false;
      this.canRedo = false;
      this.undoStack = [];
      this.redoStack = [];
    }
    this.resolveDayList();
    hilog.info(DOMAIN, TAG, 'open note id=%{public}s date=%{public}s', this.entryId, this.date);
  }

  /** 把某一篇读进来（同时带上它的心情） */
  private loadEntry(id: string, ctx: common.UIAbilityContext): void {
    const meta: NoteMeta | null = this.store.byId(id);
    if (meta !== null) {
      this.mood = meta.mood;
      this.moodText = meta.moodText;
      this.favorite = meta.favorite;
      this.tagsText = tagsToText(meta.tags);
    }
    // 解密已有内容 → 行文本 → 回灌编辑器；图片块单独提出来（正文只存 ref）
    const blocks: Block[] = this.store.readEntry(id);
    this.lines = blocksToLines(blocks);
    const refs: string[] = [];
    for (let i: number = 0; i < blocks.length; i++) {
      if (blocks[i].type === 'img' && blocks[i].ref.length > 0) {
        refs.push(blocks[i].ref);
      }
    }
    this.imgRefs = refs;
    this.refreshImagePreviews(ctx);
    // ⚠️ 不在这里灌入：RichEditor 未 onReady 时 addTextSpan 会静默失败（实拍抓到）。
    this.pendingLines = blocksToLines(blocks);
    this.words = wordCountOf(blocks);
    // 撤销基准 = 打开时的内容（否则第一次保存会push一个"空→有内容"的假撤销步骤）
    this.lastJson = blocksToJson(blocks);
    this.canUndo = false;
    this.canRedo = false;
    this.undoStack = [];
    this.redoStack = [];
  }

  /** 刷新"这一天有几篇、当前是第几篇"（切换条的数据源） */
  private resolveDayList(): void {
    this.dayEntries = this.store.entriesOfDate(this.date);
    let at: number = -1;
    for (let i: number = 0; i < this.dayEntries.length; i++) {
      if (this.dayEntries[i].id === this.entryId) {
        at = i;
      }
    }
    this.dayIndex = at;
  }

  /** 切换到这一天的上一篇/下一篇（**先保存当前**，否则丢编辑中的内容） */
  private async switchTo(delta: number): Promise<void> {
    const next: number = this.dayIndex + delta;
    if (next < 0 || next >= this.dayEntries.length) {
      return;
    }
    this.save();
    const target: NoteMeta = this.dayEntries[next];
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.entryId = target.id;
    this.loadEntry(target.id, ctx);
    this.resolveDayList();
    this.restore();
    hilog.info(DOMAIN, TAG, 'switch to %{public}s (%{public}d/%{public}d)', target.id, this.dayIndex + 1, this.dayEntries.length);
  }

  /** 这天再来一篇（先保存当前的；新篇写了才会落盘，不会留下空日记） */
  private async addAnotherHere(): Promise<void> {
    this.save();
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.entryId = this.store.newEntryId();
    this.mood = '';
    this.moodText = '';
    this.favorite = false;
    this.tagsText = '';
    this.lines = [];
    this.imgRefs = [];
    this.imgPaths = [];
    this.words = 0;
    this.saved = true;
    this.pendingLines = [];
    this.resolveDayList();
    this.restore();
    hilog.info(DOMAIN, TAG, 'add another entry at %{public}s id=%{public}s', this.date, this.entryId);
  }

  /** 把行文本灌回 RichEditor（块 → 行）—— 必须在 onReady 之后调用 */
  private restore(): void {
    // 灌入期间不要触发自动保存（否则刚打开就存一次，等于白写一遍索引）
    this.suppressUntil = Date.now() + 500;
    this.lines = this.pendingLines;
    try {
      // ⚠️ 必须**不传参数**：`deleteSpans(value?: RichEditorRange)` 的语义是
      //    "留空 = 删掉全部 span"；传 `{start:0, end:-1}` 里 end:-1 不是有效值，
      //    会静默不删 —— 于是旧内容留着、新内容接在后面（实拍抓到：撤销后 22 字）。
      //    这个 bug 同时影响 `switchTo`（切篇）与 `addAnotherHere`（新开一篇）。
      this.controller.deleteSpans();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'deleteSpans failed: %{public}s', JSON.stringify(e));
    }
    for (let i: number = 0; i < this.lines.length; i++) {
      if (i > 0) {
        this.controller.addTextSpan('\n', { style: { fontSize: RJ_FS_BODY, fontColor: $r('app.color.rj_text') } });
      }
      this.controller.addTextSpan(this.lines[i], { style: { fontSize: RJ_FS_BODY, fontColor: $r('app.color.rj_text') } });
    }
    hilog.info(DOMAIN, TAG, 'restored %{public}d lines', this.lines.length);
  }

  /**
   * 正文变化：标未保存 + **1.5s 防抖自动落盘**
   *
   * ⚠️ 为什么必须自动保存（第一性：日记 App 的底线是"写下的不会消失"）：
   * 原来只在离开页面时保存，而 HarmonyOS 后台管控随时可能杀进程（实拍日志里就有
   * `Kill Reason: UpgradeApp`）⇒ 写了半天被回收，一句"未保存"根本救不回来。
   * 保存应该是**持续保证**，不是"一个动作"。
   */
  private onContentChanged(): void {
    if (Date.now() < this.suppressUntil) {
      return;
    }
    this.saved = false;
    this.scheduleSave();
  }

  private scheduleSave(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.save();
    }, 1500);
  }

  /** 当前编辑区内容 → JSON（撤销快照的原料，与落盘用同一份序列化） */
  private currentJson(): string {
    return blocksToJson(this.collect());
  }

  /** 把一份快照灌回编辑区 */
  private applySnapshot(json: string): void {
    try {
      const blocks: Block[] = jsonToBlocks(json);
      this.pendingLines = blocksToLines(blocks);
      this.restore();
      this.words = wordCountOf(blocks);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'applySnapshot failed: %{public}s', JSON.stringify(e));
    }
  }

  private doUndo(): void {
    const popped = popSnapshot(this.undoStack);
    if (popped.json.length === 0) {
      return;
    }
    this.redoStack = pushSnapshot(this.redoStack, this.lastJson, UNDO_LIMIT);
    this.lastJson = popped.json;
    this.undoStack = popped.stack;
    this.applySnapshot(popped.json);
    this.canUndo = this.undoStack.length > 0;
    this.canRedo = this.redoStack.length > 0;
    this.save();
    hilog.info(DOMAIN, TAG, 'undo applied');
  }

  private doRedo(): void {
    const popped = popSnapshot(this.redoStack);
    if (popped.json.length === 0) {
      return;
    }
    this.undoStack = pushSnapshot(this.undoStack, this.lastJson, UNDO_LIMIT);
    this.lastJson = popped.json;
    this.redoStack = popped.stack;
    this.applySnapshot(popped.json);
    this.canUndo = this.undoStack.length > 0;
    this.canRedo = this.redoStack.length > 0;
    this.save();
    hilog.info(DOMAIN, TAG, 'redo applied');
  }

  /** 编辑器 → 块（保存路径：getSpans 碎片 → 合并 → 切行 → 块） */
  private collect(): Block[] {
    // getSpans 返回联合类型 RichEditorSpan；文本 span 的结构是
    // { value, textStyle: { fontWeight, fontStyle, ... } } —— 样式在 textStyle 子对象里（查过 SDK d.ts）
    const spans: RichEditorSpan[] = this.controller.getSpans({ start: 0, end: -1 });
    const raws: RawSpan[] = [];
    for (let i: number = 0; i < spans.length; i++) {
      const t: RichEditorTextSpanResult = spans[i] as RichEditorTextSpanResult;
      const st: RichEditorTextStyleResult | undefined = t.textStyle;
      raws.push({
        text: typeof t.value === 'string' ? t.value : '',
        fontWeight: st !== undefined && typeof st.fontWeight === 'number' ? st.fontWeight : 0,
        fontStyle: st !== undefined && typeof st.fontStyle === 'number' ? st.fontStyle : 0
      });
    }
    // 按换行把 span 切成"行"，行内保留样式
    const rows: Span[][] = [];
    let cur: Span[] = [];
    const flat: Span[] = mergeSpans(raws);
    for (let i: number = 0; i < flat.length; i++) {
      const s: Span = flat[i];
      const parts: string[] = s.text.split('\n');
      for (let j: number = 0; j < parts.length; j++) {
        if (j > 0) {
          rows.push(cur);
          cur = [];
        }
        if (parts[j].length > 0) {
          cur.push({ text: parts[j], bold: s.bold, italic: s.italic });
        }
      }
    }
    rows.push(cur);
    return linesToBlocks(rows);
  }

  /** 图片解密到 cache 后拿到可显示路径（Image 组件不认密文） */
  private refreshImagePreviews(ctx: common.UIAbilityContext): void {
    const paths: string[] = [];
    for (let i: number = 0; i < this.imgRefs.length; i++) {
      paths.push(this.images.load(this.imgRefs[i], this.store.getVault(), ctx.cacheDir));
    }
    this.imgPaths = paths;
  }

  /** 选图 → 读原文件 → 加密落沙箱 → 只把 ref 记进正文 */
  private async pickImage(): Promise<void> {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const pv: picker.PhotoViewPicker = new picker.PhotoViewPicker();
    try {
      const res: picker.PhotoSelectResult = await pv.select({ maxSelectNumber: 1 });
      if (res.photoUris.length === 0) {
        hilog.warn(DOMAIN, TAG, 'pickImage: no photo selected (picker returned empty)');
        return;
      }
      // 照片 uri 直接打开；fs 没有 fstatSync，且 uri 未必能 statSync —— 用循环读到 EOF（查过 .d.ts）
      const file: fs.File = fs.openSync(res.photoUris[0], fs.OpenMode.READ_ONLY);
      const bufSize: number = 1024 * 1024;
      const chunks: Uint8Array[] = [];
      let total: number = 0;
      try {
        while (true) {
          const buf: ArrayBuffer = new ArrayBuffer(bufSize);
          const readLen: number = fs.readSync(file.fd, buf);
          if (readLen <= 0) {
            break;
          }
          chunks.push(new Uint8Array(buf.slice(0, readLen)));
          total += readLen;
        }
      } finally {
        fs.closeSync(file);
      }
      const raw: Uint8Array = new Uint8Array(total);
      let off: number = 0;
      for (let i: number = 0; i < chunks.length; i++) {
        raw.set(chunks[i], off);
        off += chunks[i].length;
      }

      const ref: string = this.images.newRef();
      if (!this.images.save(ref, this.store.getVault(), raw)) {
        hilog.error(DOMAIN, TAG, 'save image failed');
        return;
      }
      this.imgRefs = this.imgRefs.concat([ref]);
      this.refreshImagePreviews(ctx);
      this.save();
      hilog.info(DOMAIN, TAG, 'image added: %{public}s', ref);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pickImage failed: %{public}s', JSON.stringify(e));
    }
  }

  private save(): void {
    const blocks: Block[] = this.collect();
    // 图片块：正文里只有 ref，二进制永远不进文本流
    const withImages: Block[] = blocks;
    for (let i: number = 0; i < this.imgRefs.length; i++) {
      const imgBlock: Block = { type: 'img', spans: [], ref: this.imgRefs[i] };
      withImages.push(imgBlock);
    }
    const ok: boolean = this.store.saveEntry(this.entryId, this.date, withImages, this.mood, this.moodText,
      this.favorite, parseTags(this.tagsText));
    this.saved = ok;
    this.words = wordCountOf(blocks);
    if (ok) {
      // 撤销栈：把**上一个版本**推进去（块级快照；本 SDK RichEditor 无 undo API）
      const json: string = blocksToJson(withImages);
      if (json !== this.lastJson) {
        this.undoStack = pushSnapshot(this.undoStack, this.lastJson, UNDO_LIMIT);
        this.lastJson = json;
        this.redoStack = [];
        this.canUndo = this.undoStack.length > 0;
        this.canRedo = false;
      }
      // 给出"真的存上了、什么时候存的"的确定感（安全感的来源是这个时间戳）
      this.savedAt = timeOfDay(Date.now());
      // 保存后这一天的篇数/次序可能变了 ⇒ 切换条必须跟着刷新
      this.resolveDayList();
    }
    hilog.info(DOMAIN, TAG, 'save id=%{public}s ok=%{public}s blocks=%{public}d', this.entryId, ok, withImages.length);
  }

  private setSpanStyle(bold: boolean, italic: boolean): void {
    this.controller.setTypingStyle({
      fontSize: 16,
      fontColor: $r('app.color.rj_text'),
      fontWeight: bold ? FontWeight.Bold : FontWeight.Normal,
      fontStyle: italic ? FontStyle.Italic : FontStyle.Normal
    });
  }

  /** 心情下拉的选项：0 号是「无」（用于取消），其后依次对应 MOODS */
  private moodOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    opts.push({ value: '无' });
    MOODS.forEach((m: Mood) => {
      opts.push({ value: m.emoji });
    });
    return opts;
  }

  /** 当前心情在下拉里的序号（没选 = 0） */
  private moodSelectedIndex(): number {
    for (let i: number = 0; i < MOODS.length; i++) {
      if (MOODS[i].id === this.mood) {
        return i + 1;
      }
    }
    return 0;
  }

  /** 下拉框收起时显示的文字（没选显示"心情"当占位） */
  private moodDisplay(): string {
    for (let i: number = 0; i < MOODS.length; i++) {
      if (MOODS[i].id === this.mood) {
        return MOODS[i].emoji;
      }
    }
    return '心情';
  }

  build() {
    Column() {
      // 头：日期 + 返回
      Row() {
        Text('<')
          .fontSize(RJ_FS_TITLE)
          .fontColor($r('app.color.rj_text2'))
          .onClick(() => {
            this.save();
            router.back();
          })
          .padding({ right: RJ_SP_LG })
        Text(this.date)
          .fontSize(RJ_FS_HEADING)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
        // 收藏：重要的几篇★住，以后一眼能挑出来
        Text(this.favorite ? '★' : '☆')
          .fontSize(RJ_FS_BODY)
          .fontColor(this.favorite ? $r('app.color.rj_red') : $r('app.color.rj_text3'))
          .margin({ left: RJ_SP_LG })
          .padding(RJ_SP_SM)
          .onClick(() => {
            this.favorite = !this.favorite;
            this.save();
          })
        Blank()
        /**
         * 「保存」放右上角（党哥定的层级）；自动保存状态移到**右下角**并淡化 ——
         * 它不是给人点的，是给人放心的，不配占用头部。
         * 仍保留手动保存：自动保存有 1.5s 防抖，"离开前立刻存一下"仍需要一个明确入口。
         * ⚠️ `ButtonType.Normal` 显式写死（默认值在 API 18 变过，覆盖 16+ 必须锁定）。
         */
        Button('保存', { type: ButtonType.Normal, stateEffect: true })
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .backgroundColor($r('app.color.rj_red'))
          .fontColor($r('app.color.rj_bg'))
          .fontSize(RJ_FS_CAPTION)
          .fontWeight(FontWeight.Bold)
          .borderRadius(RJ_RADIUS_LG)
          .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_LG })

      /**
       * 这天的其它篇目 / 再来一篇
       *
       * ⚠️ 显示条件必须 >= 1（**不能写成 > 1**）：
       *    若只在"已有 2 篇"时才出现，第一篇时压根没有 `＋` ⇒ **用户永远加不了第二篇**，
       *    整个"一天多篇"就成了不可达功能（真机实拍抓到）。
       *    但计数与 `‹ ›` 仍只在 >1 篇时显示 —— 单篇时界面保持零干扰。
       */
      if (this.dayEntries.length >= 1) {
        Row() {
          if (this.dayEntries.length > 1) {
            Text('本日 ' + this.dayEntries.length + ' 篇')
              .fontSize(RJ_FS_META)
              .fontFamily('monospace')
              .fontColor($r('app.color.rj_text3'))
          }
          Blank()
          if (this.dayEntries.length > 1) {
            Text('‹')
              .fontSize(RJ_FS_BODY)
              .fontColor(this.dayIndex > 0 ? $r('app.color.rj_text2') : $r('app.color.rj_line'))
              .padding({ left: RJ_SP_LG, right: RJ_SP_LG })
              .onClick(() => {
                this.switchTo(-1);
              })
            Text((this.dayIndex < 0 ? this.dayEntries.length : this.dayIndex + 1) + '/' + this.dayEntries.length)
              .fontSize(RJ_FS_CAPTION)
              .fontFamily('monospace')
              .fontColor($r('app.color.rj_text2'))
            Text('›')
              .fontSize(RJ_FS_BODY)
              .fontColor(this.dayIndex >= 0 && this.dayIndex < this.dayEntries.length - 1
                ? $r('app.color.rj_text2') : $r('app.color.rj_line'))
              .padding({ left: RJ_SP_LG, right: RJ_SP_LG })
              .onClick(() => {
                this.switchTo(1);
              })
          }
          Text('＋')
            .fontSize(RJ_FS_CALLOUT)
            .fontColor($r('app.color.rj_text'))
            .fontWeight(FontWeight.Bold)
            .padding({ left: RJ_SP_LG })
            .onClick(() => {
              this.addAnotherHere();
            })
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XS, bottom: RJ_SP_SM })
      }

      /**
       * 心情（下拉）+ 标签（收窄）合并成一行。
       *
       * ⚠️ 原来各占一大块：心情一整行 5 个大表情（RJ_FS_TITLE 级别，视觉上像在替用户
       *   强调"今天什么心情"）、标签框宽度撑满 + 长占位文案，看着像 H1 小节标题
       *   （实拍反馈"标签栏太大了"）。
       *   两者都是**元信息**，不配占两条主视觉行 ⇒ 收成一行两个次要控件。
       *
       * 心情用系统 `Select` 下拉（API 8 起，我们约束内）：0 号 = 「无」（用于取消），
       *   其后依次对应 MOODS。
       */
      Row() {
        Select(this.moodOptions())
          .selected(this.moodSelectedIndex())
          .value(this.moodDisplay())
          // ⚠️ Select 没有 fontSize 属性（编译实测报 10505001），字号走 Font 的 size
          .font({ size: RJ_FS_CAPTION })
          .fontColor($r('app.color.rj_text'))
          .onSelect((index: number) => {
            this.mood = index === 0 ? '' : MOODS[index - 1].id;
            if (this.mood.length === 0) {
              this.moodText = '';
            }
            this.save();
          })
        TextInput({ placeholder: '标签', text: this.tagsText })
          .fontSize(RJ_FS_CAPTION)
          .backgroundColor($r('app.color.rj_card'))
          .fontColor($r('app.color.rj_text'))
          .placeholderColor($r('app.color.rj_text3'))
          .height(28)
          .layoutWeight(1)
          .margin({ left: RJ_SP_MD })
          .onChange((v: string) => {
            this.tagsText = v;
            this.saved = false;
            this.scheduleSave();
          })
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })

      /**
       * 工具栏（富文本：B / I / 列表 / 图片；文档操作：撤销 / 重做 / 保存 / 字数）
       *
       * ⚠️ 位置为什么必须在**正文上方**（原来在底部，实拍被输入法盖掉过）：
       *   键盘弹出会把底部那一行顶出屏幕 —— 整排功能键消失的那一刻，
       *   恰恰是"正写到一半想加粗/插图片"最需要它的时候。
       *   放上面则键盘怎么弹都遮不住。
       *
       * ⚠️ 一律**无框**：每个键一个方框会吃掉大半行，功能一多就放不下 ——
       *   系统原生文本工具条就是一排无框小键。键与键的区分靠文字与间距，
       *   不可用的键置灰，不再用"有没有底"表达状态。
       *
       * ⚠️ 全部是真 `Button`（不是 `Text(...).onClick(...)`）：按压反馈 /
       *   读屏报"按钮" / 可聚焦。`ButtonType.Normal` 显式写死 —— 默认值在
       *   **API 18 变过**（<18 = Capsule，≥18 = ROUNDED_RECTANGLE），我们覆盖
       *   API 16+，不写死的话不同版本设备上形状不一致。
       */
      Row() {
        /**
         * —— 富文本：参考**系统原生文本工具条**的做法 —— 一排紧凑小键、无框。
         * 原来每个键一个白底方框，四个键就占掉大半行，再往后加功能（对齐/高亮/清单…）
         * 根本放不下；系统的做法证明"无框小键"既省地方又够清楚。
         */
        Button('B', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_CALLOUT)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rj_text'))
          .backgroundColor(Color.Transparent)
          .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .onClick(() => {
            this.setSpanStyle(true, false);
          })
        Button('I', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_CALLOUT)
          .fontStyle(FontStyle.Italic)
          .fontColor($r('app.color.rj_text'))
          .backgroundColor(Color.Transparent)
          .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .onClick(() => {
            this.setSpanStyle(false, true);
          })
        Button('列表', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_CAPTION)
          .fontColor($r('app.color.rj_text'))
          .backgroundColor(Color.Transparent)
          .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .onClick(() => {
            this.controller.addTextSpan('- ', { style: { fontSize: RJ_FS_BODY, fontColor: $r('app.color.rj_text') } });
          })
        Button('图片', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RJ_FS_CAPTION)
          .fontColor($r('app.color.rj_text'))
          .backgroundColor(Color.Transparent)
          .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .onClick(() => {
            this.pickImage();
          })
        Blank()
        // 撤销/重做：不可逆的编辑必须有退路（手机上手指一滑就是一段话没了）
        Button('撤销', { type: ButtonType.Normal, stateEffect: true })
          .backgroundColor(Color.Transparent)
          .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.canUndo ? $r('app.color.rj_text') : $r('app.color.rj_line'))
          .enabled(this.canUndo)   // 禁用态交给 Button，读屏也能正确报"已停用"
          .onClick(() => {
            this.doUndo();
          })
        Button('重做', { type: ButtonType.Normal, stateEffect: true })
          .backgroundColor(Color.Transparent)
          .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.canRedo ? $r('app.color.rj_text') : $r('app.color.rj_line'))
          .enabled(this.canRedo)
          .onClick(() => {
            this.doRedo();
          })
      }
      .width('100%')
      .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_XS, bottom: RJ_SP_XS })

      // 正文
      RichEditor(this.options)
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .caretColor($r('app.color.rj_red'))
        .selectedBackgroundColor($r('app.color.rj_sel'))
        /**
         * 占位文案**不再提 Markdown**（原来是「写点什么…（# 标题、- 列表）」）。
         *
         * ⚠️ 为什么改：写日记的人不该被迫先学一套标记语法 ——
         * 看到 `# `- ` 会以为"必须这么写才有效果"，这是把内部实现泄漏成了使用负担。
         * 加粗/列表这些需求，上面工具栏的按钮已经直接给了。
         *
         * ⚠️ 但**解析没删**：历史日记里已经存着 `# `/`- ` 形式的文本，
         * 去掉解析会让老内容"退化成普通文字"（等于静默改用户的日记）。
         * 所以是"入口上淡化"，不是"能力上取消"。
         */
        .placeholder('写点什么…', { font: { size: RJ_FS_BODY }, fontColor: $r('app.color.rj_text3') })
        .onReady(() => {
          this.setSpanStyle(false, false);
          this.restore();
        })
        .onDidChange(() => {
          this.onContentChanged();
        })
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_SM })

      // 已插入的图片（缩略图；正文里只存加密文件的引用）
      if (this.imgPaths.length > 0) {
        Row() {
          ForEach(this.imgPaths, (p: string) => {
            if (p.length > 0) {
              Image(fileUri.getUriFromPath(p))
                .width(64)
                .height(64)
                .objectFit(ImageFit.Cover)
                .borderRadius(RJ_RADIUS_SM)
                .margin({ right: RJ_SP_MD })
            }
          }, (p: string, index: number) => index + p)
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, top: RJ_SP_MD, bottom: RJ_SP_SM })
      }

      /**
       * 底部：字数 + 自动保存状态（**右下角、刻意淡化** —— 党哥定的层级：
       * 它不是给人点的，是给人放心的，不配占头部）。
       * 键盘弹出时这行会被盖住 —— 正好：打字时不该被状态打扰，收起键盘才看得到。
       */
      Row() {
        Text(this.words + ' 字')
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
        Blank()
        Text(this.saved ? (this.savedAt.length > 0 ? '已保存 ' + this.savedAt : '已保存') : '未保存…')
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .opacity(this.saved ? 0.7 : 0.4)
          .animation({ duration: 220, curve: Curve.EaseOut })
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_SM, bottom: RJ_SP_LG })

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
  }
}

/**
 * 打开某一篇：
 *  - 带 `id` ⇒ 精确打开那篇（搜索结果、未来的时间轴都用这个）
 *  - 只有 `date` ⇒ 打开这天最新的一篇；这天没写过就新建
 */
interface EntryParam {
  id?: string;
  date?: string;
}
