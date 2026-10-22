import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { APPEARANCE_DARK, APPEARANCE_LIGHT, APPEARANCE_SYSTEM, AppearanceMode } from '../common/Appearance';
import { applyPaletteMode } from '../common/AppearanceApply';
import { APP_NAME_CN, APP_VERSION } from '../common/AppMeta';
import { DEV_SHOW_BADGE } from '../common/DevFlags';
import { AppearancePrefs } from '../data/AppearancePrefs';
import { JournalStats, capsuleLocked, computeStats, dateKeyOf, daysSinceMs, needsBackupReminder, todayKey } from '../data/NoteMeta';
import { ChevronButton } from '../components/ChevronButton';
import { getStore } from '../data/NoteStoreHolder';
import {
  BackupItem, EXT_MD, EXT_TXT, backupFileName, buildBackup, parseBackup, readableFileName,
  toMarkdown, toPlainText, utf8Encode
} from '../data/BackupService';
import { RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_HEADING, RJ_FS_META, RJ_FS_TITLE, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_XL, RJ_SP_XXL, RJ_SP_XXXL } from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 设置页（Phase 7 备份 + 关于）
 *
 * 备份是**离线日记的生命线**（评估文档四①）：手机丢了、坏了、换机 = 全没了，
 * 用户敢不敢用全看这一条。所以导出走系统文件选择器，存到用户自己的目录。
 */
const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

@Entry
@Component
struct Settings {
  /** 运行时色板（深浅切换 = AppStorage 换对象，页面栈不动；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  @State private noteCount: number = 0;
  @State private lastBackup: string = '从未';
  /**
   * 备份到期提醒（2026-10-22 P0-3 断头路清零）：
   * 首页横幅按党哥 2026-10-15 的决策不回来（低频工具不抢主体注意力），
   * 但 needsBackupReminder 的完整实现不能没有消费方 —— 落位在设置页这行
   * 常驻信息上：到期时文案升格成"该备份了"，颜色升到 text2（不动红色纪律）。
   */
  @State private backupDue: boolean = false;
  @State private backupDays: number = -1;
  @State private toast: string = '';
  @State private stats: JournalStats = {
    total: 0, days: 0, words: 0, streak: 0, longest: 0, wroteToday: false
  };
  private store = getStore();
  private prefs: AppearancePrefs = new AppearancePrefs();
  /** 外观（跟随系统 / 深色 / 浅色）—— 默认跟随系统，不打扰 */
  @State private appearance: AppearanceMode = APPEARANCE_SYSTEM;

  aboutToAppear(): void {
    this.noteCount = this.store.list().length;
    this.stats = computeStats(this.store.list(), todayKey());
    // 上次备份：**读真实记录**，不再写死"从未"（否则"生命线"永远是句空话）
    const at: number = this.store.lastBackupAt();
    this.lastBackup = at > 0 ? dateKeyOf(new Date(at)) : '从未';
    this.backupDays = daysSinceMs(at, Date.now());
    this.backupDue = needsBackupReminder(at, Date.now(), this.noteCount > 0, 30);
    this.prefs.open(getContext(this) as common.Context);
    this.appearance = this.prefs.get();
  }

  /** 切换外观：落偏好 + 立刻作用于系统（资源限定符自动换深/浅色，全应用一致） */
  private setAppearance(mode: AppearanceMode): void {
    this.appearance = mode;
    this.prefs.set(mode);
    applyPaletteMode(getContext(this) as common.Context, mode);
  }

  /** 三态 chip：选中才亮（真 Button —— 按压反馈、读屏报"按钮"、可聚焦） */
  @Builder
  private appearanceChip(label: string, mode: AppearanceMode) {
    Button(label, { type: ButtonType.Normal, stateEffect: true })
      .fontSize(RJ_FS_META)
      .fontWeight(this.appearance === mode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.appearance === mode ? this.palette.bg : this.palette.text3)
      // 选中态用墨色 chrome —— 与首页「月历/时光」分段控件同款。
      // ⚠️ 2026-10-15 收敛：原来选中用茶褐，但 Index 的分段控件选中是墨色，
      //    同类控件（三选一）两种颜色 = 党哥说的"颜色混乱"的根源之一。
      //    纪律收口：**墨 = 可点/选中，茶 = 印记**，全 app 只剩这一条色彩逻辑。
      .backgroundColor(this.appearance === mode ? this.palette.accent : this.palette.card)
      .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
      .margin({ left: RJ_SP_SM })
      .onClick(() => {
        this.setAppearance(mode);
      })
  }

