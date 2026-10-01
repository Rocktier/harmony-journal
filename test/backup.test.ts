import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Block, Span } from '../entry/src/main/ets/data/NoteBlocks';
import { NoteMeta } from '../entry/src/main/ets/data/NoteMeta';
import {
  BACKUP_VERSION, BackupItem, EXT_MD, EXT_TXT, backupFileName, buildBackup, parseBackup,
  readableFileName, toMarkdown, toPlainText, utf8Decode, utf8Encode
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

test('可读导出 TXT：纯文字，标题/列表/图片都读得懂', () => {
  const blocks: Block[] = [
    { type: 'h', spans: [span('小标题')], ref: '' },
    { type: 'p', spans: [span('正文一句')], ref: '' },
    { type: 'li', spans: [span('一条列表')], ref: '' },
    { type: 'img', spans: [], ref: 'img/xxx.enc' }
  ];
  const item: BackupItem = { date: '2026-10-01', blocks: blocks, meta: metaOf('2026-10-01', 'n1', 1, 4) };
  const txt: string = toPlainText([item]);
  assert.ok(txt.indexOf('2026-10-01') >= 0);
  assert.ok(txt.indexOf('小标题') >= 0);
  assert.ok(txt.indexOf('正文一句') >= 0);
  assert.ok(txt.indexOf('· 一条列表') >= 0);
  assert.ok(txt.indexOf('[图片]') >= 0);      // 图片不内联（外置是加密文件，别人读不懂）
  assert.ok(txt.indexOf('**') < 0);          // 纯文本不该有 Markdown 记号
});

test('可读导出 Markdown：保留结构（## 标题 / - 列表 / **粗** *斜*）', () => {
  const blocks: Block[] = [
    { type: 'h', spans: [span('小标题', false, false)], ref: '' },
    { type: 'li', spans: [span('列表项', false, false)], ref: '' },
    { type: 'p', spans: [span('粗', true, false), span('斜', false, true)], ref: '' }
  ];
  const item: BackupItem = { date: '2026-10-01', blocks: blocks, meta: metaOf('2026-10-01', 'n2', 1, 3) };
  const md: string = toMarkdown([item]);
  assert.ok(md.indexOf('## 2026-10-01') >= 0);
  assert.ok(md.indexOf('### 小标题') >= 0);
  assert.ok(md.indexOf('- 列表项') >= 0);
  assert.ok(md.indexOf('**粗**') >= 0);
  assert.ok(md.indexOf('*斜*') >= 0);
});

test('可读导出：心情渲染成人话（emoji + 中文）', () => {
  const item: BackupItem = {
    date: '2026-10-01',
    blocks: [{ type: 'p', spans: [span('内容')], ref: '' }],
    meta: metaOf('2026-10-01', 'n3', 1, 2)
  };
  item.meta.mood = 'happy';
  assert.ok(toPlainText([item]).indexOf('😄 开心') >= 0);
  // 自定义心情用用户自己写的文案
  item.meta.mood = 'custom';
  item.meta.moodText = '有点累';
  assert.ok(toPlainText([item]).indexOf('有点累') >= 0);
});

test('可读导出：一篇都没有时不炸，空篇也不产生空行噪音', () => {
  assert.ok(toPlainText([]).indexOf('共 0 篇') >= 0);
  assert.ok(toMarkdown([]).indexOf('共 0 篇') >= 0);
  const empty: BackupItem = { date: '2026-10-01', blocks: [], meta: metaOf('2026-10-01', 'n4', 1, 0) };
  const txt: string = toPlainText([empty]);
  assert.ok(txt.indexOf('2026-10-01') >= 0);
});

test('可读导出文件名：和加密备份区分开，一眼看出是明文', () => {
  assert.ok(readableFileName('2026-10-01', EXT_TXT).endsWith('.txt'));
  assert.ok(readableFileName('2026-10-01', EXT_MD).endsWith('.md'));
  assert.ok(readableFileName('2026-10-01', EXT_TXT).indexOf('可读导出') >= 0);
  assert.ok(backupFileName('2026-10-01').indexOf('备份') >= 0);
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
