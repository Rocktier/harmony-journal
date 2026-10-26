import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  APPEARANCE_DARK, APPEARANCE_LIGHT, APPEARANCE_SYSTEM, appearanceLabel,
  isDarkMode, isSystemDarkColorMode, nextAppearance, normalizeAppearance, paletteNeedsRefresh, resolveDark
} from '../entry/src/main/ets/common/Appearance';

test('未知值一律回落「跟随系统」（默认值必须是不打扰）', () => {
  assert.equal(normalizeAppearance(''), APPEARANCE_SYSTEM);
  assert.equal(normalizeAppearance('DARK'), APPEARANCE_SYSTEM);      // 大小写敏感
  assert.equal(normalizeAppearance('深色'), APPEARANCE_SYSTEM);
  assert.equal(normalizeAppearance('night'), APPEARANCE_SYSTEM);
  assert.equal(normalizeAppearance(APPEARANCE_DARK), APPEARANCE_DARK);
  assert.equal(normalizeAppearance(APPEARANCE_LIGHT), APPEARANCE_LIGHT);
  assert.equal(normalizeAppearance(APPEARANCE_SYSTEM), APPEARANCE_SYSTEM);
});

test('切换顺序：跟随 → 深色 → 浅色 → 跟随（深色排在前，因为夜间写日记是高频）', () => {
  assert.equal(nextAppearance(APPEARANCE_SYSTEM), APPEARANCE_DARK);
  assert.equal(nextAppearance(APPEARANCE_DARK), APPEARANCE_LIGHT);
  assert.equal(nextAppearance(APPEARANCE_LIGHT), APPEARANCE_SYSTEM);
  // 走一圈回到原点
  let m: string = APPEARANCE_SYSTEM;
  for (let i = 0; i < 3; i++) {
    m = nextAppearance(m);
  }
  assert.equal(m, APPEARANCE_SYSTEM);
});

test('跟随系统时不知道当前深浅 → isDarkMode 返回 null（图标画"半填充圆"）', () => {
  assert.equal(isDarkMode(APPEARANCE_SYSTEM), null);
  assert.equal(isDarkMode(APPEARANCE_DARK), true);
  assert.equal(isDarkMode(APPEARANCE_LIGHT), false);
});

test('显示名三档齐全（图标已改自绘 Path，见 components/AppearanceIconButton）', () => {
  assert.equal(appearanceLabel(APPEARANCE_SYSTEM), '跟随系统');
  assert.equal(appearanceLabel(APPEARANCE_DARK), '深色');
  assert.equal(appearanceLabel(APPEARANCE_LIGHT), '浅色');
});

test('resolveDark：跟随系统 ⇒ 取系统当前深浅（华为反馈「跟随系统无变化」的守门）', () => {
  // 这条是本 bug 的核心：旧代码用 isDarkMode(mode) === true 定色板，
  // 而 isDarkMode('system') 是 null ⇒ 恒 false ⇒ 跟随系统永远浅色。
  assert.equal(isDarkMode(APPEARANCE_SYSTEM), null);          // 前提：跟随态"不知道"
  assert.equal(resolveDark(APPEARANCE_SYSTEM, true), true);
  assert.equal(resolveDark(APPEARANCE_SYSTEM, false), false);
  // 显式选择不能被系统覆盖
  assert.equal(resolveDark(APPEARANCE_DARK, false), true);
  assert.equal(resolveDark(APPEARANCE_LIGHT, true), false);
});

// ─────────────────────────────────────────────────────────────
// 2026-10-26 华为复评反馈的守门：
// 「选择跟随系统，打开系统深色模式后，需切换其他模式重新选择跟随系统才可变为深色」
// ─────────────────────────────────────────────────────────────

test('isSystemDarkColorMode：只有 DARK(0) 算深色，LIGHT(1)/NOT_SET(-1) 都算浅色', () => {
  // ⚠️ 数值抄自 SDK ConfigurationConstant.ColorMode：DARK=0、LIGHT=1、NOT_SET=-1
  assert.equal(isSystemDarkColorMode(0), true);
  assert.equal(isSystemDarkColorMode(1), false);
  assert.equal(isSystemDarkColorMode(-1), false);
});

test('paletteNeedsRefresh：跟随系统 + 系统深浅变了 ⇒ 必须重算（这就是本次 bug 的守门）', () => {
  // 场景复现：跟随系统（色板浅）→ 系统切深色 → 需要重算
  assert.equal(paletteNeedsRefresh(APPEARANCE_SYSTEM, true, false), true);
  // 系统切回浅色 ⇒ 也要重算
  assert.equal(paletteNeedsRefresh(APPEARANCE_SYSTEM, false, true), true);
  // 深浅一致 ⇒ 不用白换一次 palette（避免无谓重绘）
  assert.equal(paletteNeedsRefresh(APPEARANCE_SYSTEM, true, true), false);
  assert.equal(paletteNeedsRefresh(APPEARANCE_SYSTEM, false, false), false);
});

test('paletteNeedsRefresh：显式选了深/浅 ⇒ 系统怎么变都不动（用户选择优先）', () => {
  assert.equal(paletteNeedsRefresh(APPEARANCE_DARK, false, false), false);
  assert.equal(paletteNeedsRefresh(APPEARANCE_DARK, true, true), false);
  assert.equal(paletteNeedsRefresh(APPEARANCE_LIGHT, true, true), false);
  assert.equal(paletteNeedsRefresh(APPEARANCE_LIGHT, false, false), false);
});
