import { Prompt } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage, AppSettings, Citation, ChatMessageMetadataUpdate, StreamMetadata } from '../services/DataModels';
import { ArrayDataSource } from '../utils/ArrayDataSource';
import { Conversation } from '../services/ConversationModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NetworkManagerV2 } from '../services/NetworkManagerV2';
import { StreamEventEmitter, StreamEventType, EventPayload } from '../services/StreamEventEmitter';
import { TitleGenerationService } from '../services/TitleGenerationService';
import { ClipboardManager } from '../components/ClipboardManager';
import { BrowserHelper } from '../services/BrowserHelper';
import { NativeDialogHelper } from '../components/NativeDialogHelper';
import { MessageItem } from '../components/MessageItem';
import { RenameConversationDialog } from '../components/RenameConversationDialog';
import { ModelSelectorSheet } from '../components/ModelSelectorDialog';
import { AbortController, createAbortController } from '../interfaces/AbortController';
import { SearchToolService } from '../services/search/SearchToolService';
import { SearchConfigManager } from '../services/search/SearchConfigManager';

const DOMAIN = 0x0000;
const TAG = 'Chat';

// 定义模型信息接口
interface ModelInfo {
  modelName: string;
  providerName: string;
}

// 定义流式消息初始化结果接口
interface StreamingMessageResult {
  index: number;
  id: number;
}

// 定义搜索工具参数接口
interface SearchToolArgs {
  query: string;
  resultSize?: number;
}

interface MaybeStringifiable {
  toString?: () => string;
}

class ToastOptions {
  message: string;
  duration?: number;

  constructor(message: string, duration?: number) {
    this.message = message;
    this.duration = duration;
  }
}

// 明确手势事件类型，避免使用对象字面量类型
interface PanUpdateEvent {
  offsetX: number;
}

// 跳转页面入口函数
@Builder
export function ChatBuilder() {
  Chat();
}


@Entry()
@Component
struct Chat {
  @Provide('NavPathStack')
  pathStack: NavPathStack = new NavPathStack();
  // 常量定义
  private static readonly SIDEBAR_WIDTH = 300;
  private static readonly ANIMATION_DURATION = 300;
  private static readonly DEBOUNCE_DELAY = 300;
  // 状态管理
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('settingsVersion') settingsVersion: number = 0;
  @StorageLink('conversationsReloadVersion') conversationsReloadVersion: number = 0;
  @StorageLink('currentBreakPoint') currentBreakPoint: string = 'sm';
  // UI 状态
  @State showControlButton: boolean = true;
  @State showSideBar: boolean = false;
  @State isSidebarVisible: boolean = false;
  @State sidebarOffset: number = -Chat.SIDEBAR_WIDTH;
  @State backgroundBlurRadius: number = 0;
  @State showModelSelectorSheet: boolean = false;
  @State customPopup: boolean = false;
  // 数据状态
  @State messages: ChatMessage[] = [];
  @State
  @Watch('updateGroupedConversations')
  conversations: Conversation[] = [];
  @State currentConversation: Conversation | null = null;
  @State inputText: string = '';
  // 缓存已分组的对话数据，避免重复计算
  @State private cachedGroupedConversations: Record<string, Conversation[]> | null = null;
  @State private cachedGroupedKeys: string[] = [];
  // 应用状态
  @State isLoading: boolean = false;
  @State isGenerating: boolean = false; // 新增：跟踪是否正在生成内容
  @State isInitialized: boolean = false;
  @State hasSettings: boolean = false;
  @State ctrlFlag: boolean = false;
  @State enableWebSearch: boolean = false; // 阿里云通义千问 联网搜索开关
  @State isAliyunActive: boolean = false; // 是否识别为阿里云（用于驱动UI和请求选项）
  @State currentModelSupportsWebSearchFlag: boolean = false; // 当前模型是否支持联网搜索的UI驱动标志
  @State isSearching: boolean = false; // 是否正在执行搜索
  @State searchQuery: string = ''; // 当前搜索查询
  @State searchResults: string = ''; // 搜索结果摘要
  private databaseManager = DatabaseManager.getInstance();
  private networkManager = NetworkManagerV2.getInstance();
  private titleGenerationService: TitleGenerationService = new TitleGenerationService();
  private searchToolService = SearchToolService.getInstance();
  private searchConfigManager = SearchConfigManager.getInstance();
  private scroller: Scroller = new Scroller();
  private currentSettings: AppSettings | null = null;
  private previousSettingsVersion: number = 0;
  private pendingSettingsReload: Promise<void> | null = null;
  private requestedSettingsVersion: number = 0;
  private handledReloadVersion: number = 0;
  private messageDataSource: ArrayDataSource<ChatMessage> = new ArrayDataSource<ChatMessage>(this.messages);
  private currentAbortController: AbortController | null = null; // 新增：用于中断请求
  private shouldAbortRequest: boolean = false; // 中断请求标志
  private userAbortedGeneration: boolean = false; // 用户主动停止标记

  private notifyMessagesUpdated(): void {
    // 更新数据源引用与刷新（数组引用经常被替换）
    this.messageDataSource.setDataRef(this.messages);
  }

  private cloneChatMessage(message: ChatMessage): ChatMessage {
    const clone = new ChatMessage(message.content, message.role, {
      conversationId: message.conversationId,
      modelName: message.modelName,
      providerName: message.providerName,
      timestamp: message.timestamp,
      providerMessageId: message.providerMessageId,
      providerCreatedAt: message.providerCreatedAt,
      systemFingerprint: message.systemFingerprint,
      toolCallId: message.toolCallId, // 🔥 复制工具调用 ID (用于 tool 消息)
      toolCalls: message.toolCalls    // 🔥 复制工具调用列表 (用于 assistant 消息)
    });
    clone.id = message.id;
    return clone;
  }

  private replaceMessageAt(index: number, updater: (message: ChatMessage) => void): void {
    const target = this.messages[index];
    if (!target) {
      return;
    }

    const cloned = this.cloneChatMessage(target);
    updater(cloned);

    const nextMessages = [...this.messages];
    nextMessages[index] = cloned;
    this.messages = nextMessages;
    this.notifyMessagesUpdated();
  }

  private appendMessage(message: ChatMessage): number {
    this.messages = [...this.messages, message];
    this.notifyMessagesUpdated();
    return this.messages.length - 1;
  }

  /**
   * 将错误信息转换为用户友好的提示消息
   * @param error 原始错误对象
   * @returns 用户友好的错误消息
   */
  private getFriendlySendErrorMessage(error: Error): string {
    if (!error) {
      return '发送消息失败';
    }

    let rawMessage = (error.message ?? '').trim();

    if (!rawMessage) {
      const stringifiable = error as MaybeStringifiable;
      if (stringifiable.toString) {
        rawMessage = stringifiable.toString().trim();
      }
    }

    if (!rawMessage) {
      return '发送消息失败';
    }

    const normalized = rawMessage.toLowerCase();

    // 超时错误
    if (normalized.includes('timeout') || rawMessage.includes('超时')) {
      return '请求超时，请稍后重试';
    }

    // 网络连接错误
    if (normalized.includes('network') || normalized.includes('connection') || normalized.includes('fetch') ||
    rawMessage.includes('网络')) {
      return '网络连接失败，请检查网络设置';
    }

    // 认证授权错误
    if (normalized.includes('unauthorized') || normalized.includes('forbidden') ||
    normalized.includes('invalid api key') || normalized.includes('401') || normalized.includes('403') ||
    rawMessage.includes('授权') || rawMessage.includes('认证')) {
      return 'API密钥无效，请检查设置';
    }

    // 频率限制错误
    if (normalized.includes('rate limit') || normalized.includes('too many')) {
      return '请求过于频繁，请稍后再试';
    }

    // 模型相关错误
    if (normalized.includes('model') &&
      (normalized.includes('not found') || normalized.includes('does not exist') || normalized.includes('unknown'))) {
      return '模型不可用，请检查模型ID';
    }

    // HTTP状态码错误
    if (normalized.startsWith('http ') || rawMessage.startsWith('HTTP') || /http\s\d+/.test(normalized)) {
      return `服务返回错误：${rawMessage}`;
    }

    // SSL证书错误
    if (normalized.includes('ssl') || normalized.includes('certificate')) {
      return 'SSL连接失败，请检查网络或证书配置';
    }

    // 内容过滤错误
    if (normalized.includes('content_filter') || normalized.includes('content policy') ||
    rawMessage.includes('内容过滤') || rawMessage.includes('违规')) {
      return '消息内容不符合规范，请修改后重试';
    }

    // 配额不足错误
    if (normalized.includes('quota') || normalized.includes('insufficient') ||
    rawMessage.includes('配额') || rawMessage.includes('余额')) {
      return 'API配额不足，请检查账户余额';
    }

    // 服务不可用错误
    if (normalized.includes('service unavailable') || normalized.includes('502') ||
    normalized.includes('503') || rawMessage.includes('服务不可用')) {
      return 'AI服务暂时不可用，请稍后重试';
    }

    return `发送失败：${rawMessage}`;
  }

