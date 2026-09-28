/**
 * 日记块数据层（**纯逻辑，不引任何 @kit** —— 可被 esbuild 当 TS 编译进单测）
 *
 * 2026-09-28 建立（Phase 2）。评估文档六½ 实测定了三条硬约束：
 *
 *  ① `RichEditor.getSpans()` 是**碎片化**的（20 字符拿到 26 个 span，按输入会话/样式边界切分），
 *     所以绝不能把 span 原样存下来 —— 必须先做**相邻同样式合并**（`mergeSpans`）。
 *  ② 样式序列化**有损**：`fontWeight` 拿到的是内部数字（Bold→9），回填 `9` 无效。
 *     所以只存**语义值** `bold` / `italic` 布尔，打开时再映射回枚举。
 *  ③ 图片 span 拿到的是 PixelMap/Resource，不是路径 —— 图片必须独立成块、只存引用（ref）。
 *
 * 存储格式 = **自研 JSON**（不是 HTML）：十年后仍可读，兑现 Rock solid。
 */
export type BlockType = 'p' | 'h' | 'li' | 'img';

/** 块内富文本片段：只存语义样式，不存渲染层数字 */
export interface Span {
  text: string;
  bold: boolean;
  italic: boolean;
}

/** 一块 = 一个段落/一条标题/一个列表项/一张图 */
export interface Block {
  type: BlockType;
  spans: Span[];
  /** 仅 img 块使用：沙箱内图片文件的引用（相对路径），正文绝不内嵌二进制 */
  ref: string;
}

/** RichEditor 吐出来的原始 span（样式用数字表达，需在此层归一化） */
export interface RawSpan {
  text: string;
  /** 字重：内部数字，Bold 实测为 9；0/undefined 视为常规 */
  fontWeight: number;
  /** 斜体：FontStyle 枚举，Normal=0 / Italic=1 */
  fontStyle: number;
}

export const BLOCK_TYPE_P: BlockType = 'p';
export const BLOCK_TYPE_H: BlockType = 'h';
export const BLOCK_TYPE_LI: BlockType = 'li';
export const BLOCK_TYPE_IMG: BlockType = 'img';

/** 样式是否等价（合并的判据） */
function sameStyle(a: Span, b: Span): boolean {
  return a.bold === b.bold && a.italic === b.italic;
}

/**
 * 把碎片化的原始 span 合并成"最小片段"。
 *
 * 规则：相邻且样式相同 → 拼在一起；空文本 → 丢弃。
 * 这条是数据层的核心（评估文档：开工第一件事）。
 */
export function mergeSpans(raw: RawSpan[]): Span[] {
  const out: Span[] = [];
  for (let i: number = 0; i < raw.length; i++) {
    const r: RawSpan = raw[i];
    if (typeof r.text !== 'string' || r.text.length === 0) {
      continue;
    }
    const cur: Span = {
      text: r.text,
      bold: r.fontWeight === 9,
      italic: r.fontStyle === 1
    };
    const last: Span = out.length > 0 ? out[out.length - 1] : null as unknown as Span;
    if (last !== null && sameStyle(last, cur)) {
      out[out.length - 1] = { text: last.text + cur.text, bold: last.bold, italic: last.italic };
    } else {
      out.push(cur);
    }
  }
  return out;
}

/** 块是否为空（无文本、图片无引用） */
export function isEmptyBlock(b: Block): boolean {
  if (b.type === BLOCK_TYPE_IMG) {
    return b.ref.length === 0;
  }
  return plainTextOfBlock(b).length === 0;
}

/** 一块的纯文本（搜索、字数、预览都用它） */
export function plainTextOfBlock(b: Block): string {
  let s: string = '';
  for (let i: number = 0; i < b.spans.length; i++) {
    s += b.spans[i].text;
  }
  return s;
}

export function plainTextOf(blocks: Block[]): string {
  let s: string = '';
  for (let i: number = 0; i < blocks.length; i++) {
    if (i > 0) {
      s += '\n';
    }
    s += plainTextOfBlock(blocks[i]);
  }
  return s;
}

