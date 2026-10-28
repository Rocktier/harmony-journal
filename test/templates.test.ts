import { test } from 'node:test';
import assert from 'node:assert/strict';

import { NoteMeta } from '../entry/src/main/ets/data/NoteMeta';
import { encodeIndexBundle, parseIndexBundle } from '../entry/src/main/ets/data/IndexCodec';
import {
  JournalTemplate, TEMPLATE_LABEL_MAX, TEMPLATE_LINES_MAX, TEMPLATE_MAX, TEMPLATES, addTemplate, allTemplates,
  canAddTemplate, isBuiltinId, normalizeTemplates, removeTemplate, sanitizeTemplateLabel, sanitizeTemplateLines,
  templateById, templateSummary, templateTextOf, updateTemplate
} from '../entry/src/main/ets/data/JournalTemplates';

function meta(id: string, date: string): NoteMeta {
  return {
    id: id, date: date, createdAt: 2, mood: '', moodText: '', preview: 'p',
    updatedAt: 2, words: 10, hasImage: false, favorite: false, tags: [],
    imgRef: '', unlockAt: 0, journal: ''
  };
}

// ── 清洗：用户输入的脏数据不能进索引 ──────────────────────────────────

test('sanitizeTemplateLabel: trim + 限长（超长会撑破按钮）', () => {
  assert.equal(sanitizeTemplateLabel('  晨间  '), '晨间');
  assert.equal(sanitizeTemplateLabel('一二三四五六七八九十'), '一二三四五六七八');
  assert.equal(sanitizeTemplateLabel('   '), '');
});

test('sanitizeTemplateLines: 去首尾空行，但**保留中间空行**（那是留给用户填空的位置）', () => {
  const out: string[] = sanitizeTemplateLines('\n\n今天发生了什么：\n\n感谢什么：\n\n');
  assert.deepEqual(out, ['今天发生了什么：', '', '感谢什么：']);
});

test('sanitizeTemplateLines: 空输入得到空数组（不是含一个空串的数组）', () => {
  assert.deepEqual(sanitizeTemplateLines(''), []);
  assert.deepEqual(sanitizeTemplateLines('   \n  \n '), []);
});

test('sanitizeTemplateLines: 行数超限要截断（几十行的模板灌进去就成了范文）', () => {
  let text: string = '';
  for (let i: number = 0; i < TEMPLATE_LINES_MAX + 10; i++) {
    text += 'line-' + i + '\n';
  }
  assert.equal(sanitizeTemplateLines(text).length, TEMPLATE_LINES_MAX);
});

// ── 从索引里读：脏数据整条丢弃，内置模板不落盘 ────────────────────────

test('normalizeTemplates: 老索引没有 templates 字段 ⇒ 空表（内置模板来自常量表）', () => {
  assert.deepEqual(normalizeTemplates(undefined), []);
  assert.deepEqual(normalizeTemplates([]), []);
});

test('normalizeTemplates: 内置 id 的条目被剔除（不存副本，免得两边不一致）', () => {
  const raw: JournalTemplate[] = [
    { id: 'three-questions', label: '每日三问', lines: ['a'], builtin: true },
    { id: 't1', label: '我的复盘', lines: ['b'], builtin: false }
  ];
  const out: JournalTemplate[] = normalizeTemplates(raw);
  assert.equal(out.length, 1);
  assert.equal(out[0].id, 't1');
});

test('normalizeTemplates: 没名字或没内容行的模板整条丢弃（骨架坏了不如没有）', () => {
  const raw = [
    { id: 'a', label: '', lines: ['x'] },
    { id: 'b', label: '有名字', lines: [] },
    { id: 'c', label: '两条都有', lines: ['y'] }
  ] as JournalTemplate[];
  const out: JournalTemplate[] = normalizeTemplates(raw);
  assert.equal(out.length, 1);
  assert.equal(out[0].id, 'c');
});

test('normalizeTemplates: 重名 id 只留一个', () => {
  const raw: JournalTemplate[] = [
    { id: 'dup', label: '甲', lines: ['a'], builtin: false },
    { id: 'dup', label: '乙', lines: ['b'], builtin: false }
  ];
  assert.equal(normalizeTemplates(raw).length, 1);
});

// ── 展示：内置排前面（用户最常用的是通用款） ─────────────────────────

test('allTemplates: 内置 3 个在前，自建在后', () => {
  const custom: JournalTemplate[] = [{ id: 't1', label: '我的', lines: ['a'], builtin: false }];
  const all: JournalTemplate[] = allTemplates(custom);
  assert.equal(all.length, TEMPLATES.length + 1);
  assert.equal(all[0].id, TEMPLATES[0].id);
  assert.equal(all[all.length - 1].id, 't1');
});

test('templateById: 内置与自建都找得到，找不到返回 null', () => {
  const custom: JournalTemplate[] = [{ id: 't1', label: '我的', lines: ['a'], builtin: false }];
  assert.notEqual(templateById(custom, 'three-questions'), null);
  assert.notEqual(templateById(custom, 't1'), null);
  assert.equal(templateById(custom, 'nope'), null);
});

