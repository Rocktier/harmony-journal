/**
 * RichEditor ⇄ 块模型 的转换（**纯逻辑，单测可跑**）
 *
 * 为什么不在 RichEditor 里直接管理"块"：
 *  RichEditor 的块概念是 span 流，没有"这一行是标题"的一等公民；
 *  强行按块插入会把撤销栈、光标行为搞乱（这类问题只有真机长时间打字才暴露）。
 *
 * 所以采用 **行前缀约定**（Notion / 飞书 / Bear 的通行做法）：
 *  - 存：`getSpans()` → 按换行切行 → `# ` 开头 = 标题，`- ` 开头 = 列表项，其余 = 正文
 *  - 还原：块 → 文本行（标题补 `# `、列表项补 `- `）→ `addTextSpan`
 *  用户在编辑器里**看得见前缀**（写 `# ` 立刻变标题样式的直观反馈由工具栏/样式承担）。
 *
 * ⚠️ 图片块（img）当前不参与行文本转换：MVP 阶段图片插入后置，
 *    序列化的块里若有 img，还原时会退化成"图片占位行"，不会丢数据（ref 仍在 JSON 里）。
 */
import { Block, BLOCK_TYPE_H, BLOCK_TYPE_IMG, BLOCK_TYPE_LI, BLOCK_TYPE_P, Span } from './NoteBlocks';

export const H_PREFIX: string = '# ';
export const LI_PREFIX: string = '- ';

/** 行文本 → 块类型（只认行首前缀，避免正文里写个 '-' 就被当列表） */
export function blockTypeOfLine(line: string): string {
  if (line.startsWith(H_PREFIX)) {
    return BLOCK_TYPE_H;
  }
  if (line.startsWith(LI_PREFIX)) {
    return BLOCK_TYPE_LI;
  }
  return BLOCK_TYPE_P;
}

/** 去掉前缀后的正文 */
export function stripPrefix(line: string): string {
  if (line.startsWith(H_PREFIX)) {
    return line.substring(H_PREFIX.length);
  }
  if (line.startsWith(LI_PREFIX)) {
    return line.substring(LI_PREFIX.length);
  }
  return line;
}

/** 块 → 行文本（还原时用） */
export function lineOfBlock(b: Block): string {
  const text: string = spansText(b.spans);
  if (b.type === BLOCK_TYPE_H) {
    return H_PREFIX + text;
  }
  if (b.type === BLOCK_TYPE_LI) {
    return LI_PREFIX + text;
  }
  if (b.type === BLOCK_TYPE_IMG) {
    return '';
  }
  return text;
}

function spansText(spans: Span[]): string {
  let s: string = '';
  for (let i: number = 0; i < spans.length; i++) {
    s += spans[i].text;
  }
  return s;
}

/**
 * 编辑器里的行（带样式）→ 块数组。
 *
 * 入参是"每行一个 span 数组"的形态：由 UI 层把 `getSpans()` 的碎片按换行切好后传进来，
 * 这样样式（粗/斜）能保留在块里，而不是被压成纯文本。
 */
export function linesToBlocks(lines: Span[][]): Block[] {
  const out: Block[] = [];
  for (let i: number = 0; i < lines.length; i++) {
    const spans: Span[] = lines[i];
    if (spans.length === 0) {
      continue;
    }
    const first: string = spans[0].text;
    const type: string = blockTypeOfLine(first);
    const cut: Span[] = spans.slice();
    // 前缀只可能落在这一行的第一个 span 上
    const stripped: string = stripPrefix(first);
    if (stripped.length === 0) {
      cut.shift();
    } else {
      cut[0] = { text: stripped, bold: spans[0].bold, italic: spans[0].italic };
    }
    if (cut.length === 0) {
      continue;
    }
    out.push({ type: type, spans: cut, ref: '' });
  }
  return out;
}

/** 块数组 → 行文本数组（还原进编辑器） */
export function blocksToLines(blocks: Block[]): string[] {
  const out: string[] = [];
  for (let i: number = 0; i < blocks.length; i++) {
    const b: Block = blocks[i];
    if (b.type === BLOCK_TYPE_IMG) {
      continue; // MVP：图片不回灌进文本行（数据仍在 JSON 里）
    }
    out.push(lineOfBlock(b));
  }
  return out;
}

/**
 * 输入 `# ` / `- ` 时的即时转换（Markdown 快捷键）。
 * 返回 null = 不需要转换。
 */
export function markdownTransform(line: string): { prefix: string; rest: string } | null {
  if (line === '#') {
    return { prefix: H_PREFIX, rest: '' };
  }
  if (line === '-') {
    return { prefix: LI_PREFIX, rest: '' };
  }
  return null;
}

export { BLOCK_TYPE_H, BLOCK_TYPE_IMG, BLOCK_TYPE_LI, BLOCK_TYPE_P };
