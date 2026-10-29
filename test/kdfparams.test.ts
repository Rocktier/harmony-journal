/**
 * PBKDF2 派生参数守门测试（2026-10-29，AGC 点击时延整改时顺带补上）
 *
 * 为什么必须有：这次性能整改把 KDF 从同步版换成异步版（`generateSecret` →
 * `generateSecret(spec): Promise`）。两版**共用同一套 spec**，所以老库才能照常打开。
 * 但这个"共用同一套 spec"的前提，靠的是**下面这几个参数一字不变**：
 *   - 算法串 'PBKDF2|SHA256'（少写 |SHA256 ⇒ 派生结果完全不同 ⇒ 老库全锁死）
 *   - algName 'PBKDF2'
 *   - 迭代次数 100000
 *   - 密钥长度 32（AES-256）
 * 谁改了这些 ⇒ 用户的日记再也打不开（数据还在，进不去）。
 * 所以把它们锁进单测：改参数 = 测试红 = 改不动。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  KDF_ALG, KDF_ALG_NAME, KDF_KEY_SIZE, PBKDF2_ITERATIONS, kdfParamsOf
} from '../entry/src/main/ets/security/KdfParams.ets';

test('KDF 算法串必须是 PBKDF2|SHA256（少了 |SHA256 就派生不出同一个密钥）', () => {
  assert.equal(KDF_ALG, 'PBKDF2|SHA256');
});

test('PBKDF2Spec 的 algName 必须是 PBKDF2', () => {
  assert.equal(KDF_ALG_NAME, 'PBKDF2');
});

test('迭代次数锁定 100000（安全参数，不是性能旋钮）', () => {
  assert.equal(PBKDF2_ITERATIONS, 100000);
});

test('派生密钥长度锁定 32 字节（AES-256）', () => {
  assert.equal(KDF_KEY_SIZE, 32);
});

test('派生参数快照：算法名与长度按输入如实带出', () => {
  const p = kdfParamsOf('mypassword', new Uint8Array(16));
  assert.equal(p.algName, 'PBKDF2');
  assert.equal(p.password, 'mypassword');
  assert.equal(p.saltLength, 16);
  assert.equal(p.iterations, 100000);
  assert.equal(p.keySize, 32);
});

test('派生参数快照：salt 长度随实际取值走（不做截断/补齐）', () => {
  assert.equal(kdfParamsOf('x', new Uint8Array(0)).saltLength, 0);
  assert.equal(kdfParamsOf('x', new Uint8Array(32)).saltLength, 32);
});