  /**
   * 设置行（真 Button 文字态 + 右侧 › + 44vp 热区）。
   *
   * ⚠️ 原来是 `Text(...).onClick` **伪按钮** —— 没有按压反馈、读屏不报"按钮"、无法聚焦，
   * 这是 A 类无障碍问题（AGC 会查）。整行可点也比只点那一小条文字好按得多。
   */
  @Builder
  private settingRow(label: string, onTap: () => void) {
    Row() {
      // ⚠️ Button 没有 justifyContent 属性 —— 想左对齐就得用 content 形式放 Text
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Text(label)
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .backgroundColor(Color.Transparent)
      .height(44)
      .layoutWeight(1)
      .accessibilityText(label)
      .onClick(() => {
        onTap();
      })
      Text('›')
        .fontSize(RJ_FS_CALLOUT)
        .fontColor(this.palette.text3)
    }
    .width('100%')
    .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_SM, bottom: RJ_SP_SM })
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
      this.store.markBackup();
      this.lastBackup = todayKey();
      // 导出成功 ⇒ 到期提醒即时解除（不用退出重进才消）
      this.backupDays = 0;
      this.backupDue = false;
      hilog.info(DOMAIN, TAG, 'exported %{public}d notes', items.length);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'export failed: %{public}s', JSON.stringify(e));
      this.toast = '导出取消或失败';
    }
  }

  /**
   * 可读导出（**明文**，不加密）
   *
   * ⚠️ 为什么必须提示：加密备份落在外面也是密文，而这个是**明文** ——
   * 用户如果按"反正有密码"的心智把它丢网盘就露了。设置页已写明"不加密，请自行保管"。
   *
   * ⚠️ 未到期的时间胶囊**不导出**（2026-10-20）：它锁着的全部意义就是
   * "现在不能读"，而 TXT/MD 不加密 —— 导出去等于替用户提前拆信。
   * 加密备份照常全量（那是密文，恢复后胶囊该锁还锁）。
   */
  private async doExportReadable(markdown: boolean): Promise<void> {
    const all: BackupItem[] = this.store.exportAll();
    if (all.length === 0) {
      this.toast = '还没有日记可以导出';
      return;
    }
    const nowMs: number = Date.now();
    const items: BackupItem[] = all.filter((it: BackupItem) => !capsuleLocked(it.meta, nowMs));
    if (items.length === 0) {
      this.toast = '没有可导出的日记（时间胶囊到期后才导出）';
      return;
    }
    const skipped: number = all.length - items.length;
    const text: string = markdown ? toMarkdown(items) : toPlainText(items);
    const bytes: Uint8Array = utf8Encode(text);
    const ext: string = markdown ? EXT_MD : EXT_TXT;
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
    try {
      const saveOpt: picker.DocumentSaveOptions = {
        newFileNames: [readableFileName(new Date().toISOString().substring(0, 10), ext)]
      };
      const uris: string[] = await docPicker.save(saveOpt);
      if (uris.length === 0) {
        return;
      }
      const file: fs.File = fs.openSync(uris[0], fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, bytes.buffer);
      } finally {
        fs.closeSync(file);
      }
      this.toast = '已导出 ' + items.length + ' 篇（明文）' +
        (skipped > 0 ? '，跳过 ' + skipped + ' 篇未到期胶囊' : '');
      hilog.info(DOMAIN, TAG, 'exported readable %{public}d notes, md=%{public}s skipped=%{public}d',
        items.length, String(markdown), skipped);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readable export failed: %{public}s', JSON.stringify(e));
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

  /** 页面转场（2026-10-22 P0-1 动效包）：与全家族统一的推栈语言（见 Editor.pageTransition） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 280, curve: Curve.Friction })
      .translate({ x: 200 })
      .opacity(0.6)
    PageTransitionExit({ type: RouteType.Push, duration: 280, curve: Curve.Friction })
      .translate({ x: -80 })
      .opacity(0.8)
    PageTransitionEnter({ type: RouteType.Pop, duration: 280, curve: Curve.Friction })
      .translate({ x: -80 })
      .opacity(0.8)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.Friction })
      .translate({ x: 200 })
      .opacity(0.6)
  }

  build() {
    Column() {
      Row() {
        // 返回：圆形 chevron 图标按钮（2026-10-15 替换裸 `<` 字符按钮）
        ChevronButton({
          side: 'left',
          label: '返回',
          onClickHandler: () => {
            router.back();
          }
        })
        Text('设置')
          .fontSize(RJ_FS_HEADING)
          .fontColor(this.palette.text)
          .letterSpacing(2)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_LG })

      // 外观（日/夜）—— 放在设置页最上面：晚上在被窝里写日记是高频场景（党哥 2026-10-12）
      Text('外观')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, bottom: RJ_SP_MD })

      Row() {
        Text('日间 / 夜间')
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
        Blank()
        this.appearanceChip('跟随系统', APPEARANCE_SYSTEM)
        this.appearanceChip('深色', APPEARANCE_DARK)
        this.appearanceChip('浅色', APPEARANCE_LIGHT)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })

      // 备份（生命线）
      Text('备份')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, bottom: RJ_SP_MD })

      this.settingRow('导出加密备份', () => {
        this.doExport();
      })

      this.settingRow('从备份导入', () => {
        this.doImport();
      })

      // 可读导出（数据自主：不把用户锁死在本 App 里）
      this.settingRow('导出为文本 TXT', () => {
        this.doExportReadable(false);
      })

      this.settingRow('导出为 Markdown', () => {
        this.doExportReadable(true);
      })

      // 告知要说全：明文风险 **和** 图片不包含在内。
      // ⚠️ 只说"明文"是不够的 —— 用户会以为导出=全部，迁走后才发现照片全丢，
      //    那属于"承诺不一致"，比缺功能更伤信任。图片请用加密备份。
      Text('TXT / Markdown 是明文、不加密，且不含图片（只留占位）—— 图片请用上面的加密备份')
        .fontSize(RJ_FS_META)
        // ⚠️ 2026-10-15 收敛：原来是警示红，但这是**常驻说明**不是错误 ——
        //    红色纪律 = 只给"错了"（解锁失败/删除确认）；常驻红字只会变成壁纸，
        //    还让设置页显得整页都在报警（党哥：红色用得太乱，要收敛）。
        //    信息本身已经把风险说清了，弱化成次级文字反而更可信。
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_LG })

      // 到期提醒三态：正常（text3）→ 到期（text2 + 催促文案）；红色纪律只给"错了"，这里不碰
      if (this.backupDue) {
        Text(this.backupDays >= 0
          ? '共 ' + this.noteCount + ' 篇 · 距上次备份 ' + this.backupDays + ' 天了，记得导出一份'
          : '共 ' + this.noteCount + ' 篇 · 还从未备份过，记得导出一份')
          .fontSize(RJ_FS_META)
          .fontColor(this.palette.text2)
          .width('100%')
          .padding({ left: RJ_SP_XXL, top: RJ_SP_SM, bottom: RJ_SP_XL })
      } else {
        Text('共 ' + this.noteCount + ' 篇 · 上次备份 ' + this.lastBackup)
          .fontSize(RJ_FS_META)
          .fontColor(this.palette.text3)
          .width('100%')
          .padding({ left: RJ_SP_XXL, top: RJ_SP_SM, bottom: RJ_SP_XL })
      }

      // 统计（Diarium 的 diary statistics 同款；全部从内存索引算，零 IO）
      Text('统计')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, bottom: RJ_SP_MD })

      Row() {
        Text('写过日记的天数')
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
        Blank()
        Text(this.stats.days + ' 天')
          .fontSize(RJ_FS_CAPTION)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })

      Row() {
        Text('累计字数')
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
        Blank()
        Text(this.stats.words + ' 字')
          .fontSize(RJ_FS_CAPTION)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })

      Row() {
        Text('最长连续')
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
        Blank()
        Text(this.stats.longest + ' 天')
          .fontSize(RJ_FS_CAPTION)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })

      // 关于
      Text('关于')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, bottom: RJ_SP_MD })

      this.settingRow('隐私政策', () => {
        router.pushUrl({ url: 'pages/Privacy' });
      })

      Row() {
        Text('版本')
          .fontSize(RJ_FS_CALLOUT)
          .fontColor(this.palette.text)
        Blank()
        Text(APP_VERSION)
          .fontSize(RJ_FS_CAPTION)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_LG, bottom: RJ_SP_LG })

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.palette.accent)
          .margin({ top: RJ_SP_LG })
      }

      Blank()

      Text(APP_NAME_CN + ' · 数据只在这台设备上')
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text3)
        .margin({ bottom: RJ_SP_MD })
      if (DEV_SHOW_BADGE) {
        Text('开发模式：未启用上锁（提审前务必关闭）')
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.accent)
          .margin({ bottom: RJ_SP_XXXL })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }
}
