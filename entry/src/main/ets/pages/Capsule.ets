import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import {
  NoteMeta, capsuleBadge, capsuleLocked, daysUntilUnlock, dateKeyOf, isCapsule
} from '../data/NoteMeta';
import { NoteStore } from '../data/NoteStore';
import { getStore } from '../data/NoteStoreHolder';
import { ChevronButton } from '../components/ChevronButton';
import { RJ_FS_BODY, RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_META, RJ_FS_TITLE, RJ_RADIUS_LG, RJ_RADIUS_SM, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_XL, RJ_SP_XXL } from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 时间胶囊详情页（2026-10-20）
 *
 * 用户视角：锁着的信 —— 只告诉你"它在那、哪天开、还有几天"，
 * 一个字的正文都不给看（数据层封存 + 本页不解密，双保险）。
 * 到期后再来，这颗胶囊就能正常打开阅读/编辑。
 *
 * 为什么单独一页而不是编辑器里加个状态：编辑器整页都是"可编辑"的暗示，
 * 锁着的信混在里面，用户会疑心"是不是坏了"；单独一页语义干净，
 * 也是差异化功能的门面（商店截图拍的就是它）。
 */
const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

@Entry
@Component
struct Capsule {
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  /** 这一篇的 id（路由参数） */
  private entryId: string = '';
  private store: NoteStore = getStore();
  /** 这篇的元数据（null = 不存在/已删） */
  @State private meta: NoteMeta | null = null;
  /** 当前是否锁着（每次进页面重算，改系统时间到未来能即时解锁） */
  @State private locked: boolean = true;

  aboutToAppear(): void {
    const params: object = router.getParams() as object;
    const holder: CapsuleParam = params as CapsuleParam;
    this.entryId = holder.id !== undefined ? holder.id : '';
    this.refresh();
    hilog.info(DOMAIN, TAG, 'capsule page open id=%{public}s locked=%{public}s', this.entryId, this.locked);
  }

  /** 重读元数据 + 重算锁定态（页面 show 时也会走到，见 onPageShow） */
  private refresh(): void {
    const m: NoteMeta | null = this.entryId.length > 0 ? this.store.byId(this.entryId) : null;
    this.meta = m;
    if (m !== null && isCapsule(m)) {
      this.locked = capsuleLocked(m, Date.now());
    } else {
      this.locked = false;
    }
  }

  onPageShow(): void {
    // 用户可能先去改系统时间再回来 —— 刷新锁定态（诚实大于防篡改，见产品口径）
    this.refresh();
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
        ChevronButton({
          side: 'left',
          label: '返回',
          onClickHandler: () => {
            router.back();
          }
        })
        Blank()
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_MD })

      if (this.meta === null) {
        // 不存在（删了/ id 错了）：说清楚，别留一个空页让人猜
        Text('这封信不在了')
          .fontSize(RJ_FS_BODY)
          .fontColor(this.palette.text3)
          .margin({ top: RJ_SP_XL })
      } else if (this.locked) {
        this.lockedView(this.meta as NoteMeta);
      } else {
        this.unlockedView(this.meta as NoteMeta);
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }

  /** 锁定态：日期 + 倒计时 + 边界说明。一个字的正文都没有。 */
  @Builder
  private lockedView(m: NoteMeta) {
    Column() {
      Text('⏳')
        .fontSize(56)
        .margin({ top: RJ_SP_XL })
      Text('一封给未来的信')
        .fontSize(RJ_FS_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .margin({ top: RJ_SP_LG })
      Text('写在 ' + m.date)
        .fontSize(RJ_FS_CAPTION)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .margin({ top: RJ_SP_MD })
      Text('还有 ' + daysUntilUnlock(m, Date.now()) + ' 天能打开')
        .fontSize(RJ_FS_CALLOUT)
        .fontFamily('monospace')
        .fontColor(this.palette.brand)
        .margin({ top: RJ_SP_MD })
      Text('解锁日 ' + dateKeyOf(new Date(m.unlockAt)))
        .fontSize(RJ_FS_CAPTION)
        .fontFamily('monospace')
        .fontColor(this.palette.text2)
        .margin({ top: RJ_SP_SM })
      Text('到期前内容不可读 · 解锁按本机系统时间')
        .fontSize(RJ_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .margin({ top: RJ_SP_XL })
    }
    .width('100%')
    .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL })
  }

  /** 已解锁：给一个明确的入口进编辑器（正文的展示归编辑器，不在这页解密） */
  @Builder
  private unlockedView(m: NoteMeta) {
    Column() {
      Text('✉️')
        .fontSize(56)
        .margin({ top: RJ_SP_XL })
      Text('可以打开了')
        .fontSize(RJ_FS_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .margin({ top: RJ_SP_LG })
      Text(capsuleBadge(m, Date.now()) + ' · 写在 ' + m.date)
        .fontSize(RJ_FS_CAPTION)
        .fontFamily('monospace')
        .fontColor(this.palette.brand)
        .margin({ top: RJ_SP_MD })
      Button('打开阅读', { type: ButtonType.Normal, stateEffect: true })
        .backgroundColor(this.palette.accent)
        .fontColor(this.palette.bg)
        .fontSize(RJ_FS_CAPTION)
        .fontWeight(FontWeight.Bold)
        .borderRadius(RJ_RADIUS_LG)
        .padding({ left: RJ_SP_XL, right: RJ_SP_XL, top: RJ_SP_SM, bottom: RJ_SP_SM })
        .margin({ top: RJ_SP_XL })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Editor', params: { date: m.date, id: m.id } });
        })
    }
    .width('100%')
    .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL })
  }
}

/** 路由参数：这一篇的 id */
interface CapsuleParam {
  id?: string;
}
