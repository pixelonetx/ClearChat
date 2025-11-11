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
    Column({ space: 4 }) {
      // 标题和 URL
      Row() {
        Column({ space: 4 }) {
          Text(item.title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .ellipsisMode(EllipsisMode.END)

          Text(item.url)
            .fontSize(11)
            .fontColor($r('app.color.brand_primary'))
            .maxLines(1)
            .ellipsisMode(EllipsisMode.END)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Image($r('app.media.ic_external_link'))
          .width(14)
          .height(14)
          .fillColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => {
        this.onLinkTap?.(item.url);
      })

      // 摘要/文本
      Text(item.text)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .ellipsisMode(EllipsisMode.END)
        .width('100%')
        .margin({ top: 4 })

      // 索引标签（用于引用）
      if (item.index !== undefined && item.id) {
        Row({ space: 4 }) {
          Text(`[${item.index}]`)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.surface_secondary'))
            .borderRadius(4)

          Text(`ID: ${item.id}`)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.surface_secondary'))
    .borderRadius(8)
  }
}
