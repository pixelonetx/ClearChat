/**
 * SearchReferencesDialog.ets
 * 
 * 搜索引用对话框
 * 在大模型消息中点击搜索引用时显示
 */

import { WebBrowserParam } from '../components/WebViewBrowser';

export interface SearchReference {
  title: string;
  url: string;
  snippet?: string;
  index?: number;
}

@CustomDialog
export struct SearchReferencesDialog {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  @Prop references: SearchReference[];
  @Prop query: string;
  
  controller?: CustomDialogController;
  @State selectedIndex: number = -1;

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('搜索引用')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)

        Button() {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(24)
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
        }
        .type(ButtonType.Circle)
        .backgroundColor(Color.Transparent)
        .size({ width: 40, height: 40 })
        .onClick(() => {
          this.controller?.close();
        })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      // 搜索查询显示
      if (this.query) {
        Text(`关键词: ${this.query}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .width('100%')
      }

      // 引用列表
      List({ space: 8 }) {
        ForEach(this.references, (ref: SearchReference, idx: number) => {
          ListItem() {
            Column() {
              // 序号 + 标题
              Row({ space: 8 }) {
                Text(`${ref.index ?? idx + 1}.`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width(24)

                Text(ref.title)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              // 摘要
              if (ref.snippet) {
                Text(ref.snippet)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 6, left: 32 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }

              // URL
              if (ref.url) {
                Row({ space: 4 }) {
                  Text('🔗')
                    .fontSize(10)
                    .margin({ left: 32 })

                  Text(ref.url)
                    .fontSize(10)
                    .fontColor(Color.Blue)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .margin({ top: 6 })
                .alignItems(VerticalAlign.Center)
              }
            }
            .width('100%')
            .padding({ top: 12, bottom: 12, left: 12, right: 12 })
            .borderRadius(8)
            .backgroundColor(
              this.selectedIndex === idx
                ? $r('app.color.input_area_color')
                : Color.Transparent
            )
            .border({
              width: 1,
              color: this.selectedIndex === idx
                ? $r('app.color.text_color')
                : $r('app.color.text_secondary')
            })
          }
          .onClick(() => {
            this.selectedIndex = idx;
            // 点击后跳转到浏览器
            if (ref.url) {
              try {
                const browserParam: WebBrowserParam = {
                  url: ref.url,
                  title: ref.title
                };
                this.pathStack.pushPathByName('WebBrowser', browserParam);
                // 延迟关闭对话框
                setTimeout(() => {
                  this.controller?.close();
                }, 300);
              } catch (error) {
                console.error('Failed to navigate:', error);
              }
            }
          })
        })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .scrollBar(BarState.Auto)

      // 底部操作
      Button('关闭')
        .type(ButtonType.Capsule)
        .width('80%')
        .height(44)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.controller?.close();
        })
    }
    .width('100%')
    .height('70%')
    .backgroundColor($r('app.color.common_background'))
  }
}
