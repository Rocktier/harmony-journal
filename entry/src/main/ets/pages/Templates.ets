import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ChevronButton } from '../components/ChevronButton';
import {
  JournalTemplate, TEMPLATE_LABEL_MAX, TEMPLATE_LINES_MAX, TEMPLATE_MAX, TEMPLATES, addTemplate,
  canAddTemplate, isBuiltinId, removeTemplate, templateSummary, templateTextOf, updateTemplate
} from '../data/JournalTemplates';
import { getStore } from '../data/NoteStoreHolder';
import {
  RJ_FS_BODY, RJ_FS_CALLOUT, RJ_FS_CAPTION, RJ_FS_HEADING, RJ_FS_META, RJ_RADIUS_MD, RJ_RADIUS_SM,
  RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID_L, RJ_SP_XL, RJ_SP_XS, RJ_SP_XXL
} from '../theme/RjTokens';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 模板管理页（1.0.6 自定义模板）
 *
 * 用户视角：内置那几个模板只能覆盖通用场景，而"我的晨间复盘固定问这三句"
 * 是每个人的私事 —— 让用户把自己的套路存成模板，模板才真正省时间。
 *
 * ⚠️ 内置模板**只读**（不给改、不给删）：
 *    用户改坏了没地方恢复，就干脆不让改。想改？照它新建一个自己改（复制成本极低）。
 *
 * ⚠️ 与「每日提示」的分工（别做成两个重复的入口）：
 *    模板是**固定的套路**（每天晨间三问，用来养成节奏）；
 *    提示是**每天换的一句**（用来打破惯性）。一个稳、一个变。
 */
const DOMAIN: number = 0xD002;
const TAG: string = 'RockJournal';

