/**
 * MessageItem 组件 - 聊天消息项
 *
 * 功能说明：
 * - 渲染用户和AI助手的消息内容
 * - 提供消息操作功能（复制、删除、重新生成等）
 * - 支持Markdown格式渲染
 * - 优化性能，缓存计算结果
 */
import { ChatMessage, Citation } from '../../services/DataModels';
import { MarkdownRenderer } from '../markdown/MarkdownRenderer';
import { WebBrowserParam } from '../utils/WebViewBrowser';
import { SearchReferencesDialog, SearchReference } from '../dialogs/SearchReferencesDialog';
import { MessageStyle } from './MessageStyle';

interface SearchArgs {
  query?: string;
}

@Component
export struct MessageItem {
  // 导航栈：用于在消息中点击链接时跳转到内置浏览器
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop @Watch('onMessageChanged') message: ChatMessage;
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
  // 新增：响应式搜索阶段状态
  @State private currentSearchStage: 'none' | 'searching' | 'results' | 'summarizing' | 'done' | 'error' = 'none';
  // 搜索引用对话框
  @State showSearchReferencesDialog: boolean = false;
  @State searchReferences: SearchReference[] = [];
  @State searchQuery: string = '';
  searchReferencesDialogController?: CustomDialogController;

  /**
   * 打开搜索引用对话框
   * 统一提取，避免在引用列表项和"查看全部"按钮中重复
   */
  private openSearchReferencesDialog(): void {
    const refs: SearchReference[] = [];
    const totalLocal = this.message.citations!.length;
    for (let j = 0; j < totalLocal; j++) {
      const ct = this.message.citations![j];
      refs.push({ title: ct.title ?? '搜索结果', url: ct.url ?? '', snippet: ct.snippet, index: j + 1 });
    }
    this.searchReferences = refs;
    this.searchQuery = '搜索结果';
    this.showSearchReferencesDialog = true;
    this.searchReferencesDialogController = new CustomDialogController({
      builder: SearchReferencesDialog({ references: refs, query: this.searchQuery }),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      customStyle: true
    });
    this.searchReferencesDialogController?.open();
  }

  private get isAssistant(): boolean {
    return this.message.role === 'assistant';
  }

  private get hasToolCalls(): boolean {
    return !!(this.message.toolCalls && this.message.toolCalls.length > 0);
  }

  private get hasCitations(): boolean {
    return !!(this.message.citations && this.message.citations.length > 0);
  }

  private get isSearchError(): boolean {
    return typeof this.message.content === 'string' && this.message.content.startsWith('[搜索失败]');
  }
  // 获取工具调用描述
  private getToolCallDescription(toolCall: import('../../services/DataModels').ToolCall): string {
    if (toolCall.function?.name === 'search_web') {
      try {
        const args = JSON.parse(toolCall.function.arguments || '{}') as SearchArgs;
        return `正在搜索: ${args.query || '未知内容'}`;
      } catch (e) {
        return '正在搜索...';
      }
    }
    return `调用工具: ${toolCall.function?.name}`;
  }

  // 更新搜索阶段
  private updateSearchStage(): void {
    if (!this.isAssistant) {
      this.currentSearchStage = 'none';
      return;
    }
    if (this.isSearchError) {
      this.currentSearchStage = 'error';
      return;
    }
    if (this.hasToolCalls && !this.hasCitations) {
      this.currentSearchStage = 'searching';
      return;
    }
    if (this.hasCitations && this.message.content.length === 0) {
      this.currentSearchStage = 'summarizing';
      return;
    }
    if (this.hasCitations && this.message.content.length > 0) {
      this.currentSearchStage = 'done';
      return;
    }
    if (this.message.content.length === 0) {
      this.currentSearchStage = 'summarizing';
      return;
    }
    this.currentSearchStage = 'none';
  }

  /**
   * 组件初始化时缓存常用计算结果
   */
  aboutToAppear() {
    this.isUserMessage = this.message.role === 'user';
    this.messageContent = this.message.content;
    this.updateSearchStage();
  }

  /**
   * 当消息变化时更新状态
   */
  onMessageChanged(): void {
    this.messageContent = this.message.content;
    this.updateSearchStage();
  }

