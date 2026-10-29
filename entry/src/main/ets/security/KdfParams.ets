/**
 * PBKDF2 派生参数（**纯逻辑，不引任何 SDK** —— 因此可以跑单测）
 *
 * 为什么单独抽一个文件：这是**安全关键参数**，一旦漂移，老用户就再也打不开
 * 自己的日记（主密钥解不出来 = 数据还在但进不去）。历史上踩过的坑就是
 * "salt 变了 / 算法名变了 / 迭代次数变了 ⇒ 派生结果全变 ⇒ 整库锁死"。
 *
 * 所以参数在这里**唯一落一处**，由单测锁住：
 *   - algName 必须是 'PBKDF2'
 *   - 算法串必须是 'PBKDF2|SHA256'
 *   - iterations 必须是 100000（安全下限，见 VaultService 头注的论证）
 *   - keySize 必须是 32（AES-256）
 *
 * ⚠️ 迭代次数**不是性能旋钮**：本次性能整改动的是「在哪个线程跑」，
 *    不是「算多少次」（见 security/KeyCustody.ets 的 deriveKek 注释）。
 *    真要调低迭代数，必须先有安全侧的签字 + 老库迁移方案。
 */

/** PBKDF2 的算法名（PBKDF2Spec.algName） */
export const KDF_ALG_NAME: string = 'PBKDF2';

/**
 * createKdf 的算法串：**算法 + HMAC 摘要算法**
 * ⚠️ 写成 'PBKDF2'（少了 |SHA256）会派生��**完全不同的密钥** ⇒ 老库全锁死。
 */
export const KDF_ALG: string = 'PBKDF2|SHA256';

/** 迭代次数（安全参数，见文件头注：不要为了快而调低） */
export const PBKDF2_ITERATIONS: number = 100000;

/** 派生密钥字节长度（AES-256 = 32 字节） */
export const KDF_KEY_SIZE: number = 32;

/** 派生参数快照（纯数据，便于单测断言，也便于日志留证） */
export interface KdfParams {
  algName: string;
  password: string;
  saltLength: number;
  iterations: number;
  keySize: number;
}

/**
 * 从 password + salt 取出派生参数快照。
 * 真实调用（cryptoFramework.PBKDF2Spec）见 security/KeyCustody.ets 的 deriveKek。
 */
export function kdfParamsOf(password: string, salt: Uint8Array): KdfParams {
  return {
    algName: KDF_ALG_NAME,
    password: password,
    saltLength: salt.length,
    iterations: PBKDF2_ITERATIONS,
    keySize: KDF_KEY_SIZE
  };
}
