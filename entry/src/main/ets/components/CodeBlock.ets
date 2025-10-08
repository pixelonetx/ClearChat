import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

@Component
export struct CodeBlock {
  @Prop content: string;
  @Prop language: string = 'text';
  @State isHovered: boolean = false;

  private async copyToClipboard() {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.content);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);
      promptAction.showToast({ message: '代码已复制到剪贴板' });
    } catch (error) {
      console.error('Failed to copy to clipboard:', error);
      promptAction.showToast({ message: '复制失败' });
    }
  }

  build() {
    Column() {
      // 代码块标题栏
      Row() {
        // 语言标签
        Row() {
          Text(this.language)
            .fontSize(12)
            .fontColor($r('app.color.text_sec_color'))
            .margin({ left: 12 })
        }
        .layoutWeight(1)
        .height(32)
        .alignItems(VerticalAlign.Center)
        .borderRadius({ topLeft: 8 })

        // 复制按钮
        Row() {
          Button() {
            Row({ space: 4 }) {
              Text('复制')
                .fontSize(12)
                .fontColor($r('app.color.text_sec_color'))
            }
          }
          .backgroundColor($r('app.color.bg_secondary'))
          .type(ButtonType.Normal)
          .border({ width: 1, color: '#E0E0E0', radius: 4 })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.copyToClipboard();
          })
        }
        .height(32)
        .alignItems(VerticalAlign.Center)
        .padding({ right: 12 })
        .borderRadius({ topRight: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 代码内容区域
      Scroll() {
        Text(this.content)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_fa_text_secondary'))
          .fontFamily('Monaco, Menlo, "Ubuntu Mono", monospace')
          .padding(12)
          .textAlign(TextAlign.Start)
          .textOverflow({ overflow: TextOverflow.None })
          .maxLines(999)
          .copyOption(CopyOptions.InApp)
          .wordBreak(WordBreak.BREAK_WORD)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(4)
      .edgeEffect(EdgeEffect.None)
      .borderRadius({ bottomLeft: 8, bottomRight: 8 })
    }
    .border({ width: 1, color: '#E0E0E0' })
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.bg_secondary'))
    .margin({ top: 8, bottom: 8 })
  }
}
