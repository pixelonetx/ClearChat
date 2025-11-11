/**
 * MessageItem 组件 - 聊天消息项
 *
 * 功能说明：
 * - 渲染用户和AI助手的消息内容
 * - 提供消息操作功能（复制、删除、重新生成等）
 * - 支持Markdown格式渲染
 * - 优化性能，缓存计算结果
 */

import { ChatMessage, Citation } from '../services/DataModels';
import { MarkdownRenderer } from './MarkdownRenderer';
import { WebBrowserParam } from '../components/WebViewBrowser';
import { SearchReferencesDialog, SearchReference } from './SearchReferencesDialog';

@Component
export struct MessageItem {
  // 导航栈：用于在消息中点击链接时跳转到内置浏览器
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop message: ChatMessage;
  // 回调函数 - 消息操作事件
  onCopy?: (message: ChatMessage) => void | Promise<void>;
  onEdit?: (message: ChatMessage) => void | Promise<void>;
  onDelete?: (message: ChatMessage) => void | Promise<void>;
  onRegenerate?: (message: ChatMessage) => void | Promise<void>;
  // 下拉菜单显示状态
  @State showUserMenu: boolean = false;
  @State showAssistantMenu: boolean = false;
  // 缓存计算结果以提升性能，避免重复计算
  @State private isUserMessage: boolean = false;
  @State private messageContent: string = '';
  // 搜索引用对话框
  @State showSearchReferencesDialog: boolean = false;
  @State searchReferences: SearchReference[] = [];
  @State searchQuery: string = '';
  searchReferencesDialogController?: CustomDialogController;

  /**
   * 组件初始化时缓存常用计算结果
   */
  aboutToAppear() {
    this.isUserMessage = this.message.role === 'user';
    this.messageContent = this.message.content;
  }

  /**
   * 判断消息是否应该显示
   * tool 类型的消息（搜索结果）不直接显示，而是作为前一条消息的引用
   */
  shouldShowMessage(): boolean {
    return this.message.role !== 'tool';
  }

