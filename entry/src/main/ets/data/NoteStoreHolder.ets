import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { DEV_PASSWORD, DEV_UNLOCK_BYPASS } from '../common/DevFlags';
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

export function getStore(): NoteStore {
  if (instance === null) {
    instance = new NoteStore();
  }
  return instance;
}

/**
 * 启动初始化：建目录 → 取/建 salt → 解锁 → 载入索引
 *
 * 开发期（DEV_UNLOCK_BYPASS）直接用预设密码解锁，不弹锁（党哥 2026-09-28 定）。
 * 正式版：这里换成"解锁页"——生物优先、主密码兜底（见 task_plan Phase 8 待办）。
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
    hilog.info(DOMAIN, TAG, 'first run: new salt generated');
  }

  const password: string = DEV_UNLOCK_BYPASS ? DEV_PASSWORD : DEV_PASSWORD; // 正式版走解锁页拿密码
  const ok: boolean = await store.getVault().unlock(password, salt);
  if (!ok) {
    hilog.error(DOMAIN, TAG, 'bootstrap unlock failed');
    return false;
  }
  store.loadIndex();
  if (!fs.accessSync(indexPath)) {
    store.saveIndex(); // 首次运行：把 salt 随空索引落盘
  }
  return true;
}
