import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Block, Span } from '../entry/src/main/ets/data/NoteBlocks';
import {
  blocksToLines, blockTypeOfLine, linesToBlocks, markdownTransform, stripPrefix
} from '../entry/src/main/ets/data/NoteBridge';

function span(text: string, bold: boolean = false, italic: boolean = false): Span {
  return { text: text, bold: bold, italic: italic };
}

test('行前缀识别：`# ` 标题、`- ` 列表、其余正文', () => {
  assert.equal(blockTypeOfLine('# 标题'), 'h');
  assert.equal(blockTypeOfLine('- 条目'), 'li');
  assert.equal(blockTypeOfLine('普通段落'), 'p');
  assert.equal(blockTypeOfLine('正文里的 - 短横'), 'p');  // 只有行首才算
});

test('去前缀：只切行首那一份', () => {
  assert.equal(stripPrefix('# 标题'), '标题');
  assert.equal(stripPrefix('- 条目'), '条目');
  assert.equal(stripPrefix('普通'), '普通');
  assert.equal(stripPrefix('# 还有个 # 号'), '还有个 # 号');
});

test('行 → 块：样式（粗/斜）在转换后保留', () => {
  const blocks: Block[] = linesToBlocks([[span('# 标题'), span('加粗', true)]]);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].type, 'h');
  assert.equal(blocks[0].spans[0].text, '标题');
  assert.equal(blocks[0].spans[1].text, '加粗');
  assert.equal(blocks[0].spans[1].bold, true);
});

test('行 → 块：只有前缀、没有正文的行被丢弃（不产生空块）', () => {
  const blocks: Block[] = linesToBlocks([[span('# ')]]);
  assert.equal(blocks.length, 0);
});

test('块 → 行 → 块 往返：一篇混合日记还原后结构不变', () => {
  const blocks: Block[] = [
    { type: 'h', spans: [span('今天')], ref: '' },
    { type: 'p', spans: [span('去了公园')], ref: '' },
    { type: 'li', spans: [span('带伞')], ref: '' }
  ];
  const lines: string[] = blocksToLines(blocks);
  assert.deepEqual(lines, ['# 今天', '去了公园', '- 带伞']);
  const back: Block[] = linesToBlocks(lines.map((s: string) => [span(s)]));
  assert.equal(back.length, 3);
  assert.equal(back[0].type, 'h');
  assert.equal(back[1].type, 'p');
  assert.equal(back[2].type, 'li');
  assert.equal(back[0].spans[0].text, '今天');
});

test('Markdown 快捷键：输入 # 或 - 的行首触发转换', () => {
  assert.deepEqual(markdownTransform('#'), { prefix: '# ', rest: '' });
  assert.deepEqual(markdownTransform('-'), { prefix: '- ', rest: '' });
  assert.equal(markdownTransform('普通'), null);
});

test('图片块不回灌进文本行（MVP 阶段），但数据不丢（仍在 JSON）', () => {
  const blocks: Block[] = [
    { type: 'p', spans: [span('看图')], ref: '' },
    { type: 'img', spans: [], ref: 'img/a.enc' }
  ];
  const lines: string[] = blocksToLines(blocks);
  assert.equal(lines.length, 1);
  assert.equal(blocks[1].ref, 'img/a.enc');
});
