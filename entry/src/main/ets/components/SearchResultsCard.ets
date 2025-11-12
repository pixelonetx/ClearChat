/**
 * SearchResultsCard.ets
 * 
 * 搜索结果卡片组件
 * 展示 web 搜索结果、引用、加载状态
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

const DOMAIN = 0xFF00;
const TAG = 'SearchResultsCard';

/**
 * 搜索结果项数据
 */
export interface SearchResultItemData {
  title: string;
  url: string;
  text: string;
  id?: string;
  index?: number;
}

/**
 * 搜索结果卡片属性
 */
export interface SearchResultsCardProps {
  query?: string;
  results?: SearchResultItemData[];
  isLoading?: boolean;
  error?: string;
  onLinkTap?: (url: string) => void;
}

@Component
export struct SearchResultsCard {
  @Prop query: string = '';
  @Prop results: SearchResultItemData[] = [];
  @Prop isLoading: boolean = false;
  @Prop error: string = '';
  onLinkTap?: (url: string) => void;

  private scrollerForList: Scroller = new Scroller();

  build() {
    Column() {
      // 标题和搜索查询
      if (this.query.length > 0) {
        Row() {
          Image($r('app.media.ic_search'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.icon_primary'))

          Text(this.query)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .margin({ left: 8 })
            .maxLines(1)
            .ellipsisMode(EllipsisMode.END)

          // 加载指示器
          if (this.isLoading) {
            Progress({
              value: 0,
              total: 100,
              type: ProgressType.Ring
            })
              .width(20)
              .height(20)
              .color($r('app.color.brand_primary'))
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.surface_secondary'))
        .borderRadius(8)
        .margin({ bottom: 12 })
      }

      // 加载状态
      if (this.isLoading && this.results.length === 0) {
        this.loadingView()
      }

      // 错误状态
      if (this.error.length > 0 && this.results.length === 0) {
        this.errorView()
      }

      // 结果列表
      if (this.results.length > 0) {
        Scroll(this.scrollerForList) {
          Column({ space: 8 }) {
            ForEach(this.results, (item: SearchResultItemData, index: number) => {
              this.resultItemView(item, index)
            }, (item: SearchResultItemData) => item.id || item.url)
          }
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .width('100%')
        .layoutWeight(1)
      }

      // 无结果
      if (!this.isLoading && this.results.length === 0 && this.error.length === 0 && this.query.length > 0) {
        this.noResultsView()
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
  }

  @Builder
  private loadingView() {
    Column({ space: 12 }) {
      // 加载骨架屏
      ForEach([0, 1, 2], () => {
        Column() {
          Column()
            .width('60%')
            .height(14)
            .backgroundColor($r('app.color.skeleton_shine'))
            .borderRadius(4)

          Column()
            .width('100%')
            .height(10)
            .backgroundColor($r('app.color.skeleton_shine'))
            .borderRadius(4)
            .margin({ top: 8 })

          Column()
            .width('80%')
            .height(10)
            .backgroundColor($r('app.color.skeleton_shine'))
            .borderRadius(4)
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.surface_secondary'))
        .borderRadius(8)
      })

      Text('正在搜索...')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 8 })
    }
    .width('100%')
    .padding(12)
  }

  @Builder
  private errorView() {
    Column({ space: 8 }) {
      Image($r('app.media.ic_error'))
        .width(32)
        .height(32)
        .fillColor($r('app.color.error_primary'))

      Text('搜索失败')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text(this.error)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(16)
  }

  @Builder
  private noResultsView() {
    Column({ space: 8 }) {
      Image($r('app.media.ic_search'))
        .width(32)
        .height(32)
        .fillColor($r('app.color.text_secondary'))
        .opacity(0.5)

      Text('暂无结果')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(16)
  }

  @Builder
  private resultItemView(item: SearchResultItemData, index: number) {
    Row({ space: 12 }) {
      // 索引徽章
      Column() {
        Text(`${index + 1}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(26)
      .height(26)
      .backgroundColor($r('sys.color.ohos_id_color_emphasize'))
      .borderRadius(13)
      .justifyContent(FlexAlign.Center)

      // 内容区域
      Column({ space: 6 }) {
        // 标题
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 摘要/文本
        if (item.text) {
          Text(item.text)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(18)
        }

        // URL 栏
        Row({ space: 6 }) {
          Image($r('sys.symbol.link'))
            .width(12)
            .height(12)
            .fillColor($r('sys.color.ohos_id_color_emphasize'))

          Text(item.url)
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_emphasize'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Image($r('sys.symbol.arrow_up_right'))
            .width(12)
            .height(12)
            .fillColor($r('sys.color.ohos_id_color_text_secondary'))
            .opacity(0.6)
        }
        .width('100%')
        .padding({ top: 4, bottom: 4, left: 8, right: 8 })
        .backgroundColor($r('app.color.input_area_color'))
        .borderRadius(6)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.common_background'))
    .borderRadius(10)
    .border({
      width: 1,
      color: $r('sys.color.ohos_id_color_list_separator')
    })
    .shadow({
      radius: 4,
      color: 'rgba(0, 0, 0, 0.04)',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.onLinkTap?.(item.url);
    })
    .stateStyles({
      pressed: {
        .scale({ x: 0.98, y: 0.98 })
        .backgroundColor($r('app.color.input_area_color'))
      }
    })
    .animation({
      duration: 200,
      curve: Curve.EaseInOut
    })
  }
}
