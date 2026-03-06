/**
 * ChatSidebar 组件
 * 聊天侧边栏，包含对话列表、新建对话、设置入口等功能
 */
import { Conversation } from '../../services/ConversationModels';

/**
 * 侧边栏配置接口
 */
export interface ChatSidebarConfig {
  topRectHeight: number;
  bottomRectHeight: number;
}

/**
 * 对话分组数据
 */
export interface GroupedConversations {
  groups: Record<string, Conversation[]>;
  keys: string[];
}

/**
 * ChatSidebar 组件
 */
@Component
export struct ChatSidebar {
  // 对话数据
  @Link conversations: Conversation[];
  @Link currentConversation: Conversation | null;
  
  // 分组数据
  @Prop groupedConversations: Record<string, Conversation[]> = {};
  @Prop groupedKeys: string[] = [];
  
  // UI 状态
  @Link showSideBar: boolean;
  @Link showControlButton: boolean;
  
  // 配置
  @Prop config: ChatSidebarConfig = { topRectHeight: 0, bottomRectHeight: 0 };
  
  // 回调
  onCreateConversation?: () => void;
  onSelectConversation?: (conversation: Conversation) => void;
  onRenameConversation?: (conversation: Conversation) => void;
  onDeleteConversation?: (conversation: Conversation) => void;
  onOpenSettings?: () => void;
  onHideSidebar?: () => void;

  build() {
    Column() {
      // 侧边栏标题
      Column() {
        Row() {
          Text('对话列表')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)

          Button() {
            Image($r('app.media.open_sidebar'))
              .size({ width: 24, height: 24 })
              .fillColor($r('sys.color.ohos_id_color_text_primary'))
          }
          .type(ButtonType.Circle)
          .size({ width: 40, height: 40 })
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.handleHideSidebar();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 20, right: 16 })
        .justifyContent(FlexAlign.SpaceBetween)

        // 新建对话按钮
        Row() {
          Button('新建对话')
            .fontColor($r('app.color.text_color'))
            .width('90%')
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .borderRadius(24)
            .onClick(() => {
              this.onCreateConversation?.();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 12, bottom: 12 })
      }
      .margin({ top: this.getUIContext().px2vp(this.config.topRectHeight) })

      // 对话列表
      if (this.conversations.length === 0) {
        this.EmptyState()
      } else {
        this.ConversationList()
      }

      // 底部功能按钮
      Column() {
        Row() {
          Button('设置')
            .fontColor($r('app.color.text_color'))
            .width('90%')
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .borderRadius(24)
            .onClick(() => {
              this.onOpenSettings?.();
            })
            .margin({ top: 12, bottom: 12 })
        }
      }
      .width('100%')
      .margin({ bottom: this.getUIContext().px2vp(this.config.bottomRectHeight) })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.common_background'))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  EmptyState() {
    Scroll() {
      Column() {
        Text('还没有对话记录')
          .fontSize(14)
          .margin({ top: 12 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
  }

  @Builder
  ConversationList() {
    Scroll() {
      Column() {
        ForEach(this.groupedKeys, (dateKey: string) => {
          // 日期分组标题
          Text(this.formatDateGroup(dateKey))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 4, top: 12, bottom: 6 })
            .textAlign(TextAlign.Start)
            .opacity(0.7)

          // 该日期下的对话列表
          List({ space: 4 }) {
            ForEach((this.groupedConversations?.[dateKey]) || [], (conversation: Conversation) => {
              ListItem() {
                this.ConversationItem(conversation)
              }
              .swipeAction({
                end: () => this.SwipeActions(conversation),
                edgeEffect: SwipeEdgeEffect.Spring
              })
            })
          }
          .width('100%')
          .scrollBar(BarState.Off)
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
  }

  @Builder
  ConversationItem(conversation: Conversation) {
    Row() {
      Column() {
        Text(conversation.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.formatTime(conversation.updatedAt))
          .fontSize(12)
          .margin({ top: 2 })
          .width('100%')
          .textAlign(TextAlign.Start)
          .opacity(0.6)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(8)
    .onClick(() => {
      this.onSelectConversation?.(conversation);
      this.handleHideSidebar();
    })
  }

  @Builder
  SwipeActions(conversation: Conversation) {
    Row() {
      // 重命名按钮
      Button() {
        Image($r('app.media.square_and_pencil'))
          .size({ width: 20, height: 20 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .size({ width: 40, height: 40 })
      .backgroundColor($r('sys.color.button_background_color_transparent'))
      .margin({ left: 10, right: 5 })
      .onClick(() => {
        this.onRenameConversation?.(conversation);
      })

      // 删除按钮
      Button() {
        Image($r('app.media.trash'))
          .size({ width: 20, height: 20 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .size({ width: 40, height: 40 })
      .backgroundColor($r('sys.color.button_background_color_transparent'))
      .margin({ left: 5, right: 10 })
      .onClick(() => {
        this.onDeleteConversation?.(conversation);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  private handleHideSidebar(): void {
    this.onHideSidebar?.();
    this.showControlButton = !this.showControlButton;
    this.getUIContext().animateTo({
      duration: 300,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.showSideBar = false;
    });
  }

  // 格式化日期分组显示文本
  private formatDateGroup(dateKey: string): string {
    if (dateKey === 'today') {
      return '今天';
    } else if (dateKey === 'yesterday') {
      return '昨天';
    } else if (dateKey === 'this_week') {
      return '一周内';
    } else if (dateKey === 'this_month') {
      return '30天内';
    } else if (dateKey.includes('-')) {
      const dateParts = dateKey.split('-');
      const year = parseInt(dateParts[0]);
      const month = parseInt(dateParts[1]);
      const monthNames = ['一月', '二月', '三月', '四月', '五月', '六月',
        '七月', '八月', '九月', '十月', '十一月', '十二月'];
      const currentYear = new Date().getFullYear();

      if (year === currentYear) {
        return monthNames[month - 1];
      } else {
        return `${year}年${monthNames[month - 1]}`;
      }
    } else {
      return dateKey;
    }
  }

  // 格式化时间显示
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const messageDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());

    const timeDiff = today.getTime() - messageDate.getTime();
    const daysDiff = Math.floor(timeDiff / (1000 * 60 * 60 * 24));

    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const time = `${hours}:${minutes}`;

    if (daysDiff === 0) {
      return time;
    } else if (daysDiff === 1) {
      return `昨天 ${time}`;
    } else if (daysDiff <= 7) {
      const weekDays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
      return `${weekDays[date.getDay()]} ${time}`;
    } else {
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const day = date.getDate().toString().padStart(2, '0');
      return `${month}-${day} ${time}`;
    }
  }
}
