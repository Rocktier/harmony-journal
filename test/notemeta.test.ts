import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  MonthCell, MOODS, NoteMeta, TimelineRow, daysInMonth, dateKeyOf, isValidDateKey, isValidNoteId, monthGrid,
  monthOf, moodById, newNoteId, onThisDayDates, previewText, searchNotes, shiftMonth, timeOfDay,
  timelineRows, todayKey, yearsAgoLabel
} from '../entry/src/main/ets/data/NoteMeta';

/** 造条目（只关心被测字段，其余走默认） */
function entry(date: string, id: string, createdAt: number = 1): NoteMeta {
  return {
    id: id, date: date, createdAt: createdAt, mood: '', moodText: '',
    preview: '', updatedAt: createdAt, words: 0, hasImage: false, imgRef: ''
  };
}

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

test('id 生成：可用作文件名、两次不同、能避开已占用的', () => {
  const a: string = newNoteId(new Set<string>());
  const b: string = newNoteId(new Set<string>());
  assert.ok(isValidNoteId(a));
  assert.ok(isValidNoteId(b));
  assert.notEqual(a, b);   // 同一毫秒内也靠随机段区分开来
  // 已占用的 id 必须被避开
  const taken: Set<string> = new Set<string>([a]);
  assert.equal(newNoteId(taken) === a, false);
});

test('id 校验：管的是"能不能安全当文件名"，老数据的日期形 id 必须算合法', () => {
  assert.equal(isValidNoteId('2026-09-30'), true);   // ★ 迁移时老 id 就是日期串
  assert.equal(isValidNoteId('m5x2k9abc'), true);    // 新版 base36
  assert.equal(isValidNoteId(''), false);
  assert.equal(isValidNoteId('.'), false);
  assert.equal(isValidNoteId('..'), false);
  assert.equal(isValidNoteId('a/b'), false);         // 路径分隔符
  assert.equal(isValidNoteId('..\\x'), false);
  assert.equal(isValidNoteId('a b'), false);         // 空格
});

test('心情：5 个封闭选项，查得到也查不到', () => {
  assert.equal(MOODS.length, 5);
  assert.ok(moodById('happy') !== null);
  assert.equal(moodById('不存在的') , null);
});

test('搜索：大小写不敏感 + 中文 + 给出上下文摘要', () => {
  const texts: { id: string; date: string; text: string }[] = [
    { id: 'n1', date: '2026-09-28', text: '今天去了公园，看到 Hello 世界' },
    { id: 'n2', date: '2026-09-27', text: '啥也没干' }
  ];
  const hits = searchNotes(texts, 'hello');
  assert.equal(hits.length, 1);
  assert.equal(hits[0].date, '2026-09-28');
  assert.equal(hits[0].id, 'n1');        // 结果要能精确指回那一篇
  assert.ok(hits[0].snippet.indexOf('Hello') >= 0);
  assert.equal(searchNotes(texts, '公园').length, 1);
  assert.equal(searchNotes(texts, '不存在').length, 0);
  assert.equal(searchNotes(texts, '  ').length, 0);   // 空查询不搜
});

test('那年今日：只取往年同月同日，倒序，且不含今天', () => {
  const all: string[] = ['2026-09-30', '2025-09-30', '2023-09-30', '2026-09-28', '2024-10-01'];
  const got: string[] = onThisDayDates(all, '2026-09-30');
  assert.deepEqual(got, ['2025-09-30', '2023-09-30']);
});

test('那年今日：没有往年内容 ⇒ 空（界面上就不该出现卡片）', () => {
  assert.deepEqual(onThisDayDates([], '2026-09-30'), []);
  assert.deepEqual(onThisDayDates(['2026-09-28'], '2026-09-30'), []);
  assert.deepEqual(onThisDayDates(['2025-09-30'], '2025-09-30'), []); // 只有今天自己
});

test('那年今日：未来的日期不算（没人要看"未来的自己"）', () => {
  assert.deepEqual(onThisDayDates(['2027-09-30'], '2026-09-30'), []);
});

test('那年今日：闰日 02-29 只在闰年命中，不降级到 02-28', () => {
  const all: string[] = ['2024-02-29', '2023-02-28', '2020-02-29'];
  assert.deepEqual(onThisDayDates(all, '2028-02-29'), ['2024-02-29', '2020-02-29']);
});

