import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { NONCE_LEN, PayloadParts, SALT_LEN, TAG_LEN, VaultFrame, decodeFrame, encodeFrame, splitPayload } from './VaultFrame';

/**
 * 加密 vault 服务（**设备端** —— 引 cryptoFramework，跑不了单测，靠装机实测）
 *
 * API 全部查 SDK `.d.ts` 核实过（家族规矩：不靠记忆）：
 *   `createKdf('PBKDF2|SHA256')` → `generateSecretSync(spec)` → DataBlob（32B）
 *   → `createSymKeyGenerator('AES256').convertKeySync(blob)` → SymKey
 *   → `createCipher('AES256|GCM|PKCS7')` + GcmParamsSpec（iv=nonce, authTag=tag）
 *
 * 参数选择的理由：
 *  - PBKDF2 迭代 **100_000**：手机端一次约 50~150ms，用户感知不到，
 *    但把离线暴力破解的成本抬高几个数量级（日记是唯一没有云兜底的数据）。
 *  - salt 每个文件**独立随机**：同一篇日记改一次密码重新加密，密文完全不同，
 *    攻击者无法判断两份文件是否同源。
 *  - nonce 每次加密**独立随机**：GCM 下 nonce 复用 = 密钥泄露级别的灾难，绝不复用。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
const PBKDF2_ITERATIONS: number = 100000;
const KEY_SIZE: number = 32; // AES-256

export class VaultService {
  /** 派生出的主密钥（只活在当前进程内存里，退出即销毁） */
  private key: cryptoFramework.SymKey | null = null;
  /**
   * 本 vault 的 salt（unlock 时传入并记住）。
   *
   * ⚠️ **设计铁律：一个 vault 一个 salt，所有文件共用**——
   * 曾实测踩坑：encrypt() 内部每次随机 salt 的话，每篇文件用不同 key 加密，
   * 同会话内（key 在内存）读写自洽，**跨会话必崩**（重启后按帧头 salt 派生的 key
   * 对不上任何历史数据，17630001）。nonce 必须每次随机，salt 必须永远固定。
   */
  private salt: Uint8Array = new Uint8Array(0);

  /** 是否已解锁 */
  isUnlocked(): boolean {
    return this.key !== null;
  }

  /** 用主密码解锁（PBKDF2 → AES-256 主密钥，只存内存） */
  async unlock(password: string, salt: Uint8Array): Promise<boolean> {
    try {
      const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
      // ArkTS：给 API 传参也不能用裸对象字面量，先落到 SDK 声明的类型变量
      const spec: cryptoFramework.PBKDF2Spec = {
        algName: 'PBKDF2',
        password: password,
        salt: salt,
        iterations: PBKDF2_ITERATIONS,
        keySize: KEY_SIZE
      };
      const secret: cryptoFramework.DataBlob = kdf.generateSecretSync(spec);
      const gen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      this.key = gen.convertKeySync(secret);
      this.salt = salt;
      hilog.info(DOMAIN, TAG, 'unlocked');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'unlock failed: %{public}s', JSON.stringify(e));
      this.key = null;
      return false;
    }
  }

  /** 锁上（清掉内存里的密钥 —— 生物不可用时的兜底路径） */
  lock(): void {
    this.key = null;
    hilog.info(DOMAIN, TAG, 'locked');
  }

  /** 加密：产出完整 .rkd 帧字节（salt = 本 vault 固定值；nonce 每次随机） */
  encrypt(plain: Uint8Array): Uint8Array | null {
    if (this.key === null) {
      hilog.error(DOMAIN, TAG, 'encrypt before unlock');
      return null;
    }
    try {
      const nonce: Uint8Array = this.random(NONCE_LEN);
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: new Uint8Array(TAG_LEN) }
      };
      cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, this.key, params);
      // GCM 的 doFinal 输出 = 密文‖tag
      const out: cryptoFramework.DataBlob = cipher.doFinalSync({ data: plain });
      const frame: VaultFrame = { version: 1, salt: this.salt, nonce: nonce, payload: out.data };
      return encodeFrame(frame);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'encrypt failed: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  /** 解密：吃掉一个 .rkd 帧，吐出明文。密码错 / 文件坏 → null（绝不返回半截乱码） */
  decrypt(frameBytes: Uint8Array): Uint8Array | null {
    if (this.key === null) {
      hilog.error(DOMAIN, TAG, 'decrypt before unlock');
      return null;
    }
    const frame: VaultFrame | null = decodeFrame(frameBytes);
    if (frame === null) {
      hilog.error(DOMAIN, TAG, 'not a valid rkd frame');
      return null;
    }
    const parts: PayloadParts | null = splitPayload(frame.payload);
    if (parts === null) {
      return null;
    }
    try {
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: frame.nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: parts.tag }
      };
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, this.key, params);
      const out: cryptoFramework.DataBlob = cipher.doFinalSync({ data: parts.ct });
      return out.data;
    } catch (e) {
      // GCM 校验失败 = 密码错或文件被改 —— 两者对用户的处理是一样的：打不开
      hilog.error(DOMAIN, TAG, 'decrypt failed (wrong password or corrupted): %{public}s', JSON.stringify(e));
      return null;
    }
  }

  /** 从已有文件里取出 salt（换密码不改数据时复用；解锁前必须先拿到它） */
  saltOf(frameBytes: Uint8Array): Uint8Array | null {
    const frame: VaultFrame | null = decodeFrame(frameBytes);
    return frame === null ? null : frame.salt;
  }

  /**
   * 新库的 salt（首次使用时生成一次，之后随索引文件存下来）。
   * 索引文件本身就是 .rkd 帧，salt 就在帧头里 —— 不需要额外的"密码文件"。
   */
  newSalt(): Uint8Array {
    return this.random(SALT_LEN);
  }

  private random(n: number): Uint8Array {
    const rnd: cryptoFramework.Random = cryptoFramework.createRandom();
    return rnd.generateRandomSync(n)?.data ?? new Uint8Array(n);
  }
}
