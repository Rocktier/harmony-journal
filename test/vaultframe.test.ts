import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  HEADER_LEN, NONCE_LEN, RKD_VERSION, SALT_LEN, TAG_LEN, VaultFrame,
  decodeFrame, encodeFrame, isRkdFile, splitPayload
} from '../entry/src/main/ets/data/VaultFrame';

function seq(n: number, start: number = 0): Uint8Array {
  const a: Uint8Array = new Uint8Array(n);
  for (let i: number = 0; i < n; i++) {
    a[i] = (start + i) & 0xFF;
  }
  return a;
}

test('帧布局：定长头 33B（magic4 + version1 + salt16 + nonce12）', () => {
  assert.equal(HEADER_LEN, 33);
  assert.equal(SALT_LEN, 16);
  assert.equal(NONCE_LEN, 12);
  assert.equal(TAG_LEN, 16);
});

test('往返：salt / nonce / payload 逐字节保真', () => {
  const frame: VaultFrame = { version: RKD_VERSION, salt: seq(16, 1), nonce: seq(12, 100), payload: seq(64, 200) };
  const back: VaultFrame | null = decodeFrame(encodeFrame(frame));
  assert.ok(back !== null);
  if (back === null) {
    return;
  }
  assert.equal(back.version, RKD_VERSION);
  assert.deepEqual(Array.from(back.salt), Array.from(frame.salt));
  assert.deepEqual(Array.from(back.nonce), Array.from(frame.nonce));
  assert.deepEqual(Array.from(back.payload), Array.from(frame.payload));
});

test('magic 不对 → 不是我们的库（返回 null，不解密）', () => {
  const bytes: Uint8Array = encodeFrame({ version: RKD_VERSION, salt: seq(16), nonce: seq(12), payload: seq(32) });
  bytes[0] = 0x00;
  assert.equal(decodeFrame(bytes), null);
  assert.equal(isRkdFile(bytes), false);
});

test('版本不对 → 返回 null（将来换格式不会误读）', () => {
  const bytes: Uint8Array = encodeFrame({ version: 2, salt: seq(16), nonce: seq(12), payload: seq(32) });
  assert.equal(decodeFrame(bytes), null);
});

test('长度不足 / 空输入 → null（不抛异常）', () => {
  assert.equal(decodeFrame(new Uint8Array(0)), null);
  assert.equal(decodeFrame(seq(10)), null);
  assert.equal(decodeFrame(seq(HEADER_LEN)), null); // 有头无尾（连 tag 都不够）
});

test('正常文件能通过 isRkdFile', () => {
  const bytes: Uint8Array = encodeFrame({ version: RKD_VERSION, salt: seq(16), nonce: seq(12), payload: seq(32) });
  assert.equal(isRkdFile(bytes), true);
});

test('payload 切分：末 16B 是 GCM tag，其余是密文', () => {
  const payload: Uint8Array = seq(48, 7);
  const parts: { ct: Uint8Array; tag: Uint8Array } | null = splitPayload(payload);
  assert.ok(parts !== null);
  if (parts === null) {
    return;
  }
  assert.equal(parts.ct.length, 32);
  assert.equal(parts.tag.length, 16);
  assert.deepEqual(Array.from(parts.tag), Array.from(payload.slice(32)));
});

test('payload 太短（不足一个 tag）→ null', () => {
  assert.equal(splitPayload(new Uint8Array(15)), null);
});
