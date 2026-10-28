/**
 * 日记模板（2026-10-20 同质化整改的辅助功能；1.0.6 加自定义模板）
 *
 * 用户视角：面对空白页发呆是写日记的最大阻力 —— "今天没什么好写的"
 * 一半是真没什么写，一半是不知道从哪开始。模板给一个开头，
 * 写不完可以整段删掉（它只是预置文本，没有任何强制）。
 *
 * 1.0.6 的变化：模板从"4 个写死的"变成**内置 3 个 + 用户自建**。
 * 为什么值得做（对标 Day One 的 Customizable templates）：
 * 内置模板只能覆盖通用场景，而"我的晨间复盘固定问这三句"是每个人的私事 ——
 * 让用户把自己的套路存成模板，模板才真正省时间。
 *
 * ⚠️ 为什么自定义模板存进**索引**（而不是单独文件）：
 *    索引本来整块在内存里、整块加密落盘，多加一个数组 = **零额外 IO**；
 *    单独文件则要多一次读 + 多一次解密 + 多一处可能损坏的地方。
 *    模板只是骨架（不含日记内容），与索引同生共死正合适。
 */

/** 一个模板：按钮上的名字 + 灌入编辑器的预置行 */
export interface JournalTemplate {
  id: string;
  /** 按钮标签（短，4 个字以内） */
  label: string;
  /** 预置的正文行（灌入后用户可改可删） */
  lines: string[];
  /**
   * 是不是内置的（内置不可删改 —— 用户改坏了没法恢复，就干脆不让改）。
   * 老数据没有这个字段 ⇒ 按内置处理（`normalizeTemplates` 里判定）。
   */
  builtin: boolean;
}

/** 模板名上限（按钮上要放得下） */
export const TEMPLATE_LABEL_MAX: number = 8;
/** 单个模板的行数上限（超过就不是"骨架"而是"范文"了） */
export const TEMPLATE_LINES_MAX: number = 12;
/** 单行长度上限 */
export const TEMPLATE_LINE_MAX: number = 60;
/** 自定义模板的数量上限（含内置） */
export const TEMPLATE_MAX: number = 10;

export const TEMPLATES: JournalTemplate[] = [
  {
    id: 'three-questions',
    label: '每日三问',
    lines: [
      '今天发生了什么：',
      '感谢什么：',
      '明天的重点：'
    ],
    builtin: true
  },
  {
    id: 'morning',
    label: '晨间日记',
    lines: [
      '昨晚睡得：',
      '此刻的状态：',
      '今天只想做好一件事：'
    ],
    builtin: true
  },
  {
    id: 'travel',
    label: '旅行手账',
    lines: [
      '地点：',
      '吃了什么：',
      '想记住的一幕：'
    ],
    builtin: true
  }
];

/** 模板名清洗：trim + 限长（超长会撑破按钮） */
export function sanitizeTemplateLabel(raw: string): string {
  if (typeof raw !== 'string') {
    return '';
  }
  const folded: string = raw.replace(/\s+/g, ' ').trim();
  const chars: string[] = Array.from(folded);
  if (chars.length === 0) {
    return '';
  }
  return chars.slice(0, TEMPLATE_LABEL_MAX).join('');
}

/**
 * 模板正文清洗：按行拆分、去掉首尾空行、空行保留、限行限长
 *
 * ⚠️ 为什么**保留中间的空行**：模板的价值是"留空让用户输入"，
 *    空行就是那个空位（"今天发生了什么："后面留一行空，用户直接在空行上写）。
 *    只去掉首尾空行（那是误按回车造成的噪声）。
 *
 * ⚠️ 为什么限行：模板最终是灌进编辑器的行；几十行的模板灌进去
 *    就不是"降低启动阻力"，而是"塞给用户一篇作文"。
 */
