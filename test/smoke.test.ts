/**
 * 冒烟单测：验证 esbuild 编译管线 + 元信息与 app.json5 真一致。
 *
 * ⚠️ 2026-10-20 修：原版把期望值**写死**成 '0.1.0'/10000（项目最初的值），
 *    版本号升到 1.0.x 后这个测试必红 —— 而"防漂移"的测试自己成了漂移源。
 *    现在改为读 AppScope/app.json5 真比对：改哪边忘了另一边，这里就红。
 *    （app.json5 带注释不能 JSON.parse，用正则抠两个字段，够用且不引依赖。）
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { APP_BUNDLE_NAME, APP_VERSION, APP_VERSION_CODE, APP_NAME_CN } from '../entry/src/main/ets/common/AppMeta';

test('应用元信息与 app.json5 声明一致', () => {
  // 包名写死为家族规范值 —— AppMeta 改了这里就会红，防止"元信息漂移"
  assert.equal(APP_BUNDLE_NAME, 'com.rocktier.rockjournal');
  assert.equal(APP_NAME_CN, 'Rock私记');

  const raw: string = readFileSync(join(process.cwd(), 'AppScope/app.json5'), 'utf-8');
  const name: RegExpExecArray | null = /"versionName"\s*:\s*"([^"]+)"/.exec(raw);
  const code: RegExpExecArray | null = /"versionCode"\s*:\s*(\d+)/.exec(raw);
  assert.ok(name !== null, 'app.json5 里找不到 versionName');
  assert.ok(code !== null, 'app.json5 里找不到 versionCode');
  assert.equal(APP_VERSION, name![1]);
  assert.equal(APP_VERSION_CODE, Number(code![1]));
});
