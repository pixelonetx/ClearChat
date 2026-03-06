/**
 * MessageList 组件
 * 消息列表展示组件，包含空状态、消息列表、滚动到底部按钮
 */
import { ChatMessage } from '../../services/DataModels';
import { ArrayDataSource } from '../../utils/ArrayDataSource';
import { MessageItem } from './MessageItem';

/**
 * MessageList 配置接口
 */
export interface MessageListConfig {
  hasSettings: boolean;
  isInitialized: boolean;
}

/**
 * MessageList 组件
 */
@Component
export struct MessageList {
  // 数据源 - 使用普通属性传递引用
  messageDataSource: ArrayDataSource<ChatMessage> = new ArrayDataSource<ChatMessage>([]);
  
  // 状态
  @Link messages: ChatMessage[];
  @Link showScrollToBottomButton: boolean;
  @Link shouldAutoScroll: boolean;
  
  // 配置
  @Prop config: MessageListConfig = { hasSettings: false, isInitialized: false };
  
  // Scroller 引用
  scroller: Scroller = new Scroller();
  
  // 回调
  onCopyMessage?: (message: ChatMessage) => Promise<void>;
  onEditMessage?: (message: ChatMessage) => void;
  onDeleteMessage?: (message: ChatMessage) => Promise<void>;
  onRegenerateMessage?: (message: ChatMessage) => Promise<void>;
  onHideKeyboard?: () => void;
  onOpenModelSettings?: () => void;

  build() {
    Column() {
      if (this.messages.length === 0) {
        // 空状态
        this.EmptyState()
      } else {
        // 消息列表
        this.MessageListContent()
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  EmptyState() {
    Column() {
      Text('有什么可以帮忙的？')
        .fontSize(22)
        .margin({ top: 16 })

      if (!this.config.hasSettings) {
        Button('配置API设置')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .padding({ left: 20, right: 20 })
          .margin({ top: 16 })
          .onClick((): void => {
            this.onOpenModelSettings?.();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  MessageListContent() {
    Stack() {
      // 消息列表（使用 LazyForEach 虚拟化以提升性能）
      Scroll(this.scroller) {
        Column() {
          LazyForEach(this.messageDataSource, (message: ChatMessage, index: number) => {
            MessageItem({
              message: message,
              onCopy: (msg: ChatMessage): Promise<void> => {
                return this.onCopyMessage?.(msg) ?? Promise.resolve();
              },
              onEdit: (msg: ChatMessage): void => {
                this.onEditMessage?.(msg);
              },
              onDelete: (msg: ChatMessage): Promise<void> => {
                return this.onDeleteMessage?.(msg) ?? Promise.resolve();
              },
              onRegenerate: (msg: ChatMessage): Promise<void> => {
                return this.onRegenerateMessage?.(msg) ?? Promise.resolve();
              }
            })
          }, (message: ChatMessage, index: number): string => {
            // 稳定的 key 生成策略，减少重建和提升滚动性能
            if (message.id !== undefined) {
              return `saved_${message.id}_${message.content.length}`;
            } else {
              return `temp_${index}_${message.role}_${message.content.length}_${message.timestamp % 10000}`;
            }
          })
        }
        .padding({
          left: 16,
          right: 16,
          top: 16,
          bottom: 16
        })
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .friction(0.8)
      .edgeEffect(EdgeEffect.Spring)
      .onScrollEdge((side: Edge): void => {
        if (side === Edge.Bottom) {
          this.showScrollToBottomButton = false;
          this.shouldAutoScroll = true;
        }
      })
      .onDidScroll((xOffset: number, yOffset: number): void => {
        if (yOffset > 0 && !this.showScrollToBottomButton) {
          this.showScrollToBottomButton = true;
          this.shouldAutoScroll = false;
        }
      })
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.TopStart)
      .onClick((): void => {
        this.onHideKeyboard?.();
      })

      // "滚动到底部"按钮
      if (this.showScrollToBottomButton) {
        this.ScrollToBottomButton()
      }
    }
    .alignContent(Alignment.Bottom)
  }

  @Builder
  ScrollToBottomButton() {
    Button('↓')
      .fontSize(16)
      .fontColor($r('app.color.text_color'))
      .type(ButtonType.Circle)
      .backgroundColor(Color.Transparent)
      .size({ height: 40, width: 40 })
      .padding({ left: 6, right: 6 })
      .backgroundBlurStyle(BlurStyle.Thin, {
        colorMode: ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.DEFAULT,
        scale: 1.0
      })
      .onClick((): void => {
        if (this.scroller) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
        this.shouldAutoScroll = true;
        this.showScrollToBottomButton = false;
      })
      .margin({ bottom: 16 })
      .zIndex(5)
  }

  /**
   * 滚动到底部
   */
  scrollToBottom(): void {
    if (this.scroller) {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (error) {
        // 备用滚动方法
        try {
          const currentOffset = this.scroller.currentOffset();
          if (currentOffset) {
            this.scroller.scrollTo({ xOffset: 0, yOffset: (currentOffset.yOffset || 0) + 1000 });
          }
        } catch (scrollError) {
          // ignore
        }
      }
    }
  }
}
