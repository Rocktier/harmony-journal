import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { VaultService } from './VaultService';

/**
 * 图片存储（加密落盘，正文只存引用）
 *
 * 评估文档六½ 实测：`RichEditor` 的图片 span 拿到的是 **PixelMap / Resource**，不是路径 ——
 * 所以"图片独立加密存文件、正文只存 ref"是**技术上必须的**，不是设计偏好。
 *
 * 流程：选图（系统照片选择器）→ 读原文件 → 用主密钥加密 → 写 `img/<id>.enc`
 *      正文里只留 `img/<id>.enc` 这个相对路径。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';
const IMG_DIR: string = 'img';
const IMG_EXT: string = '.enc';

export class ImageStore {
  private root: string = '';

  open(filesDir: string): void {
    this.root = filesDir + '/' + IMG_DIR;
    if (!fs.accessSync(this.root)) {
      fs.mkdirSync(this.root, true);
    }
  }

  /** 新图片的文件名（时间戳 + 随机数，够用且不依赖 crypto 接口） */
  newRef(): string {
    return IMG_DIR + '/' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36) + IMG_EXT;
  }

  /** 加密写入；成功返回 ref，失败返回空串 */
  save(ref: string, vault: VaultService, raw: Uint8Array): boolean {
    if (raw.length === 0) {
      return false;
    }
    const enc: Uint8Array | null = vault.encrypt(raw);
    if (enc === null) {
      return false;
    }
    const path: string = this.root + '/' + ref.substring(IMG_DIR.length + 1);
    try {
      if (!fs.accessSync(this.root)) {
        fs.mkdirSync(this.root, true);
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, enc.buffer);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save image failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 解密读图（**只在显示时调用**）。
   *
   * 为什么要解密到临时文件再显示：Image 组件要的是路径/资源，
   * 而我们是加密文件 —— 直接给密文路径会显示破图。
   * 临时文件放在 cache 目录（系统可在空间不足时清理，不影响数据）。
   */
  load(ref: string, vault: VaultService, cacheDir: string): string {
    const path: string = this.root + '/' + ref.substring(IMG_DIR.length + 1);
    if (!fs.accessSync(path)) {
      return '';
    }
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(path).size);
      fs.readSync(file.fd, buf);
      const plain: Uint8Array | null = vault.decrypt(new Uint8Array(buf));
      if (plain === null) {
        return '';
      }
      const tmp: string = cacheDir + '/img-' + ref.substring(IMG_DIR.length + 1).replace(IMG_EXT, '') + '.bin';
      const out: fs.File = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(out.fd, plain.buffer);
      } finally {
        fs.closeSync(out);
      }
      return tmp;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load image failed: %{public}s', JSON.stringify(e));
      return '';
    } finally {
      fs.closeSync(file);
    }
  }
}
