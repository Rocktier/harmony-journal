/**
 * `.rkd` 帧格式（**纯逻辑，不引任何 @kit** —— 可被单测直接跑）
 *
 * 布局（全部定长头 + 变长负载）：
 *   ┌────────┬─────────┬──────────┬───────────┬────────────────────┐
 *   │ magic  │ version │   salt   │   nonce   │  payload(ct‖tag)   │
 *   │  4B    │   1B    │   16B    │   12B     │   ≥16B             │
 *   └────────┴─────────┴──────────┴───────────┴────────────────────┘
 *
 * 为什么自己定义帧而不是直接存密文：
 *  ① salt / nonce 必须与密文同存，否则换一次密码或一个文件就解不开；
 *  ② magic + version 让"这个文件是不是我们的库"可被快速判断（不是就别拿去解密，
 *     否则会得到一堆乱码还以为成功了）；
 *  ③ 十年后即使实现换了，按这个布局也能读出来（兑现 Rock solid）。
 *
 * ⚠️ payload = 密文‖GCM tag(16B)：GCM 的 doFinal 输出就是这两段拼在一起，
 *    存的时候不拆开（少一次拷贝、少一处可能写错的偏移），解密前再切。
 */
export const RKD_MAGIC: number[] = [0x52, 0x4B, 0x44, 0x31]; // 'RKD1'
export const RKD_VERSION: number = 1;
export const SALT_LEN: number = 16;
export const NONCE_LEN: number = 12;
export const TAG_LEN: number = 16;
export const HEADER_LEN: number = 4 + 1 + SALT_LEN + NONCE_LEN;

export interface VaultFrame {
  version: number;
  salt: Uint8Array;
  nonce: Uint8Array;
  /** 密文‖tag */
  payload: Uint8Array;
}

export function encodeFrame(frame: VaultFrame): Uint8Array {
  const out: Uint8Array = new Uint8Array(HEADER_LEN + frame.payload.length);
  let p: number = 0;
  for (let i: number = 0; i < RKD_MAGIC.length; i++) {
    out[p++] = RKD_MAGIC[i];
  }
  out[p++] = frame.version;
  out.set(frame.salt, p);
  p += SALT_LEN;
  out.set(frame.nonce, p);
  p += NONCE_LEN;
  out.set(frame.payload, p);
  return out;
}

/**
 * 解析帧。**任何一处不对就返回 null**（不抛异常）——
 * 调用方拿 null 去走"文件损坏"分支，而不是让整篇日记打不开。
 */
export function decodeFrame(bytes: Uint8Array): VaultFrame | null {
  if (bytes === null || bytes === undefined || bytes.length < HEADER_LEN + TAG_LEN) {
    return null;
  }
  for (let i: number = 0; i < RKD_MAGIC.length; i++) {
    if (bytes[i] !== RKD_MAGIC[i]) {
      return null;
    }
  }
  const version: number = bytes[4];
  if (version !== RKD_VERSION) {
    return null;
  }
  let p: number = 5;
  const salt: Uint8Array = bytes.slice(p, p + SALT_LEN);
  p += SALT_LEN;
  const nonce: Uint8Array = bytes.slice(p, p + NONCE_LEN);
  p += NONCE_LEN;
  const payload: Uint8Array = bytes.slice(p);
  return { version: version, salt: salt, nonce: nonce, payload: payload };
}

/** 把 payload 切成「密文 + tag」（解密时用它构造 GcmParamsSpec） */
export function splitPayload(payload: Uint8Array): { ct: Uint8Array; tag: Uint8Array } | null {
  if (payload === null || payload === undefined || payload.length < TAG_LEN) {
    return null;
  }
  const cut: number = payload.length - TAG_LEN;
  return { ct: payload.slice(0, cut), tag: payload.slice(cut) };
}

/** 判断一个文件是不是我们的库（不解密，只看头） */
export function isRkdFile(bytes: Uint8Array): boolean {
  return decodeFrame(bytes) !== null;
}
