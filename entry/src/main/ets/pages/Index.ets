import { APP_NAME_CN, APP_VERSION } from '../common/AppMeta';

/**
 * 骨架占位页（Phase 1）。
 *
 * 只验证：工程能编译、能启动、家族观感（纯黑底 + 白字 + 右上红点）能立住。
 * Phase 4 编辑器起来后，这里会变成「今天写一篇」的主页面；
 * 解锁页（Phase 3 HUKS 生物）会插在 EntryAbility 与本页之间。
 */
@Entry
@Component
struct Index {
  build() {
    Stack() {
      Column() {
        Blank()

        // 家族红点：应用内 UI 的识别锚（与图标的红点同色同源）
        Circle({ width: 10, height: 10 })
          .fill($r('app.color.rj_red'))
          .margin({ bottom: 24 })

        Text(APP_NAME_CN)
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rj_text'))
          .letterSpacing(6)

        Text('纯粹私密 · 永不上传')
          .fontSize(13)
          .fontColor($r('app.color.rj_text3'))
          .margin({ top: 12 })
          .letterSpacing(3)

        Blank()

        Text(`v${APP_VERSION}`)
          .fontSize(10)
          .fontColor($r('app.color.rj_text3'))
          .fontFamily('monospace')
          .margin({ bottom: 32 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rj_bg'))
    .alignContent(Alignment.Center)
  }
}
