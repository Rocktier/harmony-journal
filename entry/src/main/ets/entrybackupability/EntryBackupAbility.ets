import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

/**
 * 系统备份/恢复钩子（换机克隆、华为云备份走这里）
 *
 * ⚠️ 2026-10-22 评审 P0-4 整改前：这里只有 hilog —— 声明了 allowToBackupRestore
 *   却不做任何事，等于把「备份是生命线」的产品叙事悬空。整改后职责：
 *
 *   onBackup：**清点并写 manifest**（明文，只有数量没有内容 —— 加密纪律不动摇）。
 *     恢复完成后拿它对账：少了几个文件立刻可见，而不是等用户某天点开才发现。
 *   onRestore：**读 manifest 对账**实际落盘的文件数，结果写 hilog
 *     （info = 齐了；error = 缺文件/缺密钥封装，后续排查有据可查）。
 *
 * ⚠️ 铁律：两个钩子**绝不抛异常** —— 抛了会中断系统备份流程，
 *   那才是真的把用户的生命线掐了。所有 IO 全部 try/catch 兜底。
 *
 * ⚠️ 主密钥封装 vault_pwd.key 落在 filesDir（includes 已声明）⇒ 跟着系统备份走；
 *   换机后用户输入原主密码即可解出密钥，数据可解密（密钥是密码 PBKDF2 封装的，
 *   备份它不等于备份明文密钥）。vault_bio.key 依赖本机 HUKS，换机必失效 ——
 *   留着无害（生物解锁失败自动降级主密码，NoteStoreHolder 已实测该路径）。
 */
const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

const NOTES_DIR: string = 'notes';
const IMG_DIR: string = 'img';
const INDEX_FILE: string = 'index.rkd';
const PWD_KEY: string = 'vault_pwd.key';
const BIO_KEY: string = 'vault_bio.key';
/** 备份清单文件名（落在 filesDir ⇒ 随数据一起被带走，恢复时可对账） */
const MANIFEST_FILE: string = 'backup_manifest.json';
/** manifest 里的版本号来源（与 AppMeta 同步维护） */
const MANIFEST_VER: number = 1000003;

/** 清点结果（只有数量与存在性，没有任何内容） */
interface VaultInventory {
  notes: number;
  images: number;
  hasIndex: boolean;
  hasPwdKey: boolean;
  hasBioKey: boolean;
}

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    try {
      const root: string = this.context.filesDir;
      const inv: VaultInventory = this.inventory(root);
      this.writeManifest(root, inv);
      hilog.info(DOMAIN, TAG,
        'onBackup: notes=%{public}d images=%{public}d index=%{public}s pwdKey=%{public}s manifest written',
        inv.notes, inv.images, inv.hasIndex ? 'y' : 'n', inv.hasPwdKey ? 'y' : 'n');
    } catch (e) {
      // 绝不向上抛（见类头注铁律）；清点失败不阻塞备份本身
      hilog.error(DOMAIN, TAG, 'onBackup inventory failed (backup itself continues): %{public}s', JSON.stringify(e));
    }
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    try {
      const root: string = this.context.filesDir;
      const now: VaultInventory = this.inventory(root);
      const was: VaultInventory | null = this.readManifest(root);
      hilog.info(DOMAIN, TAG, 'onRestore from version %{public}s/%{public}d: notes=%{public}d images=%{public}d',
        bundleVersion.name, bundleVersion.code, now.notes, now.images);
      if (was === null) {
        // 没有 manifest（老版本备份，或数据本来为空）——按实际清点记录，不判失败
        hilog.info(DOMAIN, TAG, 'onRestore: no manifest (legacy backup or empty vault)');
        return;
      }
      // 对账：文件数短了 = 恢复不完整，error 级留痕（比静默好一万倍）
      if (now.notes < was.notes || now.images < was.images) {
        hilog.error(DOMAIN, TAG,
          'onRestore INCOMPLETE: notes %{public}d/%{public}d images %{public}d/%{public}d (now/was)',
          now.notes, was.notes, now.images, was.images);
      } else {
        hilog.info(DOMAIN, TAG, 'onRestore verified: %{public}d notes, %{public}d images intact',
          now.notes, now.images);
      }
      if (!now.hasPwdKey) {
        // 密钥封装没跟过来 ⇒ 换机后密码解不开，全部密文成砖 —— 必须最高级别留痕
        hilog.error(DOMAIN, TAG, 'onRestore: vault_pwd.key MISSING (data will be undecryptable)');
      }
      if (!now.hasIndex) {
        hilog.error(DOMAIN, TAG, 'onRestore: index.rkd MISSING (vault will start empty)');
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onRestore verify failed (data already in place): %{public}s', JSON.stringify(e));
    }
  }

  /** 清点沙箱（全部只读操作；任何失败按"没有"处理，不抛） */
  private inventory(root: string): VaultInventory {
    const inv: VaultInventory = {
      notes: this.countExt(root + '/' + NOTES_DIR, '.rkd'),
      images: this.countExt(root + '/' + IMG_DIR, '.enc'),
      hasIndex: this.exists(root + '/' + INDEX_FILE),
      hasPwdKey: this.exists(root + '/' + PWD_KEY),
      hasBioKey: this.exists(root + '/' + BIO_KEY)
    };
    return inv;
  }

  /** 写清点 manifest：一行管道分隔文本（手拼手解，避开 ArkTS 对 JSON.parse 的类型约束） */
  private writeManifest(root: string, inv: VaultInventory): void {
    const line: string = 'v=' + MANIFEST_VER +
      '|notes=' + inv.notes +
      '|img=' + inv.images +
      '|idx=' + (inv.hasIndex ? 1 : 0) +
      '|pwd=' + (inv.hasPwdKey ? 1 : 0) +
      '|ts=' + Date.now();
    const file: fs.File = fs.openSync(root + '/' + MANIFEST_FILE,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, line);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 读 manifest（坏行/不存在 ⇒ null，调用方按"老备份"处理） */
  private readManifest(root: string): VaultInventory | null {
    const path: string = root + '/' + MANIFEST_FILE;
    if (!this.exists(path)) {
      return null;
    }
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size: number = fs.statSync(path).size;
      const buf: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buf);
      const line: string = new util.TextDecoder().decodeToString(new Uint8Array(buf));
      // "k=v|k=v|..." → map
      const parts: string[] = line.split('|');
      const map: Record<string, string> = {};
      for (let i: number = 0; i < parts.length; i++) {
        const kv: string[] = parts[i].split('=');
        if (kv.length === 2) {
          map[kv[0]] = kv[1];
        }
      }
      const n: number = Number(map['notes'] ?? '-1');
      const m: number = Number(map['img'] ?? '-1');
      if (n < 0 || m < 0) {
        return null;
      }
      const inv: VaultInventory = {
        notes: n,
        images: m,
        hasIndex: (map['idx'] ?? '0') === '1',
        hasPwdKey: (map['pwd'] ?? '0') === '1',
        hasBioKey: false // manifest 不记它（换机必失效，对账无意义）
      };
      return inv;
    } finally {
      fs.closeSync(file);
    }
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private countExt(dir: string, ext: string): number {
    try {
      const names: string[] = fs.listFileSync(dir);
      let n: number = 0;
      for (let i: number = 0; i < names.length; i++) {
        if (names[i].endsWith(ext)) {
          n++;
        }
      }
      return n;
    } catch (e) {
      return 0; // 目录不存在按 0
    }
  }
}
