import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ImageStore } from '../data/ImageStore';

import { Block, Span, wordCountOf } from '../data/NoteBlocks';
import { blocksToLines, linesToBlocks } from '../data/NoteBridge';
import { MOODS, Mood, NoteMeta, isValidDateKey } from '../data/NoteMeta';
import { NoteStore } from '../data/NoteStore';
import { getStore } from '../data/NoteStoreHolder';
import { RawSpan } from '../data/NoteBlocks';
import { mergeSpans } from '../data/NoteBlocks';

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

@Entry
@Component
struct Editor {
  @State private date: string = '';
  @State private mood: string = '';
  @State private moodText: string = '';
  @State private words: number = 0;
  @State private saved: boolean = true;
  @State private lines: string[] = [];
  @State private imgRefs: string[] = [];
  @State private imgPaths: string[] = [];
  private pendingLines: string[] = [];
  private store: NoteStore = getStore();
  private images: ImageStore = new ImageStore();
  private controller: RichEditorController = new RichEditorController();
  private options: RichEditorOptions = { controller: this.controller };

  aboutToAppear(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.images.open(ctx.filesDir);
    const params: object = router.getParams() as object;
    const holder: DateParam = params as DateParam;
    const d: string = holder.date !== undefined ? holder.date : '';
    this.date = isValidDateKey(d) ? d : new Date().toISOString().substring(0, 10);

    const meta: NoteMeta | null = this.store.metaOf(this.date);
    if (meta !== null) {
      this.mood = meta.mood;
      this.moodText = meta.moodText;
    }
    // 解密已有内容 → 行文本 → 回灌编辑器；图片块单独提出来（正文只存 ref）
    const blocks: Block[] = this.store.readNote(this.date);
    this.lines = blocksToLines(blocks);
    const refs: string[] = [];
    for (let i: number = 0; i < blocks.length; i++) {
      if (blocks[i].type === 'img' && blocks[i].ref.length > 0) {
        refs.push(blocks[i].ref);
      }
    }
    this.imgRefs = refs;
    this.refreshImagePreviews(ctx);
    // ⚠️ 不在这里 restore：aboutToAppear 时 RichEditor 还没 onReady，
    // addTextSpan 会静默失败（实拍抓到：字数对但正文空）。灌入挪到 onReady。
    this.pendingLines = blocksToLines(blocks);
    this.words = wordCountOf(blocks);
    hilog.info(DOMAIN, TAG, 'open note %{public}s, blocks=%{public}d', this.date, blocks.length);
  }

  /** 把行文本灌回 RichEditor（块 → 行）—— 必须在 onReady 之后调用 */
  private restore(): void {
    this.lines = this.pendingLines;
    try {
      this.controller.deleteSpans({ start: 0, end: -1 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'deleteSpans skipped');
    }
    for (let i: number = 0; i < this.lines.length; i++) {
      if (i > 0) {
        this.controller.addTextSpan('\n', { style: { fontSize: 16, fontColor: '#FFFFFF' } });
      }
      this.controller.addTextSpan(this.lines[i], { style: { fontSize: 16, fontColor: '#FFFFFF' } });
    }
    hilog.info(DOMAIN, TAG, 'restored %{public}d lines', this.lines.length);
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
    const ok: boolean = this.store.writeNote(this.date, withImages, this.mood, this.moodText);
    this.saved = ok;
    this.words = wordCountOf(blocks);
    hilog.info(DOMAIN, TAG, 'save %{public}s ok=%{public}s blocks=%{public}d', this.date, ok, withImages.length);
  }

  aboutToDisappear(): void {
    this.save();
  }

  private setSpanStyle(bold: boolean, italic: boolean): void {
    this.controller.setTypingStyle({
      fontSize: 16,
      fontColor: '#FFFFFF',
      fontWeight: bold ? FontWeight.Bold : FontWeight.Normal,
      fontStyle: italic ? FontStyle.Italic : FontStyle.Normal
    });
  }

  build() {
    Column() {
      // 头：日期 + 返回
      Row() {
        Text('<')
          .fontSize(18)
          .fontColor($r('app.color.rj_text2'))
          .onClick(() => {
            this.save();
            router.back();
          })
          .padding({ right: 12 })
        Text(this.date)
          .fontSize(15)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
        Blank()
        Text(this.saved ? '已保存' : '未保存')
          .fontSize(10)
          .fontColor($r('app.color.rj_text3'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 10 })

      // 心情
      Row() {
        ForEach(MOODS, (m: Mood) => {
          Text(m.emoji)
            .fontSize(20)
            .padding({ left: 6, right: 6 })
            .opacity(this.mood === m.id ? 1 : 0.35)
            .onClick(() => {
              this.mood = this.mood === m.id ? '' : m.id;
              if (this.mood === m.id) {
                this.moodText = '';
              }
              this.save();
            })
        }, (m: Mood) => m.id)
      }
      .width('100%')
      .padding({ left: 14, bottom: 8 })

      // 正文
      RichEditor(this.options)
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .caretColor($r('app.color.rj_red'))
        .selectedBackgroundColor('#33FF4A3D')
        .placeholder('写点什么…（# 标题、- 列表）', { font: { size: 16 }, fontColor: '#52FFFFFF' })
        .onReady(() => {
          this.setSpanStyle(false, false);
          this.restore();
        })
        .onDidChange(() => {
          this.saved = false;
        })
        .padding({ left: 20, right: 20, top: 4 })

      // 已插入的图片（缩略图；正文里只存加密文件的引用）
      if (this.imgPaths.length > 0) {
        Row() {
          ForEach(this.imgPaths, (p: string) => {
            if (p.length > 0) {
              Image(fileUri.getUriFromPath(p))
                .width(64)
                .height(64)
                .objectFit(ImageFit.Cover)
                .borderRadius(2)
                .margin({ right: 8 })
            }
          }, (p: string, index: number) => index + p)
        }
        .width('100%')
        .padding({ left: 20, top: 8, bottom: 4 })
      }

      // 工具栏：B / I / 列表 / 保存
      Row() {
        Text('B')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            this.setSpanStyle(true, false);
          })
          .padding(10)
        Text('I')
          .fontSize(15)
          .fontStyle(FontStyle.Italic)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            this.setSpanStyle(false, true);
          })
          .padding(10)
        Text('• 列表')
          .fontSize(12)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            this.controller.addTextSpan('- ', { style: { fontSize: 16, fontColor: '#FFFFFF' } });
          })
          .padding(10)
        Text('图片')
          .fontSize(12)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            this.pickImage();
          })
          .padding(10)
        Blank()
        Text(this.words + ' 字')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .padding(10)
        Text('保存')
          .fontSize(12)
          .fontColor($r('app.color.rj_red'))
          .onClick(() => {
            this.save();
          })
          .padding(10)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 20 })
      .border({ width: { top: 1 }, color: $r('app.color.rj_line') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
  }
}

interface DateParam {
  date?: string;
}
