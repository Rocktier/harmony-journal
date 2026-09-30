import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Block, Span } from '../entry/src/main/ets/data/NoteBlocks';
import { NoteMeta } from '../entry/src/main/ets/data/NoteMeta';
import {
  BACKUP_VERSION, BackupItem, backupFileName, buildBackup, parseBackup, utf8Decode, utf8Encode
} from '../entry/src/main/ets/data/BackupService';

function span(text: string, bold: boolean = false, italic: boolean = false): Span {
  return { text: text, bold: bold, italic: italic };
}

function metaOf(date: string, id: string, updatedAt: number, words: number): NoteMeta {
  return {
    id: id, date: date, createdAt: updatedAt, mood: 'happy', moodText: '',
    updatedAt: updatedAt, words: words, hasImage: false
  };
}

function item(date: string, text: string, id: string = ''): BackupItem {
  const blocks: Block[] = [{ type: 'p', spans: [span(text)], ref: '' }];
  return { date: date, blocks: blocks, meta: metaOf(date, id === '' ? date : id, 1, text.length) };
}

test('备份文件名带日期，用户一眼认得出', () => {
  assert.equal(backupFileName('2026-09-28'), 'Rock私记-备份-2026-09-28.rkdbak');
});

test('往返：多条目、样式、心情全部保真', () => {
  const items: BackupItem[] = [item('2026-09-28', '今天'), item('2026-09-27', '昨天')];
  const back: BackupItem[] = parseBackup(buildBackup(items));
  assert.equal(back.length, 2);
  assert.equal(back[0].date, '2026-09-28');
  assert.equal(back[0].blocks[0].spans[0].text, '今天');
  assert.equal(back[1].meta.mood, 'happy');
});

test('中文与 emoji 编解码往返（UTF-8 手写实现不能出错）', () => {
  const s: string = '今天 😄 写日记 — 中文测试';
  assert.equal(utf8Decode(utf8Encode(s)), s);
});

test('坏数据容错：不是我们的备份 / 版本过高 / 日期非法 → 空或跳过', () => {
  assert.deepEqual(parseBackup(utf8Encode('{坏 json')), []);
  assert.deepEqual(parseBackup(utf8Encode('{"app":"别的","v":2,"items":[]}')), []);
  assert.deepEqual(parseBackup(utf8Encode('{"app":"rockjournal","v":99,"items":[]}')), []);
  // 单篇日期非法 → 跳过，不影响其余
  const mixed: Uint8Array = utf8Encode(JSON.stringify({
    app: 'rockjournal', v: BACKUP_VERSION,
    items: [{ date: '不是日期', blocks: [], meta: {} }, item('2026-09-28', '正常')]
  }));
  const back: BackupItem[] = parseBackup(mixed);
  assert.equal(back.length, 1);
  assert.equal(back[0].blocks[0].spans[0].text, '正常');
});

test('★ v1 老备份必须还能读：meta 里没有 id ⇒ 用 date 兜底', () => {
  const v1: Uint8Array = utf8Encode(JSON.stringify({
    app: 'rockjournal', v: 1,
    items: [{ date: '2026-09-28', blocks: [], meta: { date: '2026-09-28', mood: 'calm', updatedAt: 5, words: 2 } }]
  }));
  const back: BackupItem[] = parseBackup(v1);
  assert.equal(back.length, 1);
  assert.equal(back[0].meta.id, '2026-09-28');   // 老备份没有 id，必须补出来
  assert.equal(back[0].meta.createdAt, 5);       // createdAt 用 updatedAt 兜底
});

test('★ 同一天多篇：v2 往返后两篇都在，且各自的 id 保真', () => {
  const items: BackupItem[] = [
    item('2026-09-30', '上午', 'aaa111'),
    item('2026-09-30', '下午', 'bbb222')
  ];
  const back: BackupItem[] = parseBackup(buildBackup(items));
  assert.equal(back.length, 2);
  const ids: string[] = back.map((b: BackupItem) => b.meta.id).sort();
  assert.deepEqual(ids, ['aaa111', 'bbb222']);
  assert.equal(back[0].date, back[1].date);
});

test('导出的备份带 id（导入侧才能精确还原每一篇）', () => {
  const back: BackupItem[] = parseBackup(buildBackup([item('2026-09-30', '内容', 'xyz789')]));
  assert.equal(back[0].meta.id, 'xyz789');
  assert.equal(back[0].meta.words, '内容'.length);
});

test('meta 缺失/残缺时不炸：字段走默认值', () => {
  const weird: Uint8Array = utf8Encode(JSON.stringify({
    app: 'rockjournal', v: BACKUP_VERSION,
    items: [{ date: '2026-09-30', blocks: [] }]
  }));
  const back: BackupItem[] = parseBackup(weird);
  assert.equal(back.length, 1);
  assert.equal(back[0].meta.id, '2026-09-30');
  assert.equal(back[0].meta.mood, '');
});
