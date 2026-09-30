import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  INDEX_APP, INDEX_VERSION, encodeIndex, normalizeEntries, parseIndex, parseIndexStrict, sortEntries
} from '../entry/src/main/ets/data/IndexCodec';
import { NoteMeta } from '../entry/src/main/ets/data/NoteMeta';

/** 造一条完整条目（省略的字段走默认，便于只关心被测的那几个） */
function entry(date: string, id: string, extra: Partial<NoteMeta> = {}): NoteMeta {
  const base: NoteMeta = {
    id: id,
    date: date,
    createdAt: 1,
    mood: '',
    moodText: '',
    updatedAt: 2,
    words: 0,
    hasImage: false
  };
  return { ...base, ...extra };
}

test('★ 迁移：v1 条目没有 id ⇒ 取 date，于是老文件名一个都不用改', () => {
  const v1: string = JSON.stringify({
    v: 1,
    items: [{ date: '2026-09-30', mood: 'happy', moodText: '', updatedAt: 111, words: 5, hasImage: false }]
  });
  const got: NoteMeta[] = parseIndex(v1);
  assert.equal(got.length, 1);
  assert.equal(got[0].id, '2026-09-30');           // ← 就是这一步让零文件移动成立
  assert.equal(got[0].date, '2026-09-30');
  assert.equal(got[0].createdAt, 111);             // 老数据没有 createdAt ⇒ 用 updatedAt 兜底
  assert.equal(got[0].mood, 'happy');
  assert.equal(got[0].words, 5);
});

test('★ 迁移：更老的 v1 连 v 字段都没有，也必须认出来', () => {
  const noVersion: string = JSON.stringify({ items: [{ date: '2026-01-02', updatedAt: 7 }] });
  const got: NoteMeta[] = parseIndex(noVersion);
  assert.equal(got.length, 1);
  assert.equal(got[0].id, '2026-01-02');
  assert.equal(got[0].createdAt, 7);
});

test('★ 迁移必须幂等：同一份老数据解析两次结果完全一致', () => {
  const v1: string = JSON.stringify({
    v: 1,
    items: [
      { date: '2026-09-30', updatedAt: 300 },
      { date: '2026-09-28', updatedAt: 100 },
      { date: '2026-09-29', updatedAt: 200 }
    ]
  });
  assert.deepEqual(parseIndex(v1), parseIndex(v1));
  assert.equal(parseIndex(v1).length, 3);
});

test('v2 往返：id / createdAt / 心情 / 字数全部保真', () => {
  const items: NoteMeta[] = [
    entry('2026-09-30', 'aaa111', { mood: 'calm', words: 9, createdAt: 50, updatedAt: 60 }),
    entry('2026-09-30', 'bbb222', { mood: 'happy', words: 3, createdAt: 10, updatedAt: 20 })
  ];
  const back: NoteMeta[] = parseIndex(encodeIndex(items));
  assert.equal(back.length, 2);
  // 同日倒序：新的在前
  assert.equal(back[0].id, 'aaa111');
  assert.equal(back[0].mood, 'calm');
  assert.equal(back[0].words, 9);
  assert.equal(back[0].createdAt, 50);
  assert.equal(back[1].id, 'bbb222');
});

test('v2 条目缺 id ⇒ 退回 date（宁可变丑也不能丢这一篇）', () => {
  const brokenId: string = JSON.stringify({
    app: INDEX_APP, v: INDEX_VERSION,
    items: [{ id: '', date: '2026-09-30', updatedAt: 1 }]
  });
  const got: NoteMeta[] = parseIndex(brokenId);
  assert.equal(got.length, 1);
  assert.equal(got[0].id, '2026-09-30');
});

test('脏数据：日期非法就跳过，不影响其余条目', () => {
  const mixed: string = JSON.stringify({
    app: INDEX_APP, v: INDEX_VERSION,
    items: [
      { id: 'ok1', date: '不是日期', updatedAt: 1 },
      { id: 'ok2', date: '2026-09-30', updatedAt: 2 }
    ]
  });
  const got: NoteMeta[] = parseIndex(mixed);
  assert.equal(got.length, 1);
  assert.equal(got[0].id, 'ok2');
});

test('id 撞号 ⇒ 重编号而不是互相覆盖（一天多篇后更可能出现）', () => {
  const dup: string = JSON.stringify({
    app: INDEX_APP, v: INDEX_VERSION,
    items: [
      { id: 'same', date: '2026-09-30', updatedAt: 1 },
      { id: 'same', date: '2026-09-30', updatedAt: 2 }
    ]
  });
  const got: NoteMeta[] = parseIndex(dup);
  assert.equal(got.length, 2);                     // 一篇都不能少
  assert.notEqual(got[0].id, got[1].id);
});

test('严格解析：坏 JSON / 别家容器 ⇒ null（上层要报错拦住，不能当空库放行）', () => {
  assert.equal(parseIndexStrict('{坏 json'), null);
  assert.equal(parseIndexStrict(JSON.stringify({ app: '别人', v: 2, items: [] })), null);
  assert.deepEqual(parseIndexStrict(''), []);      // 空串 = 还没写过，是合法的空
  assert.deepEqual(parseIndexStrict(JSON.stringify({ app: INDEX_APP, v: INDEX_VERSION, items: [] })), []);
});

test('宽松解析：坏数据一律降级为空数组，不抛', () => {
  assert.deepEqual(parseIndex('{坏 json'), []);
  assert.deepEqual(parseIndex(JSON.stringify({ app: '别人', v: 2, items: [] })), []);
});

test('排序：跨日按日期倒序；同一天按创建时间倒序', () => {
  const got: NoteMeta[] = sortEntries([
    entry('2026-09-28', 'a', { createdAt: 1 }),
    entry('2026-09-30', 'b', { createdAt: 1 }),
    entry('2026-09-30', 'c', { createdAt: 9 })
  ]);
  assert.deepEqual(got.map((m: NoteMeta) => m.id), ['c', 'b', 'a']);
});

test('encodeIndex 永远写 v2 + app，并且写出的就是排序后的结果', () => {
  const json: string = encodeIndex([
    entry('2026-09-28', 'a', { createdAt: 1 }),
    entry('2026-09-30', 'b', { createdAt: 1 })
  ]);
  const holder = JSON.parse(json);
  assert.equal(holder.app, INDEX_APP);
  assert.equal(holder.v, INDEX_VERSION);
  assert.equal(holder.items.length, 2);
  assert.equal(holder.items[0].id, 'b');          // 新的在前
});

test('摘要与首图引用：老数据没有 ⇒ 空串（展示时优雅降级，不能炸）', () => {
  const legacy: string = JSON.stringify({ v: 1, items: [{ date: '2026-09-30', updatedAt: 5 }] });
  const got: NoteMeta[] = parseIndex(legacy);
  assert.equal(got[0].preview, '');
  assert.equal(got[0].imgRef, '');
  assert.equal(got[0].hasImage, false);
});

test('normalizeEntries：同一天多篇都能留下（这是 N2 的核心保证）', () => {
  const got: NoteMeta[] = normalizeEntries([
    entry('2026-09-30', 'x1', { createdAt: 1 }),
    entry('2026-09-30', 'x2', { createdAt: 2 })
  ], false);
  assert.equal(got.length, 2);
});
