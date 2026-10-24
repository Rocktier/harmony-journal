import { router } from '@kit.ArkUI';

import { JournalStats, MOODS, MOOD_CUSTOM_ID, Mood, MonthWords, computeStats, moodCounts, monthlyWords, todayKey } from '../data/NoteMeta';
import { ChevronButton } from '../components/ChevronButton';
import { getStore } from '../data/NoteStoreHolder';
import {
  RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_META, RJ_FS_TITLE,
  RJ_RADIUS_MD, RJ_RADIUS_SM, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID, RJ_SP_XL, RJ_SP_XXL
} from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 统计页（2026-10-23 复评 wow-point 落地）
 *
 * 第一性原则：私记的核心承诺是「数据只在这台设备上」—— 统计页让这句话
 * **从承诺变成可见**：全部数字从内存索引现算，零 IO、零联网、零权限。
 *
 * 两个既有资产的收口：
 *  ① computeStats（连续天数/总篇数）在 Settings 里躺了三行静态文本；
 *  ② 月历热度（heatByDate）已有色阶语言 —— 本页的柱状/横条复用同一套
 *     茶褐色阶，不引入第二套视觉。
 *
 * 封存纪律：未到期胶囊不计入任何统计（moodCounts 天然过滤 —— 保存时 mood
 * 已封存为 ''；monthlyWords 显式过滤 words）—— 「本月 800 字」不能剧透
 * 「锁着的那封信写了多长」。
 */
const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';
/** 月度柱状图回顾的月数 */
const MONTHS: number = 12;
/** 柱状图最大柱高（vp） */
const BAR_MAX: number = 72;

@Entry
@Component
struct RockStats {
  /** 运行时色板（深浅切换 = AppStorage 换对象；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  @State private stats: JournalStats = {
    total: 0, days: 0, words: 0, streak: 0, longest: 0, wroteToday: false
  };
  /** 心情计数（MOODS 顺序 + custom 桶） */
  @State private moods: Record<string, number> = {};
  /** 近 12 个月每月字数（倒序） */
  @State private months: MonthWords[] = [];
  private store = getStore();

  aboutToAppear(): void {
    this.reload();
  }

