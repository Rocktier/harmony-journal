import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  AsrPart, ASR_ERR_BUSY, ASR_ERR_NO_PERMISSION, ASR_ERR_TOO_LONG, ASR_LANGUAGE, ASR_MAX_AUDIO_MS,
  ASR_PHASE_FAILED, ASR_PHASE_IDLE, ASR_PHASE_LISTENING, ASR_PHASE_UNREADY, ASR_SAMPLE_BIT,
  ASR_SAMPLE_RATE, ASR_SOUND_CHANNEL,
  asrButtonEnabled, asrFinalText, asrLiveText, asrNoticeOf, asrPendingText, collectFinalText
} from '../entry/src/main/ets/data/AsrText';

function part(text: string, isFinal: boolean): AsrPart {
  return { text: text, isFinal: isFinal };
}

// ── ① 结果累积：定稿累加，中间态只取最后一条 ─────────────────────────────
test('定稿结果按顺序累加成一句话', () => {
  const parts: AsrPart[] = [part('今天', true), part('天气很好', true)];
  assert.equal(collectFinalText(parts), '今天天气很好');
});

test('中间态不参与累加（否则会拼出一串越来越长的重复）', () => {
  const parts: AsrPart[] = [part('今天', false), part('今天天', false), part('今天天气', false)];
  assert.equal(collectFinalText(parts), '');
});

test('中间态取最后一条：引擎是"越修越准地重发"，不是累加', () => {
  const parts: AsrPart[] = [part('今天', false), part('今天天', false), part('今天天气', false)];
  assert.equal(asrPendingText(parts), '今天天气');
});

test('实时文本 = 已定稿 + 正在修的那一段', () => {
  const parts: AsrPart[] = [
    part('今天', true),
    part('出门', false),
    part('出门买', false),
    part('出门买了', false)
  ];
  assert.equal(asrLiveText(parts), '今天出门买了');
});

test('新一句开始时，上一条的中间态不该再出现在预览里', () => {
  // 引擎顺序：中间态(第1句) → 定稿(第1句) → 中间态(第2句)
  const parts: AsrPart[] = [part('今天', false), part('今天', true), part('我', false)];
  assert.equal(asrLiveText(parts), '今天我');
  assert.equal(asrPendingText(parts), '我');
});

test('没有结果时什么都不显示（不显示残留文本）', () => {
  const empty: AsrPart[] = [];
  assert.equal(collectFinalText(empty), '');
  assert.equal(asrPendingText(empty), '');
  assert.equal(asrLiveText(empty), '');
  assert.equal(asrFinalText(empty), '');
});

// ── ② 落正文的文本：去首尾空白 ───────────────────────────────────────────
test('落正文前去掉首尾空格（识别结果常带）', () => {
  const parts: AsrPart[] = [part('  今天天气很好  ', true)];
  assert.equal(asrFinalText(parts), '今天天气很好');
});

test('文本中间的换行与句读原样保留（不吞用户的结构）', () => {
  const parts: AsrPart[] = [part('今天出门，', true), part('买了菜。', true)];
  assert.equal(asrFinalText(parts), '今天出门，买了菜。');
});

// ── ③ 提示文案：说人话、给原因、给下一步 ─────────────────────────────────
test('聆听中给可操作的提示（告诉用户怎么结束）', () => {
  assert.match(asrNoticeOf(ASR_PHASE_LISTENING, 0), /完成/);
});

test('设备不可用：说清是系统引擎的问题，不说"失败"了事', () => {
  assert.match(asrNoticeOf(ASR_PHASE_UNREADY, 0), /离线识别引擎/);
});

test('没权限：明确要麦克风权限', () => {
  assert.match(asrNoticeOf(ASR_PHASE_FAILED, ASR_ERR_NO_PERMISSION), /麦克风权限/);
});

test('引擎正忙 / 说太长：分别给对应原因', () => {
  assert.match(asrNoticeOf(ASR_PHASE_FAILED, ASR_ERR_BUSY), /正忙/);
  assert.match(asrNoticeOf(ASR_PHASE_FAILED, ASR_ERR_TOO_LONG), /60 秒/);
});

test('未知错误兜底：不说错误码，说"可以再说一次"', () => {
  const text: string = asrNoticeOf(ASR_PHASE_FAILED, 1002200001);
  assert.doesNotMatch(text, /1002200001/);
  assert.match(text, /再说一次/);
});

test('空闲态没有提示（不打扰）', () => {
  assert.equal(asrNoticeOf(ASR_PHASE_IDLE, 0), '');
});

// ── ④ 按钮可用性 ────────────────────────────────────────────────────────
test('空闲与失败后可点，聆听中禁用（防重复 start 报 1002200002）', () => {
  assert.equal(asrButtonEnabled(ASR_PHASE_IDLE, false), true);
  assert.equal(asrButtonEnabled(ASR_PHASE_FAILED, false), true);
  assert.equal(asrButtonEnabled(ASR_PHASE_LISTENING, false), false);
});

test('设备不可用时按钮禁用（但仍显示，配不可用文案）', () => {
  assert.equal(asrButtonEnabled(ASR_PHASE_UNREADY, false), false);
});

test('胶囊锁着（只读）时按钮禁用', () => {
  assert.equal(asrButtonEnabled(ASR_PHASE_IDLE, true), false);
});

// ── ⑤ 官方口径常量：写错值会直接报 401 ───────────────────────────────────
test('音频参数与语种是官方唯一合法值', () => {
  assert.equal(ASR_SAMPLE_RATE, 16000);
  assert.equal(ASR_SOUND_CHANNEL, 1);
  assert.equal(ASR_SAMPLE_BIT, 16);
  assert.equal(ASR_LANGUAGE, 'zh-CN');
});

test('单次上限 60 秒（短语音模式官方上限），且与提示文案一致', () => {
  assert.equal(ASR_MAX_AUDIO_MS, 60000);
  assert.match(asrNoticeOf(ASR_PHASE_FAILED, ASR_ERR_TOO_LONG), /60 秒/);
});
