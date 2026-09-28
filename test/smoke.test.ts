import { test } from 'node:test';
import assert from 'node:assert/strict';

import { APP_BUNDLE_NAME, APP_VERSION, APP_VERSION_CODE, APP_NAME_CN } from '../entry/src/main/ets/common/AppMeta';

test('应用元信息与 app.json5 声明一致', () => {
  // 包名写死为家族规范值 —— AppMeta 改了这里就会红，防止"元信息漂移"
  assert.equal(APP_BUNDLE_NAME, 'com.rocktier.rockjournal');
  assert.equal(APP_VERSION, '0.1.0');
  assert.equal(APP_VERSION_CODE, 10000);
  assert.equal(APP_NAME_CN, 'Rock私记');
});
