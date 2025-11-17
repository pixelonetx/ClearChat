/**
 * 关于应用的半模态弹窗组件
 */

// 导出 Builder 函数，可以直接在 bindSheet 中使用
@Builder
export function AboutSheetBuilder() {
  Column() {
    // 应用信息区域
    Column({ space: 8 }) {
      // 应用图标
      Image($r('app.media.foreground'))
        .width(80)
        .height(80)
        .borderRadius(20)

      // 应用名称
      Text('ClearChat')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))

      // 版本信息
      Text('版本 0.3.1')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 16 })
    .alignItems(HorizontalAlign.Center)

    // 功能特性列表
    Column({ space: 12 }) {
      InfoCard('隐私安全', '所有对话数据仅存储在本地设备，确保您的隐私安全')
      InfoCard('多模型支持', '支持接入多种主流大语言模型服务')
      InfoCard('Markdown 渲染', '完整支持 Markdown 语法，让对话更易读')
    }
    .width('100%')

    Text('特别感谢全体用户')
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .padding({top:16, bottom:16})
  }
  .width('100%')
  .padding({ left: 16, right: 16, top: 24, bottom: 24 })
}

@Builder
function InfoCard(title: string, content: string) {
  Column() {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .width('100%')
      .margin({ bottom: 8 })

    Text(content)
      .fontSize(14)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .lineHeight(20)
      .width('100%')
  }
  .width('100%')
  .padding(16)
  .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
  .borderRadius(16)
  .alignItems(HorizontalAlign.Start)
}
