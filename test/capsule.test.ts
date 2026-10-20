import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  NoteMeta, TimelineRow, capsuleBadge, capsuleLocked, computeStats, countsForStats, daysUntilUnlock,
  earliestUnlock, isCapsule, timelineRows, unlockTsOfDate
} from '../entry/src/main/ets/data/NoteMeta';
import { normalizeEntries, parseIndex } from '../entry/src/main/ets/data/IndexCodec';

/** 造条目（只关心被测字段，其余走默认） */
function entry(date: string, id: string, words: number = 0, unlockAt: number = 0): NoteMeta {
  return {
    id: id, date: date, createdAt: 1, mood: '', moodText: '',
    preview: '', updatedAt: 1, words: words, hasImage: false, imgRef: '',
    favorite: false, tags: [], unlockAt: unlockAt
  };
}

/** 固定"现在"（2026-10-20 12:00 本地时间）—— 所有用例围绕它算，不碰真实时钟 */
const NOW: number = new Date(2026, 9, 20, 12, 0, 0).getTime();
const DAY: number = 86400000;

test('isCapsule：unlockAt>0 才是胶囊；老数据（无字段/0）按普通日记', () => {
  assert.equal(isCapsule(entry('2026-10-20', 'a', 10, NOW + 30 * DAY)), true);
  assert.equal(isCapsule(entry('2026-10-20', 'b')), false);
  assert.equal(isCapsule(entry('2026-10-20', 'c', 10, 0)), false);
});

test('capsuleLocked：未来锁着、到期/过期打开；非胶囊永远不锁', () => {
  assert.equal(capsuleLocked(entry('2026-10-20', 'a', 0, NOW + 1000), NOW), true);
  assert.equal(capsuleLocked(entry('2026-10-20', 'a', 0, NOW - 1000), NOW), false);
  // 恰好在解锁那一刻 = 已解锁（>= 语义：unlockAt > now 才锁）
  assert.equal(capsuleLocked(entry('2026-10-20', 'a', 0, NOW), NOW), false);
  assert.equal(capsuleLocked(entry('2026-10-20', 'b'), NOW), false);
});

test('daysUntilUnlock：向上取整；已到期/非胶囊为 0', () => {
  // 还有 30.5 天 ⇒ "还有 31 天"（差 1 小时也算一天，用户看到的是日历天）
  assert.equal(daysUntilUnlock(entry('2026-10-20', 'a', 0, NOW + 30 * DAY + 3600000), NOW), 31);
  assert.equal(daysUntilUnlock(entry('2026-10-20', 'a', 0, NOW + 2 * DAY), NOW), 2);
  assert.equal(daysUntilUnlock(entry('2026-10-20', 'a', 0, NOW - DAY), NOW), 0);
  assert.equal(daysUntilUnlock(entry('2026-10-20', 'b'), NOW), 0);
});

test('earliestUnlock：明天本地零点（当天解锁的胶囊没有意义）', () => {
  const t: number = earliestUnlock(NOW);
  const d: Date = new Date(t);
  assert.equal(d.getFullYear(), 2026);
  assert.equal(d.getMonth(), 9);
  assert.equal(d.getDate(), 21);
  assert.equal(d.getHours(), 0);
  assert.equal(d.getMinutes(), 0);
});

test('unlockTsOfDate：本地时区零点（与 dateKeyOf/todayKey 同一个"今天"定义）', () => {
  const t: number = unlockTsOfDate(2027, 1, 15);
  const d: Date = new Date(t);
  assert.equal(d.getFullYear(), 2027);
  assert.equal(d.getMonth(), 0);
  assert.equal(d.getDate(), 15);
  assert.equal(d.getHours(), 0);
});

test('capsuleBadge：锁定显倒计时、解锁显角标、普通日记空串', () => {
  assert.equal(capsuleBadge(entry('2026-10-20', 'a', 0, NOW + 3 * DAY), NOW), '⏳ 还有 3 天');
  assert.equal(capsuleBadge(entry('2026-10-20', 'a', 0, NOW - DAY), NOW), '已解锁');
  assert.equal(capsuleBadge(entry('2026-10-20', 'b'), NOW), '');
});

test('countsForStats：未到期胶囊不计字数（防从数字反推信长），解锁后恢复计量', () => {
  assert.equal(countsForStats(entry('2026-10-20', 'a', 500, NOW + DAY), NOW), false);
  assert.equal(countsForStats(entry('2026-10-20', 'a', 500, NOW - DAY), NOW), true);
  assert.equal(countsForStats(entry('2026-10-20', 'b', 500), NOW), true);
});

