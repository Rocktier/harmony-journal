import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { DEV_SHOW_BADGE } from '../common/DevFlags';
import { NoteMeta, MonthCell, NoteText, SearchHit, moodById, monthGrid, monthOf, searchNotes, shiftMonth, todayKey } from '../data/NoteMeta';
import { NoteStore } from '../data/NoteStore';
import { getStore } from '../data/NoteStoreHolder';

/**
 * 主页面：月视图日历 + 日记列表 + 搜索
 *
 * 家族观感：纯黑底、白字、红点做"有日记"的标记（与图标红点同源）。
 * 一天一篇 —— 点任意一天直接进入那天的编辑页（没有就是新建）。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'RockJournal';

@Entry
@Component
struct Index {
  @State private metas: NoteMeta[] = [];
  @State private mode: string = 'month';
  @State private monthKey: string = monthOf(todayKey());
  @State private query: string = '';
  @State private hits: SearchHit[] = [];
  @State private loaded: boolean = false;
  private store: NoteStore = getStore();

  aboutToAppear(): void {
    this.reload();
  }

  /**
   * ⚠️ router.back 回来时 aboutToAppear **不会**重新触发（页面没销毁），
   * 必须用 onPageShow 刷新 —— 不然编辑完回来，红点和列表都是旧数据（实拍抓到）。
   */
  onPageShow(): void {
    this.reload();
  }

  private reload(): void {
    this.metas = this.store.list();
    this.loaded = true;
    hilog.info(DOMAIN, TAG, 'index loaded: %{public}d notes', this.metas.length);
  }

  private cells(): MonthCell[] {
    return monthGrid(this.monthKey, this.store.allDates());
  }

  private open(date: string): void {
    router.pushUrl({ url: 'pages/Editor', params: { date: date } }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pushUrl failed: %{public}s', JSON.stringify(e));
    });
  }

  private runSearch(): void {
    const texts: NoteText[] = [];
    for (let i: number = 0; i < this.metas.length; i++) {
      const m: NoteMeta = this.metas[i];
      const item: NoteText = {
        date: m.date,
        text: this.store.readNote(m.date).map((b) => b.spans.map((s) => s.text).join('')).join('\n')
      };
      texts.push(item);
    }
    this.hits = searchNotes(texts, this.query);
  }

  private moodEmoji(m: NoteMeta): string {
    if (m.mood.length === 0) {
      return '';
    }
    if (m.mood === 'custom') {
      return m.moodText.length > 0 ? m.moodText.substring(0, 2) : '·';
    }
    const found = moodById(m.mood);
    return found === null ? '' : found.emoji;
  }

  build() {
    Column() {
      // 顶部：视图切换 + 月份
      Row() {
        Text('Rock私记')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
        if (DEV_SHOW_BADGE) {
          Text('DEV')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_red'))
            .border({ width: 1, color: $r('app.color.rj_red') })
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ left: 8 })
        }
        Blank()
        Text(this.mode === 'month' ? '月' : '列表')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .margin({ right: 14 })
          .onClick(() => {
            this.mode = this.mode === 'month' ? 'list' : 'month';
          })
        // 设置（导出备份的生命线入口 —— 藏深了等于没有）
        Text('设置')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rj_text3'))
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      // 搜索
      TextInput({ placeholder: '搜日记', text: this.query })
        .fontSize(13)
        .backgroundColor($r('app.color.rj_card'))
        .fontColor($r('app.color.rj_text'))
        .placeholderColor($r('app.color.rj_text3'))
        .height(38)
        .margin({ left: 20, right: 20, bottom: 8 })
        .onChange((v: string) => {
          this.query = v;
          if (v.length > 0) {
            this.runSearch();
          } else {
            this.hits = [];
          }
        })

      if (this.query.length > 0) {
        // 搜索结果
        if (this.hits.length === 0) {
          Text('没有找到')
            .fontSize(12)
            .fontColor($r('app.color.rj_text3'))
            .margin({ top: 40 })
        }
        List() {
          ForEach(this.hits, (hit: SearchHit) => {
            ListItem() {
              Column() {
                Text(hit.date)
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text3'))
                Text(hit.snippet)
                  .fontSize(14)
                  .fontColor($r('app.color.rj_text'))
                  .margin({ top: 4 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
              .width('100%')
            }
            .onClick(() => {
              this.open(hit.date);
            })
          }, (hit: SearchHit) => hit.date)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      } else if (this.mode === 'month') {
        // 月视图
        Row() {
          Text('<')
            .fontSize(16)
            .fontColor($r('app.color.rj_text2'))
            .onClick(() => {
              this.monthKey = shiftMonth(this.monthKey, -1);
            })
            .padding(8)
          Text(this.monthKey)
            .fontSize(14)
            .fontFamily('monospace')
            .fontColor($r('app.color.rj_text'))
            .letterSpacing(2)
          Text('>')
            .fontSize(16)
            .fontColor($r('app.color.rj_text2'))
            .onClick(() => {
              this.monthKey = shiftMonth(this.monthKey, 1);
            })
            .padding(8)
        }
        .margin({ bottom: 8 })

        // 6×7 网格
        Grid() {
          ForEach(this.cells(), (cell: MonthCell) => {
            GridItem() {
              Stack({ alignContent: Alignment.TopEnd }) {
                Text(cell.day.toString())
                  .fontSize(13)
                  .fontFamily('monospace')
                  .fontColor(cell.inMonth ? $r('app.color.rj_text') : $r('app.color.rj_text3'))
                if (cell.hasNote) {
                  Circle({ width: 8, height: 8 })
                    .fill($r('app.color.rj_red'))
                    .margin({ top: 3, right: 8 })
                }
              }
              .width('100%')
              .height('100%')
            }
            .onClick(() => {
              this.open(cell.date);
            })
          }, (cell: MonthCell) => cell.date)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
        .height(300)
        .padding({ left: 16, right: 16 })

        // 本月日记列表
        List() {
          ForEach(this.metas, (m: NoteMeta) => {
            ListItem() {
              Row() {
                Text(m.date)
                  .fontSize(12)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text2'))
                if (this.moodEmoji(m).length > 0) {
                  Text(this.moodEmoji(m))
                    .fontSize(14)
                    .margin({ left: 10 })
                }
                Blank()
                Text(m.words + ' 字')
                  .fontSize(10)
                  .fontFamily('monospace')
                  .fontColor($r('app.color.rj_text3'))
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            }
            .onClick(() => {
              this.open(m.date);
            })
          }, (m: NoteMeta) => m.date)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      } else {
        // 列表视图（全部，倒序）
        if (!this.loaded || this.metas.length === 0) {
          Column() {
            Text('还没有日记')
              .fontSize(14)
              .fontColor($r('app.color.rj_text3'))
            Text('点下面的按钮，写今天')
              .fontSize(11)
              .fontColor($r('app.color.rj_text3'))
              .margin({ top: 6 })
          }
          .margin({ top: 60 })
        }
        List() {
          ForEach(this.metas, (m: NoteMeta) => {
            ListItem() {
              Column() {
                Row() {
                  Text(m.date)
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text2'))
                  if (this.moodEmoji(m).length > 0) {
                    Text(this.moodEmoji(m))
                      .fontSize(14)
                      .margin({ left: 10 })
                  }
                  Blank()
                  Text(m.words + ' 字')
                    .fontSize(10)
                    .fontFamily('monospace')
                    .fontColor($r('app.color.rj_text3'))
                }
                .width('100%')
              }
              .padding({ left: 20, right: 20, top: 14, bottom: 14 })
            }
            .onClick(() => {
              this.open(m.date);
            })
          }, (m: NoteMeta) => m.date)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.rj_line') })
      }

      // 写今天
      Button('写今天')
        .fontSize(14)
        .backgroundColor($r('app.color.rj_text'))
        .fontColor($r('app.color.rj_bg'))
        .height(44)
        .width('86%')
        .margin({ bottom: 28, top: 8 })
        .onClick(() => {
          this.open(todayKey());
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
  }
}