  build() {
    NavDestination() {
      SideBarContainer(SideBarContainerType.AUTO) {
        Column() {
          this.SidebarContent()
        }

        // 主内容区域
        Column() {
          Stack() {
            // 主界面
            Column() {
              // 标题栏
              Row() {
                Button() {
                  Image($r('app.media.text_alignleft'))
                    .size({ width: 24, height: 24 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                }
                .type(ButtonType.Circle)
                .backgroundColor(Color.Transparent) //$r('sys.color.button_background_color_transparent')
                .size({ width: 40, height: 40 })
                .visibility(this.showControlButton ? Visibility.Visible : Visibility.Hidden)
                .onClick(() => {
                  this.showControlButton = !this.showControlButton
                  animateTo({
                    duration: 500,
                    curve: Curve.FastOutSlowIn
                  }, () => {
                    this.showSideBar = true;
                  })
                })

                Text(this.currentConversation?.title || '聊天助手')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .layoutWeight(1)
                  .textAlign(TextAlign.JUSTIFY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 14, right: 14 })

                Button() {
                  Image($r('app.media.chat_new_line'))
                    .size({ width: 24, height: 24 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                }
                .type(ButtonType.Circle)
                .size({ width: 40, height: 40 })
                .backgroundColor(Color.Transparent) //$r('sys.color.button_background_color_transparent')
                .onClick(() => {
                  this.createNewConversation();
                })
                .margin({ right: 8 })

                Button() {
                  Image($r('app.media.dot_grid_2x2'))
                    .size({ width: 24, height: 24 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                }
                .type(ButtonType.Circle)
                .size({ width: 40, height: 40 })
                .backgroundColor(Color.Transparent) //$r('sys.color.button_background_color_transparent')
                .onClick(() => {
                  this.customPopup = !this.customPopup;
                })
                .bindMenu([
                  {
                    value: '切换模型',
                    icon: $r('app.media.reverse_order'),
                    action: () => {
                      this.switchModel();
                    }
                  },
                  {
                    value: '更多',
                    icon: $r('app.media.more_fill'),
                    enabled: false,
                    action: () => {
                    }
                  }
                ])
                .bindSheet(this.showModelSelectorSheet,
                  this.ModelSelectorSheetBuilder(),
                  {
                    height: SheetSize.MEDIUM,
                    detents: [SheetSize.MEDIUM, SheetSize.LARGE, SheetSize.LARGE],
                    dragBar: true, // 启用默认拖拽条
                    showClose: true, // 显示默认关闭按钮
                    title: { title: "选择模型" },
                    onDisappear: () => {
                      this.showModelSelectorSheet = false;
                    }
                  }
                )
              }
              .margin({ top: this.getUIContext().px2vp(this.topRectHeight) })
              .width('100%')
              .height(60) //56
              .padding({ left: 12, right: 12 })

              if (!this.isInitialized) {
                // 加载界面
                Column() {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
              } else {
                // 消息列表
                if (this.messages.length === 0) {
                  // 空状态
                  Column() {
                    Text('有什么可以帮忙的？')
                      .fontSize(18)
                      .margin({ top: 16 })

                    if (!this.hasSettings) {
                      Button('配置API设置')
                        .buttonStyle(ButtonStyleMode.NORMAL)
                        .padding({ left: 20, right: 20 })
                        .margin({ top: 16 })
                        .onClick(() => {
                          this.pathStack.pushPathByName("ModelSettings", null);
                          this.hideKeyboard();
                        })
                    }
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                } else {
                  // 消息列表（使用 LazyForEach 虚拟化以提升性能）
                  Scroll(this.scroller) {
                    Column() {
                      LazyForEach(this.messageDataSource, (message: ChatMessage, index: number) => {
                        MessageItem({
                          message: message,
                          onCopy: (msg: ChatMessage): Promise<void> => this.copyMessage(msg),
                          onEdit: (msg: ChatMessage): void => {
                            this.editMessage(msg);
                          },
                          onDelete: (msg: ChatMessage): Promise<void> => this.deleteMessage(msg),
                          onRegenerate: (msg: ChatMessage): Promise<void> => this.regenerateMessage(msg)
                        })
                      }, (message: ChatMessage, index: number) => {
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
                  .friction(0.8) // 摩擦系数（0-1，值越小惯性越强）
                  .edgeEffect(EdgeEffect.Spring) // 边缘弹性效果
                  .onScrollFrameBegin((offset, state) => {
                    // 动态调整滚动量实现自定义阻尼
                    return { offsetRemain: offset * 0.7 }
                  })
                  .layoutWeight(1)
                  .scrollable(ScrollDirection.Vertical)
                  .scrollBar(BarState.Off)
                  .width('100%')
                  .align(Alignment.TopStart)
                  .onClick(() => {
                    this.hideKeyboard(); // 点击消息列表区域时隐藏键盘
                  })
                }
              }

              // 输入
              Column() {

                TextArea({ placeholder: '输入你的消息...', text: this.inputText })
                  .fontSize(16)
                  .backgroundColor($r('app.color.input_area_color'))
                  .showCounter(true)
                  .onChange((value: string) => {
                    this.inputText = value;
                  })
                  .enterKeyType(EnterKeyType.Send)
                  .onSubmit((enterKey: EnterKeyType) => {
                    if (this.ctrlFlag) {
                      this.inputText += '\n'; // 手动添加换行
                    } else {
                      this.sendMessage();
                    }
                  })
                  .onKeyEvent((event: KeyEvent) => {
                    this.ctrlFlag = event.getModifierKeyState?.(['Ctrl']) ?? false;
                  })

                Row() {
                  // 根据当前模型是否支持内置联网搜索来显示/隐藏联网搜索开关
                  // 使用 @State 标志替代方法调用，确保 UI 能正确响应状态变化
                  if (this.currentModelSupportsWebSearchFlag) {
                    Toggle({ type: ToggleType.Button, isOn: this.enableWebSearch }) {
                      Image($r('app.media.worldclock'))
                        .size({ width: 24, height: 24 })
                        .fillColor(this.enableWebSearch ? Color.Blue : Color.Gray)
                    }
                    .size({ width: 40, height: 40 })
                    .backgroundColor(Color.Transparent)
                    .onChange((on: boolean) => {
                      this.enableWebSearch = on;
                      if (this.currentSettings) {
                        this.currentSettings.enableWebSearch = on;
                        // 异步保存设置，不阻塞输入
                        this.databaseManager.saveSettings(this.currentSettings).then(() => {
                          // bump settingsVersion 以通知其他页面
                          const ver = (this.settingsVersion ?? 0) + 1;
                          AppStorage.setOrCreate('settingsVersion', ver);
                        }).catch(() => {
                        });
                      }
                    })
                    .margin({ left: 12 })
                  }

                  Blank()

                  // 单按钮：生成中显示“停止”，否则显示“发送”
                  Button() {
                    if (this.isGenerating) {
                      SymbolGlyph($r('sys.symbol.stop_circle'))
                        .fontSize(24)
                        .fontColor([Color.Red])
                    } else if (this.isLoading) {
                      LoadingProgress()
                        .width(24)
                        .height(24)
                        .color(Color.Red)
                    } else {
                      SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                        .fontSize(24)
                        .fontColor([$r('app.color.text_color')])
                    }
                  }
                  .type(ButtonType.Circle)
                  .backgroundColor($r('sys.color.button_background_color_transparent'))
                  .size({ width: 40, height: 40 })
                  .margin({ right: 12 })
                  .enabled(this.isGenerating || (this.inputText.trim() !== '' && !this.isLoading))
                  .onClick(() => {
                    if (this.isGenerating) {
                      this.stopGeneration();
                    } else {
                      this.sendMessage();
                    }
                  })
                }
                .margin({ bottom: 12 }) //bottom: this.getUIContext().px2vp(this.bottomRectHeight)
                .justifyContent(FlexAlign.SpaceBetween) // 关键属性：两端对齐
                .width('100%') // 必须设置宽度为 100% 才能生效
              }
              .backgroundColor($r('app.color.input_area_color'))
              // .borderWidth({top:1})
              .borderColor($r('app.color.text_secondary'))
              .borderRadius({ topLeft: 20, topRight: 20 })
              .width('100%')
              .padding({
                left: 2,
                right: 2,
                top: 6,
                bottom: 4
              })
              .alignItems(HorizontalAlign.End)

            }
            .width('100%')
            .height('100%')

            // 仅在小屏（sm）渲染遮罩层；平板和桌面不显示遮罩，保留嵌入式布局
            // 遮罩层：仅在手机显示，平板和桌面不渲染
            if (this.showSideBar && (this.currentBreakPoint === 'sm' || this.currentBreakPoint === 'xs')) {
              Column()
                .width('100%')
                .height('100%')
                .position({ x: 0, y: 0 })
                .zIndex(10)
                .backgroundColor('rgba(0, 0, 0, 0.3)') // 仅半透明阴影，无模糊
                .onAppear(() => {
                  hilog.error(DOMAIN, TAG,
                    '[OVERLAY error] Rendering overlay - showSideBar=%{public}s, currentBreakPoint=%{public}s',
                    String(this.showSideBar), String(this.currentBreakPoint));
                })
                .gesture(
                  PanGesture({
                    direction: PanDirection.Horizontal,
                    fingers: 1,
                    distance: 5 // 增加最小滑动距离，避免误触
                  })
                    .onActionStart(() => {
                      hilog.error(DOMAIN, TAG, '[GESTURE error] Close gesture started');
                    })
                    .onActionUpdate((event: PanUpdateEvent) => {
                      hilog.error(DOMAIN, TAG, '[GESTURE error] Pan gesture - offsetX=%{public}s',
                        String(event.offsetX));
                      // 向左滑超过阈值，关闭侧栏
                      const closeThreshold = -30; // 增加阈值，减少误触
                      if (event.offsetX < closeThreshold) {
                        hilog.error(DOMAIN, TAG, '[GESTURE error] Closing sidebar - threshold reached');
                        animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
                          this.showSideBar = false;
                          this.showControlButton = true;
                        })
                      }
                    })
                    .onActionEnd(() => {
                      hilog.error(DOMAIN, TAG, '[GESTURE error] Close gesture ended');
                    })
                )
                .onClick(() => {
                  hilog.error(DOMAIN, TAG, '[OVERLAY error] Overlay clicked - closing sidebar');
                  if (this.showSideBar && (this.currentBreakPoint === 'sm' || this.currentBreakPoint === 'xs')) {
                    animateTo({
                      duration: Chat.ANIMATION_DURATION,
                      curve: Curve.FastOutSlowIn
                    }, () => {
                      this.showSideBar = false;
                      this.showControlButton = true;
                    })
                  }
                })
                .transition(TransitionEffect.OPACITY)
            }
          }
        }

      }
      .gesture(
        PanGesture({
          direction: PanDirection.Horizontal,
          fingers: 1,
          distance: 5 // 最小触发滑动距离
        })
          .onActionUpdate((event: PanUpdateEvent) => {
            if (event.offsetX > 30) { // 向右滑动阈值
              animateTo({ duration: 250 }, () => {
                this.showControlButton = false;
                this.showSideBar = true;
              });
            }
          })
      )
      .autoHide(false)
      .showControlButton(false)
      .showSideBar($$this.showSideBar)
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.common_background'))
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  private renameDialogController: CustomDialogController = new CustomDialogController({
    builder: RenameConversationDialog({}),
    autoCancel: true,
  });

  private showToast(message: string, duration: number = 2000) {
    const options = new ToastOptions(message, duration);

    try {
      Prompt.showToast(options);
    } catch (toastError) {
      hilog.error(DOMAIN, TAG, 'Failed to show toast: %{public}s', String(toastError));
    }
  }

  async aboutToAppear() {
    await this.initializeApp();
    this.previousSettingsVersion = this.normalizeSettingsVersion(this.settingsVersion);
    this.requestedSettingsVersion = this.previousSettingsVersion;
    this.handledReloadVersion = this.conversationsReloadVersion ?? 0;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE) // 设置键盘避让模式

    // 添加断点检测逻辑
    this.updateBreakpoint();
    // 监听窗口尺寸变化
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (context?.windowStage) {
        const windowClass = await context.windowStage.getMainWindow();
        windowClass.on('windowSizeChange', () => {
          this.updateBreakpoint();
        });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to setup window listener: %{public}s', String(err));
    }
  }

  async onPageShow() {
    const latestVersion = this.conversationsReloadVersion ?? 0;

    // 页面显示时，若检测到刷新版本变化，则强制重新加载对话/消息
    if (latestVersion !== this.handledReloadVersion) {
      hilog.error(DOMAIN, TAG,
        'Chat: onPageShow detected conversationsReloadVersion change -> %{public}d (handled=%{public}d)', latestVersion,
        this.handledReloadVersion);
      this.currentConversation = null;
      this.messages = [];
      this.notifyMessagesUpdated();
      this.conversations = [];
      this.handledReloadVersion = latestVersion;
      await this.reloadChatState('conversationsReloadVersion');
      return;
    }

    if (this.isInitialized) {
      // 如果不是因为清空数据，则按原逻辑检查设置版本
      hilog.error(DOMAIN, TAG, 'Chat: onPageShow triggered, reloading chat state due to settings version.');
      await this.reloadChatState('onPageShow');
    }
  }

  aboutToRender() {
    this.logSettingsVersionState('aboutToRender before check');
    this.checkSettingsVersionChange();
  }

  async initializeApp() {
    try {
      // 初始化数据库
      const context = getContext(this) as common.UIAbilityContext;
      await this.databaseManager.initDatabase(context);

      // 初始化搜索配置管理器
      try {
        await this.searchConfigManager.init(context);
        hilog.info(DOMAIN, TAG, 'SearchConfigManager initialized successfully');
      } catch (searchConfigError) {
        hilog.warn(DOMAIN, TAG, 'Failed to initialize SearchConfigManager: %{public}s', String(searchConfigError));
        // 不阻塞应用启动,searchConfigManager 会使用默认配置
      }

      // 补充 AppStorage 默认值
      const storedReloadVersion: number | undefined =
        AppStorage.get('conversationsReloadVersion') as (number | undefined);
      if (typeof storedReloadVersion !== 'number' || Number.isNaN(storedReloadVersion)) {
        AppStorage.SetOrCreate('conversationsReloadVersion', 0);
      }

      // 加载设置
      await this.loadSettings();

      // 加载对话列表
      await this.loadConversations();

      // 恢复最后使用的对话
      await this.restoreLastConversation();

      // 加载聊天记录
      await this.loadChatHistory();

      this.handledReloadVersion = this.conversationsReloadVersion ?? 0;
      this.isInitialized = true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize app: %{public}s', String(error));
      this.showToast('应用初始化失败');
    }
  }

  async loadSettings() {
    try {
      const settings = await this.databaseManager.getSettings();
      this.currentSettings = settings;

      if (!settings) {
        this.hasSettings = false;
        hilog.error(DOMAIN, TAG, 'No settings configured yet.');
        return;
      }

      hilog.error(DOMAIN, TAG, 'Loaded settings with provider count: %{public}s', String(settings.providers.length));

      const activeProvider = settings.providers.find(provider => provider.id === settings.activeProviderId);
      if (!activeProvider) {
        hilog.warn(DOMAIN, TAG, 'Active provider not found in settings, marking configuration as incomplete.');
        this.hasSettings = false;
        return;
      }

      const activeModel = activeProvider.models.find(model => model.id === settings.activeModelId);
      if (!activeModel) {
        hilog.warn(DOMAIN, TAG, 'Active model not found for current provider, marking configuration as incomplete.');
        this.hasSettings = false;
        return;
      }

      const providerConfigured = activeProvider.apiUrl.trim().length > 0 && activeProvider.apiKey.trim().length > 0;
      this.hasSettings = providerConfigured && activeModel.name.trim().length > 0;

      if (this.hasSettings) {
        settings.apiUrl = activeProvider.apiUrl;
        settings.apiKey = activeProvider.apiKey;
        settings.modelName = activeModel.name;
        this.currentSettings = settings;
        // 同步联网搜索开关到页面状态
        this.enableWebSearch = !!settings.enableWebSearch;
        // 联动识别阿里云开关
        this.isAliyunActive = this.isAliyunProviderActive();
        // 同步当前模型是否支持搜索的标志
        this.currentModelSupportsWebSearchFlag = this.isCurrentModelSupportsWebSearch();
        hilog.error(DOMAIN, TAG, 'Active provider resolved', {
          providerId: activeProvider.id,
          providerName: activeProvider.displayName,
          modelId: activeModel.id,
          modelName: activeModel.name
        });
      } else {
        hilog.warn(DOMAIN, TAG, 'Configuration exists but required API信息未填写完整。');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load settings: %{public}s', String(error));
      this.hasSettings = false;
    }
  }

  private async reloadChatState(reason: string = 'manual', targetVersion?: number): Promise<void> {
    const desiredVersion = targetVersion ?? this.normalizeSettingsVersion(this.settingsVersion);
    this.requestedSettingsVersion = desiredVersion;

    if (!this.pendingSettingsReload) {
      this.pendingSettingsReload = this.performSettingsReload(reason);
    } else {
      hilog.error(DOMAIN, TAG,
        'Chat: settings reload already in progress, updated targetVersion=%{public}d, reason=%{public}s',
        this.requestedSettingsVersion, String(reason));
    }

    try {
      await this.pendingSettingsReload;
    } finally {
      // no-op: performSettingsReload will reset pendingSettingsReload when finished
    }
  }

  private async performSettingsReload(initialReason: string): Promise<void> {
    let attempt = 0;
    try {
      while (true) {
        attempt += 1;
        const targetVersion = this.requestedSettingsVersion;
        hilog.error(DOMAIN, TAG,
          'Chat: reloadChatState start [reason=%{public}s] attempt=%{public}d targetVersion=%{public}d',
          String(initialReason), attempt, targetVersion);
        await this.loadSettings();
        await this.loadConversations();

        if (this.conversations.length === 0) {
          this.currentConversation = null;
          this.messages = [];
          this.notifyMessagesUpdated();
        } else {
          await this.loadChatHistory();
        }

        // 每次设置刷新后，同步更新阿里云识别状态和当前模型搜索能力，驱动 UI 即时变化
        this.isAliyunActive = this.isAliyunProviderActive();
        this.currentModelSupportsWebSearchFlag = this.isCurrentModelSupportsWebSearch();

        this.previousSettingsVersion = targetVersion;
        this.logSettingsVersionState('Chat: reloadChatState completed');

        if (this.requestedSettingsVersion === targetVersion) {
          break;
        }

        hilog.error(DOMAIN, TAG,
          'Chat: detected newer settings reload request during execution, repeating with latest targetVersion');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Chat: reloadChatState failed: %{public}s', String(error));
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(String(error));
    } finally {
      this.pendingSettingsReload = null;
    }
  }

  private checkSettingsVersionChange() {
    if (!this.isInitialized) {
      return;
    }

    const currentVersion = this.normalizeSettingsVersion(this.settingsVersion);
    if (currentVersion === this.previousSettingsVersion && !this.pendingSettingsReload) {
      return;
    }

    hilog.error(DOMAIN, TAG, 'Chat: detected settingsVersion change -> %{public}s', String(currentVersion));
    this.reloadChatState('settingsVersion change', currentVersion).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to refresh chat after settings change: %{public}s', String(error));
    });
  }

  private normalizeSettingsVersion(value: number): number {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    return 0;
  }

  private logSettingsVersionState(prefix: string) {
    const current = this.normalizeSettingsVersion(this.settingsVersion);
    hilog.error(DOMAIN, TAG, '%{public}s; currentVersion=%{public}d, previousVersion=%{public}d', String(prefix),
      current, this.previousSettingsVersion);
  }

  private async waitForLatestSettings(reason: string): Promise<void> {
    if (this.pendingSettingsReload) {
      hilog.error(DOMAIN, TAG, 'Chat: awaiting pending settings reload before %{public}s', String(reason));
      await this.pendingSettingsReload;
    }

    const currentVersion = this.normalizeSettingsVersion(this.settingsVersion);
    if (currentVersion !== this.previousSettingsVersion) {
      hilog.error(DOMAIN, TAG,
        'Chat: settings version mismatch detected during %{public}s, triggering reload to %{public}d', String(reason),
        currentVersion);
      await this.reloadChatState(reason, currentVersion);
    }
  }

  async loadChatHistory() {
    try {
      if (this.currentConversation) {
        this.messages = await this.databaseManager.getChatMessages(this.currentConversation.id);
      } else {
        this.messages = await this.databaseManager.getChatMessages();
      }
      this.notifyMessagesUpdated();

      // 滚动到底部
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load chat history: %{public}s', String(error));
      this.showToast('加载聊天记录失败');
    }
  }

  async loadConversations() {
    try {
      this.conversations = await this.databaseManager.getAllConversations();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load conversations: %{public}s', String(error));
      this.showToast('加载对话列表失败');
    }
  }

  async restoreLastConversation() {
    try {
      if (this.conversations.length > 0) {
        // 按更新时间排序，获取最近使用的对话
        const sortedConversations = [...this.conversations].sort((a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
        );

        // 设置最近使用的对话为当前对话
        this.currentConversation = sortedConversations[0];
        hilog.error(DOMAIN, TAG, 'Restored last conversation: %{public}s %{public}s',
          String(this.currentConversation.id), String(this.currentConversation.title));
      } else {
        hilog.error(DOMAIN, TAG, 'No conversations found, will start with empty state');
        this.currentConversation = null;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to restore last conversation: %{public}s', String(error));
      this.currentConversation = null;
    }
  }

  /**
   * 查找空对话（没有消息的对话）
   * @returns 返回第一个找到的空对话，如果没有则返回null
   */
  async findEmptyConversation(): Promise<Conversation | null> {
    try {
      const conversationIds = this.conversations.map(conversation => conversation.id);
      const messageCounts = await this.databaseManager.getConversationMessageCounts(conversationIds);

      for (const conversation of this.conversations) {
        const count = messageCounts[conversation.id] ?? 0;
        if (count === 0) {
          hilog.error(DOMAIN, TAG, 'Found empty conversation: %{public}s %{public}s', String(conversation.id),
            String(conversation.title));
          return conversation;
        }
      }
      hilog.error(DOMAIN, TAG, 'No empty conversations found');
      return null;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to find empty conversation: %{public}s', String(error));
      return null;
    }
  }

  // showSidebar() {
  //   // 显示侧栏时隐藏键盘
  //   this.hideKeyboard();
  //
  //   this.isSidebarVisible = true;
  //   animateTo({
  //     duration: 300,
  //     curve: Curve.FastOutSlowIn
  //   }, () => {
  //     this.sidebarOffset = 0;
  //     this.backgroundBlurRadius = 15; // 增加模糊强度
  //   });
  // }

  hideSidebar() {
    // 关闭侧边栏时隐藏键盘
    this.hideKeyboard();

    animateTo({
      duration: Chat.ANIMATION_DURATION,
      curve: Curve.EaseInOut
    }, () => {
      this.sidebarOffset = -Chat.SIDEBAR_WIDTH;
      this.backgroundBlurRadius = 0; // 侧边栏隐藏时无模糊
    });

    setTimeout(() => {
      this.isSidebarVisible = false;
    }, 300);
  }

  async createNewConversation() {
    // 创建新对话时隐藏键盘
    this.hideKeyboard();
    // 如果正在发送消息，不允许创建新对话
    if (this.isLoading) {
      this.showToast('请等待当前消息发送完成');
      return;
    }

    // 检查是否存在空对话
    const emptyConversation = await this.findEmptyConversation();
    if (emptyConversation) {
      // 如果存在空对话，切换到该对话而不是创建新的
      this.showToast('已有空对话，已为您切换');
      await this.selectConversation(emptyConversation);
      return;
    }

    try {
      hilog.error(DOMAIN, TAG, 'Creating new conversation...');
      const newConversation = await this.databaseManager.createConversation('新对话');
      hilog.error(DOMAIN, TAG, 'New conversation created');

      this.currentConversation = newConversation;
      this.messages = [];
      this.notifyMessagesUpdated();

      // 等待数据库操作完成
      await this.loadConversations();

      this.hideSidebar();
      this.showToast('已创建新对话');

      // 确保加载状态被重置
      this.isLoading = false;

      hilog.error(DOMAIN, TAG, 'New conversation setup completed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to create new conversation: %{public}s', String(error));
      this.showToast('创建对话失败');

      // 确保加载状态被重置
      this.isLoading = false;
    }
  }

  async selectConversation(conversation: Conversation) {
    // 选择对话时隐藏键盘
    this.hideKeyboard();
    // 如果正在发送消息，不允许切换对话
    if (this.isLoading) {
      this.showToast('请等待当前消息发送完成');
      return;
    }

    try {
      this.currentConversation = conversation;
      await this.loadChatHistory();
      this.hideSidebar();

      // 确保加载状态被重置
      this.isLoading = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to select conversation: %{public}s', String(error));
      this.showToast('切换对话失败');

      // 确保加载状态被重置
      this.isLoading = false;
    }
  }

  /**
   * 显示删除对话确认弹窗
   */
  showDeleteConversationDialog(conversationId: string, conversationTitle: string) {
    NativeDialogHelper.showDeleteConfirmDialog(
      conversationTitle,
      '此操作无法撤销，所有聊天记录将永久丢失。',
      () => {
        // 查找对应ID的对话对象
        const conversation = this.conversations.find(c => c.id === conversationId);
        if (conversation) {
          this.deleteConversation(conversation);
        }
      },
      () => {
        hilog.error(DOMAIN, TAG, 'User cancelled conversation deletion');
      }
    );
  }

  async deleteConversation(conversation: Conversation) {
    try {
      await this.databaseManager.deleteConversation(conversation.id);

      const updatedConversations = await this.databaseManager.getAllConversations();
      this.conversations = updatedConversations;

      if (this.currentConversation?.id === conversation.id) {
        if (updatedConversations.length > 0) {
          this.currentConversation = updatedConversations[0];
          this.messages = await this.databaseManager.getChatMessages(this.currentConversation.id);
          this.notifyMessagesUpdated();
        } else {
          this.currentConversation = null;
          this.messages = [];
          this.notifyMessagesUpdated();
        }
      }

      this.showToast('对话已删除');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete conversation: %{public}s', String(error));
      this.showToast('删除对话失败');
    }
  }

  async switchModel() {
    // 切换模型时隐藏键盘
    this.hideKeyboard();

    await this.waitForLatestSettings('switchModel');

    // 显示半模态弹窗
    if (this.currentSettings && this.currentSettings.providers && this.currentSettings.providers.length > 0) {
      this.showModelSelectorSheet = true;
    } else {
      // 如果没有配置模型，则跳转到设置页面
      this.showToast('请先配置API提供商和模型', 2000);
      this.pathStack.pushPathByName("ModelSettings", null, false);
    }
  }

  // 切换到选定的模型
  async changeModel(providerId: string, modelId: string) {
    if (!this.currentSettings) {
      return;
    }

    try {
      // 更新当前设置
      this.currentSettings.activeProviderId = providerId;
      this.currentSettings.activeModelId = modelId;

      // 找到选中的提供商和模型
      const provider = this.currentSettings.providers.find(p => p.id === providerId);
      const model = provider?.models.find(m => m.id === modelId);

      if (provider && model) {
        // 更新API相关配置
        this.currentSettings.apiUrl = provider.apiUrl;
        this.currentSettings.apiKey = provider.apiKey;
        this.currentSettings.modelName = model.name;

        // 同步 providers 的 isActive 标志，确保状态与 activeProviderId 一致
        if (Array.isArray(this.currentSettings.providers)) {
          for (const p of this.currentSettings.providers) {
            p.isActive = (p.id === providerId);
          }
        }

        // 保存到数据库
        await this.databaseManager.saveSettings(this.currentSettings);

        // 切换模型后，立即刷新是否为阿里云状态和当前模型搜索能力，驱动 UI
        this.isAliyunActive = this.isAliyunProviderActive();
        this.currentModelSupportsWebSearchFlag = this.isCurrentModelSupportsWebSearch();

        this.showToast(`已切换到${provider.displayName}的${model.displayName}`, 2000);
      }

      // 模型切换完成后，弹窗会自动关闭
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to change model: %{public}s', String(error));
      this.showToast('切换模型失败', 2000);
    }
  }

  async generateConversationTitle() {
    if (!this.currentConversation || !this.currentSettings) {
      return;
    }

    try {
      const title: string = await this.titleGenerationService.generateTitle(
        this.messages,
        this.currentSettings.apiKey,
        this.currentSettings.apiUrl,
        this.currentSettings.modelName
      );
      if (title && title !== this.currentConversation.title) {
        await this.databaseManager.updateConversationTitle(this.currentConversation.id, title);
        this.currentConversation.title = title;
        await this.loadConversations();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to generate conversation title: %{public}s', String(error));
    }
  }

  // 获取当前活跃的模型和提供商信息
  getCurrentModelInfo(): ModelInfo {
    if (!this.currentSettings) {
      return { modelName: 'unknown', providerName: 'unknown' };
    }

    if (this.currentSettings.providers.length === 0 || !this.currentSettings.activeProviderId) {
      return { modelName: 'unknown', providerName: 'unknown' };
    }

    const activeProvider =
      this.currentSettings.providers.find(provider => provider.id === this.currentSettings!.activeProviderId);
    if (!activeProvider) {
      return { modelName: 'unknown', providerName: 'unknown' };
    }

    if (activeProvider.models.length === 0) {
      return {
        modelName: '未配置模型',
        providerName: activeProvider.displayName || activeProvider.name
      };
    }

    const activeModel = activeProvider.models.find(model => model.id === this.currentSettings!.activeModelId)
      ?? activeProvider.models[0];

    return {
      modelName: activeModel.displayName || activeModel.name,
      providerName: activeProvider.displayName || activeProvider.name
    };
  }

  // 判断当前是否是阿里云通义千问提供商
  // 兼容“快速配置”中使用中文展示名、未设置 activeProviderId、或仅依赖 apiUrl 的场景
  private isAliyunProviderActive(): boolean {
    const settings = this.currentSettings;
    if (!settings) {
      return false;
    }

    // 归一化判断函数：支持中英文关键词与 URL 特征
    const isAliyunLike = (name: string | undefined, url: string | undefined): boolean => {
      const n = (name || '').toLowerCase();
      const u = (url || '').toLowerCase();
      // 名称关键字（中英文）
      const nameHit = n.includes('aliyun') || n.includes('dashscope') || n.includes('qwen') || n.includes('tongyi')
        || (name || '').includes('阿里云') || (name || '').includes('通义') || (name || '').includes('千问');
      // URL 关键字
      const urlHit = u.includes('dashscope.aliyuncs.com') || u.includes('/compatible-mode/v1')
        || u.includes('aliyun') || u.includes('dashscope') || u.includes('qwen');
      return nameHit || urlHit;
    };

    // 优先：按 activeProviderId 命中
    let provider = settings.providers.find(p => p.id === settings.activeProviderId);
    if (provider) {
      // 进一步结合模型名辅助判断
      const activeModel = provider.models.find(m => m.id === settings.activeModelId) ?? provider.models[0];
      const modelName = activeModel ? `${activeModel.name} ${activeModel.displayName}` : '';
      if (isAliyunLike(provider.name || provider.displayName, provider.apiUrl) || isAliyunLike(modelName, '')) {
        return true;
      }
    }

    // 其次：根据当前 settings.apiUrl 反推（用户可能未正确设置 activeProviderId）
    if (settings.apiUrl && isAliyunLike('', settings.apiUrl)) {
      return true;
    }

    // 再次：扫描所有 provider，找到名称或 URL 命中的，并且该 provider 当前被标记为激活
    const anyActiveAliyun = settings.providers.some(p => {
      const hit = isAliyunLike(p.name || p.displayName, p.apiUrl);
      return hit && (p.id === settings.activeProviderId || p.isActive === true);
    });
    if (anyActiveAliyun) {
      return true;
    }

    return false;
  }

  // 判断当前活跃模型是否支持内置联网搜索
  private isCurrentModelSupportsWebSearch(): boolean {
    const settings = this.currentSettings;
    if (!settings || !settings.activeProviderId || !settings.activeModelId) {
      return false;
    }

    // 查找当前活跃的提供商
    const activeProvider = settings.providers.find(p => p.id === settings.activeProviderId);
    if (!activeProvider) {
      return false;
    }

    // 查找当前活跃的模型
    const activeModel = activeProvider.models.find(m => m.id === settings.activeModelId);
    if (!activeModel) {
      return false;
    }

    // 返回模型是否支持联网搜索
    return !!activeModel.supportsWebSearch;
  }

  // 判断是否应该生成标题
  private shouldGenerateTitle(): boolean {
    // 如果已经有自定义标题，不再生成
    if (!this.currentConversation || this.currentConversation.title !== '新对话') {
      return false;
    }

    // 至少需要4条消息（2轮对话）才考虑生成标题
    if (this.messages.length < 4) {
      return false;
    }

    // 缓存消息统计以避免重复计算
    let userMessageCount = 0;
    let aiMessageCount = 0;
    let totalUserChars = 0;
    let totalAiChars = 0;
    let firstUserMessage: string | undefined;

    // 单次遍历计算所有统计信息
    for (const msg of this.messages) {
      if (msg.role === 'user') {
        userMessageCount++;
        totalUserChars += msg.content.length;
        if (!firstUserMessage) {
          firstUserMessage = msg.content.toLowerCase().trim();
        }
      } else if (msg.role === 'assistant') {
        aiMessageCount++;
        totalAiChars += msg.content.length;
      }
    }

    // 检查是否包含常见的简单问候语
    const greetings = ['你好', 'hello', 'hi', '您好', '在吗', '在不在', '早上好', '晚上好', '下午好'];

    // 如果第一条消息是简单问候语
    if (firstUserMessage && greetings.some(greeting =>
    firstUserMessage!.includes(greeting.toLowerCase()) && firstUserMessage!.length <= 10)) {

      // 即使是问候语开头，如果AI回复很长，说明可能有有意义的对话
      if (totalAiChars >= 50) {
        return true;
      }

      // 对于简单问候语开头的对话，需要至少6条消息和更多内容
      return this.messages.length >= 6 && (totalUserChars >= 20 || totalAiChars >= 100);
    }

    // 对于非问候语开头的对话，综合考虑用户问题和AI回复
    // 如果用户问题虽短但AI回复很长，说明问题有价值
    if (totalUserChars >= 10 || totalAiChars >= 30) {
      return true;
    }

    // 用户消息和AI回复总字符数至少要达到25个字符
    return (totalUserChars + totalAiChars) >= 25;
  }

  // ✅ 分离职责 - 消息验证和初始化
  /**
   * 验证和准备消息
   * @param text 原始输入文本
   * @returns 准备好的消息对象，或null表示验证失败
   */
  private validateAndPrepareMessage(text: string): ChatMessage | null {
    const trimmedInput = text.trim();
    if (!trimmedInput) {
      return null;
    }

    // 输入验证
    if (trimmedInput.length > 10000) {
      this.showToast('消息内容不能超过10000个字符');
      return null;
    }

    // 检查是否包含潜在的恶意内容
    if (this.containsSuspiciousContent(trimmedInput)) {
      this.showToast('消息内容包含不当内容，请修改后重试');
      return null;
    }

    // 检查设置
    if (!this.hasSettings) {
      this.showToast('请先配置API设置');
      this.pathStack.pushPathByName("Settings", null, false);
      return null;
    }

    if (!this.currentSettings) {
      this.showToast('设置加载失败，请重新配置');
      return null;
    }

    return new ChatMessage(trimmedInput, 'user', {
      conversationId: this.currentConversation?.id || 'default'
    });
  }

  // ✅ 分离职责 - 初始化流式消息
  /**
   * 初始化流式AI消息并保存到数据库
   * @param userMessage 用户消息
   * @param conversationId 对话ID
   * @returns 流式消息索引和数据库ID
   */
  private async initializeStreamingMessage(
    userMessage: ChatMessage,
    conversationId: string
  ): Promise<StreamingMessageResult> {
    const modelInfo = this.getCurrentModelInfo();
    const streamingMessage = new ChatMessage('', 'assistant', {
      conversationId: conversationId,
      modelName: modelInfo.modelName,
      providerName: modelInfo.providerName
    });

    const index = this.appendMessage(streamingMessage);
    const id = await this.databaseManager.insertChatMessage(streamingMessage);

    this.replaceMessageAt(index, (msg) => {
      msg.id = id;
    });

    const result: StreamingMessageResult = { index: index, id: id };
    return result;
  }

  // ✅ 分离职责 - 追加数据块
  /**
   * 将流式数据块追加到消息中
   * @param messageIndex 消息索引
   * @param chunk 数据块
   * @param conversationId 对话ID
   */
  private appendChunkToMessage(
    messageIndex: number,
    chunk: string,
    conversationId: string
  ): void {
    if (this.currentConversation?.id !== conversationId) {
      return;
    }

    if (messageIndex < this.messages.length) {
      this.replaceMessageAt(messageIndex, (msg) => {
        msg.content += chunk;
      });
    }
  }

  // ✅ 分离职责 - 处理流式完成
  /**
   * 处理流式请求完成，重置UI状态
   */
  private handleStreamComplete(): void {
    this.isLoading = false;
    this.isGenerating = false;
    this.currentAbortController = null;
    this.userAbortedGeneration = false;
  }

  // ✅ 分离职责 - 持久化消息
  /**
   * 异步持久化流式消息到数据库
   * @param messageIndex 消息索引
   * @param conversationId 对话ID
   */
  private async persistStreamedMessage(
    messageIndex: number,
    conversationId: string
  ): Promise<void> {
    if (messageIndex >= this.messages.length) {
      return;
    }

    const message = this.messages[messageIndex];
    if (!message.id) {
      return;
    }

    try {
      await this.databaseManager.updateChatMessage(message.id, message.content);

      if (!this.userAbortedGeneration && this.shouldGenerateTitle()) {
        await this.generateConversationTitle();
      }

      await this.databaseManager.updateConversationMessageCount(conversationId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Error persisting message: %{public}s', String(error));
    }
  }

  // ✅ 事件驱动处理 - 设置流式事件处理
  /**
   * 为流式请求设置事件处理（替代回调地狱）
   * @param emitter 事件发射器
   * @param streamingMessageIndex 流式消息索引
   * @param conversationId 对话ID
   */
  private setupStreamEventHandlers(
    emitter: StreamEventEmitter,
    streamingMessageIndex: number,
    conversationId: string
  ): void {
    hilog.info(DOMAIN, TAG, 'Setting up stream event handlers for message index: %{public}d', streamingMessageIndex);
    
    // 监听数据事件
    emitter.on(StreamEventType.DATA, (payload: EventPayload) => {
      const chunk = payload as string;
      hilog.info(DOMAIN, TAG, 'Received DATA event, chunk length: %{public}d', chunk.length);
      this.appendChunkToMessage(streamingMessageIndex, chunk, conversationId);
    });

    // 监听元数据事件
    emitter.on(StreamEventType.METADATA, (payload: EventPayload) => {
      const meta = payload as StreamMetadata;
      hilog.info(DOMAIN, TAG, 'Received METADATA event');
      this.updateStreamingMessageMetadata(streamingMessageIndex, meta, conversationId);
    });

    // 监听完成事件
    emitter.once(StreamEventType.COMPLETE, () => {
      hilog.info(DOMAIN, TAG, 'Received COMPLETE event for message index: %{public}d', streamingMessageIndex);
      this.handleStreamComplete();
      // 异步持久化，不阻塞UI状态更新
      this.persistStreamedMessage(streamingMessageIndex, conversationId)
        .catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to persist message: %{public}s', String(err));
        });
    });

    // 监听错误事件
    emitter.on(StreamEventType.ERROR, (payload: EventPayload) => {
      const error = payload as Error;
      hilog.error(DOMAIN, TAG, 'Received ERROR event: %{public}s', String(error));
      this.handleStreamError(streamingMessageIndex, error);
    });

    // 监听警告事件（可选）
    emitter.on(StreamEventType.WARNING, (payload: EventPayload) => {
      const warning = payload as string;
      hilog.warn(DOMAIN, TAG, 'Stream warning: %{public}s', warning);
    });

    // 监听工具调用事件
    emitter.once(StreamEventType.TOOL_CALL, (payload: EventPayload) => {
      const toolCalls = payload as import('../services/StreamEventEmitter').ToolCallData[];
      hilog.info(DOMAIN, TAG, 'Received TOOL_CALL event with %{public}d calls', toolCalls.length);
      this.handleToolCalls(toolCalls, streamingMessageIndex, conversationId)
        .catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to handle tool calls: %{public}s', String(err));
          this.handleStreamError(streamingMessageIndex, err);
        });
    });
    
    hilog.info(DOMAIN, TAG, 'Stream event handlers setup completed');
  }

  // ✅ 事件驱动处理 - 设置重新生成事件处理
  /**
   * 为重新生成流式请求设置事件处理
   * @param emitter 事件发射器
   * @param streamingMessageIndex 重新生成消息的索引
   * @param conversationId 对话ID
   */
  private setupRegenrationStreamEventHandlers(
    emitter: StreamEventEmitter,
    streamingMessageIndex: number,
    conversationId: string
  ): void {
    // 监听数据事件 - 更新重新生成的消息内容
    emitter.on(StreamEventType.DATA, (payload: EventPayload) => {
      const chunk = payload as string;
      if (!this.currentConversation || this.currentConversation.id !== conversationId) {
        return;
      }
      if (streamingMessageIndex >= this.messages.length || !this.messages[streamingMessageIndex]) {
        return;
      }

      this.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
        regeneratedMessage.content += chunk;
      });

      hilog.error(DOMAIN, TAG, 'Regenerated content length=%{public}d',
        this.messages[streamingMessageIndex].content.length);
    });

    // 监听元数据事件 - 更新重新生成消息的元数据
    emitter.on(StreamEventType.METADATA, (payload: EventPayload) => {
      const meta = payload as StreamMetadata;
      if (!this.currentConversation || this.currentConversation.id !== conversationId) {
        return;
      }
      if (streamingMessageIndex >= this.messages.length || !this.messages[streamingMessageIndex]) {
        return;
      }

      let metadataChanged = false;
      this.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
        if (meta.id && regeneratedMessage.providerMessageId !== meta.id) {
          regeneratedMessage.providerMessageId = meta.id;
          metadataChanged = true;
        }
        if (meta.systemFingerprint && regeneratedMessage.systemFingerprint !== meta.systemFingerprint) {
          regeneratedMessage.systemFingerprint = meta.systemFingerprint;
          metadataChanged = true;
        }
        if (meta.created !== undefined) {
          const createdTimestamp = meta.created * 1000;
          if (regeneratedMessage.timestamp < createdTimestamp) {
            regeneratedMessage.timestamp = createdTimestamp;
            regeneratedMessage.providerCreatedAt = meta.created;
            metadataChanged = true;
          } else if (regeneratedMessage.providerCreatedAt !== meta.created) {
            regeneratedMessage.providerCreatedAt = meta.created;
            metadataChanged = true;
          }
        }
      });

      if (metadataChanged) {
        const regeneratedMessage = this.messages[streamingMessageIndex];
        if (regeneratedMessage?.id !== undefined) {
          this.databaseManager.updateChatMessageMetadata(regeneratedMessage.id, {
            timestamp: regeneratedMessage.timestamp,
            providerMessageId: regeneratedMessage.providerMessageId ?? null,
            providerCreatedAt: regeneratedMessage.providerCreatedAt ?? null,
            systemFingerprint: regeneratedMessage.systemFingerprint ?? null,
            modelName: regeneratedMessage.modelName ?? null,
            providerName: regeneratedMessage.providerName ?? null
          }).catch((metadataError: Error) => {
            hilog.error(DOMAIN, TAG, 'Failed to persist regenerated metadata: %{public}s', String(metadataError));
          });
        }
      }
    });

    // 监听完成事件 - 处理重新生成完成
    emitter.once(StreamEventType.COMPLETE, () => {
      hilog.error(DOMAIN, TAG, 'Regeneration completed');

      // 立即重置UI状态，不等待数据库操作
      this.isLoading = false;
      this.isGenerating = false;
      this.currentAbortController = null;

      // 异步执行数据库操作，不阻塞UI状态更新
      (async () => {
        try {
          if (this.currentConversation && this.currentConversation.id === conversationId) {
            if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
              const regeneratedMessage = this.messages[streamingMessageIndex];

              // 更新数据库中的消息内容
              if (regeneratedMessage.id !== undefined) {
                await this.databaseManager.updateChatMessage(regeneratedMessage.id, regeneratedMessage.content);
                hilog.error(DOMAIN, TAG, 'Regenerated message updated in DB ID=%{public}s',
                  String(regeneratedMessage.id));
              } else {
                // 兜底方案：如果没有ID，保存到数据库
                const savedId = await this.databaseManager.insertChatMessage(regeneratedMessage);
                this.replaceMessageAt(streamingMessageIndex, (messageToPersist: ChatMessage) => {
                  messageToPersist.id = savedId;
                });
                hilog.error(DOMAIN, TAG, 'Regenerated message saved with new ID: %{public}s', String(savedId));
              }
              // 滚动到底部
              setTimeout(() => {
                if (this.scroller) {
                  this.scroller.scrollEdge(Edge.Bottom);
                }
              }, 100);
            }
          }
        } catch (dbError) {
          hilog.error(DOMAIN, TAG, 'Error during regeneration database operations: %{public}s', String(dbError));
        }
      })();
    });

    // 监听错误事件 - 处理重新生成失败
    emitter.on(StreamEventType.ERROR, (payload: EventPayload) => {
      const error = payload as Error;
      hilog.error(DOMAIN, TAG, 'Regeneration failed: %{public}s', String(error));

      if (this.currentConversation && this.currentConversation.id === conversationId) {
        if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
          this.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
            regeneratedMessage.content = `重新生成失败: ${error.message || error}`;
          });
        }
      }

      this.isLoading = false;
      this.isGenerating = false;
      this.currentAbortController = null;
      this.showToast('重新生成失败');
    });
  }

  // ✅ 分离职责 - 处理流式错误
  /**
   * 处理流式请求错误
   * @param messageIndex 消息索引
   * @param error 错误对象
   */
  private handleStreamError(messageIndex: number, error: Error): void {
    const friendlyError = this.getFriendlySendErrorMessage(error);

    if (messageIndex < this.messages.length) {
      this.replaceMessageAt(messageIndex, (msg) => {
        msg.content = `[错误] ${friendlyError}`;
      });
    }

    this.isLoading = false;
    this.isGenerating = false;
    this.currentAbortController = null;
    this.userAbortedGeneration = false;
    this.showToast(friendlyError);
  }

  // ✅ 分离职责 - 更新元数据
  /**
   * 更新流式消息的元数据
   * @param streamingMessageIndex 流式消息索引
   * @param meta 元数据
   * @param conversationId 对话ID
   */
  private updateStreamingMessageMetadata(
    streamingMessageIndex: number,
    meta: StreamMetadata,
    conversationId: string
  ): void {
    if (!this.currentConversation || this.currentConversation.id !== conversationId) {
      return;
    }
    if (streamingMessageIndex >= this.messages.length) {
      return;
    }

    let metadataChanged = false;
    this.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
      if (meta.id && message.providerMessageId !== meta.id) {
        message.providerMessageId = meta.id;
        metadataChanged = true;
      }
      if (meta.systemFingerprint && message.systemFingerprint !== meta.systemFingerprint) {
        message.systemFingerprint = meta.systemFingerprint;
        metadataChanged = true;
      }
      if (meta.created !== undefined) {
        const createdTimestamp = meta.created * 1000;
        if (message.timestamp < createdTimestamp) {
          message.timestamp = createdTimestamp;
          message.providerCreatedAt = meta.created;
          metadataChanged = true;
        } else if (message.providerCreatedAt !== meta.created) {
          message.providerCreatedAt = meta.created;
          metadataChanged = true;
        }
      }
    });

    if (metadataChanged) {
      const persistedMessage = this.messages[streamingMessageIndex];
      if (persistedMessage?.id !== undefined) {
        const update: ChatMessageMetadataUpdate = {
          timestamp: persistedMessage.timestamp,
          providerMessageId: persistedMessage.providerMessageId ?? null,
          providerCreatedAt: persistedMessage.providerCreatedAt ?? null,
          systemFingerprint: persistedMessage.systemFingerprint ?? null,
          modelName: persistedMessage.modelName ?? null,
          providerName: persistedMessage.providerName ?? null
        };
        if (meta && meta.citations) {
          update.citations = meta.citations as Citation[];
          this.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
            if (update.citations) {
              message.citations = update.citations as Citation[];
            }
          });
        }
        this.databaseManager.updateChatMessageMetadata(persistedMessage.id, update)
          .catch((metadataError: Error) => {
            hilog.error(DOMAIN, TAG, 'Failed to persist streaming metadata: %{public}s', String(metadataError));
          });
      }
    }
  }

  // ✅ 简化的主函数 - 仅负责流程控制
  async sendMessage() {
    try {
      // 1️⃣ 验证和准备消息
      const userMessage = this.validateAndPrepareMessage(this.inputText);
      if (!userMessage) {
        return;
      }

      // 2️⃣ 前置检查和准备
      await this.waitForLatestSettings('sendMessage');
      this.hideKeyboard();
      this.scrollToBottom();

      // 3️⃣ 确保对话存在
      if (!this.currentConversation) {
        await this.createNewConversationForMessage();
      }

      if (!this.currentConversation || !this.currentConversation.id) {
        this.showToast('对话状态异常，请重新创建对话');
        return;
      }

      const targetConversationId = this.currentConversation.id;

      // 4️⃣ 准备状态和消息
      this.isLoading = true;
      this.isGenerating = true;
      this.currentAbortController = createAbortController();
      this.inputText = '';

      // 5️⃣ 保存用户消息
      const userMessageIndex = this.appendMessage(userMessage);
      const userMessageId = await this.databaseManager.insertChatMessage(userMessage);
      this.replaceMessageAt(userMessageIndex, (msg) => {
        msg.id = userMessageId;
      });

      // 6️⃣ 初始化流式消息
      const streamingResult: StreamingMessageResult =
        await this.initializeStreamingMessage(userMessage, targetConversationId);
      const streamingIndex: number = streamingResult.index;

      // 7️⃣ 准备AI消息列表
      const messagesForAI = this.prepareMessagesForAPI(userMessage);

      // 8️⃣ 检查是否启用联网搜索并构建工具数组
      let tools: object[] = [];
      try {
        const searchConfig = this.searchConfigManager.getConfig();
        // 检查是否启用网络搜索，并且已配置搜索服务
        if (searchConfig && searchConfig.enableWebSearch && searchConfig.enabledServices.length > 0) {
          const selectedService = this.searchConfigManager.getSelectedService();
          if (selectedService) {
            const toolDef = this.searchToolService.getToolDefinition();
            tools = [toolDef as object];
            hilog.info(DOMAIN, TAG, 'Web search tool enabled with service: %{public}s', selectedService.type);
          } else {
            hilog.warn(DOMAIN, TAG, 'Web search enabled but no service selected');
          }
        } else {
          hilog.info(DOMAIN, TAG, 'Web search not enabled or no services configured');
        }
      } catch (configError) {
        hilog.warn(DOMAIN, TAG, 'Failed to get search config, using default: %{public}s', String(configError));
        // 降级到不使用工具调用
      }

      // 9️⃣ 发送流式请求（使用新的事件驱动架构）
      const emitter = await this.networkManager.sendStreamChatRequestV2(
        this.currentSettings!.apiUrl,
        this.currentSettings!.apiKey,
        this.currentSettings!.modelName,
        messagesForAI,
        {
          enableWebSearch: this.isAliyunActive && this.enableWebSearch,
          tools: tools.length > 0 ? tools : undefined, // OpenAI 工具调用
          abortController: this.currentAbortController,
          requestTimeout: 30000
        }
      );

      // 🔟 设置事件处理（替代回调地狱）
      this.setupStreamEventHandlers(emitter, streamingIndex, targetConversationId);

    } catch (error) {
      this.isLoading = false;
      this.isGenerating = false;
      this.currentAbortController = null;
      const friendlyError = this.getFriendlySendErrorMessage(error instanceof Error ? error : new Error(String(error)));
      this.showToast(friendlyError);
    }
  }

  // ✅ 辅助方法 - 创建新对话
  private async createNewConversationForMessage(): Promise<void> {
    try {
      const newConversation = await this.databaseManager.createConversation('新对话');
      this.currentConversation = newConversation;
      await this.loadConversations();
      await new Promise<void>(resolve => setTimeout(resolve, 100));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to create conversation for message: %{public}s', String(error));
      const err = error instanceof Error ? error : new Error(String(error));
      throw err;
    }
  }

  // ✅ 辅助方法 - 准备API消息列表
  private prepareMessagesForAPI(userMessage: ChatMessage): ChatMessage[] {
    const endIndex = this.messages.length - 1;
    const startIndex = Math.max(0, endIndex - 10);
    const messagesForAI = this.messages.slice(startIndex, endIndex);
    if (messagesForAI.length === 0) {
      messagesForAI.push(this.cloneChatMessage(userMessage));
    }
    return messagesForAI;
  }

  // ✅ 工具调用处理 - 执行搜索并继续对话
  // ✅ 工具调用处理 - 执行搜索并继续对话
  private async handleToolCalls(
    toolCalls: import('../services/StreamEventEmitter').ToolCallData[],
    assistantMessageIndex: number,
    conversationId: string
  ): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Handling %{public}d tool calls', toolCalls.length);

    // 🔥 关键修复：将工具调用信息保存到 assistant 消息中
    if (assistantMessageIndex < this.messages.length) {
      // 转换为 ToolCall 格式
      const formattedToolCalls: import('../services/DataModels').ToolCall[] = toolCalls.map((tc): import('../services/DataModels').ToolCall => {
        const toolFunction: import('../services/DataModels').ToolFunction = {
          name: tc.name,
          arguments: tc.arguments
        };
        
        const toolCall: import('../services/DataModels').ToolCall = {
          id: tc.id,
          type: tc.type || 'function',
          function: toolFunction
        };
        
        return toolCall;
      });
      
      this.replaceMessageAt(assistantMessageIndex, (msg) => {
        msg.toolCalls = formattedToolCalls;
      });
      
      hilog.info(DOMAIN, TAG, 'Saved %{public}d tool calls to assistant message', formattedToolCalls.length);
    }

    // 停止当前流
    this.handleStreamComplete();

    // 执行每个工具调用
    for (const toolCall of toolCalls) {
      hilog.info(DOMAIN, TAG, 'Processing tool call: id=%{public}s, name=%{public}s, type=%{public}s', 
        String(toolCall.id || 'MISSING'), String(toolCall.name), String(toolCall.type));
      
      if (toolCall.name === 'search_web' && toolCall.arguments) {
        try {
          // 验证工具调用 ID
          if (!toolCall.id) {
            hilog.error(DOMAIN, TAG, 'Tool call missing required ID field');
            throw new Error('工具调用缺少必需的 ID 字段，无法继续处理');
          }

          // 解析参数
          const args = JSON.parse(toolCall.arguments) as SearchToolArgs;
          const query = args.query;

          hilog.info(DOMAIN, TAG, 'Executing search for query: %{public}s with toolCallId: %{public}s', 
            query, toolCall.id);

          // 显示搜索状态提示
          this.showToast(`正在搜索: ${query}`);

          // 执行搜索
          const searchResult = await this.searchToolService.executeSearch(query, args.resultSize);

          hilog.info(DOMAIN, TAG, 'Search completed with %{public}d results', searchResult.items.length);

          // 将搜索结果转换为Citation数组，保存到AI消息中
          let citations: Citation[] = [];
          if (assistantMessageIndex < this.messages.length) {
            const assistantMessage = this.messages[assistantMessageIndex];
            // 创建Citation数组（仅用于UI显示）
            citations = searchResult.items.map((item): Citation => ({
              title: item.title,
              url: item.url,
              snippet: item.text
            }));

            // 只更新citations到assistant消息（用于UI显示一个胶囊）
            this.replaceMessageAt(assistantMessageIndex, (msg) => {
              msg.citations = citations;
            });

            // 持久化assistant消息的citations更新
            if (assistantMessage.id) {
              const update: ChatMessageMetadataUpdate = {
                timestamp: assistantMessage.timestamp,
                providerMessageId: assistantMessage.providerMessageId ?? null,
                providerCreatedAt: assistantMessage.providerCreatedAt ?? null,
                systemFingerprint: assistantMessage.systemFingerprint ?? null,
                modelName: assistantMessage.modelName ?? null,
                providerName: assistantMessage.providerName ?? null,
                citations: citations
              };
              await this.databaseManager.updateChatMessageMetadata(assistantMessage.id, update);
            }
          }

          // 继续对话 - 基于搜索结果生成回复
          await this.continueConversationWithToolResult(conversationId, searchResult, toolCall.id, toolCall.name);

        } catch (error) {
          hilog.error(DOMAIN, TAG, 'Tool execution failed: %{public}s', String(error));
          const err = error instanceof Error ? error : new Error(String(error));
          
          // 显示友好的错误提示
          let errorMessage = '搜索失败';
          if (err.message.includes('未配置')) {
            errorMessage = err.message;
          } else if (err.message.includes('未启用')) {
            errorMessage = err.message;
          } else if (err.message.includes('未选择')) {
            errorMessage = err.message;
          } else if (err.message.includes('缺少')) {
            errorMessage = err.message;
          } else {
            errorMessage = `搜索失败: ${err.message}`;
          }
          
          this.showToast(errorMessage);
          
          // 在消息中显示错误
          if (assistantMessageIndex < this.messages.length) {
            this.replaceMessageAt(assistantMessageIndex, (msg) => {
              msg.content = `[搜索失败] ${errorMessage}\n\n请检查搜索配置或稍后重试。`;
            });
          }
          
          // 不抛出错误，允许继续处理其他工具调用
          continue;
        }
      }
    }
  }

  // ✅ 继续对话 - 在工具执行后
  private async continueConversationWithToolResult(
    conversationId: string,
    searchResult?: import('../services/search/SearchModels').SearchResult,
    toolCallId?: string,
    toolName?: string
  ): Promise<void> {
    if (!this.currentConversation || this.currentConversation.id !== conversationId) {
      hilog.warn(DOMAIN, TAG, 'Conversation changed, skipping tool result continuation');
      return;
    }

    // 重置状态
    this.isLoading = true;
    this.isGenerating = true;
    this.currentAbortController = createAbortController();
    
    hilog.info(DOMAIN, TAG, 'Starting continueConversationWithToolResult, isLoading=%{public}s, isGenerating=%{public}s', 
      String(this.isLoading), String(this.isGenerating));

    try {
      // 构建工具结果消息 - 这是API格式所需的标准tool_result
      let toolContent = '';
      if (searchResult) {
        // 构建搜索结果文本供API使用
        if (searchResult.answer) {
          toolContent = `搜索摘要: ${searchResult.answer}\n\n`;
        }
        toolContent += '详细搜索结果:\n';
        for (const item of searchResult.items) {
          toolContent += `[${item.index || 0}] 标题: ${item.title}\n内容: ${item.text}\nURL: ${item.url}\n\n`;
        }

        // 验证 toolCallId 是否存在
        if (!toolCallId) {
          hilog.error(DOMAIN, TAG, 'Tool call ID is missing, cannot create tool message');
          throw new Error('工具调用ID缺失，无法继续对话');
        }

        // 添加工具结果消息到对话历史 - 这个消息包含搜索结果，大模型会据此生成回答
        const toolResultMessage = new ChatMessage(
          toolContent,
          'tool',
          { conversationId: conversationId, timestamp: Date.now(), toolCallId: toolCallId }
        );

        hilog.info(DOMAIN, TAG, 'Creating tool message with toolCallId: %{public}s', toolCallId);

        const toolIndex = this.appendMessage(toolResultMessage);
        const toolId = await this.databaseManager.insertChatMessage(toolResultMessage);
        this.replaceMessageAt(toolIndex, (msg) => {
          msg.id = toolId;
        });

        // 🔍 验证 toolCallId 在 replaceMessageAt 后是否保留
        hilog.info(DOMAIN, TAG, 'Added tool result message with %{public}d search items, toolCallId preserved: %{public}s', 
          searchResult.items.length, String(!!this.messages[toolIndex].toolCallId));

      }

      // 初始化新的流式消息（AI的继续回答）
      const dummyMessage = new ChatMessage(
        '',
        'user',
        { conversationId: conversationId, timestamp: Date.now() }
      );
      const streamingResult = await this.initializeStreamingMessage(dummyMessage, conversationId);
      const streamingIndex = streamingResult.index;

      // 准备消息列表 - 包含：user → assistant(with tool_call) → tool_result → 新assistant(stream)
      // 注意：需要排除最后一个空的 assistant 消息（刚刚创建的流式消息占位符）
      const allMessages = this.messages.slice(0, this.messages.length - 1); // 排除刚创建的空 assistant
      const messagesForAI = allMessages.slice(Math.max(0, allMessages.length - 20));

      hilog.info(DOMAIN, TAG, 'Continuing with %{public}d messages in context (excluded new assistant placeholder)', messagesForAI.length);
      
      // 打印消息序列以便调试
      for (let i = 0; i < messagesForAI.length; i++) {
        const msg = messagesForAI[i];
        hilog.info(DOMAIN, TAG, 'Message[%{public}d]: role=%{public}s, hasToolCallId=%{public}s, hasToolCalls=%{public}s, contentLength=%{public}d', 
          i, msg.role, String(!!msg.toolCallId), String(!!(msg.toolCalls && msg.toolCalls.length > 0)), msg.content.length);
      }

      // 检查搜索配置并构建工具数组
      let tools: object[] = [];
      try {
        const searchConfig = this.searchConfigManager.getConfig();
        // 检查是否启用网络搜索，并且已配置搜索服务
        if (searchConfig && searchConfig.enableWebSearch && searchConfig.enabledServices.length > 0) {
          const selectedService = this.searchConfigManager.getSelectedService();
          if (selectedService) {
            const toolDef = this.searchToolService.getToolDefinition();
            tools = [toolDef as object];
            hilog.info(DOMAIN, TAG, 'Web search tool enabled in continuation with service: %{public}s', selectedService.type);
          } else {
            hilog.warn(DOMAIN, TAG, 'Web search enabled in continuation but no service selected');
          }
        }
      } catch (configError) {
        hilog.warn(DOMAIN, TAG, 'Failed to get search config in continueConversation: %{public}s', String(configError));
      }

      // 发送流式请求
      hilog.info(DOMAIN, TAG, 'About to send stream request for continuation...');
      hilog.info(DOMAIN, TAG, 'Request params: apiUrl=%{public}s, model=%{public}s, messageCount=%{public}d', 
        this.currentSettings!.apiUrl.substring(0, 30), this.currentSettings!.modelName, messagesForAI.length);
      
      const emitter = await this.networkManager.sendStreamChatRequestV2(
        this.currentSettings!.apiUrl,
        this.currentSettings!.apiKey,
        this.currentSettings!.modelName,
        messagesForAI,
        {
          enableWebSearch: this.isAliyunActive && this.enableWebSearch,
          tools: tools.length > 0 ? tools : undefined,
          abortController: this.currentAbortController,
          requestTimeout: 30000
        }
      );

      hilog.info(DOMAIN, TAG, 'Stream request sent, emitter created successfully');

      // 🔥 关键修复：设置事件处理器来接收流式响应
      this.setupStreamEventHandlers(emitter, streamingIndex, conversationId);
      
      hilog.info(DOMAIN, TAG, 'Stream event handlers set up for continuation response, waiting for data...');
      
      // ⏱️ 设置超时保护：如果60秒内没有收到任何数据或完成事件，强制重置状态
      const timeoutId = setTimeout(() => {
        if (this.isLoading || this.isGenerating) {
          hilog.error(DOMAIN, TAG, 'Stream timeout after 60s, forcing state reset');
          this.isLoading = false;
          this.isGenerating = false;
          this.currentAbortController = null;
          this.showToast('请求超时，请重试');
          
          // 在消息中显示超时提示
          if (streamingIndex < this.messages.length) {
            this.replaceMessageAt(streamingIndex, (msg) => {
              if (!msg.content || msg.content.length === 0) {
                msg.content = '[超时] 未收到响应，请检查网络或重试';
              }
            });
          }
        }
      }, 60000);
      
      // 在完成或错误时清除超时
      emitter.once(StreamEventType.COMPLETE, () => {
        clearTimeout(timeoutId);
      });
      emitter.once(StreamEventType.ERROR, () => {
        clearTimeout(timeoutId);
      });

    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to continue conversation with tool result: %{public}s', String(error));
      this.isLoading = false;
      this.isGenerating = false;
      this.currentAbortController = null;
      const friendlyError = this.getFriendlySendErrorMessage(error instanceof Error ? error : new Error(String(error)));
      this.showToast(friendlyError);
    }
  }

  /**
   * 停止当前的AI生成
   */
  stopGeneration() {
    if (this.currentAbortController && this.isGenerating) {
      hilog.error(DOMAIN, TAG, 'Stopping AI generation...');
      this.userAbortedGeneration = true;
      this.currentAbortController.abort();
      // 不立即设置状态，让onComplete回调来处理
      this.showToast('已停止生成');
    }
  }

  scrollToBottom() {
    if (this.scroller) {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to scroll to bottom: %{public}s', String(error));
        // 备用方案：尝试使用scrollTo方法
        try {
          const currentOffset = this.scroller.currentOffset();
          if (currentOffset) {
            this.scroller.scrollTo({ xOffset: 0, yOffset: (currentOffset.yOffset || 0) + 1000 });
          }
        } catch (scrollError) {
          hilog.error(DOMAIN, TAG, 'Backup scroll method also failed: %{public}s', String(scrollError));
        }
      }
    }
  }

  // 消息操作方法
  async copyMessage(message: ChatMessage) {
    try {
      const clipboardManager = ClipboardManager.getInstance();
      const success = await clipboardManager.copyText(message.content);

      if (success) {
        this.showToast('已复制到剪贴板');
        hilog.error(DOMAIN, TAG, 'Message copied successfully: %{public}s', String(message.content));
      } else {
        this.showToast('复制失败');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to copy message: %{public}s', String(error));
      this.showToast('复制失败');
    }
  }

  async editMessage(message: ChatMessage) {
    if (message.role === 'user') {
      // 用户消息编辑：将内容填入输入框，并标记要替换的消息
      this.inputText = message.content;

      // 找到这条消息的索引
      const messageIndex = this.messages.findIndex(msg => msg.id === message.id);
      if (messageIndex >= 0) {
        // 删除这条消息及其后的所有消息（包括对应的AI回复）
        const messagesToDelete = this.messages.slice(messageIndex);

        // 从数据库删除这些消息
        for (const msg of messagesToDelete) {
          if (msg.id !== undefined) {
            await this.databaseManager.deleteMessage(msg.id);
          }
        }

        // 从UI中移除这些消息
        this.messages = this.messages.slice(0, messageIndex);
        this.notifyMessagesUpdated();

        this.showToast('已移除此消息及后续对话，请重新编辑发送');
      } else {
        this.showToast('消息内容已填入输入框，修改后重新发送');
      }
    }
  }

  async deleteMessage(message: ChatMessage) {
    try {
      if (!this.currentConversation) {
        this.showToast('当前没有活跃对话');
        return;
      }

      // 从数据库删除消息
      if (message.id !== undefined) {
        await this.databaseManager.deleteMessage(message.id);
      }

      // 从本地列表删除消息
      this.messages = this.messages.filter(msg => msg.id !== message.id);
      this.notifyMessagesUpdated();

      this.showToast('消息已删除');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete message: %{public}s', String(error));
      this.showToast('删除消息失败');
    }
  }

  async regenerateMessage(message: ChatMessage) {
    if (message.role !== 'assistant') {
      return;
    }

    await this.waitForLatestSettings('regenerateMessage');

    // 重新生成时隐藏键盘，避免干扰
    this.hideKeyboard();

    try {
      // 找到这条AI消息的索引
      const messageIndex = this.messages.findIndex(msg => msg.id === message.id);
      if (messageIndex <= 0) {
        this.showToast('无法找到对应的用户消息');
        return;
      }

      const userMessage = this.messages[messageIndex - 1];
      if (userMessage.role !== 'user') {
        this.showToast('消息顺序异常');
        return;
      }

      // 检查当前对话状态
      if (!this.currentConversation) {
        this.showToast('对话状态异常，请重新创建对话');
        return;
      }

      // 删除当前AI消息之后的所有消息
      const messagesToDelete = this.messages.slice(messageIndex + 1);
      for (const msg of messagesToDelete) {
        if (msg.id !== undefined) {
          await this.databaseManager.deleteMessage(msg.id);
        }
      }
      this.messages = this.messages.slice(0, messageIndex + 1);
      this.notifyMessagesUpdated();

      // 清空当前AI消息的内容，保留消息结构用于重新生成，并更新模型信息
      const modelInfo = this.getCurrentModelInfo();
      this.replaceMessageAt(messageIndex, (regeneratingMessage: ChatMessage) => {
        regeneratingMessage.content = '';
        regeneratingMessage.modelName = modelInfo.modelName;
        regeneratingMessage.providerName = modelInfo.providerName;
      });

      // 从数据库删除旧的AI消息内容
      if (message.id !== undefined) {
        await this.databaseManager.deleteMessage(message.id);
        // 清除 ID，因为消息将被重新生成并重新保存
        this.replaceMessageAt(messageIndex, (regeneratingMessage: ChatMessage) => {
          regeneratingMessage.id = undefined;
        });
      }

      // 立即为重新生成的消息创建新的数据库记录
      const regeneratedMessageRecord = this.messages[messageIndex];
      const newMessageId = await this.databaseManager.insertChatMessage(regeneratedMessageRecord);
      this.replaceMessageAt(messageIndex, (regeneratingMessage: ChatMessage) => {
        regeneratingMessage.id = newMessageId;
      });
      hilog.error(DOMAIN, TAG, 'Created regenerated record ID=%{public}s', String(newMessageId));

      // 设置为重新生成模式
      this.isLoading = true;
      this.isGenerating = true;
      this.currentAbortController = createAbortController();
      const targetConversationId = this.currentConversation.id;
      const streamingMessageIndex = messageIndex;

      // 滚动到重新生成的消息位置
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);

      // 准备发送给AI的消息列表（不包括当前正在重新生成的消息）
      const messagesForAI = this.messages.slice(0, messageIndex);

      hilog.error(DOMAIN, TAG, 'Regenerating AI message at index=%{public}d', streamingMessageIndex);

      // 发送流式请求重新生成（使用新的事件驱动架构）
      const emitter = await this.networkManager.sendStreamChatRequestV2(
        this.currentSettings?.apiUrl || '',
        this.currentSettings?.apiKey || '',
        this.currentSettings?.modelName || '',
        messagesForAI,
        {
          enableWebSearch: this.isAliyunActive && this.enableWebSearch,
          abortController: this.currentAbortController,
          requestTimeout: 30000
        }
      );

      // 设置重新生成的事件处理
      this.setupRegenrationStreamEventHandlers(emitter, streamingMessageIndex, targetConversationId);

    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to regenerate message: %{public}s', String(error));
      this.isLoading = false;
      this.showToast('重新生成失败');
    }
  }

  async clearHistory() {
    try {
      await this.databaseManager.clearChatHistory();
      this.messages = [];
      this.notifyMessagesUpdated();
      this.showToast('聊天记录已清空');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear history: %{public}s', String(error));
      this.showToast('清空记录失败');
    }
  }

  /**
   * 测试浏览器启动功能
   * 用于验证链接点击功能是否正常工作
   */
  testBrowserLaunch(url: string = 'https://www.huawei.com') {
    const context = getContext(this) as common.UIAbilityContext;
    BrowserHelper.openUrl(context, url);
  }

  /**
   * 隐藏输入法键盘
   */
  private hideKeyboard() {
    try {
      const inputMethodController = inputMethod.getController();
      inputMethodController.hideTextInput()
        .then(() => {
          hilog.error(DOMAIN, TAG, 'Keyboard hidden successfully');
        })
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to hide keyboard: %{public}s', String(error));
        });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Error getting input method controller: %{public}s', String(error));
    }
  }

  /**
   * 监听 conversations 变化，更新缓存的分组数据
   * 仅在数据真正变化时重新计算，避免每次渲染都重新计算
   */
  private updateGroupedConversations() {
    this.cachedGroupedConversations = this.groupConversationsByDate();
    this.cachedGroupedKeys = Object.keys(this.cachedGroupedConversations);
  }

  @Builder
  buildGroupedConversations() {
    ForEach(this.cachedGroupedKeys, (dateKey: string) => {
      // 日期分组标题
      Text(this.formatDateGroup(dateKey))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 4, top: 16, bottom: 8 })
        .textAlign(TextAlign.Start)

      // 该日期下的对话列表
      List({ space: 2 }) {
        ForEach((this.cachedGroupedConversations?.[dateKey]) || [], (conversation: Conversation, index: number) => {
          ListItem() {
            this.ConversationItem(conversation)
          }
          .swipeAction({
            end: () => this.conversationSwipeAction(conversation),
            edgeEffect: SwipeEdgeEffect.Spring
          })
        })
      }
      .width('100%')
      .scrollBar(BarState.Off)
    })
  }

  // 获取分组对话的日期键数组（直接使用缓存数据，避免重复计算）
  private getGroupedConversationKeys(): string[] {
    return this.cachedGroupedKeys;
  }

  // 获取指定日期的对话列表（直接使用缓存数据，避免重复计算）
  private getConversationsForDate(dateKey: string): Conversation[] {
    return (this.cachedGroupedConversations?.[dateKey]) || [];
  }

  // 按日期分组对话的工具方法
  private groupConversationsByDate(): Record<string, Conversation[]> {
    const groups: Record<string, Conversation[]> = {};

    // 按更新时间倒序排列对话
    const sortedConversations = [...this.conversations].sort((a, b) =>
    new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
    );

    sortedConversations.forEach(conversation => {
      const date = new Date(conversation.updatedAt);
      const dateKey = this.getDateKey(date);

      if (!groups[dateKey]) {
        groups[dateKey] = [];
      }
      groups[dateKey].push(conversation);
    });

    return groups;
  }

  // 生成日期分组的key
  private getDateKey(date: Date): string {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const conversationDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());

    // 计算时间差（天数）
    const timeDiff = today.getTime() - conversationDate.getTime();
    const daysDiff = Math.floor(timeDiff / (1000 * 60 * 60 * 24));

    if (daysDiff === 0) {
      return 'today';
    } else if (daysDiff === 1) {
      return 'yesterday';
    } else if (daysDiff >= 2 && daysDiff <= 7) {
      return 'this_week';
    } else if (daysDiff >= 8 && daysDiff <= 30) {
      return 'this_month';
    } else {
      // 超过30天的按年月分组
      const conversationYear = date.getFullYear();
      const conversationMonth = date.getMonth() + 1;
      const currentYear = now.getFullYear();

      if (conversationYear === currentYear) {
        // 今年的显示月份
        return `${conversationYear}-${conversationMonth.toString().padStart(2, '0')}`;
      } else {
        // 往年的显示年月
        return `${conversationYear}-${conversationMonth.toString().padStart(2, '0')}`;
      }
    }
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
      // 月份格式 YYYY-MM
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
      // 兜底处理
      return dateKey;
    }
  }

  @Builder
  SidebarContent() {
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
          .backgroundColor(Color.Transparent) //$r('sys.color.button_background_color_transparent')
          .onClick(() => {
            this.hideSidebar();
            this.showControlButton = !this.showControlButton;
            animateTo({
              duration: 300,
              curve: Curve.FastOutSlowIn
            }, () => {
              this.showSideBar = false;
            })
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
              this.createNewConversation();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 12, bottom: 12 })
      }
      .margin({ top: this.getUIContext().px2vp(this.topRectHeight) })

      // 对话列表
      if (this.conversations.length === 0) {
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
      } else {
        Scroll() {
          Column() {
            this.buildGroupedConversations()
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }

      // 底部功能按钮
      Column() {
        // 设置按钮
        Row() {
          Button('设置')
            .fontColor($r('app.color.text_color'))
            .width('90%')
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .borderRadius(24)
            .onClick(() => {
              this.pathStack.pushPathByName("Settings", null);
              this.hideKeyboard();
              this.showSideBar = !this.showSideBar
              this.showControlButton = !this.showControlButton
            })
            .margin({ top: 12, bottom: 12 })
        }
      }
      .width('100%')
      .margin({ bottom: this.getUIContext().px2vp(this.bottomRectHeight) })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.common_background'))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  conversationSwipeAction(conversation: Conversation) {
    Row() {
      // 重命名按钮 - 圆形
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
        this.showRenameDialog(conversation);
      })

      // 删除按钮 - 圆形
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
        this.showDeleteConversationDialog(conversation.id, conversation.title || '新对话');
      })
    }
    .padding(4)
    .justifyContent(FlexAlign.SpaceEvenly)
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

        // 显示时间（时:分格式）
        Text(this.formatTime(conversation.updatedAt))
          .fontSize(12)
          .margin({ top: 2 })
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(64)
    .padding({
      left: 12,
      right: 12,
      top: 8,
      bottom: 8
    })
    .borderRadius(8)
    .onClick(() => {
      this.selectConversation(conversation);
      animateTo({
        duration: 300,
        curve: Curve.FastOutSlowIn
      }, () => {
        this.showControlButton = true
        this.showSideBar = false;
      })
    })
  }

  // 格式化时间显示（只显示时分）
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  // 显示重命名对话框
  private showRenameDialog(conversation: Conversation) {
    this.renameDialogController = new CustomDialogController({
      builder: RenameConversationDialog({
        conversation: conversation,
        onConfirm: (conversationId: string, newTitle: string) => {
          this.renameConversation(conversationId, newTitle);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });

    this.renameDialogController.open();
  }

  // 重命名对话
  private async renameConversation(conversationId: string, newTitle: string) {
    try {
      await this.databaseManager.updateConversationTitle(conversationId, newTitle);

      // 更新当前对话标题
      if (this.currentConversation?.id === conversationId) {
        this.currentConversation.title = newTitle;
      }

      // 刷新对话列表
      await this.loadConversations();

      this.showToast('重命名成功', 2000);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to rename conversation: %{public}s', String(error));
      this.showToast('重命名失败', 2000);
    }
  }

  @Builder
  @Builder
  ModelSelectorSheetBuilder() {
    ModelSelectorSheet({
      providers: this.currentSettings?.providers || [],
      currentProviderId: this.currentSettings?.activeProviderId || '',
      currentModelId: this.currentSettings?.activeModelId || '',
      onModelSelected: (providerId: string, modelId: string) => {
        this.changeModel(providerId, modelId);
      },
      onClose: () => {
        this.showModelSelectorSheet = false;
      }
    })
  }

  // 根据窗口宽度计算断点
  /**
   * 检查输入内容是否包含可疑内容
   */
  private containsSuspiciousContent(input: string): boolean {
    // 检查是否包含潜在的脚本注入
    const scriptPatterns = [
      /<script[^>]*>.*?<\/script>/gi,
      /javascript:/gi,
      /on\w+\s*=/gi,
      /<iframe[^>]*>/gi,
      /<object[^>]*>/gi,
      /<embed[^>]*>/gi
    ];

    // 检查是否包含SQL注入模式
    const sqlPatterns = [
      /(\bUNION\b|\bSELECT\b|\bINSERT\b|\bUPDATE\b|\bDELETE\b|\bDROP\b).*(\bFROM\b|\bWHERE\b|\bINTO\b)/gi,
      /['";].*(-{2}|\/\*)/gi
    ];

    // 检查所有模式
    const allPatterns = [...scriptPatterns, ...sqlPatterns];
    return allPatterns.some(pattern => pattern.test(input));
  }

  private updateBreakpoint(): void {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (context?.windowStage) {
        context.windowStage.getMainWindow()
          .then((windowClass: window.Window) => {
            return windowClass.getWindowProperties();
          })
          .then((properties: window.WindowProperties) => {
            const width: number = properties.windowRect.width;
            const uiCtx = this.getUIContext();
            const widthVp: number = uiCtx ? uiCtx.px2vp(width) : width;

            hilog.error(DOMAIN, TAG, '[BREAKPOINT error] Window width: %{public}dpx, widthVp=%{public}d', width,
              widthVp);

            let breakpoint: string = 'sm';

            if (widthVp >= 1440) {
              breakpoint = 'xl';
            } else if (widthVp >= 840) {
              breakpoint = 'lg';
            } else if (widthVp >= 600) {
              breakpoint = 'md';
            } else if (widthVp >= 320) {
              breakpoint = 'sm';
            } else {
              breakpoint = 'xs';
            }

            hilog.error(DOMAIN, TAG, '[BREAKPOINT error] Calculated breakpoint: %{public}s', String(breakpoint));

            // 只使用AppStorage更新，@StorageLink会自动同步
            AppStorage.setOrCreate('currentBreakPoint', breakpoint);
          })
          .catch((err: Error) => {
            hilog.error(DOMAIN, TAG, 'Failed to get window properties: %{public}s', String(err));
          });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to update breakpoint: %{public}s', String(err));
    }
  }
}
