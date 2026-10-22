import { router } from '@kit.ArkUI';
import { RJ_LH_PARA, RJ_FS_CALLOUT, RJ_FS_HEADING, RJ_FS_TITLE, RJ_SP_LG, RJ_SP_MD, RJ_SP_SM, RJ_SP_VOID, RJ_SP_XL, RJ_SP_XXL } from '../theme/RjTokens';
import { ChevronButton } from '../components/ChevronButton';
import { ThemePalette } from '../theme/ThemePalette';

/**
 * 隐私政策（应用内可看 —— 照 RockReader 的做法）
 *
 * ⚠️ 双写纪律：这段文字必须与外部真源（党哥博客那篇法律文件的 `#privacy` 章）**逐字一致**，
 * 不一致 = 上架时"政策与实现不符"的拒审理由。改一边就要改另一边。
 *
 * 外部真源 = 党哥博客《Rock 家族 隐私政策、用户协议与数据权利》的 `#privacy` 章
 * （一篇覆盖 Rock阅读 + Rock私记 两款应用，桌面底稿《Rock家族-隐私政策-用户协议-数据权利.md》）；
 * 这里只放**隐私政策章**（用户协议 `#agreement` 与数据权利 `#rights` 只在网页侧提供）。
 *
 * ⚠️ 为什么是"家族版"而不是"Rock私记专属版"：两款应用共用同一个隐私政策链接，
 * 页面正文必须同时涵盖两者；应用内若只写自己那一款，就与真源不一致（= 拒审理由）。
 *
 * 口径：**零权限**（连 INTERNET 都没有）+ 本地加密 + 不采集不上传。
 */
const LINES: string[] = [
  '#一、我们收集什么',
  '不收集任何个人信息。',
  '两款应用都没有账号、没有登录、没有云端同步。我们不知道你是谁，',
  '也无法把你的任何数据关联到你这个人。',
  '#二、你的数据存在哪里',
  '全部存在你的设备本地（应用沙箱内），不会离开你的设备。',
  'Rock阅读：',
  '· 导入的书籍：应用沙箱（从你选中的文件复制一份）',
  '· 阅读进度：设备本地数据库',
  '· 设置（字号、行距、主题、字体、朗读偏好）：设备本地偏好存储',
  '· 字体文件：随应用内置，安装即在你的设备上',
  'Rock私记（日记内容经 AES-256-GCM 加密后存储）：',
  '· 日记正文与索引：应用沙箱，密钥由你的主密码派生，只存在于内存中；',
  '· 心情与图片：应用沙箱（图片单独加密存储，正文只保存引用）；',
  '· 设置（字号、主题等）：设备本地偏好存储；',
  '· 备份文件：由你主动导出到你自选的目录，同样经过加密。',
  '以上任何一项都不会上传。卸载应用 = 该应用的上述数据全部删除；',
  '你也可以在应用内删除单本书 / 单篇日记，同时删除它的副本与相关记录。',
  '#三、我们联网吗',
  '不联网。两款应用都没有任何需要联网的功能：',
  '· Rock阅读：书籍由你从本地导入，字体已内置在应用里，',
  '　阅读、目录、搜索、统计与朗读全部在你的设备上完成；',
  '· Rock私记：写日记、看日历、搜索、导出备份，全部在你的设备上完成。',
  'Rock阅读 的朗读使用设备自带的语音合成能力，在你的设备上完成，',
  '不会把书本内容发送到任何服务器。（个别朗读音色由系统提供，',
  '首次使用时可能需要下载语音资源；下载的是语音模型本身，不包含你的任何数据，',
  '下载完成后朗读依旧离线进行。）',
  '我们也没有申请网络权限（见第四节）—— 这不是"默认关闭"，',
  '而是应用本身不具备联网能力。',
  '#四、我们申请了哪些权限',
  '没有。两款应用都不申请任何权限：没有网络、位置、通讯录、相机、麦克风、',
  '短信、通话记录、日历、健康数据、设备标识符等任何权限。',
  '关于你的文件：',
  '· Rock阅读：导入书籍通过系统文件选择器完成，是你主动挑选的那一个文件，',
  '　应用只读取它并复制一份到沙箱；',
  '· Rock私记：插入图片、导出与导入备份，也都通过系统文件选择器完成，',
  '　是你主动指定的那一个文件或位置。',
  '两款应用都不会扫描、读取或上传你设备上的其他任何文件。',
  '#五、第三方 SDK 与开源素材',
  '当前版本不含任何第三方 SDK，也不含任何广告服务与数据统计服务。',
  'Rock阅读 内置字体基于思源宋体（Noto Serif SC）做 GB2312 子集而来，',
  '以 SIL OFL 1.1 授权发布，可免费商用；原字体的版权归其原作者所有。',
  'Rock私记 未内置任何第三方字体或素材。',
  '#六、数据出境',
  '不存在。你的数据不出设备，我们也没有任何服务器可接收。',
  '#七、未成年人',
  '两款应用都不提供个性化推荐，不基于用户画像推送内容。',
  '未成年人使用不产生额外数据收集。',
  '#八、你的权利',
  '· 查看与导出：数据就在设备上，应用内可直接查看（Rock私记 还可随时修改）；',
  '　Rock阅读 如需导出，可在卸载前通过系统文件管理访问应用目录；',
  '　Rock私记 可在应用内导出加密备份（.rkdbak）或导出为 TXT / Markdown；',
  '· 删除：Rock阅读 可在应用内删除单本书及其记录；',
  '　Rock私记 可在应用内删除单篇日记；卸载应用可删除该应用全部数据；',
  '· 无需任何操作：两款应用都不具备联网能力，因此没有需要撤回的授权。',
  '#九、政策更新',
  '如本政策发生实质性变更，会在应用内及上架页面更新。',
  '若不同意，可停止使用并卸载（卸载会删除全部本地数据）。',
  '#十、联系我们',
  '如对本政策有疑问，或需要行使上述权利，可通过邮件联系：',
  'danglei328@163.com',
  '我们会在合理期限内答复。'
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
  /** 运行时色板（深浅切换 = AppStorage 换对象，页面栈不动；见 ThemePalette 头注） */
  @StorageLink('palette') palette: ThemePalette = new ThemePalette(false);

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
        Text('隐私政策')
          .fontSize(RJ_FS_HEADING)
          .fontColor(this.palette.text)
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
                .fontColor(this.palette.text)
                .margin({ top: RJ_SP_XXL, bottom: RJ_SP_MD })
                .width('100%')
            } else {
              Text() {
                ForEach(splitInline(line), (part: InlinePart) => {
                  Span(part.text)
                    .fontWeight(part.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(part.bold ? this.palette.text : this.palette.text2)
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
    .backgroundColor(this.palette.bg)
  }
}
