/**
 * SearchResultsSheet.ets
 * 
 * 联网搜索结果展示组件
 * 半模态弹窗形式展示搜索结果，支持点击跳转到浏览器
 */

import { WebBrowserParam } from './WebViewBrowser';
import { MessageStyle } from '../chat/MessageStyle';

export interface SearchResultItem {
  title: string;
  url: string;
  text: string;
  id?: string;
  index?: number;
  source?: string;
}

export interface SearchResultsSheetParam {
  query: string;
  answer?: string;
  items: SearchResultItem[];
  onResultSelected: (item: SearchResultItem) => void;
  onClose: () => void;
}

@Component
export struct SearchResultsSheet {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  @Prop param: SearchResultsSheetParam;
  @State selectedIndex: number = -1;

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('搜索结果')
          .fontSize(18)
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
          this.param.onClose();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .border({
        width: { bottom: 1 },
        color: $r('app.color.text_secondary')
      })

      // 搜索查询和摘要
      Column() {
        Text(`搜索: ${this.param.query}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.param.answer) {
          Text(this.param.answer)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.input_area_color'))

      // 搜索结果列表
      List({ space: 8 }) {
        ForEach(this.param.items, (item: SearchResultItem, idx: number) => {
          ListItem() {
            Column() {
              // 结果编号和标题
              Row({ space: 8 }) {
                Text(`${item.index ?? idx + 1}.`)
                  .fontSize(MessageStyle.SEARCH_RESULT_SUMMARY_FONT_SIZE)
                  .fontColor($r('app.color.text_secondary'))
                  .width(24)

                Text(item.title)
                  .fontSize(MessageStyle.SEARCH_RESULT_TITLE_FONT_SIZE)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              // 摘要文本
              if (item.text) {
                Text(item.text)
                  .fontSize(MessageStyle.SEARCH_RESULT_SUMMARY_FONT_SIZE)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 6, left: 32 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }

              // URL
              Row({ space: 6 }) {
                Text('🔗')
                  .fontSize(MessageStyle.SEARCH_RESULT_SUMMARY_FONT_SIZE)
                  .margin({ left: 32 })

                Text(item.url)
                  .fontSize(MessageStyle.SEARCH_RESULT_URL_FONT_SIZE)
                  .fontColor(Color.Blue)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .margin({ top: 6 })
              .alignItems(VerticalAlign.Center)
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
            // 跳转到浏览器
            try {
              const browserParam: WebBrowserParam = {
                url: item.url,
                title: item.title
              };
              this.pathStack.pushPathByName('WebBrowser', browserParam);
              // 延迟后关闭弹窗
              setTimeout(() => {
                this.param.onClose();
              }, 300);
            } catch (error) {
              console.error('Failed to navigate to browser:', error);
            }
          })
        })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .scrollBar(BarState.Auto)

      // 底部操作栏
      Row() {
        Button('关闭')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .layoutWeight(1)
          .onClick(() => {
            this.param.onClose();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .justifyContent(FlexAlign.Center)
      .border({
        width: { top: 1 },
        color: $r('app.color.text_secondary')
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.common_background'))
  }
}
