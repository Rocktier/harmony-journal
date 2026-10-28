import { test } from 'node:test';
import assert from 'node:assert/strict';

import { NoteMeta } from '../entry/src/main/ets/data/NoteMeta';
import { encodeIndexBundle, parseIndexBundle } from '../entry/src/main/ets/data/IndexCodec';
import {
  JOURNAL_EMOJIS, JOURNAL_MAIN_ID, JOURNAL_MAX, JournalInfo, addJournal, canAddJournal, canRemoveJournal,
  copyWithJournal, defaultJournals, journalById, journalCounts, journalEmojiOf, journalNameOf, journalOf,
  moveEntries, normalizeJournalRef, normalizeJournals, removeJournal, renameJournal, sanitizeJournalName
} from '../entry/src/main/ets/data/Journals';

/** 造一条最简日记（只带本功能关心的字段，其余给安全默认值） */
function meta(id: string, date: string, journal: string): NoteMeta {
  return {
    id: id, date: date, createdAt: 2, mood: '', moodText: '', preview: 'p',
    updatedAt: 2, words: 10, hasImage: false, favorite: false, tags: [],
    imgRef: '', unlockAt: 0, journal: journal
  };
}

// ── 迁移：老索引没有 journals 字段 ⇒ 必须得到「只有默认本」 ──────────────

test('normalizeJournals: 老索引（undefined）得到只有默认本', () => {
  const list: JournalInfo[] = normalizeJournals(undefined);
  assert.equal(list.length, 1);
  assert.equal(list[0].id, JOURNAL_MAIN_ID);
  assert.equal(list[0].name, '生活');
  assert.equal(list[0].createdAt, 0);
});

test('normalizeJournals: 传空数组也补出默认本（本列表不能是空的）', () => {
  const list: JournalInfo[] = normalizeJournals([]);
  assert.equal(list.length, 1);
  assert.equal(list[0].id, JOURNAL_MAIN_ID);
});

test('normalizeJournals: 默认本永远排第一（即使传入的列表里没有它）', () => {
  const other: JournalInfo = { id: 'j1', name: '工作', emoji: '📘', createdAt: 100 };
  const list: JournalInfo[] = normalizeJournals([other]);
  assert.equal(list.length, 2);
  assert.equal(list[0].id, JOURNAL_MAIN_ID);
  assert.equal(list[1].id, 'j1');
});

test('normalizeJournals: 默认本被改过名要保留用户的名字（但仍在第一位）', () => {
  const raw: JournalInfo[] = [
    { id: 'j1', name: '工作', emoji: '📘', createdAt: 100 },
    { id: JOURNAL_MAIN_ID, name: '我的日记', emoji: '📕', createdAt: 0 }
  ];
  const list: JournalInfo[] = normalizeJournals(raw);
  assert.equal(list[0].id, JOURNAL_MAIN_ID);
  assert.equal(list[0].name, '我的日记');
  assert.equal(list[0].emoji, '📕');
  assert.equal(list[1].id, 'j1');
});

test('normalizeJournals: 幂等（迁移可能被跑多次，结果必须一致）', () => {
  const raw: JournalInfo[] = [
    { id: 'j1', name: '工作', emoji: '📘', createdAt: 100 },
    { id: JOURNAL_MAIN_ID, name: '我的日记', emoji: '📕', createdAt: 0 }
  ];
  const once: JournalInfo[] = normalizeJournals(raw);
  const twice: JournalInfo[] = normalizeJournals(once);
  assert.deepEqual(twice, once);
});

test('normalizeJournals: 脏数据被清洗而不是被丢掉本（空名 → 未命名）', () => {
  const raw = [
    { id: 'ok', name: '  ', emoji: '', createdAt: 5 },
    { id: 'BAD ID!', name: '非法 id', emoji: '', createdAt: 6 }
  ] as JournalInfo[];
  const list: JournalInfo[] = normalizeJournals(raw);
  assert.equal(list.length, 2); // 默认本 + 那条合法的
  assert.equal(list[1].id, 'ok');
  assert.equal(list[1].name, '未命名');
  assert.equal(journalEmojiOf(list[1]), JOURNAL_EMOJIS[0]); // 空 emoji 有兜底
});

test('normalizeJournals: 数量超上限要截断（太多本就失去切分意义）', () => {
  const raw: JournalInfo[] = [];
  for (let i: number = 0; i < JOURNAL_MAX + 5; i++) {
    raw.push({ id: 'j' + i, name: '本' + i, emoji: '', createdAt: i + 1 });
  }
  const list: JournalInfo[] = normalizeJournals(raw);
  assert.equal(list.length, JOURNAL_MAX);
  assert.equal(list[0].id, JOURNAL_MAIN_ID);
});