test('isBuiltinId: 内置 id 判定准确（它决定能不能删改）', () => {
  assert.equal(isBuiltinId('three-questions'), true);
  assert.equal(isBuiltinId('t1'), false);
});

// ── 增删改：内置不可动，超限要明确拒绝 ───────────────────────────────

test('addTemplate: 新建成功', () => {
  const r = addTemplate([], '复盘', '今天做对了：\n\n今天可以更好：');
  assert.notEqual(r, null);
  assert.equal(r!.created.label, '复盘');
  assert.deepEqual(r!.created.lines, ['今天做对了：', '', '今天可以更好：']);
  assert.equal(r!.created.builtin, false);
});

test('addTemplate: 名字空 / 没内容行 / 满了 → null（UI 据此提示，不静默失败）', () => {
  assert.equal(addTemplate([], '  ', '有内容'), null);
  assert.equal(addTemplate([], '有名字', '   '), null);
  let list: JournalTemplate[] = [];
  while (canAddTemplate(list)) {
    const r = addTemplate(list, '模' + list.length, '行-' + list.length);
    assert.notEqual(r, null);
    list = r!.list;
  }
  assert.equal(list.length + TEMPLATES.length, TEMPLATE_MAX);
  assert.equal(addTemplate(list, '再来', '内容'), null);
});

test('updateTemplate: 内置模板改不动（改坏了没法恢复，就干脆不让改）', () => {
  const before: JournalTemplate[] = [{ id: 't1', label: '旧名', lines: ['旧'], builtin: false }];
  const out: JournalTemplate[] = updateTemplate(before, 'three-questions', '被改了', '内容');
  assert.deepEqual(out, before);
});

test('updateTemplate: 自建模板可以改，id 保持不变', () => {
  const before: JournalTemplate[] = [{ id: 't1', label: '旧名', lines: ['旧'], builtin: false }];
  const out: JournalTemplate[] = updateTemplate(before, 't1', '新名', '新行一\n新行二');
  assert.equal(out.length, 1);
  assert.equal(out[0].id, 't1');
  assert.equal(out[0].label, '新名');
  assert.deepEqual(out[0].lines, ['新行一', '新行二']);
});

test('removeTemplate: 内置删不掉', () => {
  const before: JournalTemplate[] = [{ id: 't1', label: '甲', lines: ['a'], builtin: false }];
  assert.deepEqual(removeTemplate(before, 'three-questions'), before);
});

test('removeTemplate: 自建能删，且只删那一条', () => {
  const before: JournalTemplate[] = [
    { id: 't1', label: '甲', lines: ['a'], builtin: false },
    { id: 't2', label: '乙', lines: ['b'], builtin: false }
  ];
  const out: JournalTemplate[] = removeTemplate(before, 't1');
  assert.equal(out.length, 1);
  assert.equal(out[0].id, 't2');
});

// ── 列表预览：短到一眼读完，长了的用省略号 ─────────────────────────────

test('templateSummary: 只取前两行，超出的用省略号表示', () => {
  const t: JournalTemplate = { id: 'x', label: 'x', lines: ['第一行', '第二行', '第三行'], builtin: false };
  assert.equal(templateSummary(t, 2), '第一行 / 第二行 …');
});

test('templateSummary: 行数没超就不加省略号（宁可短，也不画蛇添足）', () => {
  const t: JournalTemplate = { id: 'x', label: 'x', lines: ['只有一行'], builtin: false };
  assert.equal(templateSummary(t, 2), '只有一行');
  const two: JournalTemplate = { id: 'y', label: 'y', lines: ['甲', '乙'], builtin: false };
  assert.equal(templateSummary(two, 2), '甲 / 乙');
});

test('templateSummary: 空行也要占位（那是留给用户的填空位置）', () => {
  const t: JournalTemplate = { id: 'x', label: 'x', lines: ['问：', ''], builtin: false };
  assert.equal(templateSummary(t, 2), '问： / ');
});

test('templateTextOf: 灌进编辑器的正文按原样拼行（空行保留）', () => {
  const t: JournalTemplate = { id: 'x', label: 'x', lines: ['第一行', '', '第二行'], builtin: false };
  assert.equal(templateTextOf(t), '第一行\n\n第二行');
});

// ── 索引往返：自定义模板跟着索引存，模板名称上限内不失真 ─────────────

test('索引往返：自定义模板跟索引一起存取，条目一篇不少', () => {
  const r = addTemplate([], '复盘', '今天做对了：\n今天可以更好：');
  const ms: NoteMeta[] = [meta('a', '2026-10-02'), meta('b', '2026-10-01')];
  const json: string = encodeIndexBundle({ items: ms, journals: [], templates: r!.list });
  const back = parseIndexBundle(json);
  assert.equal(back.items.length, 2);
  assert.equal(back.templates.length, 1);
  assert.equal(back.templates[0].label, '复盘');
  assert.deepEqual(back.templates[0].lines, ['今天做对了：', '今天可以更好：']);
});

test('模板名长度受上限保护（存进去再读出来不会超长）', () => {
  const longName: string = '一二三四五六七八九十';
  const r = addTemplate([], longName, '内容');
  assert.equal(r!.created.label.length, TEMPLATE_LABEL_MAX);
});
