import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { NoteStore } from './NoteStore';

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
 * 用主密码解锁（解锁页调用）：PBKDF2 派生主密钥 → 载入索引。
 * 首次运行且解锁成功 → 把 salt 随空索引落盘。
 * ⚠️ 与 DevFlags.DEV_UNLOCK_BYPASS 无关：正式版只用用户输入的密码。
 */
export async function unlockWith(password: string): Promise<boolean> {
  const ok: boolean = await getStore().getVault().unlock(password, vaultSalt);
  if (!ok) {
    return false;
  }
  getStore().loadIndex();
  if (firstRun) {
    getStore().saveIndex();
    firstRun = false;
    hilog.info(DOMAIN, TAG, 'first run: index saved, salt persisted');
  }
  return true;
}