test('normalizeJournals: 重名 id 只留一个（切换本失效的元凶）', () => {
  const raw: JournalInfo[] = [
    { id: 'dup', name: '甲', emoji: '', createdAt: 1 },
    { id: 'dup', name: '乙', emoji: '', createdAt: 2 }
  ];
  const list: JournalInfo[] = normalizeJournals(raw);
  const ids: string[] = list.map((j: JournalInfo) => j.id);
  assert.equal(ids.filter((x: string) => x === 'dup').length, 1);
});

// ── 归属读取：缺字段一律兜到默认本（日记绝不能因为升级而消失） ──────────

test('normalizeJournalRef: 缺字段/空串 = 默认本', () => {
  assert.equal(normalizeJournalRef(undefined), JOURNAL_MAIN_ID);
  assert.equal(normalizeJournalRef(''), JOURNAL_MAIN_ID);
  assert.equal(normalizeJournalRef('j1'), 'j1');
});

test('journalOf: 空 id 表示全部（与"不筛选"同义）', () => {
  const ms: NoteMeta[] = [meta('a', '2026-10-01', 'j1'), meta('b', '2026-10-02', '')];
  assert.equal(journalOf(ms, '').length, 2);
  assert.equal(journalOf(ms, 'j1').length, 1);
  assert.equal(journalOf(ms, 'j1')[0].id, 'a');
});

test('journalOf: 老条目没有 journal 字段 ⇒ 归默认本而不是消失', () => {
  const legacy = { id: 'x', date: '2026-10-01' } as NoteMeta;
  const ms: NoteMeta[] = [legacy];
  assert.equal(journalOf(ms, JOURNAL_MAIN_ID).length, 1);
  assert.equal(journalOf(ms, 'j1').length, 0);
});

test('journalCounts: 各本篇数正确，无归属的算进默认本', () => {
  const js: JournalInfo[] = normalizeJournals([{ id: 'j1', name: '工作', emoji: '', createdAt: 1 }]);
  const ms: NoteMeta[] = [
    meta('a', '2026-10-01', 'j1'),
    meta('b', '2026-10-02', 'j1'),
    meta('c', '2026-10-03', ''),
    { id: 'd', date: '2026-10-04' } as NoteMeta
  ];
  const counts: Record<string, number> = journalCounts(js, ms);
  assert.equal(counts['j1'], 2);
  assert.equal(counts[JOURNAL_MAIN_ID], 2);
});

// ── 增删改：删本绝不能删日记 ───────────────────────────────────────────

test('addJournal: 新建成功且默认本仍在首位', () => {
  const base: JournalInfo[] = defaultJournals();
  const r = addJournal(base, '工作', '📘', 1000);
  assert.notEqual(r, null);
  assert.equal(r!.list.length, 2);
  assert.equal(r!.list[0].id, JOURNAL_MAIN_ID);
  assert.equal(r!.created.name, '工作');
  assert.equal(r!.created.emoji, '📘');
});

test('addJournal: 名字被 trim/限长，纯空白名直接拒绝（不建无名本）', () => {
  const base: JournalInfo[] = defaultJournals();
  assert.equal(addJournal(base, '   ', '', 1), null);
  assert.equal(addJournal(base, '', '', 1), null);
  const r = addJournal(base, '  读书笔记  ', '', 1);
  assert.equal(r!.created.name, '读书笔记');
});

test('addJournal: 满了返回 null（UI 据此提示，不静默失败）', () => {
  let list: JournalInfo[] = defaultJournals();
  while (canAddJournal(list)) {
    const r = addJournal(list, '本' + list.length, '', list.length + 1);
    assert.notEqual(r, null);
    list = r!.list;
  }
  assert.equal(list.length, JOURNAL_MAX);
  assert.equal(addJournal(list, '再来一个', '', 999), null);
});

test('canRemoveJournal: 默认本删不掉（回收港必须常在）', () => {
  const list: JournalInfo[] = defaultJournals();
  assert.equal(canRemoveJournal(list[0]), false);
  const r = addJournal(list, '工作', '', 1);
  assert.equal(canRemoveJournal(r!.list[1]), true);
});

test('removeJournal: 删本返回要搬走的篇目 id，且不删日记本身', () => {
  const r0 = addJournal(defaultJournals(), '工作', '', 1);
  const targetId: string = r0!.created.id;
  const ms2: NoteMeta[] = [meta('a', '2026-10-01', targetId), meta('b', '2026-10-02', '')];
  const r = removeJournal(r0!.list, targetId, ms2);
  assert.notEqual(r, null);
  assert.equal(r!.list.length, 1);
  assert.equal(r!.list[0].id, JOURNAL_MAIN_ID);
  assert.deepEqual(r!.movedIds, ['a']);
  // 日记一条都没少
  const moved: NoteMeta[] = moveEntries(ms2, r!.movedIds, JOURNAL_MAIN_ID);
  assert.equal(moved.length, 2);
  assert.equal(journalOf(moved, JOURNAL_MAIN_ID).length, 2);
  assert.equal(journalOf(moved, targetId).length, 0);
});