test('computeStats：胶囊篇数/天数照算，字数过滤；连续天数不受影响', () => {
  // 三天各一篇：10-18 普通 100 字、10-19 胶囊 800 字（锁着）、10-20 普通 50 字
  const metas: NoteMeta[] = [
    entry('2026-10-18', 'a', 100),
    entry('2026-10-19', 'b', 800, NOW + 5 * DAY),
    entry('2026-10-20', 'c', 50)
  ];
  const s = computeStats(metas, '2026-10-20', NOW);
  assert.equal(s.total, 3);            // 篇数含胶囊（坚持的痕迹可见）
  assert.equal(s.days, 3);             // 天数含胶囊日
  assert.equal(s.words, 150);          // 800 字的胶囊不计（100+50）
  assert.equal(s.streak, 3);           // 连续天数照算（写过就是写过）
  assert.equal(s.longest, 3);
  assert.equal(s.wroteToday, true);
});

test('索引兼容：老数据（JSON 无 unlockAt）解析为 0；新数据原样带回', () => {
  // 老格式：条目里没有 unlockAt 键
  const legacy: string = JSON.stringify({
    app: 'rockjournal', v: 2,
    items: [{ id: 'x1', date: '2026-10-19', createdAt: 1, mood: '', moodText: '', preview: '旧文', updatedAt: 1, words: 42, hasImage: false, imgRef: '', favorite: false, tags: ['旧'] }]
  });
  const parsed: NoteMeta[] = parseIndex(legacy);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].unlockAt, 0);          // 缺字段 ⇒ 普通日记
  assert.equal(parsed[0].preview, '旧文');      // 其余字段不受影响

  // 新格式：unlockAt 原样带回
  const fresh: string = JSON.stringify({
    app: 'rockjournal', v: 2,
    items: [{ id: 'x2', date: '2026-10-19', createdAt: 1, mood: '', moodText: '', preview: '', updatedAt: 1, words: 99, hasImage: false, imgRef: '', favorite: false, tags: [], unlockAt: NOW + 99 * DAY }]
  });
  const parsed2: NoteMeta[] = parseIndex(fresh);
  assert.equal(parsed2[0].unlockAt, NOW + 99 * DAY);
  assert.equal(capsuleLocked(parsed2[0], NOW), true);
});

test('normalizeEntries：脏 unlockAt（负数/NaN/非数字）一律按 0 处理', () => {
  const raw: NoteMeta[] = [
    Object.assign(entry('2026-10-19', 'ok', 1, NOW + DAY), {}),
    Object.assign(entry('2026-10-18', 'neg'), { unlockAt: -5 }),
    Object.assign(entry('2026-10-17', 'str'), { unlockAt: 'x' as unknown as number })
  ];
  const out: NoteMeta[] = normalizeEntries(raw, false);
  const byId: Map<string, NoteMeta> = new Map<string, NoteMeta>();
  for (let i: number = 0; i < out.length; i++) {
    byId.set(out[i].id, out[i]);
  }
  assert.equal(byId.get('ok')!.unlockAt, NOW + DAY);
  assert.equal(byId.get('neg')!.unlockAt, 0);
  assert.equal(byId.get('str')!.unlockAt, 0);
});

test('timelineRows 的 key：普通日记恒定；胶囊带锁定/倒计时标签（LazyForEach 重建依据）', () => {
  const plain: NoteMeta = entry('2026-10-20', 'plain', 10);
  const capsule: NoteMeta = entry('2026-10-19', 'cap', 20, NOW + 3 * DAY);
  const unlocked: NoteMeta = entry('2026-10-18', 'old', 30, NOW - DAY);
  const rows = timelineRows([plain, capsule, unlocked], NOW);
  const keys: Map<string, string> = new Map<string, string>();
  for (const r of rows) {
    if (r.meta !== null) {
      keys.set(r.meta.id, r.key);
    }
  }
  // 普通日记：key 与历史版本一致（'n:'+id）—— 不带来额外重建
  assert.equal(keys.get('plain'), 'n:plain');
  // 锁定胶囊：'n:'+id+':L'+剩余天数
  assert.equal(keys.get('cap'), 'n:cap:L3');
  // 已解锁胶囊：':O' 后缀（与锁定态 key 不同 ⇒ 解锁瞬间那一行会重建）
  assert.equal(keys.get('old'), 'n:old:O');
  // 跨天：倒计时数字进 key ⇒ 天数变化行也会重建（数字不会陈旧）
  // 注意单条数据也会带月份头行（index 0 是 header），要按 meta 定位日记行
  const tomorrowRows = timelineRows([capsule], NOW + 2 * DAY);
  const capRow = tomorrowRows.filter((r: TimelineRow) => r.meta !== null)[0];
  assert.equal(capRow.key, 'n:cap:L1');
});
