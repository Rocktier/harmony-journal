import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  APPEARANCE_DARK, APPEARANCE_LIGHT, APPEARANCE_SYSTEM, appearanceIcon, appearanceLabel,
  isDarkMode, nextAppearance, normalizeAppearance
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

test('跟随系统时不知道当前深浅 → isDarkMode 返回 null（按钮只能显示"随"）', () => {
  assert.equal(isDarkMode(APPEARANCE_SYSTEM), null);
  assert.equal(isDarkMode(APPEARANCE_DARK), true);
  assert.equal(isDarkMode(APPEARANCE_LIGHT), false);
});

test('显示名与图标三档齐全', () => {
  assert.equal(appearanceLabel(APPEARANCE_SYSTEM), '跟随系统');
  assert.equal(appearanceLabel(APPEARANCE_DARK), '深色');
  assert.equal(appearanceLabel(APPEARANCE_LIGHT), '浅色');
  assert.equal(appearanceIcon(APPEARANCE_DARK), '夜');
  assert.equal(appearanceIcon(APPEARANCE_LIGHT), '昼');
  assert.equal(appearanceIcon(APPEARANCE_SYSTEM), '随');
});
