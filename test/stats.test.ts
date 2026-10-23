import { test } from 'node:test';
import assert from 'node:assert/strict';

import { MOODS, MOOD_CUSTOM_ID, MonthWords, NoteMeta, moodCounts, monthlyWords } from '../entry/src/main/ets/data/NoteMeta';

/**
 * stats 守卫（2026-10-23 复评 wow-point 落地）
 *
 * 守的是统计页（RockStats）的两个纯函数：
 *  - moodCounts：心情分布横条的计数口径；
 *  - monthlyWords：月度柱状图的桶 + **未到期胶囊不计入**的封存纪律。
 *
 * 为什么值得单测：统计页是「数据只在这台设备上」的承诺可视化，
 * 而 monthlyWords 的胶囊过滤是**防剧透**的（「本月 800 字」会泄露
 * 「锁着的那封信写了多长」）—— 这种口径一旦被"顺手优化"掉，
 * 用户看到的还是绿屏，没有任何报错，所以必须 CI 钉死。
 */

const NOW: number = new Date(2026, 9, 23, 12, 0, 0).getTime();
const NOW_KEY: string = '2026-10-23';
/** 未到期胶囊：明年才解锁 */
const LOCKED_AT: number = new Date(2027, 0, 1, 8, 0, 0).getTime();
/** 已到期胶囊：上个月就解锁了 */
const OPENED_AT: number = new Date(2026, 8, 1, 8, 0, 0).getTime();

function metaOf(date: string, id: string, mood: string, words: number, unlockAt: number = 0): NoteMeta {
  return {
    id: id, date: date, createdAt: 1, mood: mood, moodText: '', preview: '',
    updatedAt: 1, words: words, hasImage: false, imgRef: '', unlockAt: unlockAt,
    favorite: false, tags: []
  };
}

test('moodCounts：按 MOODS 计数，无心情不计，自定义进 custom 桶', () => {
  const metas: NoteMeta[] = [
    metaOf('2026-10-21', 'a', 'happy', 10),
    metaOf('2026-10-21', 'b', 'happy', 10),
    metaOf('2026-10-22', 'c', 'happy', 10),
    metaOf('2026-10-22', 'd', 'calm', 10),
    metaOf('2026-10-23', 'e', MOOD_CUSTOM_ID, 10),
    metaOf('2026-10-23', 'f', '', 10)
  ];
  const out: Record<string, number> = moodCounts(metas);
  assert.equal(out['happy'], 3);
  assert.equal(out['calm'], 1);
  assert.equal(out[MOOD_CUSTOM_ID], 1);
  // 无心情的篇目不进任何桶（不凑数）
  const total: number = Object.keys(out).reduce((sum: number, k: string) => sum + out[k], 0);
  assert.equal(total, 5);
  // MOODS 每个 id 都有初始桶（渲染侧直接索引，不用判存在）
  for (let i: number = 0; i < MOODS.length; i++) {
    assert.equal(typeof out[MOODS[i].id], 'number');
  }
  assert.equal(out['sad'], 0);
});

test('monthlyWords：近 N 月倒序、当月含今天、空月补 0', () => {
  const metas: NoteMeta[] = [
    metaOf('2026-10-23', 'a', 'happy', 100),  // 当月（今天）
    metaOf('2026-10-01', 'b', 'happy', 50),   // 当月
    metaOf('2026-09-15', 'c', 'happy', 30),   // 上月
    metaOf('2026-07-04', 'd', 'happy', 20)    // 中间断一个月
  ];
  const out: MonthWords[] = monthlyWords(metas, NOW_KEY, 3, NOW);
  assert.equal(out.length, 3);
  // 倒序：最新在右 ⇒ out[0] 是 8 月、out[2] 是当月 10 月
  assert.equal(out[0].month, '2026-08');
  assert.equal(out[0].words, 0);              // 断月补 0，不是断轴
  assert.equal(out[1].month, '2026-09');
  assert.equal(out[1].words, 30);
  assert.equal(out[2].month, '2026-10');
  assert.equal(out[2].words, 150);            // 当月两篇合计，含今天
});

test('monthlyWords：未到期胶囊的字数不计入（防剧透）', () => {
  const metas: NoteMeta[] = [
    metaOf('2026-10-10', 'a', 'happy', 100),
    // 锁着的信：写了 9999 字也一个字都不能进桶
    metaOf('2026-10-11', 'b', '', 9999, LOCKED_AT)
  ];
  const out: MonthWords[] = monthlyWords(metas, NOW_KEY, 1, NOW);
  assert.equal(out.length, 1);
  assert.equal(out[0].month, '2026-10');
  assert.equal(out[0].words, 100);
});

test('monthlyWords：已到期胶囊恢复正常计量', () => {
  const metas: NoteMeta[] = [
    metaOf('2026-10-10', 'a', 'happy', 100),
    metaOf('2026-10-11', 'b', '', 40, OPENED_AT)  // 上个月已解锁
  ];
  const out: MonthWords[] = monthlyWords(metas, NOW_KEY, 1, NOW);
  assert.equal(out[0].words, 140);
});
