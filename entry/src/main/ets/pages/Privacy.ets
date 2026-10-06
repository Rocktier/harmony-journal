import { router } from '@kit.ArkUI';
import { RJ_LH_PARA, RJ_FS_CALLOUT, RJ_FS_HEADING, RJ_FS_TITLE, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID, RJ_SP_XL, RJ_SP_XXL } from '../theme/RjTokens';

/**
 * 隐私政策（应用内可看 —— 照 RockReader 的做法）
 *
 * ⚠️ 双写纪律：这段文字与外部真源（党哥博客那篇法律文件）必须一致，
 * 不一致 = 上架时"政策与实现不符"的拒审理由。改一边就要改另一边。
 *
 * 口径：**零权限**（连 INTERNET 都没有）+ 本地加密 + 不采集不上传。
 */
const LINES: string[] = [
  '#隐私政策',
  'Rock私记（下称"本应用"）是一款**纯本地、不联网**的日记应用。',
  '这不是"默认关闭联网"，而是本应用不具备联网能力。',
  '#一、我们收集什么',
  '什么都不收集。',
  '你写的日记、选择的心情、导入的图片，全部只保存在你这台设备的本应用沙箱内，',
  '经过 AES-256-GCM 加密；我们不设服务器，也没有任何接收方。',
  '#二、我们联网吗',
  '不联网。书籍式离线：写日记、看日历、搜索、导出备份，全部在你的设备上完成。',
  '本应用没有申请网络权限（见第三节）—— 这是设计，不是开关。',
  '#三、我们申请了哪些权限',
  '没有。本应用不申请任何权限：没有网络、位置、通讯录、相机、麦克风、短信、',
  '通话记录、日历、健康数据、设备标识符等任何权限。',
  '关于你的文件：导出备份与导入通过系统文件选择器完成，是你主动指定的位置；',
  '本应用不会扫描、读取或上传你设备上的其他任何文件。',
  '#四、第三方 SDK',
  '当前版本不含任何第三方 SDK，也不含任何广告服务与数据统计服务。',
  '#五、你的日记怎么存',
  '· 正文与索引：加密后存于本应用沙箱，密钥由你的密码派生，只存在于内存中；',
  '· 图片：加密后存于本应用沙箱，正文只保存引用；',
  '· 备份：你主动导出的备份文件同样经过加密，存放在你自选的目录。',
  '#六、你的权利',
  '· 查看与修改：在应用内随时进行；',
  '· 彻底删除：卸载应用即全部删除（我们没有任何副本）；',
  '· 无需任何操作：本应用不具备联网能力，因此没有需要撤回的授权。',
  '#七、联系',
  '有问题写信到：danglei328@163.com'
];

/** 一段行内文字（bold 标记是否加粗） */
interface InlinePart {
  text: string;
  bold: boolean;
}

/**
 * 极简行内解析：按 `**` 切段，奇数段加粗。
 *
 * ⚠️ 为什么要做：政策文本里写了 `**纯本地、不联网**`，直接 Text 会把星号**原样显示**
 * （审核员必看的信任页出现裸星号 = 不专业）。支持行内加粗后，政策文本也能正常强调。
 */
function splitInline(line: string): InlinePart[] {
  const parts: string[] = line.split('**');
  const out: InlinePart[] = [];
  for (let i: number = 0; i < parts.length; i++) {
    if (parts[i].length === 0) {
      continue;
    }
    const part: InlinePart = { text: parts[i], bold: i % 2 === 1 };
    out.push(part);
  }
  return out;
}

@Entry
@Component
struct Privacy {
  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(RJ_FS_TITLE)
          .fontColor($r('app.color.rj_text2'))
          .onClick(() => {
            router.back();
          })
          .padding({ right: RJ_SP_LG })
        Text('隐私政策')
          .fontSize(RJ_FS_HEADING)
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(2)
      }
      .width('100%')
      .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, top: RJ_SP_XL, bottom: RJ_SP_LG })

      Scroll() {
        Column() {
          ForEach(LINES, (line: string) => {
            if (line.startsWith('#')) {
              Text(line.substring(1))
                .fontSize(RJ_FS_HEADING)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.rj_text'))
                .margin({ top: RJ_SP_XXL, bottom: RJ_SP_MD })
                .width('100%')
            } else {
              Text() {
                ForEach(splitInline(line), (part: InlinePart) => {
                  Span(part.text)
                    .fontWeight(part.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(part.bold ? $r('app.color.rj_text') : $r('app.color.rj_text2'))
                }, (part: InlinePart) => part.text)
              }
                .fontSize(RJ_FS_CALLOUT)
                .lineHeight(RJ_LH_PARA)
                .margin({ bottom: RJ_SP_SM })
                .width('100%')
            }
          }, (line: string, index: number) => index + line)
        }
        .padding({ left: RJ_SP_XXL, right: RJ_SP_XXL, bottom: RJ_SP_VOID })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
  }
}
