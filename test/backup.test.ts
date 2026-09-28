import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Block, Span } from '../entry/src/main/ets/data/NoteBlocks';
import {
  BackupItem, backupFileName, buildBackup, parseBackup, utf8Decode, utf8Encode
} from '../entry/src/main/ets/data/BackupService';

function span(text: string, bold: boolean = false, italic: boolean = false): Span {
  return { text: text, bold: bold, italic: italic };
}

function item(date: string, text: string): BackupItem {
  const blocks: Block[] = [{ type: 'p', spans: [span(text)], ref: '' }];
  return { date: date, blocks: blocks, meta: { date: date, mood: 'happy', moodText: '', updatedAt: 1, words: text.length, hasImage: false } };
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

test('坏数据容错：不是我们的备份 / 版本不对 / 日期非法 → 空或跳过', () => {
  assert.deepEqual(parseBackup(utf8Encode('{坏 json')), []);
  assert.deepEqual(parseBackup(utf8Encode('{"app":"别的","v":1,"items":[]}')), []);
  assert.deepEqual(parseBackup(utf8Encode('{"app":"rockjournal","v":99,"items":[]}')), []);
  // 单篇日期非法 → 跳过，不影响其余
  const mixed: Uint8Array = utf8Encode(JSON.stringify({
    app: 'rockjournal', v: 1,
    items: [{ date: '不是日期', blocks: [], meta: {} }, item('2026-09-28', '正常')]
  }));
  const back: BackupItem[] = parseBackup(mixed);
  assert.equal(back.length, 1);
  assert.equal(back[0].blocks[0].spans[0].text, '正常');
});
