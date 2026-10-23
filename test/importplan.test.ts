import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Block, Span, firstImgRef, plainOfBlocks } from '../entry/src/main/ets/data/NoteBlocks';
import { NoteMeta } from '../entry/src/main/ets/data/NoteMeta';
import { BackupItem, PlannedNote, planImport } from '../entry/src/main/ets/data/BackupService';

/**
 * importplan 守卫（2026-10-23 复评新增）
 *
 * 守的是 NoteStore.importAll 的 O(N²) 修复：导入的「决策」（id 分配 /
 * 胶囊封存 / 跳过非法 date）被抽成纯函数 planImport，IO 只留
 * 「逐篇写正文 + 一次 saveIndex」。这里把决策语义全部钉死，
 * 任何人改坏了 planImport，CI 当场红。
 */

const NOW: number = new Date(2026, 9, 23, 12, 0, 0).getTime();
const CAPSULE_AT: number = new Date(2027, 0, 1, 8, 0, 0).getTime();

function span(text: string): Span {
  return { text: text, bold: false, italic: false };
}

function pBlock(text: string): Block {
  return { type: 'p', spans: [span(text)], ref: '' };
}

function metaOf(date: string, id: string): NoteMeta {
  return {
    id: id, date: date, createdAt: 1, mood: 'happy', moodText: '', preview: '',
    updatedAt: 1, words: 3, hasImage: false, imgRef: '', unlockAt: 0,
    favorite: false, tags: []
  };
}

/** 造一条备份条目（老备份形态：id 可能为空、unlockAt 可能为 0） */
function itemOf(date: string, id: string, text: string, unlockAt: number = 0, tags: string[] = []): BackupItem {
  return {
    date: date,
    blocks: [pBlock(text)],
    meta: {
      id: id, date: date, createdAt: 1, mood: 'calm', moodText: '心情', preview: '',
      updatedAt: 1, words: text.length, hasImage: false, imgRef: '', unlockAt: unlockAt,
      favorite: false, tags: tags
    }
  };
}

test('planImport：空库导入逐字保留 id，createdAt/updatedAt 取注入的 now', () => {
  const items: BackupItem[] = [
    itemOf('2026-10-20', 'aaa', '第一天'),
    itemOf('2026-10-22', 'bbb', '第三天'),
    itemOf('2026-10-21', 'ccc', '第二天')
  ];
  const plan: PlannedNote[] = planImport([], items, NOW);
  assert.equal(plan.length, 3);
  // 规划保持备份原顺序（排序是 saveIndex 前 concat+sortEntries 的事，不在这里做）
  assert.equal(plan[0].id, 'aaa');
  assert.equal(plan[1].id, 'bbb');
  assert.equal(plan[2].id, 'ccc');
  assert.equal(plan[0].meta.createdAt, NOW);
  assert.equal(plan[0].meta.updatedAt, NOW);
  assert.ok(plan[0].meta.preview.length > 0);
  assert.equal(plan[0].meta.words, 3);
});

test('planImport：id 撞现有索引 ⇒ 换新号，一篇不丢', () => {
  const existing: NoteMeta[] = [metaOf('2026-10-22', 'aaa')];
  const plan: PlannedNote[] = planImport(existing, [itemOf('2026-10-22', 'aaa', '撞号的另一天')], NOW);
  assert.equal(plan.length, 1);
  assert.notEqual(plan[0].id, 'aaa');
  assert.ok(plan[0].id.length > 0);
  // 备份内部两篇同 id ⇒ 两篇都留住，第二篇再换号（"宁可多一篇也不丢一篇"）
  const dup: PlannedNote[] = planImport([], [itemOf('2026-10-22', 'aaa', '一'), itemOf('2026-10-22', 'aaa', '二')], NOW);
  assert.equal(dup.length, 2);
  assert.notEqual(dup[0].id, dup[1].id);
});

test('planImport：胶囊封存 —— unlockAt>0 的内容字段一律不进索引', () => {
  const plan: PlannedNote[] = planImport([], [itemOf('2026-10-22', 'cap', '锁着的信', CAPSULE_AT, ['secret'])], NOW);
  assert.equal(plan.length, 1);
  const m: NoteMeta = plan[0].meta;
  assert.equal(m.unlockAt, CAPSULE_AT); // 解锁时刻保留（列表要显示倒计时）
  assert.equal(m.mood, '');
  assert.equal(m.moodText, '');
  assert.equal(m.preview, '');
  assert.equal(m.hasImage, false);
  assert.equal(m.imgRef, '');
  assert.equal(m.tags.length, 0);
});

test('planImport：date 非法的条目跳过（不写、不崩）', () => {
  const items: BackupItem[] = [
    itemOf('2026-1-1', 'x', '月份没补零'),
    itemOf('not-a-date', 'y', '根本不是日期'),
    itemOf('', 'z', '空日期'),
    itemOf('2026-10-22', 'ok', '好的')
  ];
  const plan: PlannedNote[] = planImport([], items, NOW);
  assert.equal(plan.length, 1);
  assert.equal(plan[0].id, 'ok');
});

test('planImport：老备份没有 id ⇒ 回退 date 当 id；没有 unlockAt ⇒ 普通日记', () => {
  const legacy: BackupItem = {
    date: '2026-10-01',
    blocks: [pBlock('老备份')],
    meta: {
      id: '', date: '2026-10-01', createdAt: 1, mood: 'happy', moodText: '', preview: '',
      updatedAt: 1, words: 3, hasImage: false, imgRef: '', unlockAt: 0,
      favorite: false, tags: []
    }
  };
  const plan: PlannedNote[] = planImport([], [legacy], NOW);
  assert.equal(plan.length, 1);
  assert.equal(plan[0].id, '2026-10-01');
  assert.ok(plan[0].meta.preview.length > 0);
  assert.equal(plan[0].meta.unlockAt, 0);
});

test('planImport：同一天多篇不互顶（id 不同 ⇒ 各自成篇）', () => {
  const plan: PlannedNote[] = planImport([], [
    itemOf('2026-10-22', 'day-a', '上午写的'),
    itemOf('2026-10-22', 'day-b', '晚上写的')
  ], NOW);
  assert.equal(plan.length, 2);
  assert.equal(plan[0].meta.date, '2026-10-22');
  assert.equal(plan[1].meta.date, '2026-10-22');
  assert.notEqual(plan[0].id, plan[1].id);
});

test('plainOfBlocks/firstImgRef：从 NoteStore 抽出后的公共行为不变', () => {
  assert.equal(plainOfBlocks([pBlock('甲'), pBlock('乙')]), '甲\n乙');
  assert.equal(plainOfBlocks([]), '');
  const withImg: Block[] = [
    { type: 'img', spans: [], ref: 'img/xxx.enc' },
    pBlock('文字')
  ];
  assert.equal(firstImgRef(withImg), 'img/xxx.enc');
  assert.equal(firstImgRef([pBlock('没有图')]), '');
  // 图片块没有文本 ⇒ 贡献一个空行（这是原 NoteStore 私有版的既有行为，
  // 重构不许悄悄改；前导空行由 previewText 的"折叠空白"吃掉，不进摘要）
  assert.equal(plainOfBlocks(withImg), '\n文字');
});
