/**
 * SearchReferencesDialog.ets
 * 
 * 搜索引用对话框 - 原生半模态样式
 * 在大模型消息中点击搜索引用时显示
 */

import { WebBrowserParam } from '../utils/WebViewBrowser';

export interface SearchReference {
  title: string;
  url: string;
  snippet?: string;
  index?: number;
}

@Builder
export function SearchReferencesSheet(references: SearchReference[], query: string, pathStack: NavPathStack, onClose?: () => void) {
  Column({ space: 0 }) {
    // 顶部指示条
    Row() {
      Divider()
        .width(36)
        .height(4)
        .backgroundColor($r('sys.color.ohos_id_color_list_separator'))
        .borderRadius(2)
    }
    .width('100%')
    .height(20)
    .justifyContent(FlexAlign.Center)

    // 标题栏
    Row() {
      Text('搜索引用')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      
      Blank()
      
      if (query) {
        Text(`"${query}"`)
          .fontSize(14)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 150 })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 16 })

    // 来源计数
    Text(`${references.length} 个来源`)
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .padding({ left: 24, right: 24, bottom: 12 })

    Divider()
      .color($r('sys.color.ohos_id_color_list_separator'))

    // 引用列表
    List({ space: 0 }) {
      ForEach(references, (ref: SearchReference, idx: number) => {
        ListItem() {
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              // 序号
              Text(`${ref.index ?? idx + 1}`)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_emphasize'))
                .width(28)

              // 内容
              Column({ space: 4 }) {
                Text(ref.title)
                  .fontSize(16)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (ref.snippet) {
                  Text(ref.snippet)
                    .fontSize(14)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 2 })
                }

                if (ref.url) {
                  Text(ref.url)
                    .fontSize(12)
                    .fontColor($r('sys.color.ohos_id_color_emphasize'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Image($r('sys.symbol.chevron_right'))
                .width(20)
                .height(20)
                .fillColor($r('sys.color.ohos_id_color_fourth'))
            }
            .width('100%')
            .padding({ left: 24, right: 24, top: 16, bottom: 16 })
            .onClick(() => {
              if (ref.url) {
                const browserParam: WebBrowserParam = {
                  url: ref.url,
                  title: ref.title
                };
                pathStack.pushPathByName('WebBrowser', browserParam);
                onClose?.();
              }
            })

            // 分隔线放在列表项内部
            if (idx < references.length - 1) {
              Divider()
                .color($r('sys.color.ohos_id_color_list_separator'))
                .margin({ left: 64, right: 24 })
            }
          }
        }
        .backgroundColor($r('sys.color.ohos_id_color_background'))
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }
  .width('100%')
  .height('100%')
  .backgroundColor($r('sys.color.ohos_id_color_background'))
}

@CustomDialog
export struct SearchReferencesDialog {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  @Prop references: SearchReference[];
  @Prop query: string;
  
  controller?: CustomDialogController;

  build() {
    Column({ space: 0 }) {
      SearchReferencesSheet(this.references, this.query, this.pathStack, () => {
        this.controller?.close();
      })
    }
    .width('100%')
    .height('75%')
  }
}
