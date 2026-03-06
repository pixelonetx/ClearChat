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
import { ClipboardManager } from '../components/utils/ClipboardManager';
import { BrowserHelper } from '../services/BrowserHelper';
import { NativeDialogHelper } from '../components/dialogs/NativeDialogHelper';
import { MessageItem } from '../components/chat/MessageItem';
import { RenameConversationDialog } from '../components/dialogs/RenameConversationDialog';
import { ModelSelectorSheet } from '../components/dialogs/ModelSelectorDialog';
import { AbortController, createAbortController } from '../interfaces/AbortController';
import { SearchToolService } from '../services/search/SearchToolService';
import { SearchConfigManager } from '../services/search/SearchConfigManager';
import { cloneChatMessage, getFriendlyErrorMessage, containsSuspiciousContent, shouldGenerateTitle } from '../viewmodels/ChatUtils';
import { ChatSidebar, ChatSidebarConfig } from '../components/chat/ChatSidebar';
import { MessageList, MessageListConfig } from '../components/chat/MessageList';
import { throttle, debounce } from '../common/NetworkUtils';
import { ChatViewModel } from '../viewmodels/ChatViewModel';

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
  private static readonly ANIMATION_DURATION = 300;
  
  // ViewModel 实例
  private viewModel: ChatViewModel = new ChatViewModel();
  
  // 状态管理
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('keyboardHeight') keyboardHeight: number = 0;
  @StorageProp('settingsVersion') settingsVersion: number = 0;
  @StorageLink('conversationsReloadVersion') conversationsReloadVersion: number = 0;
  @StorageLink('currentBreakPoint') currentBreakPoint: string = 'sm';
  // UI 状态
  @State showControlButton: boolean = true;
  @State showSideBar: boolean = false;
  @State showModelSelectorSheet: boolean = false;
  // 数据状态
  @State messages: ChatMessage[] = [];
  @State
  @Watch('updateGroupedConversations')
  conversations: Conversation[] = [];
  @State currentConversation: Conversation | null = null;
  @State inputText: string = '';
  // 缓存已分组的对话数据，避免重复计算
  @State private cachedGroupedConversations: Record<string, Conversation[]> = {};
  @State private cachedGroupedKeys: string[] = [];
  // 逻辑时间戳：确保消息顺序正确，即使系统时间不准确
  private logicalTimestamp: number = Date.now();
  // 应用状态
  @State isLoading: boolean = false;
  @State isGenerating: boolean = false; // 跟踪是否正在生成内容
  @State isInitialized: boolean = false;
  @State hasSettings: boolean = false;
  @State enableWebSearch: boolean = false; // 联网搜索开关（统一控制）
  private ctrlFlag: boolean = false; // Ctrl键状态，用于Ctrl+Enter换行
  // 滚动按钮相关状态
  @State showScrollToBottomButton: boolean = false; // 是否显示"滚动到底部"按钮
  @State shouldAutoScroll: boolean = true; // 是否自动跟随滚动到底部
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

  // 防抖/节流优化包装函数
  private throttledScrollToBottom: () => void = throttle(() => this.doScrollToBottom(), 100);
  private debouncedUpdateBreakpoint: () => void = debounce(() => this.doUpdateBreakpoint(), 200);

  private notifyMessagesUpdated(): void {
    // 更新数据源引用与刷新（数组引用经常被替换）
    this.messageDataSource.setDataRef(this.messages);
  }

  /**
   * 生成递增的逻辑时间戳，确保消息顺序正确
   * 即使系统时间不准确或时间戳相同，也能保证消息按照发送顺序排列
   */
  private getNextTimestamp(): number {
    const now = Date.now();
    // 如果当前时间大于逻辑时间戳，更新逻辑时间戳
    if (now > this.logicalTimestamp) {
      this.logicalTimestamp = now;
    } else {
      // 否则，递增逻辑时间戳（每次增加1毫秒）
      this.logicalTimestamp += 1;
    }
    return this.logicalTimestamp;
  }

  private replaceMessageAt(index: number, updater: (message: ChatMessage) => void): void {
    const target = this.messages[index];
    if (!target) {
      return;
    }

    const cloned = cloneChatMessage(target);
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

  build() {
    NavDestination() {
      SideBarContainer(SideBarContainerType.AUTO) {
        // 使用独立的 ChatSidebar 组件
        ChatSidebar({
          conversations: this.conversations,
          currentConversation: this.currentConversation,
          groupedConversations: this.cachedGroupedConversations,
          groupedKeys: this.cachedGroupedKeys,
          showSideBar: this.showSideBar,
          showControlButton: this.showControlButton,
          config: {
            topRectHeight: this.topRectHeight,
            bottomRectHeight: this.bottomRectHeight
          } as ChatSidebarConfig,
          onCreateConversation: (): void => { this.createNewConversation(); },
          onSelectConversation: (conversation: Conversation): void => { this.selectConversation(conversation); },
          onRenameConversation: (conversation: Conversation): void => { this.showRenameDialog(conversation); },
          onDeleteConversation: (conversation: Conversation): void => { this.deleteConversation(conversation); },
          onOpenSettings: (): void => {
            this.pathStack.pushPathByName("Settings", null);
            this.hideKeyboard();
          },
          onHideSidebar: (): void => { this.hideSidebar(); }
        })

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
                .backgroundColor(Color.Transparent)
                .size({ width: 40, height: 40 })
                .visibility(this.showControlButton ? Visibility.Visible : Visibility.Hidden)
                .onClick(() => {
                  this.showControlButton = !this.showControlButton
                  this.getUIContext().animateTo({
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
                .backgroundColor(Color.Transparent)
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
                .backgroundColor(Color.Transparent)
                .bindMenu([
                  {
                    value: '切换模型',
                    icon: $r('app.media.reverse_order'),
                    action: () => {
                      this.switchModel();
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
                // 消息列表 - 使用独立的 MessageList 组件
                MessageList({
                  messageDataSource: this.messageDataSource,
                  messages: this.messages,
                  showScrollToBottomButton: this.showScrollToBottomButton,
                  shouldAutoScroll: this.shouldAutoScroll,
                  scroller: this.scroller,
                  config: {
                    hasSettings: this.hasSettings,
                    isInitialized: this.isInitialized
                  } as MessageListConfig,
                  onCopyMessage: (msg: ChatMessage): Promise<void> => this.copyMessage(msg),
                  onEditMessage: (msg: ChatMessage): void => { this.editMessage(msg); },
                  onDeleteMessage: (msg: ChatMessage): Promise<void> => this.deleteMessage(msg),
                  onRegenerateMessage: (msg: ChatMessage): Promise<void> => this.regenerateMessage(msg),
                  onHideKeyboard: (): void => { this.hideKeyboard(); },
                  onOpenModelSettings: (): void => {
                    this.pathStack.pushPathByName("ModelSettings", null);
                    this.hideKeyboard();
                  }
                })
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
                  // 联网搜索开关 - 统一控制，始终显示
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
                .margin({ bottom: 12 })
                .justifyContent(FlexAlign.SpaceBetween) // 关键属性：两端对齐
                .width('100%') // 必须设置宽度为 100% 才能生效
              }
              .backgroundColor($r('app.color.input_area_color'))
              .borderColor($r('app.color.text_secondary'))
              .borderRadius({ topLeft: 20, topRight: 20 })
              .width('100%')
              .padding({
                left: 2,
                right: 2,
                top: 6,
                // 键盘未弹出时添加导航栏高度，键盘弹出时不添加（避免重复避让）
                bottom: 4 + (this.keyboardHeight > 0 ? 0 : this.getUIContext().px2vp(this.bottomRectHeight))
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
                  hilog.debug(DOMAIN, TAG,
                    '[OVERLAY] Rendering overlay - showSideBar=%{public}s, currentBreakPoint=%{public}s',
                    String(this.showSideBar), String(this.currentBreakPoint));
                })
                .gesture(
                  PanGesture({
                    direction: PanDirection.Horizontal,
                    fingers: 1,
                    distance: 5 // 增加最小滑动距离，避免误触
                  })
                    .onActionStart(() => {
                      
                    })
                    .onActionUpdate((event: PanUpdateEvent) => {
                      hilog.debug(DOMAIN, TAG, '[GESTURE] Pan gesture - offsetX=%{public}s',
                        String(event.offsetX));
                      // 向左滑超过阈值，关闭侧栏
                      const closeThreshold = -30; // 增加阈值，减少误触
                      if (event.offsetX < closeThreshold) {
                        
                        this.getUIContext().animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
                          this.showSideBar = false;
                          this.showControlButton = true;
                        })
                      }
                    })
                    .onActionEnd(() => {
                      
                    })
                )
                .onClick(() => {
                  
                  if (this.showSideBar && (this.currentBreakPoint === 'sm' || this.currentBreakPoint === 'xs')) {
                    this.getUIContext().animateTo({
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
              this.getUIContext().animateTo({ duration: 250 }, () => {
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
    .width('100%')
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
      
    }
  }

  async aboutToAppear() {
    await this.initializeApp();
    this.previousSettingsVersion = this.normalizeSettingsVersion(this.settingsVersion);
    this.requestedSettingsVersion = this.previousSettingsVersion;
    this.handledReloadVersion = this.conversationsReloadVersion ?? 0;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE) // 设置键盘避让模式

    // 同步状态到 ViewModel
    this.syncStateToViewModel();

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
      
    }
  }

  async onPageShow() {
    const latestVersion = this.conversationsReloadVersion ?? 0;

    // 页面显示时，若检测到刷新版本变化，则强制重新加载对话/消息
    if (latestVersion !== this.handledReloadVersion) {
      hilog.info(DOMAIN, TAG,
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
      hilog.debug(DOMAIN, TAG, 'Chat: onPageShow triggered, reloading chat state due to settings version.');
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

      // 清理历史中的tool消息（修复消息顺序问题）
      try {
        const cleanedCount = await this.databaseManager.cleanupToolMessages();
        if (cleanedCount > 0) {
          
        }
      } catch (cleanupError) {
        hilog.warn(DOMAIN, TAG, 'Failed to cleanup tool messages: %{public}s', String(cleanupError));
        // 不阻塞应用启动，忽略清理失败
      }

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
        AppStorage.setOrCreate('conversationsReloadVersion', 0);
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
      
      this.showToast('应用初始化失败');
    }
  }

  /**
   * 同步页面状态到 ViewModel
   * 用于保持 MVVM 架构中 View 和 ViewModel 的状态一致性
   */
  private syncStateToViewModel(): void {
    this.viewModel.setCurrentSettings(this.currentSettings);
    this.viewModel.setCurrentConversation(this.currentConversation);
    this.viewModel.setMessages(this.messages);
  }
  // 加载设置 - 委托给 ViewModel
  async loadSettings(): Promise<void> {
    try {
      await this.viewModel.loadSettings();
      const settings = this.viewModel.currentSettings;
      this.currentSettings = settings;

      if (!settings) {
        this.hasSettings = false;
        hilog.info(DOMAIN, TAG, 'No settings configured yet.');
        return;
      }

      hilog.info(DOMAIN, TAG, 'Loaded settings with provider count: %{public}s', String(settings.providers.length));

      const activeProvider = settings.providers.find((provider) => provider.id === settings.activeProviderId);
      if (!activeProvider) {
        hilog.warn(DOMAIN, TAG, 'Active provider not found in settings, marking configuration as incomplete.');
        this.hasSettings = false;
        return;
      }

      const activeModel = activeProvider.models.find((model) => model.id === settings.activeModelId);
      if (!activeModel) {
        hilog.warn(DOMAIN, TAG, 'Active model not found for current provider, marking configuration as incomplete.');
        this.hasSettings = false;
        return;
      }

      const providerConfigured = activeProvider.apiUrl.trim().length > 0 && activeProvider.apiKey.trim().length > 0;
      this.hasSettings = providerConfigured && activeModel.name.trim().length > 0;

      if (this.hasSettings) {
        this.enableWebSearch = !!settings.enableWebSearch;
        hilog.info(DOMAIN, TAG, 'Active provider resolved: %{public}s / %{public}s',
          String(activeProvider.displayName), String(activeModel.name));
      }
      
      this.syncStateToViewModel();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Load settings failed: %{public}s', String(error));
      this.hasSettings = false;
    }
  }

  private async reloadChatState(reason: string = 'manual', targetVersion?: number): Promise<void> {
    const desiredVersion = targetVersion ?? this.normalizeSettingsVersion(this.settingsVersion);
    this.requestedSettingsVersion = desiredVersion;

    if (!this.pendingSettingsReload) {
      this.pendingSettingsReload = this.performSettingsReload(reason);
    } else {
      hilog.warn(DOMAIN, TAG,
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
        hilog.info(DOMAIN, TAG,
          'Chat: reloadChatState start [reason=%{public}s] attempt=%{public}d targetVersion=%{public}d',
          String(initialReason), attempt, targetVersion);
        await this.loadSettings();
        await this.loadConversations();

        if (this.conversations.length === 0) {
          // 修复：如果没有对话，创建一个空对话，确保 currentConversation 不为空
          hilog.info(DOMAIN, TAG, 'No conversations after reload, creating empty conversation');
          try {
            const emptyConversation = await this.databaseManager.createConversation('新对话');
            this.currentConversation = emptyConversation;
            this.conversations.push(emptyConversation);
            this.messages = [];
            this.notifyMessagesUpdated();
          } catch (createError) {
            hilog.error(DOMAIN, TAG, 'Failed to create conversation during reload: %{public}s', String(createError));
            this.currentConversation = null;
            this.messages = [];
            this.notifyMessagesUpdated();
          }
        } else {
          await this.loadChatHistory();
        }

        this.previousSettingsVersion = targetVersion;
        this.logSettingsVersionState('Chat: reloadChatState completed');

        if (this.requestedSettingsVersion === targetVersion) {
          break;
        }

        hilog.debug(DOMAIN, TAG,
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

    hilog.info(DOMAIN, TAG, 'Chat: detected settingsVersion change -> %{public}s', String(currentVersion));
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
    hilog.debug(DOMAIN, TAG, '%{public}s; currentVersion=%{public}d, previousVersion=%{public}d', String(prefix),
      current, this.previousSettingsVersion);
  }

  private async waitForLatestSettings(reason: string): Promise<void> {
    if (this.pendingSettingsReload) {
      hilog.debug(DOMAIN, TAG, 'Chat: awaiting pending settings reload before %{public}s', String(reason));
      await this.pendingSettingsReload;
    }

    const currentVersion = this.normalizeSettingsVersion(this.settingsVersion);
    if (currentVersion !== this.previousSettingsVersion) {
      hilog.info(DOMAIN, TAG,
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

      // 同步逻辑时间戳：从已加载的消息中找出最大时间戳
      if (this.messages.length > 0) {
        let maxTimestamp = 0;
        for (let i = 0; i < this.messages.length; i++) {
          if (this.messages[i].timestamp > maxTimestamp) {
            maxTimestamp = this.messages[i].timestamp;
          }
        }
        this.logicalTimestamp = maxTimestamp;
      }

      // 重置自动滚动状态并滚动到底部
      this.shouldAutoScroll = true;
      this.showScrollToBottomButton = false;

      // 滚动到底部
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);
    } catch (error) {
      
      this.showToast('加载聊天记录失败');
    }
  }

  // 加载对话列表 - 委托给 ViewModel
  async loadConversations(): Promise<void> {
    try {
      await this.viewModel.loadConversations();
      this.conversations = this.viewModel.conversations;
      this.updateGroupedConversations();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Load conversations failed: %{public}s', String(error));
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
        hilog.info(DOMAIN, TAG, 'Restored last conversation: %{public}s %{public}s',
          String(this.currentConversation.id), String(this.currentConversation.title));
      } else {
        // 修复：如果没有对话，创建一个空对话，而不是设置为 null
        // 这样用户第一次发送消息时就有一个现成的 conversationId
        hilog.info(DOMAIN, TAG, 'No conversations found, creating empty conversation for initial state');
        const emptyConversation = await this.databaseManager.createConversation('新对话');
        this.currentConversation = emptyConversation;
        this.conversations.push(emptyConversation);
        hilog.info(DOMAIN, TAG, 'Created empty conversation: %{public}s %{public}s',
          String(emptyConversation.id), String(emptyConversation.title));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to restore last conversation: %{public}s', String(error));
      this.currentConversation = null;
    }
  }

  hideSidebar() {
    // 关闭侧边栏时隐藏键盘
    this.hideKeyboard();
  }

  // 创建新对话 - 委托给 ViewModel
  async createNewConversation(): Promise<void> {
    this.hideKeyboard();
    
    if (this.isLoading) {
      this.showToast('请等待当前消息发送完成');
      return;
    }

    try {
      // 检查是否存在空对话
      const emptyConversation = await this.viewModel.findEmptyConversation();
      if (emptyConversation) {
        this.showToast('已有空对话，已为您切换');
        await this.selectConversation(emptyConversation);
        return;
      }

      // 委托给 ViewModel 创建
      const newConversation = await this.viewModel.createNewConversation();
      
      // 同步状态
      this.currentConversation = this.viewModel.currentConversation;
      this.conversations = this.viewModel.conversations;
      this.messages = this.viewModel.messages;
      this.notifyMessagesUpdated();
      this.updateGroupedConversations();

      this.hideSidebar();
      this.showToast('已创建新对话');
      this.isLoading = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to create new conversation: %{public}s', String(error));
      this.showToast('创建对话失败');
      this.isLoading = false;
    }
  }

  // 选择对话 - 委托给 ViewModel
  async selectConversation(conversation: Conversation): Promise<void> {
    this.hideKeyboard();
    
    if (this.isLoading) {
      this.showToast('请等待当前消息发送完成');
      return;
    }

    try {
      // 委托给 ViewModel
      await this.viewModel.selectConversation(conversation);
      
      // 同步状态
      this.currentConversation = this.viewModel.currentConversation;
      this.messages = this.viewModel.messages;
      this.notifyMessagesUpdated();
      
      // 同步逻辑时间戳
      if (this.messages.length > 0) {
        const maxTimestamp = Math.max(...this.messages.map(m => m.timestamp));
        if (maxTimestamp > this.logicalTimestamp) {
          this.logicalTimestamp = maxTimestamp;
        }
      }
      
      this.hideSidebar();
      this.isLoading = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to select conversation: %{public}s', String(error));
      this.showToast('切换对话失败');
      this.isLoading = false;
    }
  }

  /**
   * 显示删除对话确认弹窗
   */
  showDeleteConversationDialog(conversationId: string, conversationTitle: string) {
    NativeDialogHelper.showDeleteConfirmDialog(
      this.getUIContext(),
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
        
      }
    );
  }

  // 删除对话 - 委托给 ViewModel
  async deleteConversation(conversation: Conversation): Promise<void> {
    try {
      // 委托给 ViewModel
      await this.viewModel.deleteConversation(conversation.id);
      
      // 同步状态
      this.conversations = this.viewModel.conversations;
      this.currentConversation = this.viewModel.currentConversation;
      this.messages = this.viewModel.messages;
      this.notifyMessagesUpdated();
      this.updateGroupedConversations();

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


  // 兼容“快速配置”中使用中文展示名、未设置 activeProviderId、或仅依赖 apiUrl 的场景




  // 分离职责 - 消息验证和初始化
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
    if (containsSuspiciousContent(trimmedInput)) {
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
      conversationId: this.currentConversation?.id || 'default',
      timestamp: this.getNextTimestamp()  // 使用逻辑时间戳确保顺序
    });
  }

  // 分离职责 - 初始化流式消息
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
      providerName: modelInfo.providerName,
      // 关键修复：使用逻辑时间戳确保AI消息严格晚于用户消息
      timestamp: this.getNextTimestamp()
    });

    const index = this.appendMessage(streamingMessage);
    const id = await this.databaseManager.insertChatMessage(streamingMessage);

    this.replaceMessageAt(index, (msg) => {
      msg.id = id;
    });

    const result: StreamingMessageResult = { index: index, id: id };
    return result;
  }

  // 分离职责 - 追加数据块
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

  // 分离职责 - 处理流式完成
  /**
   * 处理流式请求完成，重置UI状态
   */
  private handleStreamComplete(): void {
    this.isLoading = false;
    this.isGenerating = false;
    this.currentAbortController = null;
    this.userAbortedGeneration = false;
  }

  // 分离职责 - 持久化消息
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

      if (!this.userAbortedGeneration && shouldGenerateTitle(this.messages, this.currentConversation?.title ?? '')) {
        await this.generateConversationTitle();
      }

      await this.databaseManager.updateConversationMessageCount(conversationId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Error persisting message: %{public}s', String(error));
    }
  }

  // 控制方法：停止生成与滚动行为，提前声明以便在UI回调中使用
  private stopGeneration(): void {
    if (this.currentAbortController && this.isGenerating) {
      hilog.info(DOMAIN, TAG, 'Stopping AI generation...');
      this.userAbortedGeneration = true;
      try {
        this.currentAbortController.abort();
      } catch (err) {
        // ignore abort errors
      }
      this.showToast('已停止生成，已显示的内容已保留');
    }
  }

  // 节流调用入口：避免频繁滚动
  private scrollToBottom(): void {
    this.throttledScrollToBottom();
  }

  // 实际滚动实现
  private doScrollToBottom(): void {
    if (!this.shouldAutoScroll) {
      hilog.debug(DOMAIN, TAG, 'Auto scroll is disabled, skipping scroll to bottom');
      return;
    }

    if (this.scroller) {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (error) {
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

  // 事件驱动处理 - 设置流式事件处理
  /**
   * 为流式请求设置事件处理（替代回调地狱）
   * @param emitter 事件发射器
   * @param streamingMessageIndex 流式消息索引
   * @param conversationId 对话ID
   * @param isToolContinuation 是否是工具继续阶段（默认 false）
   */
  private setupStreamEventHandlers(
    emitter: StreamEventEmitter,
    streamingMessageIndex: number,
    conversationId: string,
    isToolContinuation: boolean = false
  ): void {
    hilog.info(DOMAIN, TAG,
      'Setting up stream event handlers for message index: %{public}d, isToolContinuation=%{public}s',
      streamingMessageIndex, String(isToolContinuation));

    // 标志：用于跟踪是否已处理工具调用（防止 COMPLETE 事件在工具执行期间重置状态）
    let toolCallHandled = false;

    // 监听数据事件
    emitter.on(StreamEventType.DATA, (payload: EventPayload) => {
      const chunk = payload as string;
      
      this.appendChunkToMessage(streamingMessageIndex, chunk, conversationId);
    });

    // 监听元数据事件
    emitter.on(StreamEventType.METADATA, (payload: EventPayload) => {
      const meta = payload as StreamMetadata;
      
      this.updateStreamingMessageMetadata(streamingMessageIndex, meta, conversationId);
    });

    // 监听完成事件
    emitter.once(StreamEventType.COMPLETE, () => {
      hilog.info(DOMAIN, TAG, 'Received COMPLETE event for message index: %{public}d, toolCallHandled=%{public}s',
        streamingMessageIndex, String(toolCallHandled));

      // 关键修复：只有在没有工具调用时才重置状态
      // 如果有工具调用，让 continueConversationWithToolResult 中的流来处理完成
      if (!toolCallHandled) {
        this.handleStreamComplete();
      }

      // 异步持久化，不阻塞UI状态更新
      if (!toolCallHandled) {
        this.persistStreamedMessage(streamingMessageIndex, conversationId)
          .catch((err: Error) => {
            
          });
      }
    });

    // 监听错误事件
    emitter.on(StreamEventType.ERROR, (payload: EventPayload) => {
      const error = payload as Error;
      hilog.error(DOMAIN, TAG, 'Received ERROR event: %{public}s', String(error));
      // 在工具继续阶段的错误会有不同的处理
      this.handleStreamError(streamingMessageIndex, error, isToolContinuation);
    });

    // 监听警告事件（可选）
    emitter.on(StreamEventType.WARNING, (payload: EventPayload) => {
      const warning = payload as string;
      
    });

    // 监听工具调用事件
    emitter.once(StreamEventType.TOOL_CALL, (payload: EventPayload) => {
      const toolCalls = payload as import('../services/StreamEventEmitter').ToolCallData[];
      

      // 标记已处理工具调用，这样之后的 COMPLETE 事件就不会重置状态
      toolCallHandled = true;

      this.handleToolCalls(toolCalls, streamingMessageIndex, conversationId)
        .catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to handle tool calls: %{public}s', String(err));
          // 工具调用错误不应该通过 handleStreamError 处理，因为已经在 handleToolCalls 中处理过了
          // this.handleStreamError(streamingMessageIndex, err);
        });
    });

    
  }

  // 事件驱动处理 - 设置重新生成事件处理
  /**
   * 为重新生成流式请求设置事件处理
   * @param emitter 事件发射器
   * @param streamingMessageIndex 重新生成消息的索引
   * @param conversationId 对话ID
   */
  private setupRegenerationStreamEventHandlers(
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

      hilog.debug(DOMAIN, TAG, 'Regenerated content length=%{public}d',
        this.messages[streamingMessageIndex].content.length);
    });

    // 监听元数据事件 - 复用统一的元数据更新方法
    emitter.on(StreamEventType.METADATA, (payload: EventPayload) => {
      const meta = payload as StreamMetadata;
      this.updateStreamingMessageMetadata(streamingMessageIndex, meta, conversationId);
    });

    // 监听完成事件 - 处理重新生成完成
    emitter.once(StreamEventType.COMPLETE, () => {
      

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
                hilog.info(DOMAIN, TAG, 'Regenerated message updated in DB ID=%{public}s',
                  String(regeneratedMessage.id));
              } else {
                // 兜底方案：如果没有ID，保存到数据库
                const savedId = await this.databaseManager.insertChatMessage(regeneratedMessage);
                this.replaceMessageAt(streamingMessageIndex, (messageToPersist: ChatMessage) => {
                  messageToPersist.id = savedId;
                });
                
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

  // 分离职责 - 处理流式错误
  /**
   * 处理流式请求错误
   * @param messageIndex 消息索引
   * @param error 错误对象
   * @param isToolContinuation 是否是工具继续阶段的错误（默认 false）
   */
  private handleStreamError(messageIndex: number, error: Error, isToolContinuation: boolean = false): void {
    const friendlyError = getFriendlyErrorMessage(error);

    // 如果是用户主动中止，保留已显示的内容；否则显示错误提示
    if (!this.userAbortedGeneration && messageIndex < this.messages.length) {
      this.replaceMessageAt(messageIndex, (msg) => {
        // 如果消息为空，显示错误提示；如果已有内容，追加错误说明
        if (msg.content.length === 0) {
          msg.content = `[错误] ${friendlyError}`;
        } else {
          // 根据是否是工具继续阶段来显示不同的错误前缀
          const errorPrefix = isToolContinuation ? '继续生成失败' : '生成过程中出现错误';
          msg.content += `\n\n[错误] ${errorPrefix}: ${friendlyError}`;
        }
      });
    }

    this.isLoading = false;
    this.isGenerating = false;
    this.currentAbortController = null;
    this.userAbortedGeneration = false;
    this.showToast(friendlyError);
  }

  // 分离职责 - 更新元数据
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
            
          });
      }
    }
  }

  // 简化的主函数 - 仅负责流程控制
  async sendMessage() {
    try {
      // 验证和准备消息
      const userMessage = this.validateAndPrepareMessage(this.inputText);
      if (!userMessage) {
        return;
      }

      // 前置检查和准备
      await this.waitForLatestSettings('sendMessage');
      this.hideKeyboard();
      // 发送消息时重置自动滚动状态
      this.shouldAutoScroll = true;
      this.showScrollToBottomButton = false;
      this.scrollToBottom();

      // 确保对话存在
      if (!this.currentConversation) {
        await this.createNewConversationForMessage();
      }

      if (!this.currentConversation || !this.currentConversation.id) {
        this.showToast('对话状态异常，请重新创建对话');
        return;
      }

      const targetConversationId = this.currentConversation.id;

      // 准备状态和消息
      this.isLoading = true;
      this.isGenerating = true;
      this.currentAbortController = createAbortController();
      this.inputText = '';

      // 保存用户消息
      const userMessageIndex = this.appendMessage(userMessage);
      const userMessageId = await this.databaseManager.insertChatMessage(userMessage);
      this.replaceMessageAt(userMessageIndex, (msg) => {
        msg.id = userMessageId;
      });

      // 初始化流式消息
      const streamingResult: StreamingMessageResult =
        await this.initializeStreamingMessage(userMessage, targetConversationId);
      const streamingIndex: number = streamingResult.index;

      // 准备AI消息列表
      const messagesForAI = this.prepareMessagesForAPI(userMessage);

      // 检查是否启用联网搜索并构建工具数组
      const tools = this.getSearchTools();

      // 发送流式请求（使用新的事件驱动架构）
      const emitter = await this.networkManager.sendStreamChatRequestV2(
        this.currentSettings!.apiUrl,
        this.currentSettings!.apiKey,
        this.currentSettings!.modelName,
        messagesForAI,
        {
          tools: tools.length > 0 ? tools : undefined,
          abortController: this.currentAbortController,
          requestTimeout: 60000
        }
      );

      // 设置事件处理（替代回调地狱）
      this.setupStreamEventHandlers(emitter, streamingIndex, targetConversationId);

    } catch (error) {
      this.isLoading = false;
      this.isGenerating = false;
      this.currentAbortController = null;
      const friendlyError = getFriendlyErrorMessage(error instanceof Error ? error : new Error(String(error)));
      this.showToast(friendlyError);
    }
  }

  // 辅助方法 - 创建新对话
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

  /**
   * 获取联网搜索工具定义数组
   * 统一提取，避免在 sendMessage / continueConversation / regenerateMessage 中重复
   */
  private getSearchTools(): object[] {
    if (!this.enableWebSearch) {
      return [];
    }
    try {
      const searchConfig = this.searchConfigManager.getConfig();
      if (searchConfig && searchConfig.enabledServices.length > 0) {
        const selectedService = this.searchConfigManager.getSelectedService();
        if (selectedService) {
          const toolDef = this.searchToolService.getToolDefinition();
          hilog.info(DOMAIN, TAG, 'Web search enabled with service: %{public}s', selectedService.type);
          return [toolDef as object];
        }
      }
    } catch (configError) {
      hilog.warn(DOMAIN, TAG, 'Search config error: %{public}s', String(configError));
    }
    return [];
  }

  // 辅助方法 - 准备API消息列表
  private prepareMessagesForAPI(userMessage: ChatMessage): ChatMessage[] {
    const endIndex = this.messages.length - 1;
    const startIndex = Math.max(0, endIndex - 10);
    const messagesForAI = this.messages.slice(startIndex, endIndex);
    if (messagesForAI.length === 0) {
      messagesForAI.push(cloneChatMessage(userMessage));
    }
    return messagesForAI;
  }

  // 工具调用处理 - 执行搜索并继续对话
  private async handleToolCalls(
    toolCalls: import('../services/StreamEventEmitter').ToolCallData[],
    assistantMessageIndex: number,
    conversationId: string
  ): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Handling %{public}d tool calls', toolCalls.length);

    // 关键修复：将工具调用信息保存到 assistant 消息中
    if (assistantMessageIndex < this.messages.length) {
      // 转换为 ToolCall 格式
      const formattedToolCalls: import('../services/DataModels').ToolCall[] =
        toolCalls.map((tc): import('../services/DataModels').ToolCall => {
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

    // 重要修复：不在此处调用 handleStreamComplete()
    // 原因：工具调用完成后还需继续生成模型回答，不应该重置 isGenerating 状态
    // handleStreamComplete() 应该在最终流完成时由 setupStreamEventHandlers 中的 COMPLETE 事件处理器调用
    // this.handleStreamComplete();

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


          // 执行搜索
          const searchResult = await this.searchToolService.executeSearch(query, args.resultSize);

          

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

          await this.continueConversationWithToolResult(conversationId, assistantMessageIndex, searchResult,
            toolCall.id, toolCall.name);

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

          // 关键修复：只在消息为空时才设置错误，否则追加
          // 这样可以保留已有的内容并追加错误说明
          if (assistantMessageIndex < this.messages.length) {
            this.replaceMessageAt(assistantMessageIndex, (msg) => {
              if (msg.content.length === 0) {
                // 消息为空，设置错误信息
                msg.content = `[搜索失败] ${errorMessage}\n\n请检查搜索配置或稍后重试。`;
              } else {
                // 消息不为空，追加错误信息而不是替换
                msg.content += `\n\n[搜索失败] ${errorMessage}\n请检查搜索配置或稍后重试。`;
              }
            });
          }

          // 错误处理：如果搜索失败，不继续生成，而是重置状态
          // 这样可以避免继续对话时出现"生成过程中出现错误"
          this.isLoading = false;
          this.isGenerating = false;
          this.currentAbortController = null;

          // 不抛出错误，允许继续处理其他工具调用
          continue;
        }
      }
    }
  }

  // 继续对话 - 在工具执行后
  private async continueConversationWithToolResult(
    conversationId: string,
    assistantMessageIndex: number,
    searchResult?: import('../services/search/SearchModels').SearchResult,
    toolCallId?: string,
    toolName?: string
  ): Promise<void> {
    if (!this.currentConversation || this.currentConversation.id !== conversationId) {
      
      return;
    }

    // 关键修复：保持 isGenerating = true，因为工具执行后还要继续生成模型回答
    // 不要在此处重置状态，应该让 setupStreamEventHandlers 中的事件处理器来管理
    // 这样可以确保按钮在整个过程中保持正确的状态

    // 保持 isLoading = true 和 isGenerating = true，确保按钮显示"停止"而不是"发送"
    this.isLoading = true;
    // isGenerating 应该已经为 true（来自 handleToolCalls 调用前的状态）
    this.currentAbortController = createAbortController();

    hilog.info(DOMAIN, TAG,
      'Starting continueConversationWithToolResult, isLoading=%{public}s, isGenerating=%{public}s',
      String(this.isLoading), String(this.isGenerating));

    try {
      // 构建工具结果消息 - 这是API格式所需的标准tool_result
      let toolContent = '';
      // 检查是否有搜索结果，构建工具内容
      if (searchResult) {
        // 构建搜索结果文本供API使用
        if (searchResult.answer) {
          toolContent = `搜索摘要: ${searchResult.answer}\n\n`;
        }
        toolContent += '详细搜索结果:\n';
        for (const item of searchResult.items) {
          toolContent += `[${item.index || 0}] 标题: ${item.title}\n内容: ${item.text}\nURL: ${item.url}\n\n`;
        }
      }

      // 验证 toolCallId 是否存在
      if (!toolCallId) {
        hilog.error(DOMAIN, TAG, 'Tool call ID is missing, cannot create tool message');
        throw new Error('工具调用ID缺失，无法继续对话');
      }

      // 添加工具结果消息到对话历史（仅内存，不持久化）
      const toolResultMessage = new ChatMessage(
        toolContent,
        'tool',
        { conversationId: conversationId, timestamp: this.getNextTimestamp(), toolCallId: toolCallId }
      );

      // 为内存中的消息分配一个临时ID（不从数据库获取）
      toolResultMessage.id = -toolContent.length - Math.floor(Math.random() * 10000);

      // 获取当前的 Assistant 消息
      const previousAssistantMsg = this.messages[assistantMessageIndex];
      
      // 准备 API 请求所需的上下文
      const contextMessages = this.messages.slice(0, assistantMessageIndex + 1);
      contextMessages.push(toolResultMessage);
      
      // 重用旧消息的 ID 和模型信息，清空内容用于接收新响应
      // 这样避免创建重复的数据库记录
      const modelInfo = this.getCurrentModelInfo();
      this.replaceMessageAt(assistantMessageIndex, (msg) => {
        // 保留原有的 ID（已在数据库中），清空内容以接收新流式数据
        msg.content = '';
        // 更新模型信息以反映当前使用的模型
        msg.modelName = modelInfo.modelName;
        msg.providerName = modelInfo.providerName;
        msg.timestamp = this.getNextTimestamp();
        // 保留工具调用信息
        msg.toolCalls = previousAssistantMsg.toolCalls ? [...previousAssistantMsg.toolCalls] : [];
      });
      
      // 更新当前流式更新的目标索引
      const streamingIndex = assistantMessageIndex;

      // 构建 API 请求消息列表
      const messagesForAI = contextMessages.slice(Math.max(0, contextMessages.length - 20));

      hilog.info(DOMAIN, TAG, 'Continuing conversation with merged UI bubble. Context length: %{public}d', messagesForAI.length);

      // 打印消息序列以便调试
      for (let i = 0; i < messagesForAI.length; i++) {
        const msg = messagesForAI[i];
        hilog.info(DOMAIN, TAG,
          'Message[%{public}d]: role=%{public}s, hasToolCallId=%{public}s, hasToolCalls=%{public}s, contentLength=%{public}d',
          i, msg.role, String(!!msg.toolCallId), String(!!(msg.toolCalls && msg.toolCalls.length > 0)),
          msg.content.length);
      }

      // 检查搜索配置并构建工具数组
      const tools = this.getSearchTools();
      
      // 发送流式请求
      hilog.info(DOMAIN, TAG, 'Request params: apiUrl=%{public}s, model=%{public}s, messageCount=%{public}d',
        this.currentSettings!.apiUrl.substring(0, 30), this.currentSettings!.modelName, messagesForAI.length);

      const emitter = await this.networkManager.sendStreamChatRequestV2(
        this.currentSettings!.apiUrl,
        this.currentSettings!.apiKey,
        this.currentSettings!.modelName,
        messagesForAI,
        {
          tools: tools.length > 0 ? tools : undefined,
          abortController: this.currentAbortController,
          requestTimeout: 60000
        }
      );

      // 设置事件处理器来接收流式响应
      this.setupStreamEventHandlers(emitter, streamingIndex, conversationId, true);

      // 设置超时保护
      const timeoutId = setTimeout(() => {
        if (this.isLoading || this.isGenerating) {
          hilog.error(DOMAIN, TAG, 'Stream timeout after 60s, forcing state reset');
          this.isLoading = false;
          this.isGenerating = false;
          this.currentAbortController = null;
          this.showToast('请求超时，请重试');

          if (streamingIndex < this.messages.length) {
            this.replaceMessageAt(streamingIndex, (msg) => {
              if (!msg.content || msg.content.length === 0) {
                msg.content = '[超时] 未收到响应，请检查网络或重试';
              } else {
                msg.content += '\n\n[超时] 响应中断';
              }
            });
          }
        }
      }, 60000);
      
      emitter.once(StreamEventType.COMPLETE, () => {
        clearTimeout(timeoutId);
        
        // 工具继续对话完成：重置UI状态并持久化消息
        this.isLoading = false;
        this.isGenerating = false;
        this.currentAbortController = null;
        
        // 异步持久化流式消息到数据库
        this.persistStreamedMessage(streamingIndex, conversationId)
          .catch((err: Error) => {
            hilog.error(DOMAIN, TAG, 'Failed to persist message after tool continuation: %{public}s', String(err));
          });
      });
      emitter.once(StreamEventType.ERROR, () => {
        clearTimeout(timeoutId);
      });

    } catch (error) {
      
      this.isLoading = false;
      this.isGenerating = false;
      this.currentAbortController = null;
      const friendlyError = getFriendlyErrorMessage(error instanceof Error ? error : new Error(String(error)));

      // 关键修复：在消息中追加错误而不是覆盖
      // 如果已经有搜索结果，应该追加错误而不是完全替换
      const streamingIndex = assistantMessageIndex;
      if (streamingIndex < this.messages.length) {
        this.replaceMessageAt(streamingIndex, (msg) => {
          if (msg.content.length === 0) {
            // 如果消息为空，显示错误
            msg.content = `[错误] ${friendlyError}`;
          } else {
            // 如果已有内容，追加错误
            msg.content += `\n\n[错误] 继续生成失败: ${friendlyError}`;
          }
        });
      }

      this.showToast(friendlyError);
    }
  }

  // 辅助方法：去除思维链标签
  private cleanThinkingTags(content: string): string {
    if (!content) return '';
    // 移除 <reasoning_content>...</reasoning_content> 及其内容
    // 使用非贪婪匹配，并处理多行内容
    return content.replace(/<reasoning_content>[\s\S]*?<\/reasoning_content>/g, '').trim();
  }

  // 消息操作方法
  async copyMessage(message: ChatMessage) {
    try {
      const clipboardManager = ClipboardManager.getInstance();
      // 清理思维链标签后再复制，如果清理后为空（只有思考内容），则复制原始内容
      const cleanContent = this.cleanThinkingTags(message.content);
      const textToCopy = cleanContent.length > 0 ? cleanContent : message.content;
      
      const success = await clipboardManager.copyText(textToCopy);

      if (success) {
        this.showToast('已复制到剪贴板');
        
      } else {
        this.showToast('复制失败');
      }
    } catch (error) {
      
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
      hilog.info(DOMAIN, TAG, 'Created regenerated record ID=%{public}s', String(newMessageId));

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

      hilog.info(DOMAIN, TAG, 'Regenerating AI message at index=%{public}d', streamingMessageIndex);

      // 检查是否启用联网搜索并构建工具数组
      const tools = this.getSearchTools();

      // 发送流式请求重新生成（使用新的事件驱动架构）
      const emitter = await this.networkManager.sendStreamChatRequestV2(
        this.currentSettings?.apiUrl || '',
        this.currentSettings?.apiKey || '',
        this.currentSettings?.modelName || '',
        messagesForAI,
        {
          tools: tools.length > 0 ? tools : undefined,
          abortController: this.currentAbortController,
          requestTimeout: 30000
        }
      );

      // 设置重新生成的事件处理
      this.setupRegenerationStreamEventHandlers(emitter, streamingMessageIndex, targetConversationId);

    } catch (error) {
      
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
          hilog.debug(DOMAIN, TAG, 'Keyboard hidden successfully');
        })
        .catch((error: Error) => {
          hilog.debug(DOMAIN, TAG, 'Failed to hide keyboard: %{public}s', String(error));
        });
    } catch (error) {
      hilog.debug(DOMAIN, TAG, 'Error getting input method controller: %{public}s', String(error));
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

  // 重命名对话 - 委托给 ViewModel
  private async renameConversation(conversationId: string, newTitle: string) {
    try {
      await this.viewModel.renameConversation(conversationId, newTitle);
      
      // 同步 ViewModel 状态到页面
      this.currentConversation = this.viewModel.currentConversation;
      this.conversations = this.viewModel.conversations;
      this.updateGroupedConversations();
      
      this.showToast('重命名成功', 2000);
    } catch (error) {
      this.showToast('重命名失败', 2000);
    }
  }

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

  // 防抖调用入口：避免窗口调整时频繁计算
  private updateBreakpoint(): void {
    this.debouncedUpdateBreakpoint();
  }

  // 实际断点计算实现
  private doUpdateBreakpoint(): void {
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

            hilog.debug(DOMAIN, TAG, '[BREAKPOINT] Window width: %{public}dpx, widthVp=%{public}d', width,
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

            hilog.debug(DOMAIN, TAG, '[BREAKPOINT] Calculated breakpoint: %{public}s', String(breakpoint));

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