@Entry
@Component
struct TemplatesPage {
  /** 运行时色板（深浅切换 = AppStorage 换对象，页面栈不动；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);
  /** 用户自建模板（内置模板来自常量表，不进这里） */
  @State private custom: JournalTemplate[] = [];
  /** 正在编辑的模板（空串 = 没有）；内置不可编 ⇒ 永远进不来 */
  @State private editingId: string = '';
  @State private editLabel: string = '';
  @State private editLines: string = '';
  @State private newLabel: string = '';
  @State private newLines: string = '';
  @State private confirmId: string = '';
  @State private hint: string = '';
  /**
   * 新建区的重建版本号（只用来让输入框真的被清空）。
   *
   * ⚠️ 为什么需要它（2026-10-27 模拟器实拍抓到）：保存后 `newLabel/newLines`
   *    已经置空，但输入框里还留着刚才填的内容 —— 因为 @Builder 的**值参数
   *    不随 @State 重跑**（家族第 4 次同型坑），TextInput 的 text 停在首帧。
   *    这里用 ForEach key 带上版本号 ⇒ 版本号一变就强制重建那个输入块。
   */
  @State private addBoxRev: number = 0;
  private store = getStore();

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.custom = this.store.customTemplates();
  }

  private persist(): boolean {
    const ok: boolean = this.store.saveIndex();
    if (!ok) {
      hilog.error(DOMAIN, TAG, 'saveIndex failed in Templates page');
    }
    return ok;
  }

  private showHint(text: string): void {
    this.hint = text;
    setTimeout(() => {
      this.hint = '';
    }, 2600);
  }

  private doAdd(): void {
    const r = addTemplate(this.custom, this.newLabel, this.newLines);
    if (r === null) {
      if (!canAddTemplate(this.custom)) {
        this.showHint('最多 ' + TEMPLATE_MAX + ' 个模板');
      } else {
        this.showHint('名字和内容都要填');
      }
      return;
    }
    this.store.setTemplates(r.list);
    if (this.persist()) {
      this.showHint('已保存「' + r.created.label + '」');
    }
    this.newLabel = '';
    this.newLines = '';
    this.addBoxRev = this.addBoxRev + 1;
    this.refresh();
  }

  private doSaveEdit(id: string): void {
    this.store.setTemplates(updateTemplate(this.custom, id, this.editLabel, this.editLines));
    if (this.persist()) {
      this.showHint('已保存');
    }
    this.editingId = '';
    this.refresh();
  }

  private doRemove(id: string): void {
    this.store.setTemplates(removeTemplate(this.custom, id));
    if (this.persist()) {
      this.showHint('已删除');
    }
    this.confirmId = '';
    this.refresh();
  }

  build() {
    // 根 Column 给确定高度（Scroll 的 layoutWeight 才有解）
    Column() {
      Row() {
        ChevronButton({
          side: 'left',
          label: '返回',
          onClickHandler: () => {
            router.back();
          }
        })
        Text('模板')
          .fontSize(RJ_FS_HEADING)
          .fontColor(this.palette.text)
          .letterSpacing(2)
        Blank()
        Text((TEMPLATES.length + this.custom.length) + '/' + TEMPLATE_MAX)
          .fontSize(RJ_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_SM })

      Text('模板是每天不变的套路；每天换的那句叫「提示」，在写新日记时出现。')
        .fontSize(RJ_FS_META)
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_MD })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(RJ_FS_CAPTION)
          .fontColor(this.palette.brand)
          .width('100%')
          .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_SM })
      }

      Scroll() {
        Column() {
          // ── 内置（只读） ──
          Text('内置')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .width('100%')
            .padding({ bottom: RJ_SP_SM })
          ForEach(TEMPLATES, (t: JournalTemplate) => {
            Row() {
              Text(t.label)
                .fontSize(RJ_FS_CALLOUT)
                .fontColor(this.palette.text)
              Text('内置')
                .fontSize(RJ_FS_META)
                .fontFamily('monospace')
                .fontColor(this.palette.text3)
                .margin({ left: RJ_SP_MD })
              Blank()
              Text(templateSummary(t, 2))
                .fontSize(RJ_FS_META)
                .fontColor(this.palette.text3)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .padding({ top: RJ_SP_MD, bottom: RJ_SP_MD })
          }, (t: JournalTemplate) => t.id)

          // ── 自建 ──
          Text('我的模板')
            .fontSize(RJ_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .width('100%')
            .padding({ top: RJ_SP_XL, bottom: RJ_SP_SM })

          if (this.custom.length === 0) {
            Text('还没有自建模板。把你每周都问自己的那几句存下来，下次一键灌进去。')
              .fontSize(RJ_FS_CAPTION)
              .fontColor(this.palette.text3)
              .width('100%')
              .padding({ top: RJ_SP_SM, bottom: RJ_SP_MD })
          }

          ForEach(this.custom, (t: JournalTemplate) => {
            Column() {
              Row() {
                Text(t.label)
                  .fontSize(RJ_FS_CALLOUT)
                  .fontColor(this.palette.text)
                Text(t.lines.length + ' 行')
                  .fontSize(RJ_FS_META)
                  .fontFamily('monospace')
                  .fontColor(this.palette.text3)
                  .margin({ left: RJ_SP_MD })
                Blank()
                Button('编辑', { type: ButtonType.Normal, stateEffect: true })
                  .buttonStyle(ButtonStyleMode.TEXTUAL)
                  .fontSize(RJ_FS_CAPTION)
                  .fontColor(this.palette.text3)
                  .padding({ left: RJ_SP_SM, right: RJ_SP_SM, top: RJ_SP_XS, bottom: RJ_SP_XS })
                  .onClick(() => {
                    this.editingId = t.id;
                    this.editLabel = t.label;
                    this.editLines = templateTextOf(t);
                    this.confirmId = '';
                  })
                Button('删除', { type: ButtonType.Normal, stateEffect: true })
                  .buttonStyle(ButtonStyleMode.TEXTUAL)
                  .fontSize(RJ_FS_CAPTION)
                  .fontColor(this.palette.text3)
                  .padding({ left: RJ_SP_SM, right: RJ_SP_SM, top: RJ_SP_XS, bottom: RJ_SP_XS })
                  .onClick(() => {
                    this.confirmId = t.id;
                    this.editingId = '';
                  })
              }
              .width('100%')

              if (this.editingId === t.id) {
                this.editorBox(this.editLabel, this.editLines, (v: string) => {
                  this.editLabel = v;
                }, (v: string) => {
                  this.editLines = v;
                }, () => {
                  this.doSaveEdit(t.id);
                }, () => {
                  this.editingId = '';
                })
              }

              if (this.confirmId === t.id) {
                Column() {
                  Text('删除「' + t.label + '」？已经用过它的日记不受影响。')
                    .fontSize(RJ_FS_CAPTION)
                    .fontColor(this.palette.text2)
                    .width('100%')
                  Row() {
                    Button('取消', { type: ButtonType.Normal, stateEffect: true })
                      .buttonStyle(ButtonStyleMode.TEXTUAL)
                      .fontSize(RJ_FS_CAPTION)
                      .fontColor(this.palette.text3)
                      .onClick(() => {
                        this.confirmId = '';
                      })
                    Button('确认删除', { type: ButtonType.Normal, stateEffect: true })
                      .backgroundColor(this.palette.accent)
                      .fontColor(this.palette.bg)
                      .fontSize(RJ_FS_CAPTION)
                      .borderRadius(RJ_RADIUS_MD)
                      .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
                      .margin({ left: RJ_SP_MD })
                      .onClick(() => {
                        this.doRemove(t.id);
                      })
                  }
                  .margin({ top: RJ_SP_SM })
                }
                .width('100%')
                .padding({ left: RJ_SP_MD, right: RJ_SP_MD, top: RJ_SP_SM, bottom: RJ_SP_MD })
                .backgroundColor(this.palette.card)
                .borderRadius(RJ_RADIUS_SM)
              }
            }
            .width('100%')
            .padding({ top: RJ_SP_XS })
            // ⚠️ key 带"编辑中/确认中"状态（家族第 4 次同型坑：@Builder 值参数
            //    不随 @State 重跑，key 不变就不重建 ⇒ 点了编辑看不到输入框）
          }, (t: JournalTemplate) => t.id + (this.editingId === t.id ? ':edit' : '') +
            (this.confirmId === t.id ? ':confirm' : ''))

          // ── 新建 ──
          Column() {
            Text('新建')
              .fontSize(RJ_FS_META)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .width('100%')
              .padding({ bottom: RJ_SP_SM })
            // ⚠️ ForEach key 带 `addBoxRev`：保存后版本号递增 ⇒ 整块重建 ⇒ 输入框真的清空
            ForEach([this.addBoxRev], () => {
              this.editorBox(this.newLabel, this.newLines, (v: string) => {
                this.newLabel = v;
              }, (v: string) => {
                this.newLines = v;
              }, () => {
                this.doAdd();
              }, null)
            }, (k: number) => 'addbox' + k)
          }
          .width('100%')
          .padding({ top: RJ_SP_XL })
        }
        .width('100%')
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_VOID_L })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }

  /**
   * 名字 + 正文的编辑块（新建与编辑共用）
   *
   * ⚠️ 为什么用四个回调而不是 @State 双向绑定：ArkTS 里 @Builder 拿不到调用方的
   *    `$$` 语法，值参数又**不随 @State 重跑**（输入内容会停在首帧）。
   *    回调是这里唯一既类型安全又能刷新的写法。
   */
  @Builder
  private editorBox(label: string, lines: string, onLabel: (v: string) => void,
    onLines: (v: string) => void, onSave: () => void, onCancel: (() => void) | null) {
    Column() {
      TextInput({ placeholder: '模板名字（最多 ' + TEMPLATE_LABEL_MAX + ' 字）', text: label })
        .fontSize(RJ_FS_CALLOUT)
        .backgroundColor(this.palette.card)
        .fontColor(this.palette.text)
        .placeholderColor(this.palette.text3)
        .height(38)
        .onChange((v: string) => {
          onLabel(v);
        })
      TextArea({ placeholder: '每行一句，最多 ' + TEMPLATE_LINES_MAX + ' 行（空行会留出来给你填）', text: lines })
        .fontSize(RJ_FS_CALLOUT)
        .backgroundColor(this.palette.card)
        .fontColor(this.palette.text)
        .placeholderColor(this.palette.text3)
        .height(96)
        .margin({ top: RJ_SP_SM })
        .onChange((v: string) => {
          onLines(v);
        })
      Row() {
        if (onCancel !== null) {
          Button('取消', { type: ButtonType.Normal, stateEffect: true })
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontSize(RJ_FS_CAPTION)
            .fontColor(this.palette.text3)
            .onClick(() => {
              onCancel();
            })
        }
        Button('保存', { type: ButtonType.Normal, stateEffect: true })
          .backgroundColor(this.palette.accent)
          .fontColor(this.palette.bg)
          .fontSize(RJ_FS_CAPTION)
          .borderRadius(RJ_RADIUS_MD)
          .padding({ left: RJ_SP_LG, right: RJ_SP_LG, top: RJ_SP_SM, bottom: RJ_SP_SM })
          .margin({ left: onCancel !== null ? RJ_SP_MD : 0 })
          .onClick(() => {
            onSave();
          })
      }
      .margin({ top: RJ_SP_SM })
    }
    .width('100%')
    .padding({ bottom: RJ_SP_MD })
  }
}