  /** 每次进入都重算（编辑器可能刚改过；索引是内存的，重算零 IO） */
  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    const metas = this.store.list();
    const nowMs: number = Date.now();
    this.stats = computeStats(metas, todayKey());
    this.moods = moodCounts(metas);
    this.months = monthlyWords(metas, todayKey(), MONTHS, nowMs);
  }

  /** 心情分布的最大计数（横条归一化用；全 0 时返回 1 防除零） */
  private moodMax(): number {
    let max: number = 1;
    for (let i: number = 0; i < MOODS.length; i++) {
      const n: number = this.moodOf(MOODS[i].id);
      if (n > max) {
        max = n;
      }
    }
    return max;
  }

  /** 月度字数的最大值（柱高归一化用） */
  private wordsMax(): number {
    let max: number = 1;
    for (let i: number = 0; i < this.months.length; i++) {
      if (this.months[i].words > max) {
        max = this.months[i].words;
      }
    }
    return max;
  }

  /** 某心情的计数（Record 索引在 ArkTS 下不当 number 用，typeof 窄化防脏键） */
  private moodOf(id: string): number {
    const v = this.moods[id];
    return typeof v === 'number' ? v : 0;
  }

  /** 大数字千分位（1 万字以上也要一眼读得下） */
  private bigNum(n: number): string {
    if (n < 10000) {
      return n.toString();
    }
    return (n / 10000).toFixed(1) + ' 万';
  }

  build() {
    Column() {
      // 顶栏（与 Privacy/About 同构：chevron 返回 + 等宽标题）
      Row() {
        ChevronButton({
          side: 'left',
          label: '返回',
          onClickHandler: () => {
            router.back();
          }
        })
        Text('STATS')
          .fontSize(RJ_FS_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .margin({ left: RJ_SP_MD })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_LG })
      .border({ width: { bottom: 1 }, color: this.palette.line })

      Scroll() {
        Column() {
          // 总览四数（2×2；今天写没写作为第五态单独一行）
          Row({ space: RJ_SP_MD }) {
            this.numCard('篇数', this.stats.total.toString())
            this.numCard('天数', this.stats.days + ' 天')
          }
          .width('100%')
          .margin({ top: RJ_SP_XL })

          Row({ space: RJ_SP_MD }) {
            this.numCard('累计字数', this.bigNum(this.stats.words))
            this.numCard('最长连续', this.stats.longest + ' 天')
          }
          .width('100%')
          .margin({ top: RJ_SP_MD })

          Text(this.stats.streak > 0
            ? '已连续写下 ' + this.stats.streak + ' 天' + (this.stats.wroteToday ? ' · 今天已写' : ' · 今天还没写')
            : '从今天开始，写下第一篇')
            .fontSize(RJ_FS_CAPTION)
            .fontColor(this.palette.text3)
            .width('100%')
            .margin({ top: RJ_SP_MD, bottom: RJ_SP_XL })

          // 月度字数（近 12 个月，从左到右 = 从过去到现在，当月压轴）
          Text('每月字数 · 近 ' + MONTHS + ' 个月')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .width('100%')
            .margin({ top: RJ_SP_XL, bottom: RJ_SP_MD })

          Row({ space: 4 }) {
            ForEach(this.months, (m: MonthWords) => {
              // ⚠️ item 必须 layoutWeight(1) 拿确定宽度（2026-10-24 模拟器实测的血泪）：
              //    早先靠内容撑宽，柱的 width('100%') 百分比循环回退到 Row 全宽
              //    ⇒ 12 个月每个都占满行宽并排，只有第 0 个月在屏内、其余全推出右缘
              //    （屏上只见一个「11月」标签，当月满柱在 x≈12000 外）。
              Column({ space: 2 }) {
                // 柱区：FlexAlign.End 压底 —— 数字贴柱顶，0 字月只留 2vp 基线痕。
                // 不用 Stack({alignContent:Bottom})：柱后画会把数字盖住。
                Column({ space: 2 }) {
                  Text(m.words > 0 ? this.bigNum(m.words) : '')
                    .fontSize(8)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                  // 柱：高度 = 当月字数 / 最大值 × BAR_MAX；0 字留 2vp 的基线痕
                  Column()
                    .width(14)
                    .height(m.words > 0 ? Math.max(3, Math.round(m.words * BAR_MAX / this.wordsMax())) : 2)
                    .backgroundColor(m.words > 0 ? this.palette.brand : this.palette.line)
                    .borderRadius({ topLeft: 2, topRight: 2 })
                }
                .justifyContent(FlexAlign.End)
                .width('100%')
                .height(BAR_MAX + 14)
                // 月份标签：只留「M月」（12 个放不下 2026-10）
                Text(Number(m.month.substring(5, 7)) + '月')
                  .fontSize(8)
                  .fontFamily('monospace')
                  .fontColor(m.month === todayKey().substring(0, 7) ? this.palette.accent : this.palette.text3)
              }
              .layoutWeight(1)
            }, (m: MonthWords) => m.month)
          }
          .width('100%')
          .height(BAR_MAX + 30)
          .margin({ top: RJ_SP_SM, bottom: RJ_SP_XL })

          // 心情分布（横条：emoji + 名称 + 茶褐条 + 计数）
          Text('心情分布')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .width('100%')
            .margin({ top: RJ_SP_XL, bottom: RJ_SP_MD })

          ForEach(MOODS, (m: Mood) => {
            // ⚠️ ForEach 生成器里只许 UI 语法 —— 局部 const 会报
            //    "Only UI component syntax can be written here"，
            //    计数直接内联 this.moodOf(m.id)（Record 查找，零成本）。
            Row({ space: RJ_SP_MD }) {
              Text(m.emoji + ' ' + m.label)
                .fontSize(RJ_FS_CAPTION)
                .fontColor(this.palette.text2)
                .width(72)
              Stack({ alignContent: Alignment.Start }) {
                Column()
                  .width('100%')
                  .height(8)
                  .backgroundColor(this.palette.line)
                  .borderRadius(RJ_RADIUS_SM)
                Column()
                  .width(this.moodOf(m.id) > 0 ? Math.max(4, Math.round(this.moodOf(m.id) * 100 / this.moodMax())) + '%' : '0%')
                  .height(8)
                  .backgroundColor(this.palette.brand)
                  .borderRadius(RJ_RADIUS_SM)
              }
              .height(8)
              .layoutWeight(1)
              Text(this.moodOf(m.id).toString())
                .fontSize(RJ_FS_CAPTION)
                .fontFamily('monospace')
                .fontColor(this.palette.text3)
                .width(28)
            }
            .width('100%')
            .padding({ top: RJ_SP_SM, bottom: RJ_SP_SM })
          }, (m: Mood) => m.id)

          // 自定义心情桶（有才显示）
          if (this.moodOf(MOOD_CUSTOM_ID) > 0) {
            Row({ space: RJ_SP_MD }) {
              Text('✏️ 自定义')
                .fontSize(RJ_FS_CAPTION)
                .fontColor(this.palette.text2)
                .width(72)
              Blank()
              Text(this.moodOf(MOOD_CUSTOM_ID).toString())
                .fontSize(RJ_FS_CAPTION)
                .fontFamily('monospace')
                .fontColor(this.palette.text3)
                .width(28)
            }
            .width('100%')
            .padding({ top: RJ_SP_SM, bottom: RJ_SP_SM })
          }

          // 数据说明（信任锚：与备份提醒同款的压底小字）
          Text('全部数字在本机现算 · 不联网 · 未到期的时间胶囊不计入')
            .fontSize(RJ_FS_CAPTION)
            .fontColor(this.palette.text3)
            .width('100%')
            .margin({ top: RJ_SP_XL, bottom: RJ_SP_VOID })
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }

  /** 总览数字卡（label + 大数字；茶褐描边，家族纸面语言） */
  @Builder
  private numCard(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(RJ_FS_CAPTION)
        .fontColor(this.palette.text3)
      Text(value)
        .fontSize(RJ_FS_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_MD, bottom: RJ_SP_MD })
    .backgroundColor(this.palette.card)
    .border({ width: 1, color: this.palette.line, radius: RJ_RADIUS_MD })
    .layoutWeight(1)
  }
}