test('那年今日：脏日期键被滤掉，不影响其余', () => {
  assert.deepEqual(onThisDayDates(['不是日期', '2025-09-30'], '2026-09-30'), ['2025-09-30']);
});

test('N 年前：年份差即年数（MM-DD 已相同）；非法返回空串', () => {
  assert.equal(yearsAgoLabel('2025-09-30', '2026-09-30'), '1 年前');
  assert.equal(yearsAgoLabel('2023-09-30', '2026-09-30'), '3 年前');
  assert.equal(yearsAgoLabel('2026-09-30', '2026-09-30'), '');   // 同一天
  assert.equal(yearsAgoLabel('2027-09-30', '2026-09-30'), '');   // 未来
  assert.equal(yearsAgoLabel('不是日期', '2026-09-30'), '');
});

test('时间轴：月份变化处插入标题，首行必是标题', () => {
  const rows: TimelineRow[] = timelineRows([
    entry('2026-09-30', 'a'), entry('2026-09-28', 'b'), entry('2026-08-01', 'c')
  ]);
  assert.equal(rows[0].kind, 'header');
  assert.equal(rows[0].monthKey, '2026-09');
  assert.equal(rows[1].kind, 'note');
  assert.equal(rows[3].kind, 'header');      // 换月
  assert.equal(rows[3].monthKey, '2026-08');
  assert.equal(rows.length, 5);              // 2 个标题 + 3 篇
});

test('时间轴：key 必须全局唯一（LazyForEach 强依赖，重复会渲染错乱）', () => {
  const rows: TimelineRow[] = timelineRows([
    entry('2026-09-30', 'a'), entry('2026-09-30', 'b'), entry('2026-09-28', 'c')
  ]);
  const keys: string[] = rows.map((r: TimelineRow) => r.key);
  assert.equal(new Set(keys).size, keys.length);
  assert.ok(keys.indexOf('n:a') >= 0);
  assert.ok(keys.indexOf('h:2026-09') >= 0);
});

test('时间轴：同一天多篇才标 showTime（否则几行日期一模一样）', () => {
  const rows: TimelineRow[] = timelineRows([
    entry('2026-09-30', 'a', 1), entry('2026-09-30', 'b', 2), entry('2026-09-28', 'c', 3)
  ]);
  const notes: TimelineRow[] = rows.filter((r: TimelineRow) => r.kind === 'note');
  assert.equal(notes.length, 3);
  assert.equal(notes[0].showTime, true);
  assert.equal(notes[1].showTime, true);
  assert.equal(notes[2].showTime, false);   // 这天只有一篇
});

test('时间轴：空输入 ⇒ 空', () => {
  assert.deepEqual(timelineRows([]), []);
});

test('摘要：折叠换行与空白、按字符截断并补省略号', () => {
  assert.equal(previewText('第一行\n第二行  中间', 100), '第一行 第二行 中间');
  assert.equal(previewText('abcdef', 3), 'abc…');
  assert.equal(previewText('abc', 3), 'abc');      // 刚好等于不补
  assert.equal(previewText('  ', 10), '');
  assert.equal(previewText('内容', 0), '');
});

test('摘要：emoji 不会被切成半个', () => {
  const s: string = '😀😀😀😀abcdef';
  const cut: string = previewText(s, 5);
  assert.ok(cut.indexOf('�') < 0);
});

test('时间 HH:mm 补零正确', () => {
  assert.equal(timeOfDay(new Date(2026, 8, 30, 9, 5).getTime()), '09:05');
  assert.equal(timeOfDay(new Date(2026, 8, 30, 18, 40).getTime()), '18:40');
  assert.equal(timeOfDay(0), '');         // 老数据没有创建时间 ⇒ 不瞎显示
});

test('搜索摘要：emoji 不会被切成半个（代理对安全）', () => {
  const text: string = '开头😀😀😀中间结尾';
  const hits = searchNotes([{ id: 'n1', date: '2026-09-28', text: text }], '中间');
  assert.equal(hits.length, 1);
  // 摘要里必须出现完整的 emoji，不能出现替换字符
  assert.ok(hits[0].snippet.indexOf('�') < 0);
  assert.ok(hits[0].snippet.indexOf('😀') >= 0);
});
