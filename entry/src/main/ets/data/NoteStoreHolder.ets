import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { NoteStore } from './NoteStore';
import { setupVault as custodySetup, recoverByPassword, recoverByBiometric, hasBiometric as custodyHasBio } from '../security/KeyCustody';

/**
 * 全局唯一的 store（**进程级单例**）
 *
 * 为什么必须单例：主密钥只在内存里（解锁后才有），
 * 每个页面各 new 一个 store = 各持一个没解锁的 vault = 读写全部失败。
 * 所以由 EntryAbility 在启动时解锁一次，页面共享它。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
const INDEX_FILE: string = 'index.rkd';

let instance: NoteStore | null = null;
/** 当前 vault 的固定 salt（unlock 时传入并记住；详见 VaultService 设计铁律） */
let vaultSalt: Uint8Array = new Uint8Array(0);
/** 是否首次运行（解锁页据此切「设置密码」/「输入密码」） */
let firstRun: boolean = false;
/** 应用沙箱根目录（保管文件 vault_pwd.key / vault_bio.key 落这里） */
let vaultRoot: string = '';

export function getStore(): NoteStore {
  if (instance === null) {
    instance = new NoteStore();
  }
  return instance;
}

/**
 * 启动准备（替代原 bootstrap 的「自动解锁」）：建目录 → 取/建 salt → **不解锁**。
 * 解锁移到 pages/Unlock.ets（主密码 / 生物），解锁后才进 Index。
 * 返回 true 表示 store 已 open、salt 已就绪。
 */
export async function bootstrap(ctx: common.UIAbilityContext): Promise<boolean> {
  const store: NoteStore = getStore();
  store.open(ctx);

  const indexPath: string = ctx.filesDir + '/' + INDEX_FILE;
  let salt: Uint8Array | null = null;
  if (fs.accessSync(indexPath)) {
    const file: fs.File = fs.openSync(indexPath, fs.OpenMode.READ_ONLY);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(indexPath).size);
      fs.readSync(file.fd, buf);
      salt = store.getVault().saltOf(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }
  if (salt === null) {
    salt = store.getVault().newSalt();
    firstRun = true;
    hilog.info(DOMAIN, TAG, 'first run: new salt generated');
  }
  vaultSalt = salt;
  vaultRoot = ctx.filesDir;
  return true;
}

/** 当前 vault 的 salt（解锁页用） */
export function getSalt(): Uint8Array {
  return vaultSalt;
}

/** 是否首次运行 */
export function isFirstRun(): boolean {
  return firstRun;
}

/**
 * 首次运行建库（解锁页调用）：生成随机主密钥、写两份备份（密码 + 生物）、载入空索引。
 * 失败（极少，多为 IO 异常）返 false，解锁页提示重试。
 */
export async function setupVault(password: string): Promise<boolean> {
  const master: Uint8Array | null = await custodySetup(password, vaultSalt, vaultRoot);
  if (master === null) {
    return false;
  }
  getStore().getVault().setKeyFromRaw(master, vaultSalt);
  if (firstRun) {
    getStore().saveIndex();
    firstRun = false;
    hilog.info(DOMAIN, TAG, 'first run: vault setup, index saved');
  }
  return true;
}

/**
 * 用主密码解锁（解锁页调用）：KeyCustody 用 PBKDF2 解封主密钥 → 载入索引。
 * ⚠️ 与 DevFlags.DEV_UNLOCK_BYPASS 无关：正式版只用用户输入的密码。
 */
export async function unlockWith(password: string): Promise<boolean> {
  const master: Uint8Array | null = await recoverByPassword(password, vaultSalt, vaultRoot);
  if (master === null) {
    return false;
  }
  getStore().getVault().setKeyFromRaw(master, vaultSalt);
  const idxOk: boolean = getStore().loadIndex();
  if (!idxOk) {
    // 主密钥解出了，但索引解不开：密码错 或 数据被别的密钥加密/损坏。
    // 绝不能放行进空主页（用户会以为日记全没了），拦在解锁页报错。
    hilog.error(DOMAIN, TAG, 'index load failed after unlock, abort (wrong password or corrupted data)');
    getStore().getVault().lock();
    return false;
  }
  if (firstRun) {
    getStore().saveIndex();
    firstRun = false;
    hilog.info(DOMAIN, TAG, 'first run: index saved, salt persisted');
  }
  return true;
}

/**
 * 用生物解锁（解锁页调用）：HUKS 弹指纹/面容 → 解封主密钥 → 载入索引。
 * 失败（无生物/取消/模拟器）返 false，解锁页自动降级主密码，绝不卡死。
 */
export async function unlockWithBiometric(): Promise<boolean> {
  const master: Uint8Array | null = await recoverByBiometric(vaultRoot);
  if (master === null) {
    return false;
  }
  getStore().getVault().setKeyFromRaw(master, vaultSalt);
  const idxOk: boolean = getStore().loadIndex();
  if (!idxOk) {
    hilog.error(DOMAIN, TAG, 'index load failed after biometric unlock');
    getStore().getVault().lock();
    return false;
  }
  return true;
}

/** 本机是否支持生物解锁（UI 据此显示「使用指纹/面容解锁」按钮） */
export async function hasBiometric(): Promise<boolean> {
  return await custodyHasBio(vaultRoot);
}