  @Builder
  UserDropdownMenu() {
    Column() {
      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.trash'))
            .size({ width: 14, height: 14 })
            .fillColor($r('sys.color.ohos_id_color_text_primary'))
          Text('删除')
            .fontSize(12)
        }
      }
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .backgroundColor($r('sys.color.background_primary'))
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete(this.message);
        }
        this.showUserMenu = false;
      })
    }
  }

  @Builder
  AssistantDropdownMenu() {
    Column() {
      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.trash'))
            .size({ width: 14, height: 14 })
            .fillColor($r('sys.color.ohos_id_color_text_primary'))
          Text('删除')
            .fontSize(12)
        }
      }
      .backgroundColor($r('sys.color.background_primary'))
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete(this.message);
        }
        this.showAssistantMenu = false;
      })
    }
  }

  @Builder
  UserActionButtons() {
    Row({ space: 2 }) {
      // 复制按钮 - 圆形
      Button() {
        Image($r('app.media.rectangle_on_rectangle'))
          .size({ width: 14, height: 14 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.common_background'))
      .size({ width: 28, height: 28 })
      .onClick(() => {
        if (this.onCopy) {
          this.onCopy(this.message);
        }
      })

      // 编辑按钮 - 圆形
      Button() {
        Image($r('app.media.square_and_pencil'))
          .size({ width: 14, height: 14 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.common_background'))
      .size({ width: 28, height: 28 })
      .onClick(() => {
        if (this.onEdit) {
          this.onEdit(this.message);
        }
      })

      // 更多按钮 - 圆形
      Button() {
        Image($r('app.media.more_fill'))
          .size({ width: 14, height: 14 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.common_background'))
      .size({ width: 28, height: 28 })
      .bindPopup(this.showUserMenu, {
        builder: this.UserDropdownMenu,
        placement: Placement.BottomLeft,
        maskColor: Color.Transparent,
        popupColor: Color.Transparent,
        enableArrow: false,
        showInSubWindow: false,
        onStateChange: (e) => {
          if (!e.isVisible) {
            this.showUserMenu = false;
          }
        }
      })
      .onClick(() => {
        this.showUserMenu = !this.showUserMenu;
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .margin({ top: 4, right: 4 })
  }

  @Builder
  AssistantActionButtons() {
    Row({ space: 2 }) {
      // 复制按钮 - 圆形
      Button() {
        Image($r('app.media.rectangle_on_rectangle'))
          .size({ width: 14, height: 14 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.common_background'))
      .size({ width: 28, height: 28 })
      .onClick(() => {
        if (this.onCopy) {
          this.onCopy(this.message);
        }
      })

      // 重新生成按钮 - 圆形
      Button() {
        Image($r('app.media.arrow_clockwise'))
          .size({ width: 14, height: 14 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.common_background'))
      .size({ width: 28, height: 28 })
      .onClick(() => {
        if (this.onRegenerate) {
          this.onRegenerate(this.message);
        }
      })

      // 更多按钮 - 圆形
      Button() {
        Image($r('app.media.more_fill'))
          .size({ width: 14, height: 14 })
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .type(ButtonType.Circle)
      .backgroundColor($r('app.color.common_background'))
      .size({ width: 28, height: 28 })
      .bindPopup(this.showAssistantMenu, {
        builder: this.AssistantDropdownMenu,
        placement: Placement.BottomRight,
        maskColor: Color.Transparent,
        popupColor: Color.Transparent,
        enableArrow: false,
        showInSubWindow: false,
        onStateChange: (e) => {
          if (!e.isVisible) {
            this.showAssistantMenu = false;
          }
        }
      })
      .onClick(() => {
        this.showAssistantMenu = !this.showAssistantMenu;
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .margin({ top: 4, left: 4 })
  }

  @Builder
  UserMessage() {
    Column() {
      Row() {
        Blank()
        Row() {
          Column() {
            Text(this.messageContent)
              .fontSize($r('app.float.message_text_font_size')) //14
              .fontColor($r('app.color.text_color'))
              .maxLines(999)
              .textOverflow({ overflow: TextOverflow.None })
              .wordBreak(WordBreak.BREAK_ALL)
          }
          .padding(12)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))

          // .constraintSize({
          //   minWidth: 40,  // 减小最小宽度，适合短消息
          //   minHeight: 36  // 保持最小高度，防止变成小圆形
          // })
        }
        .constraintSize({ maxWidth: '85%' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 添加操作按钮
      this.UserActionButtons()
    }
    .width('100%')
    // .margin({ bottom: Constants.MESSAGE_MARGIN })
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  AssistantMessage() {
    Column() {
      // 只显示模型名称（如果有）
      if (this.message.modelName) {
        Row() {
          Text(this.message.modelName)
            .fontSize(12)
            // .opacity(0.8)
            .margin({ bottom: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }

      // 搜索引用胶囊 - 只显示1个，代表所有搜索结果
      if (this.message.citations && this.message.citations.length > 0) {
        Button() {
          Row({ space: 4 }) {
            Text('🔍')
              .fontSize(12)
            Text(`${this.message.citations.length} 个搜索结果`)
              .fontSize(12)
          }
          .padding({
            left: 12,
            right: 12,
            top: 6,
            bottom: 6
          })
        }
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.input_area_color'))
        .fontColor($r('app.color.text_color'))
        .height(32)
        .margin({ bottom: 8 })
        .onClick(() => {
          // 点击胶囊，显示搜索引用对话框
          const references: SearchReference[] = [];
          for (let i = 0; i < this.message.citations!.length; i++) {
            const citation = this.message.citations![i];
            references.push({
              title: citation.title ?? '搜索结果',
              url: citation.url ?? '',
              snippet: citation.snippet,
              index: i + 1
            });
          }
          this.searchReferences = references;
          this.searchQuery = '搜索结果';
          this.showSearchReferencesDialog = true;
          this.searchReferencesDialogController = new CustomDialogController({
            builder: SearchReferencesDialog({
              references: references,
              query: this.searchQuery
            }),
            autoCancel: true,
            alignment: DialogAlignment.Bottom,
            customStyle: true
          });
          this.searchReferencesDialogController?.open();
        })
      }

      Row() {
        Row() {
          Column() {
            if (this.messageContent === '') {
              LoadingProgress()
                .width(24)
                .height(24)
            } else {
              MarkdownRenderer({
                content: this.message.content,
                maxWidth: 'auto' // 自动继承父容器宽度限制
              })
            }
          }
          // .padding(16)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)

          // .backgroundColor('#F3F4F6')
          // .constraintSize({
          //   minWidth: 40,  // 减小最小宽度，适合短消息
          //   minHeight: 36  // 保持最小高度，防止变成小圆形
          // })
        }
        // .constraintSize({ maxWidth: '85%' }) // 动态宽度，最大85%
        .layoutWeight(0) // 不占用剩余空间，根据内容调整大小

        // Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.Start) // 靠左对齐，不居中

      // 注释：原有的详细citations展示已由上面的胶囊容器替代
      // 如需显示详细信息，请点击胶囊打开对话框

      // 添加操作按钮
      this.AssistantActionButtons()
    }
    .width('100%')
    // .margin({ bottom: Constants.MESSAGE_MARGIN })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (this.shouldShowMessage()) {
        if (this.isUserMessage) {
          this.UserMessage()
        } else {
          this.AssistantMessage()
        }
      }
    }
    .width('100%')
    .margin({ bottom: 12 })
  }
}