/**
 * 字数：中英混排的实用口径 —— 中日韩字符**一字一数**，
 * 西文按**词**数（连续非空白非 CJK 串算一个词），
 * **emoji 及所有非 BMP 字符一字一数**（表情是日记的高频内容，不能数错）。
 *
 * ⚠️ 用 `Array.from` 而不是 `str.length`：emoji 是代理对，
 * `.length` 会把一个 emoji 数成 2。
 */
export function wordCountOf(blocks: Block[]): number {
  const chars: string[] = Array.from(plainTextOf(blocks));
  let count: number = 0;
  let inWord: boolean = false;
  for (let i: number = 0; i < chars.length; i++) {
    const c: string = chars[i];
    if (isCjk(c)) {
      count++;
      inWord = false;
      continue;
    }
    // emoji / 扩展平面字符（代理对）：独立成"一字"，否则连续的 😀😀 会被当成一个西文单词
    if ((c.codePointAt(0) as number) > 0xFFFF) {
      count++;
      inWord = false;
      continue;
    }
    if (c === ' ' || c === '\n' || c === '\t' || c === '\r') {
      inWord = false;
      continue;
    }
    if (!inWord) {
      count++;
      inWord = true;
    }
  }
  return count;
}

/** CJK 判定（含中日韩统一表意文字、假名、谚文、全角标点区） */
function isCjk(c: string): boolean {
  const code: number = c.codePointAt(0) as number;
  return (code >= 0x4E00 && code <= 0x9FFF)
    || (code >= 0x3400 && code <= 0x4DBF)
    || (code >= 0x3040 && code <= 0x30FF)
    || (code >= 0xAC00 && code <= 0xD7AF)
    || (code >= 0xF900 && code <= 0xFAFF)
    || (code >= 0xFF00 && code <= 0xFFEF);
}

/** 规范化：剔除空块、补齐 img 的 ref、未知类型降级为 p（坏数据不炸） */
export function normalizeBlocks(blocks: Block[]): Block[] {
  const out: Block[] = [];
  for (let i: number = 0; i < blocks.length; i++) {
    const b: Block = blocks[i];
    if (b === null || b === undefined) {
      continue;
    }
    const type: BlockType = (b.type === BLOCK_TYPE_H || b.type === BLOCK_TYPE_LI || b.type === BLOCK_TYPE_IMG)
      ? b.type
      : BLOCK_TYPE_P;
    const spans: Span[] = type === BLOCK_TYPE_IMG ? [] : mergeSpans(toRaw(b.spans));
    if (type === BLOCK_TYPE_IMG && (typeof b.ref !== 'string' || b.ref.length === 0)) {
      continue;
    }
    if (type !== BLOCK_TYPE_IMG && spans.length === 0) {
      continue;
    }
    out.push({ type: type, spans: spans, ref: type === BLOCK_TYPE_IMG ? b.ref : '' });
  }
  return out;
}

/** Span[] → RawSpan[]（把语义布尔还原成 mergeSpans 的输入形态，复用同一套合并逻辑） */
function toRaw(spans: Span[]): RawSpan[] {
  const out: RawSpan[] = [];
  for (let i: number = 0; i < spans.length; i++) {
    const s: Span = spans[i];
    out.push({
      text: s.text,
      fontWeight: s.bold ? 9 : 0,
      fontStyle: s.italic ? 1 : 0
    });
  }
  return out;
}

/** 序列化：自研 JSON（不是 HTML），十年后仍可读 */
export function blocksToJson(blocks: Block[]): string {
  return JSON.stringify({ v: 1, blocks: normalizeBlocks(blocks) });
}

/**
 * 反序列化：**容错优先**。
 *
 * 为什么不用 `JSON.parse` 后直接断言：日记是用户的全部记忆，
 * 一个字段坏掉不该让整篇打不开 —— 能救多少救多少，救不回的跳过。
 */
export function jsonToBlocks(json: string): Block[] {
  if (json.length === 0) {
    return [];
  }
  let root: object = {};
  try {
    root = JSON.parse(json) as object;
  } catch (e) {
    return [];
  }
  if (root === null || typeof root !== 'object') {
    return [];
  }
  const holder: RootHolder = root as RootHolder;
  const list: Block[] = holder.blocks !== undefined && holder.blocks !== null ? holder.blocks : [];
  if (!Array.isArray(list)) {
    return [];
  }
  return normalizeBlocks(list);
}

interface RootHolder {
  v?: number;
  blocks?: Block[];
}
