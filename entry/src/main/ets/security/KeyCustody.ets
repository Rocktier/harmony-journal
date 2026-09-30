import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import huks from '@ohos.security.huks';

import { NONCE_LEN, TAG_LEN } from '../data/VaultFrame';

/**
 * 主密钥保管（决策 4：真·生物解锁）
 *
 * 设计：主密钥是一把随机的 AES-256，只活在内存里。它有两份"备份"，都在本机沙箱：
 *   ① 密码备份  vault_pwd.key —— KEK = PBKDF2(密码, salt) → AES-GCM 加密主密钥。
 *      忘密码 = 这份备份作废（但日记仍在，可用生物解锁，见下）。
 *   ② 生物备份  vault_bio.key —— HUKS 里生成一把「绑指纹/面容」的 AES key，
 *      用它把主密钥加密存盘。解锁时弹生物 → HUKS 解封主密钥到内存 → 直接进应用。
 *
 * ⚠️ 模拟器 / 无生物录入的设备：HUKS 的 USER_AUTH key 生成与 initSession 都会抛错，
 *    本模块全部 try/catch，生物路径失败绝不拖累密码路径（密码永远能解锁）。
 * ⚠️ 用户删了指纹：HUKS key 失效 → 生物路径抛错 → 自动降级主密码。两份备份互为兜底。
 * ⚠️ 所有 HUKS / crypto 调用都包 try/catch；本文件不引 UI，返回值/null 交给上层判断。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
const PBKDF2_ITERATIONS: number = 100000;
const KEY_SIZE: number = 32; // AES-256
const BIO_KEY_ALIAS: string = 'rockjournal_bio_unlock';
const PWD_FILE: string = 'vault_pwd.key';
const BIO_FILE: string = 'vault_bio.key';

/** 首次建库：生成随机主密钥，写入两份备份，返回主密钥字节（失败返 null） */
export async function setupVault(password: string, salt: Uint8Array, filesDir: string): Promise<Uint8Array | null> {
  try {
    const master: Uint8Array = randomBytes(KEY_SIZE);
    // ① 密码备份（必做）
    const kek: cryptoFramework.SymKey = deriveKek(password, salt);
    const iv: Uint8Array = randomBytes(NONCE_LEN);
    const enc: Uint8Array = aesGcmEncrypt(kek, iv, master);
    const pwdBlob: Uint8Array = new Uint8Array(iv.length + enc.length);
    pwdBlob.set(iv, 0);
    pwdBlob.set(enc, iv.length);
    writeFile(filesDir + '/' + PWD_FILE, pwdBlob);
    // ② 生物备份（尽力而为，失败不影响密码解锁）
    try {
      await setupBioKey();
      const biv: Uint8Array = randomBytes(NONCE_LEN);
      const encMaster: Uint8Array = await hukSeal(biv, master);
      const blob: Uint8Array = new Uint8Array(biv.length + encMaster.length);
      blob.set(biv, 0);
      blob.set(encMaster, biv.length);
      writeFile(filesDir + '/' + BIO_FILE, blob);
      hilog.info(DOMAIN, TAG, 'biometric vault enabled');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'biometric vault skipped (no biometric hardware / canceled): %{public}s', JSON.stringify(e));
    }
    return master;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'setupVault failed: %{public}s', JSON.stringify(e));
    return null;
  }
}

/** 用主密码解封主密钥（读 vault_pwd.key） */
export async function recoverByPassword(password: string, salt: Uint8Array, filesDir: string): Promise<Uint8Array | null> {
  try {
    const path: string = filesDir + '/' + PWD_FILE;
    if (!fs.accessSync(path)) {
      return null;
    }
    const blob: Uint8Array = readFile(path);
    const iv: Uint8Array = blob.subarray(0, NONCE_LEN);
    const enc: Uint8Array = blob.subarray(NONCE_LEN);
    const kek: cryptoFramework.SymKey = deriveKek(password, salt);
    return aesGcmDecrypt(kek, iv, enc);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'recoverByPassword failed: %{public}s', JSON.stringify(e));
    return null;
  }
}

/** 用生物解封主密钥（读 vault_bio.key → HUKS 解封；弹生物在此处触发） */
export async function recoverByBiometric(filesDir: string): Promise<Uint8Array | null> {
  try {
    const path: string = filesDir + '/' + BIO_FILE;
    if (!fs.accessSync(path)) {
      return null;
    }
    if (!(await huks.isKeyItemExist(BIO_KEY_ALIAS, { inData: new Uint8Array(0) }))) {
      return null;
    }
    const blob: Uint8Array = readFile(path);
    const iv: Uint8Array = blob.subarray(0, NONCE_LEN);
    const enc: Uint8Array = blob.subarray(NONCE_LEN);
    return await hukUnseal(iv, enc);
  } catch (e) {
    hilog.info(DOMAIN, TAG, 'recoverByBiometric unavailable (simulator / no biometrics / canceled): %{public}s', JSON.stringify(e));
    return null;
  }
}

