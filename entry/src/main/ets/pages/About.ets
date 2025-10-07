import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

// 跳转页面入口函数
@Builder
export function AboutBuilder() {
  About();
}

@Entry
@Component
struct About {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;

  @State qqGroupNumber: string = '428701303'; // 后续填写QQ群号

  private copyToClipboard(text: string) {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);

      promptAction.showToast({
        message: '已复制到剪贴板',
        duration: 2000
      });
    } catch (error) {
      promptAction.showToast({
        message: '复制失败',
        duration: 2000
      });
    }
  }

  @Builder
  InfoCard(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_color'))
        .margin({ bottom: 8 })
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(content)
        .fontSize(14)
        .fontColor($r('app.color.text_sec_color'))
        .lineHeight(20)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
    .borderRadius(12)
    .margin({ bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Column() {

        Scroll() {
          Column() {
            // 应用图标和名称
            Column() {
              Image($r('app.media.foreground'))
                .width(80)
                .height(80)
                .borderRadius(16)
                .margin({ bottom: 12 })

              Text('ClearChat')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_color'))
                .margin({ bottom: 4 })

              Text('AI 对话助手')
                .fontSize(14)
                .fontColor($r('app.color.text_sec_color'))
                .margin({ bottom: 12 })
            }
            .margin({ top: 32, bottom: 32 })

            // 应用介绍
            this.InfoCard(
              '应用简介',
              'ClearChat 是一款支持多种 AI 模型的智能对话应用。您可以与 deepseek、通义千问等先进的 AI 模型进行自然对话，获得写作、编程、学习等各方面的智能协助。'
            )

            // 版本信息
            this.InfoCard(
              '版本信息',
              '版本号：1.0.0\n构建时间：2025年9月\n\n更新日志：\n• 首次发布\n• 支持多种 AI 模型\n• 完整的 Markdown 渲染\n• 本地对话管理'
            )

            // 数据安全
            this.InfoCard(
              '数据安全说明',
              '重要提醒：本应用不存储您的任何对话数据。所有对话内容仅保存在您的设备本地数据库中。\n\n当您使用 AI 服务时，您的消息将直接发送给您选择的服务提供商（如深度求索、阿里云等）进行处理。这些第三方服务商有各自的数据处理政策，我们无法控制也不保证他们对您数据的处理方式。\n\n本应用仅作为 AI 服务的客户端工具，不对第三方 AI 服务商提供的内容负责。用户在使用过程中应遵守相关法律法规，合理使用 AI 服务。\n\n第三方服务的可用性、准确性及数据处理方式由各服务商独立负责，与本应用开发者无关。'
            )

            // QQ交流群
            Column() {
              Text('交流反馈')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_color'))
                .margin({ bottom: 8 })
                .width('100%')
                .textAlign(TextAlign.Start)

              Text('欢迎加入 QQ 交流群，获取使用帮助或反馈问题：')
                .fontSize(14)
                .fontColor($r('app.color.text_sec_color'))
                .lineHeight(20)
                .margin({ bottom: 12 })
                .width('100%')
                .textAlign(TextAlign.Start)

              Row() {
                Text(`QQ群：${this.qqGroupNumber}`)
                  .fontSize(16)
                  .fontColor('#007AFF')
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                Button('复制群号')
                  .height(36)
                  .backgroundColor('#007AFF')
                  .fontColor('#FFFFFF')
                  .fontSize(14)
                  .borderRadius(18)
                  .enabled(this.qqGroupNumber !== '待填写')
                  .onClick(() => {
                    if (this.qqGroupNumber !== '待填写') {
                      this.copyToClipboard(this.qqGroupNumber);
                    }
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
            .borderRadius(12)
            .margin({ bottom: 12 })
            .alignItems(HorizontalAlign.Start)

          }
          .padding(16)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.common_background'))
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight)
    })
    .title('关于')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })

  }
}