export function sanitizeTemplateLines(raw: string): string[] {
  if (typeof raw !== 'string') {
    return [];
  }
  const parts: string[] = raw.split('\n');
  const out: string[] = [];
  for (let i: number = 0; i < parts.length && out.length < TEMPLATE_LINES_MAX; i++) {
    const one: string = parts[i].replace(/\r/g, '').trim();
    const chars: string[] = Array.from(one);
    out.push(chars.slice(0, TEMPLATE_LINE_MAX).join(''));
  }
  // 去掉首尾空行（中间的留给用户当填空位）
  while (out.length > 0 && out[0].length === 0) {
    out.shift();
  }
  while (out.length > 0 && out[out.length - 1].length === 0) {
    out.pop();
  }
  return out;
}

/**
 * 洗白用户自建模板列表（**从索引读出来的入口**）
 *
 * 保证：id 唯一、名字非空、至少有一行；脏数据整条丢弃（骨架坏了不如没有）。
 */
export function normalizeTemplates(raw: JournalTemplate[] | undefined): JournalTemplate[] {
  const out: JournalTemplate[] = [];
  if (!Array.isArray(raw)) {
    return out;
  }
  const seen: Set<string> = new Set<string>(builtinIds());
  for (let i: number = 0; i < raw.length && out.length < TEMPLATE_MAX; i++) {
    const it: JournalTemplate = raw[i];
    if (it === null || it === undefined) {
      continue;
    }
    if (typeof it.id !== 'string' || it.id.length === 0 || it.id.length > 64) {
      continue;
    }
    // 内置模板由常量表提供，不在索引里存副本（免得两边不一致）
    if (isBuiltinId(it.id)) {
      continue;
    }
    if (seen.has(it.id)) {
      continue;
    }
    const label: string = sanitizeTemplateLabel(it.label);
    const lines: string[] = sanitizeTemplateLines(Array.isArray(it.lines) ? it.lines.join('\n') : '');
    if (label.length === 0 || lines.length === 0) {
      continue;
    }
    seen.add(it.id);
    const t: JournalTemplate = { id: it.id, label: label, lines: lines, builtin: false };
    out.push(t);
  }
  return out;
}

/** 内置模板的 id 集合 */
function builtinIds(): Set<string> {
  const s: Set<string> = new Set<string>();
  for (let i: number = 0; i < TEMPLATES.length; i++) {
    s.add(TEMPLATES[i].id);
  }
  return s;
}

/** 是不是内置模板的 id */
export function isBuiltinId(id: string): boolean {
  for (let i: number = 0; i < TEMPLATES.length; i++) {
    if (TEMPLATES[i].id === id) {
      return true;
    }
  }
  return false;
}

/**
 * 界面上要展示的全部模板 = 内置 3 个 + 用户自建
 *
 * ⚠️ 内置排前面：用户最常用的是内置那几个通用款，
 *    自建的是补充，不该把"每日三问"挤到后面去。
 */
export function allTemplates(custom: JournalTemplate[]): JournalTemplate[] {
  const out: JournalTemplate[] = [];
  for (let i: number = 0; i < TEMPLATES.length; i++) {
    out.push(TEMPLATES[i]);
  }
  for (let i: number = 0; i < custom.length; i++) {
    out.push(custom[i]);
  }
  return out;
}

/** 按 id 找模板（内置 + 自建） */
export function templateById(custom: JournalTemplate[], id: string): JournalTemplate | null {
  for (let i: number = 0; i < TEMPLATES.length; i++) {
    if (TEMPLATES[i].id === id) {
      return TEMPLATES[i];
    }
  }
  for (let i: number = 0; i < custom.length; i++) {
    if (custom[i].id === id) {
      return custom[i];
    }
  }
  return null;
}

/** 还能不能再建模板（数量超限要给 UI 明确答复） */
export function canAddTemplate(custom: JournalTemplate[]): boolean {
  return TEMPLATES.length + custom.length < TEMPLATE_MAX;
}