test('removeJournal: 默认本拒绝删除（返回 null，日记不受影响）', () => {
  const ms: NoteMeta[] = [meta('a', '2026-10-01', '')];
  assert.equal(removeJournal(defaultJournals(), JOURNAL_MAIN_ID, ms), null);
  assert.equal(ms.length, 1);
});

test('removeJournal: 删一个不存在的本返回 null（防御手滑的二次调用）', () => {
  const ms: NoteMeta[] = [meta('a', '2026-10-01', '')];
  assert.equal(removeJournal(defaultJournals(), 'nope', ms), null);
});

test('moveEntries: 只改命中的那几篇，其余原样返回', () => {
  const ms: NoteMeta[] = [meta('a', '2026-10-01', 'j1'), meta('b', '2026-10-02', 'j2')];
  const out: NoteMeta[] = moveEntries(ms, ['a'], 'j3');
  assert.equal(out[0].journal, 'j3');
  assert.equal(out[1].journal, 'j2');
});

test('copyWithJournal: 改归属但不动其他字段（字数/胶囊/图片都要保住）', () => {
  const m: NoteMeta = {
    ...meta('a', '2026-10-01', 'j1'), words: 88, favorite: true, unlockAt: 12345, imgRef: 'img/a.enc'
  };
  const out: NoteMeta = copyWithJournal(m, 'j2');
  assert.equal(out.journal, 'j2');
  assert.equal(out.words, 88);
  assert.equal(out.favorite, true);
  assert.equal(out.unlockAt, 12345);
  assert.equal(out.imgRef, 'img/a.enc');
});

test('renameJournal: 默认本也可以改名（用户有权叫它「我的日记」）', () => {
  const out: JournalInfo[] = renameJournal(defaultJournals(), JOURNAL_MAIN_ID, '我的日记', '📕');
  assert.equal(out[0].name, '我的日记');
  assert.equal(out[0].emoji, '📕');
});

test('renameJournal: 空名字不改（宁可保留旧名也不留空 chip）', () => {
  const base: JournalInfo[] = defaultJournals();
  const out: JournalInfo[] = renameJournal(base, JOURNAL_MAIN_ID, '  ', '');
  assert.equal(out[0].name, '生活');
});

// ── 展示层兜底 ──────────────────────────────────────────────────────

test('journalEmojiOf/journalNameOf: 拿不到本时也有可读兜底', () => {
  assert.equal(journalEmojiOf(null), JOURNAL_EMOJIS[0]);
  assert.equal(journalEmojiOf({ id: 'x', name: 'x', emoji: '', createdAt: 1 }), JOURNAL_EMOJIS[0]);
  assert.equal(journalNameOf(null), '生活');
  assert.equal(journalNameOf({ id: 'x', name: '', emoji: '', createdAt: 1 }), '未命名');
});

test('journalById: 有就返回、没有返回 null（UI 据此降级而不是崩）', () => {
  const list: JournalInfo[] = defaultJournals();
  assert.notEqual(journalById(list, JOURNAL_MAIN_ID), null);
  assert.equal(journalById(list, 'nope'), null);
});

test('sanitizeJournalName: 按字符截断（emoji 不会被切成半）', () => {
  assert.equal(sanitizeJournalName('  工作  '), '工作');
  assert.equal(sanitizeJournalName('一二三四五六七八九十十一十二十三'), '一二三四五六七八九十十一');
  assert.equal(sanitizeJournalName(''), '');
});

// ── 索引往返：本与模板跟着索引一起存、一起读 ──────────────────────────

test('索引往返：v3 容器带得走本列表，条目一条不少', () => {
  const r0 = addJournal(defaultJournals(), '工作', '📘', 1);
  const ms: NoteMeta[] = [meta('a', '2026-10-02', r0!.created.id), meta('b', '2026-10-01', '')];
  const json: string = encodeIndexBundle({ items: ms, journals: r0!.list, templates: [] });
  const back = parseIndexBundle(json);
  assert.equal(back.items.length, 2);
  assert.equal(back.journals.length, 2);
  assert.equal(back.journals[0].id, JOURNAL_MAIN_ID);
  assert.equal(back.journals[1].name, '工作');
  // 排序：日期倒序
  assert.equal(back.items[0].id, 'a');
});

test('迁移：老索引（v2，无 journals 字段）读进来条目不变、本自动补默认本', () => {
  const legacy = { app: 'rockjournal', v: 2, items: [{ date: '2026-10-01', id: '2026-10-01', words: 5 }] };
  const back = parseIndexBundle(JSON.stringify(legacy));
  assert.equal(back.items.length, 1);
  assert.equal(back.items[0].id, '2026-10-01');
  assert.equal(back.items[0].words, 5);
  assert.equal(back.journals.length, 1);
  assert.equal(back.journals[0].id, JOURNAL_MAIN_ID);
  assert.equal(back.templates.length, 0);
  // ★ 老条目没有 journal 字段 ⇒ 归默认本，绝不会消失
  assert.equal(journalOf(back.items, JOURNAL_MAIN_ID).length, 1);
});
