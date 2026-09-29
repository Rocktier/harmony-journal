import huks from '@ohos.security.huks';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 生物解锁层（决策 4：对接生物加密机制）
 *
 * 设计：**主密钥仍由密码 PBKDF2 派生、加解密走 cryptoFramework（已验证跨会话）**；
 * HUKS 只做「生物即开」的认证层 —— 把一把 AES key 存进 HUKS 并绑生物（指纹/面容），
 * 解锁时优先弹生物，通过即放行。
 *
 * ⚠️ 模拟器无生物录入 → initSession 必抛错 → tryBioUnlock 返 false → 解锁页降级到主密码。
 *    HUKS「主密钥保管」（生物通过后解封主密钥到内存）留作真机专项，本层只做认证。
 * ⚠️ 所有 HUKS 调用 try/catch：HUKS 失败绝不影响主密码解锁链路（加密核心绝不回归）。
 * ⚠️ 常量全部来自 SDK `.d.ts`（@ohos.security.huks）：export default huks 命名空间，
 *    HUKS_TAG_* 在 huks.HuksTag、HUKS_KEY_PURPOSE_* 在 huks.HuksKeyPurpose、
 *    HUKS_USER_AUTH_TYPE_* 在 huks.HuksUserAuthType、HUKS_ALG_AES 在 huks.HuksKeyAlg。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
const BIO_KEY_ALIAS: string = 'rockjournal_bio_unlock';

/** 首次建库时调用：存一把绑生物的 AES key（仅用于认证挑战，内容随机无意义） */
export async function ensureBioKey(): Promise<void> {
  try {
    const rnd: cryptoFramework.Random = cryptoFramework.createRandom();
    const keyBlob: Uint8Array = rnd.generateRandomSync(32)?.data ?? new Uint8Array(32);
    await huks.importKeyItem(BIO_KEY_ALIAS, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
        },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: 1 }, // 1 = GCM
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: 0 }, // 0 = NONE
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: 0 }, // 0 = NONE
        { tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_ACCESS_TYPE, value: huks.HuksAuthAccessType.HUKS_AUTH_ACCESS_ALWAYS_VALID },
        {
          tag: huks.HuksTag.HUKS_TAG_USER_AUTH_TYPE,
          value: huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FINGERPRINT | huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FACE
        }
      ],
      inData: keyBlob
    });
    hilog.info(DOMAIN, TAG, 'bio key ensured');
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'ensureBioKey skipped: %{public}s', JSON.stringify(e));
  }
}

/** 尝试生物解锁：弹生物认证，通过返 true；无生物/失败/取消返 false（降级主密码） */
export async function tryBioUnlock(): Promise<boolean> {
  try {
    const rnd: cryptoFramework.Random = cryptoFramework.createRandom();
    const nonce: Uint8Array = rnd.generateRandomSync(12)?.data ?? new Uint8Array(12);
    const session: huks.HuksSessionHandle = await huks.initSession(BIO_KEY_ALIAS, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_ACCESS_TYPE, value: huks.HuksAuthAccessType.HUKS_AUTH_ACCESS_ALWAYS_VALID },
        {
          tag: huks.HuksTag.HUKS_TAG_USER_AUTH_TYPE,
          value: huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FINGERPRINT | huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FACE
        },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: nonce }
      ]
    });
    const handle: number = session.handle;
    await huks.finishSession(handle, { inData: new Uint8Array(8) });
    return true;
  } catch (e) {
    hilog.info(DOMAIN, TAG, 'bio unlock unavailable (simulator / no biometrics): %{public}s', JSON.stringify(e));
    return false;
  }
}
