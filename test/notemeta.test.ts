import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  MonthCell, MOODS, NoteMeta, daysInMonth, dateKeyOf, isValidDateKey, monthGrid, monthOf,
  moodById, searchNotes, shiftMonth, todayKey
} from '../entry/src/main/ets/data/NoteMeta';

test('日期键：补零、今天、合法校验', () => {
  assert.equal(dateKeyOf(new Date(2026, 8, 28)), '2026-09-28');
  assert.equal(dateKeyOf(new Date(2026, 0, 1)), '2026-01-01');
  assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(todayKey()));
  assert.equal(isValidDateKey('2026-09-28'), true);
  assert.equal(isValidDateKey('2026-9-28'), false);
  assert.equal(isValidDateKey('2026-02-30'), false);   // 2 月没有 30 号
  assert.equal(isValidDateKey('2026-13-01'), false);
  assert.equal(isValidDateKey('不是日期'), false);
});

test('闰年：2024-02 有 29 天，2026-02 只有 28 天', () => {
  assert.equal(daysInMonth(2024, 2), 29);
  assert.equal(daysInMonth(2026, 2), 28);
  assert.equal(daysInMonth(1900, 2), 28);  // 百年不闰
  assert.equal(daysInMonth(2000, 2), 29);  // 四百年再闰
  assert.equal(daysInMonth(2026, 12), 31);
  assert.equal(daysInMonth(2026, 4), 30);
});

test('月份切换：跨年正确（2026-01 往前 = 2025-12）', () => {
  assert.equal(monthOf('2026-09-28'), '2026-09');
  assert.equal(shiftMonth('2026-01', -1), '2025-12');
  assert.equal(shiftMonth('2025-12', 1), '2026-01');
  assert.equal(shiftMonth('2026-09', -9), '2025-12');
  assert.equal(shiftMonth('2026-09', 3), '2026-12');
});

test('月视图：42 格固定、周一开头、有日记的日子打点', () => {
  // 2026-09-01 是周二 → 前面补 1 格（周一）
  const cells: MonthCell[] = monthGrid('2026-09', ['2026-09-28', '2026-09-01']);
  assert.equal(cells.length, 42);
  assert.equal(cells[0].inMonth, false);          // 补的那一格是 8 月尾
  assert.equal(cells[1].date, '2026-09-01');
  assert.equal(cells[1].hasNote, true);
  assert.equal(cells[1].day, 1);
  const d28: MonthCell | undefined = cells.find((c: MonthCell) => c.date === '2026-09-28');
  assert.ok(d28 !== undefined);
  assert.equal(d28 !== undefined && d28.hasNote, true);
  // 没写日记的日子不打点
  const d02: MonthCell | undefined = cells.find((c: MonthCell) => c.date === '2026-09-02');
  assert.equal(d02 !== undefined && d02.hasNote, false);
});

test('月视图：9 月只有 30 天，第 31 格开始是下月（inMonth=false）', () => {
  const cells: MonthCell[] = monthGrid('2026-09', []);
  const inMonthCount: number = cells.filter((c: MonthCell) => c.inMonth).length;
  assert.equal(inMonthCount, 30);
});

test('心情：5 个封闭选项，查得到也查不到', () => {
  assert.equal(MOODS.length, 5);
  assert.ok(moodById('happy') !== null);
  assert.equal(moodById('不存在的') , null);
});

test('搜索：大小写不敏感 + 中文 + 给出上下文摘要', () => {
  const texts: { date: string; text: string }[] = [
    { date: '2026-09-28', text: '今天去了公园，看到 Hello 世界' },
    { date: '2026-09-27', text: '啥也没干' }
  ];
  const hits = searchNotes(texts, 'hello');
  assert.equal(hits.length, 1);
  assert.equal(hits[0].date, '2026-09-28');
  assert.ok(hits[0].snippet.indexOf('Hello') >= 0);
  assert.equal(searchNotes(texts, '公园').length, 1);
  assert.equal(searchNotes(texts, '不存在').length, 0);
  assert.equal(searchNotes(texts, '  ').length, 0);   // 空查询不搜
});

test('搜索摘要：emoji 不会被切成半个（代理对安全）', () => {
  const text: string = '开头😀😀😀中间结尾';
  const hits = searchNotes([{ date: '2026-09-28', text: text }], '中间');
  assert.equal(hits.length, 1);
  // 摘要里必须出现完整的 emoji，不能出现替换字符
  assert.ok(hits[0].snippet.indexOf('�') < 0);
  assert.ok(hits[0].snippet.indexOf('😀') >= 0);
});
