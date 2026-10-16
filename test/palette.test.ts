/**
 * 色板单测：**与 color.json 逐值比对**，防"改了资源忘了 TS"两边漂移。
 *
 * 背景：深浅色运行时切换不走 setColorMode（炸页面栈，见 ThemePalette 头注），
 * 改走 AppStorage 色板 ⇒ color.json 与 ThemePalette 两份值必须永远一致。
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert';

import { PALETTE_KEYS, ThemePalette, paletteFor } from '../entry/src/main/ets/theme/ThemePalette';

function loadColorJson(qualifier: string): Record<string, string> {
  const raw: string = readFileSync(
    join(process.cwd(), 'entry/src/main/resources', qualifier, 'element/color.json'), 'utf-8');
  const parsed: { color: { name: string; value: string }[] } = JSON.parse(raw);
  const out: Record<string, string> = {};
  for (const item of parsed.color) {
    out[item.name] = item.value;
  }
  return out;
}

const light: Record<string, string> = loadColorJson('base');
const dark: Record<string, string> = loadColorJson('dark');

test('浅色板与 base/color.json 逐个 token 一致', () => {
  const p: ThemePalette = paletteFor(false);
  assert.equal(p.dark, false);
  for (const k of PALETTE_KEYS) {
    assert.equal((p as unknown as Record<string, string>)[k], light['rj_' + k],
      '浅色 token rj_' + k + ' 与 color.json 不一致');
  }
});

test('深色板与 dark/color.json 逐个 token 一致', () => {
  const p: ThemePalette = paletteFor(true);
  assert.equal(p.dark, true);
  for (const k of PALETTE_KEYS) {
    assert.equal((p as unknown as Record<string, string>)[k], dark['rj_' + k],
      '深色 token rj_' + k + ' 与 color.json 不一致');
  }
});

test('深浅两套必须真的有区别（防止误把同一份值填两边）', () => {
  const l: ThemePalette = paletteFor(false);
  const d: ThemePalette = paletteFor(true);
  assert.notEqual(l.bg, d.bg, '底色两套相同 = 切换无效果');
  assert.notEqual(l.text, d.text, '正文色两套相同 = 切换无效果');
  assert.notEqual(l.accent, d.accent, '强调色两套相同 = 切换无效果');
});

test('色板互不共享（每次构造新对象，AppStorage 换引用才能触发重绘）', () => {
  const a: ThemePalette = paletteFor(false);
  const b: ThemePalette = paletteFor(false);
  assert.notEqual(a, b, '同一个实例被复用 ⇒ AppStorage.Set 同对象不会触发 @StorageLink 更新');
});

test('PALETTE_KEYS 覆盖 color.json 全部 rj_ 前缀 token', () => {
  for (const k of PALETTE_KEYS) {
    assert.ok(light['rj_' + k] !== undefined, 'color.json(base) 缺少 rj_' + k);
    assert.ok(dark['rj_' + k] !== undefined, 'color.json(dark) 缺少 rj_' + k);
  }
});
