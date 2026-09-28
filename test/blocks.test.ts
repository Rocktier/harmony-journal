import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  Block, BlockType, BLOCK_TYPE_H, BLOCK_TYPE_IMG, BLOCK_TYPE_LI, BLOCK_TYPE_P, RawSpan, Span,
  blocksToJson, isEmptyBlock, jsonToBlocks, mergeSpans, normalizeBlocks, plainTextOf, wordCountOf
} from '../entry/src/main/ets/data/NoteBlocks';

function span(text: string, bold: boolean = false, italic: boolean = false): Span {
  return { text: text, bold: bold, italic: italic };
}

function raw(text: string, weight: number = 0, style: number = 0): RawSpan {
  return { text: text, fontWeight: weight, fontStyle: style };
}

function block(type: BlockType, spans: Span[] = [], ref: string = ''): Block {
  return { type: type, spans: spans, ref: ref };
}

// ── ① 碎片化合并（评估文档六½ 的核心约束）───────────────────────────────
test('碎片化 span：相邻同样式合并成一段', () => {
  // 实测：20 个字符拿到 26 个 span，几乎每字符一个
  const raws: RawSpan[] = ['H', 'e', 'l', 'l', 'o'].map((c: string) => raw(c));
  const merged: Span[] = mergeSpans(raws);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].text, 'Hello');
  assert.equal(merged[0].bold, false);
});

test('样式边界不合并：粗体与普通之间必须断开', () => {
  const merged: Span[] = mergeSpans([raw('a', 0, 0), raw('b', 0, 0), raw('c', 9, 0), raw('d', 9, 0), raw('e', 0, 0)]);
  assert.equal(merged.length, 3);
  assert.deepEqual(merged[0], span('ab'));
  assert.deepEqual(merged[1], span('cd', true, false));
  assert.deepEqual(merged[2], span('e'));
});

test('斜体与粗体是两条独立的样式轴', () => {
  const merged: Span[] = mergeSpans([raw('a', 9, 0), raw('b', 9, 1), raw('c', 0, 1)]);
  assert.equal(merged.length, 3);
  assert.deepEqual(merged[1], span('b', true, true));
});

test('空文本片段被丢弃（不产生空 span）', () => {
  const merged: Span[] = mergeSpans([raw(''), raw('x'), raw(''), raw('y')]);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].text, 'xy');
});

// ── ② 语义样式：不存渲染层数字 ────────────────────────────────────────
test('fontWeight 内部数字 9 → semantic bold（不存数字，回填才有效）', () => {
  const merged: Span[] = mergeSpans([raw('x', 9, 0)]);
  assert.equal(merged[0].bold, true);
  // 序列化后必须是布尔，绝不能出现 9
  const json: string = blocksToJson([block(BLOCK_TYPE_P, merged)]);
  assert.ok(json.indexOf('"bold":true') >= 0);
  assert.ok(json.indexOf(':9') < 0);
});

// ── ③ 图片块只存 ref ─────────────────────────────────────────────────
test('图片块：无 ref 视为空块；有 ref 才有意义', () => {
  assert.equal(isEmptyBlock(block(BLOCK_TYPE_IMG, [], '')), true);
  assert.equal(isEmptyBlock(block(BLOCK_TYPE_IMG, [], 'img/2026-09-28-a1b2.enc')), false);
});

// ── ④ 规范化 ─────────────────────────────────────────────────────────
test('normalize：剔除空块、未知类型降级为 p', () => {
  const out: Block[] = normalizeBlocks([
    block(BLOCK_TYPE_P, [span('')]),
    block('quote' as BlockType, [span('坏类型')]),
    block(BLOCK_TYPE_H, [span('标题')]),
    block(BLOCK_TYPE_IMG, [], 'r1')
  ]);
  assert.equal(out.length, 3);
  assert.equal(out[0].type, BLOCK_TYPE_P);
  assert.equal(out[0].spans[0].text, '坏类型');
  assert.equal(out[2].type, BLOCK_TYPE_IMG);
});

test('normalize：正文块强制清空 ref（ref 只属于图片）', () => {
  const out: Block[] = normalizeBlocks([block(BLOCK_TYPE_P, [span('x')], '不该有')]);
  assert.equal(out[0].ref, '');
});

// ── ⑤ 序列化往返 ─────────────────────────────────────────────────────
test('序列化往返：块结构、样式、图片 ref 全部保真', () => {
  const blocks: Block[] = [
    block(BLOCK_TYPE_H, [span('今天')]),
    block(BLOCK_TYPE_P, [span('普通'), span('粗', true), span('斜', false, true)]),
    block(BLOCK_TYPE_LI, [span('条目一')]),
    block(BLOCK_TYPE_IMG, [], 'img/a.enc')
  ];
  const back: Block[] = jsonToBlocks(blocksToJson(blocks));
  assert.equal(back.length, 4);
  assert.equal(back[1].spans.length, 3);
  assert.equal(back[1].spans[1].bold, true);
  assert.equal(back[3].ref, 'img/a.enc');
});

test('坏数据容错：非法 JSON / 空串 / 结构不对 → 返回空数组，不抛异常', () => {
  assert.deepEqual(jsonToBlocks(''), []);
  assert.deepEqual(jsonToBlocks('{ 不是 json'), []);
  assert.deepEqual(jsonToBlocks('null'), []);
  assert.deepEqual(jsonToBlocks('{"blocks":"不是数组"}'), []);
  assert.deepEqual(jsonToBlocks('{}'), []);
});

// ── ⑥ 纯文本与字数 ───────────────────────────────────────────────────
test('纯文本：块之间用换行拼接', () => {
  const text: string = plainTextOf([block(BLOCK_TYPE_P, [span('一')]), block(BLOCK_TYPE_P, [span('二')])]);
  assert.equal(text, '一\n二');
});

test('字数：中日韩一字一数，西文按词', () => {
  assert.equal(wordCountOf([block(BLOCK_TYPE_P, [span('今天写了日记')])]), 6);
  assert.equal(wordCountOf([block(BLOCK_TYPE_P, [span('hello world')])]), 2);
  assert.equal(wordCountOf([block(BLOCK_TYPE_P, [span('我 love 鸿蒙')])]), 4); // 我/鸿蒙 2 + love/鸿蒙? → 我·love·鸿蒙
});

test('字数：emoji 按 1 计（代理对不能被数成 2）', () => {
  const n: number = wordCountOf([block(BLOCK_TYPE_P, [span('😀😀')])]);
  assert.equal(n, 2);
  assert.equal('😀'.length, 2); // 佐证：.length 确实是 2，所以必须用 Array.from
});
