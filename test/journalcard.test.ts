/**
 * 桌面卡片数据层单测（2026-10-26）
 *
 * 守两条线：
 *  ① **本地时区**（家族铁律）：卡片上写"今天几号"，一旦用了 UTC，
 *     东八区 00:00–08:00 会显示成"昨天" —— 用户看着莫名其妙。
 *     这条用两个固定时刻（本地 00:05 与 23:55）断言，覆盖 UTC 偏移的经典翻车点。
 *  ② **零泄漏**：卡片绑定数据里**不得出现任何日记内容字段**
 *     （正文/摘要/字数/心情/标签/日期键以外的内容）。
 *     字段级白名单断言 —— 将来有人"顺手加个 todayWords"就会红。
 */
import test from 'node:test';
import assert from 'node:assert';

import {
  CARD_DIM_SMALL, CARD_DIM_WIDE, CARD_INTENT_WRITE_TODAY,
  cardDateText, cardWeekdayText, journalCardData
} from '../entry/src/main/ets/data/JournalCardData';

/**
 * 造一个"本地墙上时间恰好是 (y,m,d,h,mi)"的 Date（**任何时区下都成立**）
 *
 * ⚠️ 不能直接用 `new Date(y, m, d, h, mi)`：那是**运行时本地时区**的墙上时间，
 *    在 UTC 机器与东八区机器上指向的 UTC 时刻不同 ⇒ 跨 UTC 日界线的断言
 *    会在 CI（ubuntu, TZ=UTC）与本地给出不同结论（家族血泪：时区脆弱断言）。
 *    这里先按 UTC 造，再减去本地偏移 ⇒ 无论机器在哪个时区，
 *    `d.getMonth()/getDate()/getHours()` 都精确等于入参。
 */
function localAt(y: number, m: number, d: number, h: number, mi: number): Date {
  const utcGuess: number = Date.UTC(y, m, d, h, mi);
  // ⚠️ 符号：JS 的 getTimezoneOffset() = 「UTC − 本地」的分钟数（东八区 = −480），
  //    且 本地 = UTC − offset ⇒ 想让本地墙上时间 = T，就得 UTC = T + offset。
  const offsetMs: number = new Date(utcGuess).getTimezoneOffset() * 60000;
  return new Date(utcGuess + offsetMs);
}

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

test('卡片日期用本地时区：本地 00:05 仍是"今天"', () => {
  const d: Date = localAt(2026, 9, 26, 0, 5);
  assert.equal(cardDateText(d), '10月26日');
  assert.equal(cardWeekdayText(d), '星期一');
});

test('卡片日期用本地时区：本地 23:55 仍是"今天"', () => {
  const d: Date = localAt(2026, 9, 26, 23, 55);
  assert.equal(cardDateText(d), '10月26日');
});

test('跨 UTC 日界线时也必须用本地日期（UTC 会写成昨天）', () => {
  // 逐个小时扫一遍：凡本地日期与 UTC 日期不同的时刻，
  // 实现一旦误用 toISOString() 就会答错日期 ⇒ 这里逐点断言。
  for (let h: number = 0; h < 24; h++) {
    const d: Date = localAt(2026, 9, 26, h, 5);
    assert.equal(cardDateText(d), '10月26日', '本地 10月26日 ' + h + ':05 被算成了别的日期');
    const utcDay: string = d.toISOString().substring(0, 10);
    const localDay: string = d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    if (utcDay !== localDay) {
      // 这个时刻正是"UTC 与本地跨日"的雷区（东八区 00:00–08:00）
      assert.notEqual(utcDay, '2026-10-26', '测试前提失效：本机时区不是 UTC+8');
      assert.equal(cardDateText(d), '10月26日');
    }
  }
});

test('跨月跨年边界', () => {
  assert.equal(cardDateText(localAt(2026, 0, 1, 12, 0)), '1月1日');
  assert.equal(cardDateText(localAt(2026, 11, 31, 12, 0)), '12月31日');
  assert.equal(cardDateText(localAt(2027, 0, 1, 12, 0)), '1月1日');
});

test('星期几映射正确（0=周日）', () => {
  assert.equal(cardWeekdayText(localAt(2026, 9, 25, 12, 0)), '星期日');
  assert.equal(cardWeekdayText(localAt(2026, 9, 26, 12, 0)), '星期一');
  assert.equal(cardWeekdayText(localAt(2026, 9, 27, 12, 0)), '星期二');
  assert.equal(cardWeekdayText(localAt(2026, 9, 1, 12, 0)), '星期四');
  assert.equal(cardWeekdayText(localAt(2026, 9, 2, 12, 0)), '星期五');
  assert.equal(cardWeekdayText(localAt(2026, 9, 3, 12, 0)), '星期六');
  assert.equal(cardWeekdayText(localAt(2026, 9, 4, 12, 0)), '星期日');
});

test('组装卡片数据：字段齐全且只有日期类信息', () => {
  const d: JournalCardDataForTest = journalCardData(CARD_DIM_WIDE, localAt(2026, 9, 26, 9, 0));
  assert.equal(d.dimension, '2*4');
  assert.equal(d.dateText, '10月26日');
  assert.equal(d.weekdayText, '星期一');
  assert.equal(d.todayKey, '2026-10-26');
});

test('组装卡片数据：尺寸缺省按 2×2', () => {
  const d: JournalCardDataForTest = journalCardData('', localAt(2026, 9, 26, 9, 0));
  assert.equal(d.dimension, CARD_DIM_SMALL);
});

test('零泄漏：卡片数据里不得出现任何日记内容字段', () => {
  const d: JournalCardDataForTest = journalCardData(CARD_DIM_SMALL, localAt(2026, 9, 26, 9, 0));
  const allowed: string[] = ['dimension', 'dateText', 'weekdayText', 'todayKey'];
  const keys: string[] = Object.keys(d);
  for (const k of keys) {
    assert.ok(allowed.indexOf(k) >= 0, '卡片数据出现未授权字段（可能泄漏日记内容）：' + k);
  }
  // 明确点名几个"绝不能出现"的字段（防后来者顺手加）
  for (const banned of ['words', 'preview', 'content', 'mood', 'tags', 'summary', 'text', 'title']) {
    assert.ok(keys.indexOf(banned) < 0, '卡片数据出现禁用字段：' + banned);
  }
});

test('卡片意图常量固定为 writeToday（EntryAbility/Index 两侧靠它对齐）', () => {
  assert.equal(CARD_INTENT_WRITE_TODAY, 'writeToday');
});

/** 本地类型别名（测试内避免依赖 ArkTS 类型导出） */
interface JournalCardDataForTest {
  dimension: string;
  dateText: string;
  weekdayText: string;
  todayKey: string;
}