/** 本机是否具备生物解锁（文件 + HUKS key 都在） */
export async function hasBiometric(filesDir: string): Promise<boolean> {
  try {
    const path: string = filesDir + '/' + BIO_FILE;
    if (!fs.accessSync(path)) {
      return false;
    }
    return await huks.isKeyItemExist(BIO_KEY_ALIAS, { inData: new Uint8Array(0) });
  } catch (e) {
    hilog.info(DOMAIN, TAG, 'hasBiometric false: %{public}s', JSON.stringify(e));
    return false;
  }
}

/** HUKS：生成绑生物的 AES key（首次建库调用一次） */
async function setupBioKey(): Promise<void> {
  await huks.generateKeyItem(BIO_KEY_ALIAS, {
    properties: [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: 0 }, // NONE
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: 0 }, // NONE
      { tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_ACCESS_TYPE, value: huks.HuksAuthAccessType.HUKS_AUTH_ACCESS_ALWAYS_VALID },
      {
        tag: huks.HuksTag.HUKS_TAG_USER_AUTH_TYPE,
        value: huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FINGERPRINT | huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FACE
      }
    ],
    inData: new Uint8Array(0)
  });
}

/** HUKS：用生物 key 加密主密钥（initSession 触发生物弹窗） */
async function hukSeal(iv: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
  const session: huks.HuksSessionHandle = await huks.initSession(BIO_KEY_ALIAS, {
    properties: [
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
      { tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_ACCESS_TYPE, value: huks.HuksAuthAccessType.HUKS_AUTH_ACCESS_ALWAYS_VALID },
      {
        tag: huks.HuksTag.HUKS_TAG_USER_AUTH_TYPE,
        value: huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FINGERPRINT | huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FACE
      },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
    ]
  });
  try {
    await huks.updateSession(session.handle, { inData: plain });
    const fin: huks.HuksReturnResult = await huks.finishSession(session.handle, { inData: new Uint8Array(0) });
    return fin.outData ?? new Uint8Array(0);
  } catch (e) {
    await huks.abortSession(session.handle, { inData: new Uint8Array(0) }).catch(() => {});
    throw new Error(JSON.stringify(e));
  }
}

/** HUKS：用生物 key 解密主密钥（initSession 触发生物弹窗） */
async function hukUnseal(iv: Uint8Array, ct: Uint8Array): Promise<Uint8Array> {
  const session: huks.HuksSessionHandle = await huks.initSession(BIO_KEY_ALIAS, {
    properties: [
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_KEY_AUTH_ACCESS_TYPE, value: huks.HuksAuthAccessType.HUKS_AUTH_ACCESS_ALWAYS_VALID },
      {
        tag: huks.HuksTag.HUKS_TAG_USER_AUTH_TYPE,
        value: huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FINGERPRINT | huks.HuksUserAuthType.HUKS_USER_AUTH_TYPE_FACE
      },
      { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
    ]
  });
  try {
    await huks.updateSession(session.handle, { inData: ct });
    const fin: huks.HuksReturnResult = await huks.finishSession(session.handle, { inData: new Uint8Array(0) });
    return fin.outData ?? new Uint8Array(0);
  } catch (e) {
    await huks.abortSession(session.handle, { inData: new Uint8Array(0) }).catch(() => {});
    throw new Error(JSON.stringify(e));
  }
}

/** PBKDF2(密码, salt) → AES-256 KEK（与 VaultService 同源参数） */
function deriveKek(password: string, salt: Uint8Array): cryptoFramework.SymKey {
  const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password: password,
    salt: salt,
    iterations: PBKDF2_ITERATIONS,
    keySize: KEY_SIZE
  };
  const secret: cryptoFramework.DataBlob = kdf.generateSecretSync(spec);
  const gen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
  return gen.convertKeySync(secret);
}

function aesGcmEncrypt(kek: cryptoFramework.SymKey, iv: Uint8Array, plain: Uint8Array): Uint8Array {
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
  const params: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: iv },
    aad: { data: new Uint8Array(0) },
    authTag: { data: new Uint8Array(TAG_LEN) }
  };
  cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, kek, params);
  return cipher.doFinalSync({ data: plain }).data;
}

function aesGcmDecrypt(kek: cryptoFramework.SymKey, iv: Uint8Array, enc: Uint8Array): Uint8Array | null {
  if (enc.length < TAG_LEN) {
    return null;
  }
  const ct: Uint8Array = enc.subarray(0, enc.length - TAG_LEN);
  const tag: Uint8Array = enc.subarray(enc.length - TAG_LEN);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES256|GCM|PKCS7');
  const params: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: iv },
    aad: { data: new Uint8Array(0) },
    authTag: { data: tag }
  };
  cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, kek, params);
  return cipher.doFinalSync({ data: ct }).data;
}

function randomBytes(n: number): Uint8Array {
  const rnd: cryptoFramework.Random = cryptoFramework.createRandom();
  return rnd.generateRandomSync(n)?.data ?? new Uint8Array(n);
}

function writeFile(path: string, bytes: Uint8Array): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, bytes.buffer);
  } finally {
    fs.closeSync(file);
  }
}

function readFile(path: string): Uint8Array {
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(path).size);
    fs.readSync(file.fd, buf);
    return new Uint8Array(buf);
  } finally {
    fs.closeSync(file);
  }
}
