import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { APP_NAME_CN, APP_VERSION } from '../common/AppMeta';
import { DEV_SHOW_BADGE } from '../common/DevFlags';
import { getStore } from '../data/NoteStoreHolder';
import { BackupItem, backupFileName, buildBackup, parseBackup } from '../data/BackupService';

/**
 * 设置页（Phase 7 备份 + 关于）
 *
 * 备份是**离线日记的生命线**（评估文档四①）：手机丢了、坏了、换机 = 全没了，
 * 用户敢不敢用全看这一条。所以导出走系统文件选择器，存到用户自己的目录。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

@Entry
@Component
struct Settings {
  @State private noteCount: number = 0;
  @State private lastBackup: string = '从未';
  @State private toast: string = '';
  private store = getStore();

  aboutToAppear(): void {
    this.noteCount = this.store.list().length;
  }

  private async doExport(): Promise<void> {
    const items = this.store.exportAll();
    if (items.length === 0) {
      this.toast = '还没有日记可以导出';
      return;
    }
    // 明文 JSON → 用主密钥再加密一次：备份文件会落到沙箱外（下载/网盘），不能明文
    const bytes: Uint8Array = buildBackup(items);
    const enc: Uint8Array | null = this.store.getVault().encrypt(bytes);
    if (enc === null) {
      this.toast = '加密失败，未导出';
      return;
    }
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    // SDK 里没有 DocumentSavePicker 类 —— 保存走 DocumentViewPicker.save(DocumentSaveOptions)（查过 .d.ts）
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
    try {
      const saveOpt: picker.DocumentSaveOptions = {
        newFileNames: [backupFileName(new Date().toISOString().substring(0, 10))]
      };
      const uris: string[] = await docPicker.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const file: fs.File = fs.openSync(uri, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, enc.buffer);
      } finally {
        fs.closeSync(file);
      }
      this.toast = '已导出 ' + items.length + ' 篇';
      this.lastBackup = new Date().toISOString().substring(0, 10);
      hilog.info(DOMAIN, TAG, 'exported %{public}d notes', items.length);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'export failed: %{public}s', JSON.stringify(e));
      this.toast = '导出取消或失败';
    }
  }

  private async doImport(): Promise<void> {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const docView: picker.DocumentViewPicker = new picker.DocumentViewPicker();
    try {
      const uris: string[] = await docView.select({ maxSelectNumber: 1, fileSuffixFilters: ['.rkdbak'] });
      if (uris.length === 0) {
        return;
      }
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const buf: ArrayBuffer = new ArrayBuffer(fs.statSync(uris[0]).size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const plain: Uint8Array | null = this.store.getVault().decrypt(new Uint8Array(buf));
      if (plain === null) {
        this.toast = '解密失败：密码不对或文件损坏';
        return;
      }
      const items: BackupItem[] = parseBackup(plain);
      if (items.length === 0) {
        this.toast = '文件里没有可导入的日记';
        return;
      }
      const n: number = this.store.importAll(items);
      this.noteCount = this.store.list().length;
      this.toast = '已导入 ' + n + ' 篇';
      hilog.info(DOMAIN, TAG, 'imported %{public}d notes', n);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'import failed: %{public}s', JSON.stringify(e));
      this.toast = '导入取消或失败';
    }
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(18)
          .fontColor($r('app.color.rj_text2'))
          .onClick(() => {
            router.back();
          })
          .padding({ right: 12 })
        Text('设置')
          .fontSize(15)
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      // 备份（生命线）
      Text('备份')
        .fontSize(10.5)
        .fontFamily('monospace')
        .fontColor($r('app.color.rj_text3'))
        .width('100%')
        .padding({ left: 20, bottom: 6 })

      Row() {
        Text('导出加密备份')
          .fontSize(14)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            this.doExport();
          })
        Blank()
        Text('>')
          .fontColor($r('app.color.rj_text3'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      Row() {
        Text('从备份导入')
          .fontSize(14)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            this.doImport();
          })
        Blank()
        Text('>')
          .fontColor($r('app.color.rj_text3'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      Text('共 ' + this.noteCount + ' 篇 · 上次备份 ' + this.lastBackup)
        .fontSize(10)
        .fontColor($r('app.color.rj_text3'))
        .width('100%')
        .padding({ left: 20, top: 4, bottom: 16 })

      // 关于
      Text('关于')
        .fontSize(10.5)
        .fontFamily('monospace')
        .fontColor($r('app.color.rj_text3'))
        .width('100%')
        .padding({ left: 20, bottom: 6 })

      Row() {
        Text('隐私政策')
          .fontSize(14)
          .fontColor($r('app.color.rj_text'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/Privacy' });
          })
        Blank()
        Text('>')
          .fontColor($r('app.color.rj_text3'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      Row() {
        Text('版本')
          .fontSize(14)
          .fontColor($r('app.color.rj_text'))
        Blank()
        Text(APP_VERSION)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(12)
          .fontColor($r('app.color.rj_red'))
          .margin({ top: 12 })
      }

      Blank()

      Text(APP_NAME_CN + ' · 数据只在这台设备上')
        .fontSize(10)
        .fontColor($r('app.color.rj_text3'))
        .margin({ bottom: 8 })
      if (DEV_SHOW_BADGE) {
        Text('开发模式：未启用上锁（提审前务必关闭）')
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_red'))
          .margin({ bottom: 28 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
  }
}