/** 生成一个新模板的 id（与 newNoteId 同套路：base36 时间戳 + 随机） */
export function newTemplateId(existing: Set<string>): string {
  let id: string = '';
  let attempt: number = 0;
  do {
    const salt: number = Math.floor(Math.random() * 1000000000);
    id = 't' + Date.now().toString(36) + salt.toString(36);
    attempt++;
  } while (existing.has(id) && attempt < 100);
  return id;
}

/** 新建/保存的结果（返回新列表，交给调用方赋值 —— 就地改数组不触发 ArkUI 刷新） */
export interface AddTemplateResult {
  list: JournalTemplate[];
  created: JournalTemplate;
}

/**
 * 新建一个自定义模板
 *
 * @returns null = 名字空 / 一行都没有 / 数量已满（UI 据此提示，不静默失败）
 */
export function addTemplate(custom: JournalTemplate[], label: string, linesText: string): AddTemplateResult | null {
  if (!canAddTemplate(custom)) {
    return null;
  }
  const cleanLabel: string = sanitizeTemplateLabel(label);
  const lines: string[] = sanitizeTemplateLines(linesText);
  if (cleanLabel.length === 0 || lines.length === 0) {
    return null;
  }
  const taken: Set<string> = new Set<string>(builtinIds());
  for (let i: number = 0; i < custom.length; i++) {
    taken.add(custom[i].id);
  }
  const created: JournalTemplate = {
    id: newTemplateId(taken),
    label: cleanLabel,
    lines: lines,
    builtin: false
  };
  const list: JournalTemplate[] = custom.slice();
  list.push(created);
  return { list: list, created: created };
}

/** 改一个自定义模板（内置不可改 —— 直接忽略） */
export function updateTemplate(custom: JournalTemplate[], id: string, label: string, linesText: string): JournalTemplate[] {
  if (isBuiltinId(id)) {
    return custom;
  }
  const cleanLabel: string = sanitizeTemplateLabel(label);
  const lines: string[] = sanitizeTemplateLines(linesText);
  if (cleanLabel.length === 0 || lines.length === 0) {
    return custom;
  }
  const out: JournalTemplate[] = [];
  for (let i: number = 0; i < custom.length; i++) {
    if (custom[i].id === id) {
      const next: JournalTemplate = { id: id, label: cleanLabel, lines: lines, builtin: false };
      out.push(next);
    } else {
      out.push(custom[i]);
    }
  }
  return out;
}

/** 删一个自定义模板（内置不可删） */
export function removeTemplate(custom: JournalTemplate[], id: string): JournalTemplate[] {
  if (isBuiltinId(id)) {
    return custom;
  }
  const out: JournalTemplate[] = [];
  for (let i: number = 0; i < custom.length; i++) {
    if (custom[i].id !== id) {
      out.push(custom[i]);
    }
  }
  return out;
}

/**
 * 模板内容的**一行预览**（列表/模板页里显示用，纯逻辑可单测）
 *
 * ⚠️ 为什么不直接把全部行拼起来显示：内置模板有三行，
 *    "今天发生了什么： / 感谢什么： / 明天的重点：" 在列表右侧会顶到边被截断 ——
 *    用户看到的是半句话，反而不知道这个模板问什么。
 *    只取前两行 + 省略号，短到一眼能读完，又保留了"它问的是这种问题"的信息。
 */
export function templateSummary(t: JournalTemplate, maxLines: number): string {
  const parts: string[] = [];
  for (let i: number = 0; i < t.lines.length && i < maxLines; i++) {
    parts.push(t.lines[i]);
  }
  let s: string = parts.join(' / ');
  if (t.lines.length > maxLines) {
    s = s + ' …';
  }
  return s;
}

/**
 * 模板预览文本（编辑器里"插入这个模板"时实际写入的内容）
 *
 * 直接用 lines.join('\n')：编辑器本来就是按行存的（NoteBlocks 的 p 块），
 * 模板灌进去就是几个 p 块，与手写完全同路 ⇒ 字数/搜索/撤销自动生效。
 */
export function templateTextOf(t: JournalTemplate): string {
  return t.lines.join('\n');
}