  /**
   * 当消息内容变化时更新状态
   */
  aboutToRecycle(): void {
    this.updateSearchStage();
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
              .fontSize(MessageStyle.USER_MESSAGE_FONT_SIZE)
              .fontColor($r('app.color.text_color'))
              .maxLines(999)
              .textOverflow({ overflow: TextOverflow.None })
              .wordBreak(WordBreak.BREAK_ALL)
          }
          .padding(12)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
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
  ToolCallView() {
    Column({ space: 8 }) {
      ForEach(this.message.toolCalls || [], (toolCall: import('../../services/DataModels').ToolCall, index: number) => {
        Row({ space: 8 }) {
          // 图标
          if (toolCall.function?.name === 'search_web') {
            Image($r('app.media.worldclock'))
              .width(16)
              .height(16)
              .fillColor($r('sys.color.ohos_id_color_text_secondary'))
          } else {
            Image($r('sys.symbol.square_grid_2x2'))
              .width(16)
              .height(16)
              .fillColor($r('sys.color.ohos_id_color_text_secondary'))
          }

          // 文本
          Text(this.getToolCallDescription(toolCall))
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          // 状态 (如果 content 为空，且是最后一个 toolCall，可能正在执行)
          if (this.message.content.length === 0 && index === (this.message.toolCalls?.length || 0) - 1) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('sys.color.ohos_id_color_text_secondary'))
          } else {
            Image($r('sys.symbol.checkmark'))
              .width(16)
              .height(16)
              .fillColor(Color.Green)
          }
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
        .borderRadius(8)
      })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  AssistantMessage() {
    Column() {
      // 只显示模型名称（如果有）
      if (this.message.modelName) {
        Row() {
          Text(this.message.modelName)
            .fontSize(MessageStyle.MODEL_NAME_FONT_SIZE)
            // .opacity(0.8)
            .margin({ bottom: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }

      // 工具调用展示
      if (this.hasToolCalls) {
        this.ToolCallView()
      }

      // 原生简洁的搜索状态展示 (仅当没有工具调用时显示，避免重复)
      if (this.currentSearchStage !== 'none' && !this.hasToolCalls) {
        Row({ space: 10 }) {
          if (this.currentSearchStage === 'searching') {
            // 搜索中
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('sys.color.ohos_id_color_emphasize'))
            
            Text('正在联网搜索...')
              .fontSize(MessageStyle.SEARCH_STATUS_FONT_SIZE)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              
          } else if (this.currentSearchStage === 'summarizing') {
            // 生成摘要中
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('sys.color.ohos_id_color_warning'))
            
            Text(this.hasCitations ? `找到 ${this.message.citations!.length} 个结果，生成摘要中...` : '生成中...')
              .fontSize(MessageStyle.SEARCH_STATUS_FONT_SIZE)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              
          } else if (this.currentSearchStage === 'done') {
            // 搜索完成
            Image($r('sys.symbol.checkmark_circle_fill'))
              .width(18)
              .height(18)
              .fillColor(Color.Green)
            
            Text(`已使用联网搜索 (${this.message.citations!.length} 个来源)`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              
          } else if (this.currentSearchStage === 'error') {
            // 搜索失败
            Image($r('sys.symbol.exclamationmark_circle_fill'))
              .width(18)
              .height(18)
              .fillColor($r('sys.color.ohos_id_color_warning'))
            
            Text('搜索失败')
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_warning'))
          }
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.input_area_color'))
        .borderRadius(8)
        .margin({ bottom: 10 })
      }

      // 原生简洁的引用卡片展示
      if (this.hasCitations) {
        Column({ space: 6 }) {
          // 引用标题行
          Row({ space: 6 }) {
            Image($r('sys.symbol.link'))
              .width(16)
              .height(16)
              .fillColor($r('sys.color.ohos_id_color_text_secondary'))
            
            Text(`${this.message.citations!.length} 个参考来源`)
              .fontSize(MessageStyle.CITATION_COUNT_FONT_SIZE)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          }
          
          // 展示前3个引用 - 原生列表样式
          ForEach(this.message.citations!.slice(0, Math.min(3, this.message.citations!.length)), (c: Citation, i: number) => {
            Row({ space: 12 }) {
              // 序号
              Text(`${i + 1}`)
                .fontSize(MessageStyle.CITATION_TITLE_FONT_SIZE)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_emphasize'))
                .width(24)
              
              // 标题和URL
              Column({ space: 2 }) {
                Text(c.title ?? '来源')
                  .fontSize(MessageStyle.CITATION_TITLE_FONT_SIZE)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                
                if (c.url) {
                  Text(c.url)
                    .fontSize(MessageStyle.CITATION_URL_FONT_SIZE)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              
              // 箭头
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor($r('sys.color.ohos_id_color_fourth'))
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor($r('sys.color.ohos_id_color_background'))
            .borderRadius(8)
            .onClick(() => {
              this.openSearchReferencesDialog();
            })
          }, (c: Citation, i: number) => `${i}`)

          // 查看全部按钮
          if (this.message.citations!.length > 3) {
            Row({ space: 6 }) {
              Text(`查看全部 ${this.message.citations!.length} 个来源`)
                .fontSize(MessageStyle.CITATION_TITLE_FONT_SIZE)
                .fontColor($r('sys.color.ohos_id_color_emphasize'))
              
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor($r('sys.color.ohos_id_color_emphasize'))
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor($r('sys.color.ohos_id_color_background'))
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.openSearchReferencesDialog();
            })
          }
        }
        .margin({ bottom: 12 })
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.input_area_color'))
        .borderRadius(12)
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
