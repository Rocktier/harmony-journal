import { test } from 'node:test';
import assert from 'node:assert/strict';

import { PROMPTS, nextDateKey, promptIndexOn, promptOfDate, repeatedNeighborDays } from '../entry/src/main/ets/data/Prompts';

test('每日提示：同一天永远同一条（打开三次必须看到同一句）', () => {
  const a: string = promptOfDate('2026-10-27');
  const b: string = promptOfDate('2026-10-27');
  const c: string = promptOfDate('2026-10-27');
  assert.equal(a, b);
  assert.equal(b, c);
  assert.ok(a.length > 0);
});

test('每日提示：提示条来自库内，且序号可反查（排错时能用）', () => {
  const key: string = '2026-10-27';
  const idx: number = promptIndexOn(key);
  assert.ok(idx >= 0 && idx < PROMPTS.length);
  assert.equal(promptOfDate(key), PROMPTS[idx]);
});

test('每日提示：入参不是日期键就返回空串（宁可不显示，也不给随机一句）', () => {
  assert.equal(promptOfDate(''), '');
  assert.equal(promptOfDate('2026-10'), '');
  assert.equal(promptIndexOn(''), -1);
  assert.equal(promptIndexOn('2026-1'), -1);
});

test('每日提示：一年内几乎每天都是不同的一句（这才叫"每日"提示）', () => {
  const seen = new Set<string>();
  let cursor: string = '2026-01-01';
  for (let i: number = 0; i < 365; i++) {
    seen.add(promptOfDate(cursor));
    cursor = nextDateKey(cursor);
  }
  // 72 条库、365 天：每个槽位平均命中 5 次 ⇒ 一年内应该几乎用遍全部条目
  assert.ok(seen.size >= 60, '一年内只用到 ' + seen.size + ' 句，分布太差');
});

test('每日提示：相邻两天撞同一句的次数要很低（连着两天看到同一句会显得功能坏了）', () => {
  const repeats: number = repeatedNeighborDays('2026-01-01', '2026-12-31');
  // 随机落到 72 个槽位，364 次相邻比较 ⇒ 期望约 5 次；给 20 的余量防止某次改库就挂
  assert.ok(repeats < 20, '相邻撞句 ' + repeats + ' 次，太多');
});

test('每日提示：库本身没有空串与重复条目（脏条目会直接显示成空白提示条）', () => {
  const seen = new Set<string>();
  for (let i: number = 0; i < PROMPTS.length; i++) {
    assert.ok(PROMPTS[i].trim().length > 0, '第 ' + i + ' 条是空的');
    assert.equal(seen.has(PROMPTS[i]), false, '第 ' + i + ' 条重复了');
    seen.add(PROMPTS[i]);
  }
});

test('nextDateKey: 跨月 / 跨年 / 闰年 2 月都要对', () => {
  assert.equal(nextDateKey('2026-01-31'), '2026-02-01');
  assert.equal(nextDateKey('2026-12-31'), '2027-01-01');
  assert.equal(nextDateKey('2028-02-28'), '2028-02-29'); // 闰年
  assert.equal(nextDateKey('2026-02-28'), '2026-03-01'); // 平年
  assert.equal(nextDateKey('2026-10-27'), '2026-10-28');
});

test('nextDateKey: 入参不合法返回空串（循环推进靠它终止，不能给出脏日期）', () => {
  assert.equal(nextDateKey(''), '');
  assert.equal(nextDateKey('2026-10'), '');
  assert.equal(nextDateKey('2026-13-01'), '');
});
