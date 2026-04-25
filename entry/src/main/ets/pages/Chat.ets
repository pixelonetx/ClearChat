import { Prompt } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage, AppSettings, AIProvider, AIModel } from '../services/DataModels';
import { ArrayDataSource } from '../utils/ArrayDataSource';
import { Conversation } from '../services/ConversationModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NetworkManagerV2 } from '../services/NetworkManagerV2';
import { ClipboardManager } from '../components/utils/ClipboardManager';
import { BrowserHelper } from '../services/BrowserHelper';
import { NativeDialogHelper } from '../components/dialogs/NativeDialogHelper';
import { RenameConversationDialog } from '../components/dialogs/RenameConversationDialog';
import { ModelSelectorSheet } from '../components/dialogs/ModelSelectorDialog';
import { AbortController, createAbortController } from '../interfaces/AbortController';
import { SearchConfigManager } from '../services/search/SearchConfigManager';
import { cloneChatMessage, getFriendlyErrorMessage, containsSuspiciousContent } from '../viewmodels/ChatUtils';
import { ChatSidebar, ChatSidebarConfig } from '../components/chat/ChatSidebar';
import { MessageList, MessageListConfig } from '../components/chat/MessageList';
import { throttle, debounce } from '../common/NetworkUtils';
import { ChatViewModel } from '../viewmodels/ChatViewModel';
import { ChatStreamingService, StreamingCallbacks, ModelInfo, ApiConfig } from '../services/ChatStreamingService';
import { SettingsReloadService, SettingsReloadCallbacks } from '../services/SettingsReloadService';
import { groupConversationsByDate } from '../services/ConversationGroupHelper';
import { PresetProvider, PRESET_PROVIDERS, inferApiFormat } from '../services/PresetProviders';

const DOMAIN = 0x0000;
const TAG = 'Chat';

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
  // 首次使用引导
  @State showSetupSheet: boolean = false;
  @State private setupSelectedPresetType: string = '';
  @State private setupApiKey: string = '';
  @State private setupIsFetching: boolean = false;
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
  private searchConfigManager = SearchConfigManager.getInstance();
  private scroller: Scroller = new Scroller();
  private currentSettings: AppSettings | null = null;
  private handledReloadVersion: number = 0;
  private messageDataSource: ArrayDataSource<ChatMessage> = new ArrayDataSource<ChatMessage>(this.messages);
  private currentAbortController: AbortController | null = null;
  private userAbortedGeneration: boolean = false;

  // 提取的服务（在 aboutToAppear 的 initServices 中初始化）
  private streamingService: ChatStreamingService | null = null;
  private settingsReloadService: SettingsReloadService | null = null;

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
    .bindSheet(this.showSetupSheet, this.SetupSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      detents: [SheetSize.FIT_CONTENT],
      blurStyle: BlurStyle.Thick,
      showClose: true,
      preferType: SheetType.BOTTOM,
      enableOutsideInteractive: false,
      dragBar: true,
      onDisappear: () => {
        this.showSetupSheet = false;
        this.resetSetupState();
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  private renameDialogController: CustomDialogController = new CustomDialogController({
    builder: RenameConversationDialog({}),
    autoCancel: true,
  });

  private showToast(message: string, duration: number = 2000): void {
    const options = new ToastOptions(message, duration);
    try {
      Prompt.showToast(options);
    } catch (toastError) {
      // ignore
    }
  }

  /**
   * 首次使用引导：确认配置
   */
  private async handleSetupConfirm(): Promise<void> {
    const preset = PRESET_PROVIDERS.find(p => p.type === this.setupSelectedPresetType);
    if (!preset) {
      this.showToast('请选择一个服务商');
      return;
    }
    const apiKey = (this.setupApiKey || '').trim();
    if (!apiKey) {
      this.showToast('请输入 API 密钥');
      return;
    }
    if (apiKey.length < 10) {
      this.showToast('API 密钥似乎过短，请检查');
      return;
    }

    this.setupIsFetching = true;
    try {
      // 1. 创建provider
      const provider = preset.createProvider();
      provider.apiKey = apiKey;
      provider.isActive = true;

      // 2. 尝试拉取模型
      try {
        const models = await this.networkManager.fetchModels(preset.apiUrl, apiKey, preset.apiFormat);
        if (models.length > 0) {
          provider.models = models;
        }
      } catch (fetchError) {
        // 兜底使用预设模型
        hilog.info(DOMAIN, TAG, 'Auto-fetch models failed, using defaults: %{public}s', String(fetchError));
      }

      // 3. 构建设置并保存
      const settings = new AppSettings();
      settings.providers = [provider];
      settings.activeProviderId = provider.id;
      settings.activeModelId = provider.models[0]?.id ?? '';

      if (!this.databaseManager.isInitialized()) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await this.databaseManager.initDatabase(context);
      }
      await this.databaseManager.saveSettings(settings);

      // 4. 通知设置更新
      const version = Date.now();
      if (!AppStorage.set('settingsVersion', version)) {
        AppStorage.setOrCreate('settingsVersion', version);
      }

      // 5. 关闭引导，重新加载
      this.showSetupSheet = false;
      this.resetSetupState();
      this.showToast('配置完成，开始对话吧！');
      await this.initializeApp();
      this.syncStateToViewModel();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save setup config: %{public}s', String(error));
      this.showToast('配置保存失败，请重试');
    } finally {
      this.setupIsFetching = false;
    }
  }

  private getPresetWebsite(): string {
    const preset = PRESET_PROVIDERS.find(p => p.type === this.setupSelectedPresetType);
    return preset?.website ?? '';
  }

  private resetSetupState(): void {
    this.setupSelectedPresetType = '';
    this.setupApiKey = '';
    this.setupIsFetching = false;
  }

  @Builder
  SetupSheetBuilder() {
    Column() {
      Text('欢迎使用 ClearChat')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 4 })

      Text('选择一个服务商并填入 API 密钥，即可开始使用')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 20 })

      // 服务商选择
      Text('选择服务商')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: 8 })

      Grid() {
        ForEach(PRESET_PROVIDERS, (preset: PresetProvider) => {
          GridItem() {
            Column() {
              Text(preset.displayName)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.setupSelectedPresetType === preset.type
                  ? '#4CAF50'
                  : $r('sys.color.ohos_id_color_text_primary'))
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .borderRadius(10)
            .border({
              width: this.setupSelectedPresetType === preset.type ? 2 : 1,
              color: this.setupSelectedPresetType === preset.type
                ? '#4CAF50'
                : $r('sys.color.ohos_id_color_text_secondary')
            })
            .backgroundColor(this.setupSelectedPresetType === preset.type
              ? 'rgba(76, 175, 80, 0.06)'
              : Color.Transparent)
            .onClick(() => {
              this.setupSelectedPresetType = preset.type;
              // 选中后不自动清空已输入的密钥，方便用户切换
            })
          }
        })
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .margin({ bottom: 18 })

      // API 密钥
      Column() {
        Text('API 密钥')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 6 })

        TextInput({ placeholder: '请输入 API 密钥', text: this.setupApiKey })
          .height(44)
          .borderRadius(10)
          .fontSize(15)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.setupApiKey = value;
          })
      }
      .width('100%')
      .margin({ bottom: 10 })

      // 获取 API Key 提示
      if (this.setupSelectedPresetType) {
        Text(`获取密钥: ${this.getPresetWebsite()}`)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
          .decoration({ type: TextDecorationType.Underline })
          .onClick(() => {
            const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
            const site = this.getPresetWebsite();
            if (site) {
              BrowserHelper.openUrl(context, site);
            }
          })
          .margin({ bottom: 16 })
      }

      // 确定按钮
      Button() {
        Row({ space: 6 }) {
          if (this.setupIsFetching) {
            LoadingProgress().width(18).height(18).color(Color.White)
          }
          Text(this.setupIsFetching ? '正在配置...' : '开始使用')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
        }
      }
      .width('100%')
      .height(48)
      .borderRadius(24)
      .backgroundColor('#4CAF50')
      .fontColor(Color.White)
      .enabled(!this.setupIsFetching && !!this.setupSelectedPresetType && (this.setupApiKey || '').trim().length > 0)
      .opacity((!this.setupIsFetching && !!this.setupSelectedPresetType && (this.setupApiKey || '').trim().length > 0) ? 1 : 0.5)
      .onClick(() => {
        this.handleSetupConfirm();
      })

      Blank().height(8)

      // 跳过
      Text('以后再说')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ top: 8, bottom: 8 })
        .onClick(() => {
          this.showSetupSheet = false;
          this.resetSetupState();
        })
    }
    .width('100%')
    .padding(24)
  }

  async aboutToAppear() {
    // 初始化提取的服务
    this.initServices();

    await this.initializeApp();
    this.settingsReloadService!.initialize(this.settingsVersion);
    this.handledReloadVersion = this.conversationsReloadVersion ?? 0;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)

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

  /**
   * 初始化提取的服务，建立回调绑定
   */
  private initServices(): void {
    const streamingCallbacks: StreamingCallbacks = {
      replaceMessageAt: (index: number, updater: (message: ChatMessage) => void): void => {
        this.replaceMessageAt(index, updater);
      },
      appendMessage: (message: ChatMessage): number => {
        return this.appendMessage(message);
      },
      getMessages: (): ChatMessage[] => {
        return this.messages;
      },
      getCurrentConversationId: (): string | undefined => {
        return this.currentConversation?.id;
      },
      getCurrentModelInfo: (): ModelInfo => {
        return this.getCurrentModelInfo();
      },
      getNextTimestamp: (): number => {
        return this.getNextTimestamp();
      },
      showToast: (message: string, duration?: number): void => {
        this.showToast(message, duration);
      },
      scrollToBottom: (): void => {
        this.scrollToBottom();
      },
      setLoadingState: (isLoading: boolean, isGenerating: boolean): void => {
        this.isLoading = isLoading;
        this.isGenerating = isGenerating;
      },
      setAbortController: (controller: AbortController | null): void => {
        this.currentAbortController = controller;
      },
      isUserAborted: (): boolean => {
        return this.userAbortedGeneration;
      },
      setUserAborted: (value: boolean): void => {
        this.userAbortedGeneration = value;
      },
      getApiConfig: (): ApiConfig | null => {
        if (!this.currentSettings) {
          return null;
        }
        const config: ApiConfig = {
          apiUrl: this.currentSettings.apiUrl,
          apiKey: this.currentSettings.apiKey,
          modelName: this.currentSettings.modelName
        };
        return config;
      },
      getCurrentConversationTitle: (): string => {
        return this.currentConversation?.title ?? '';
      },
      onTitleGenerated: async (title: string): Promise<void> => {
        if (this.currentConversation && title !== this.currentConversation.title) {
          await this.databaseManager.updateConversationTitle(this.currentConversation.id, title);
          this.currentConversation.title = title;
          await this.loadConversations();
        }
      }
    };

    this.streamingService = new ChatStreamingService(streamingCallbacks);

    const reloadCallbacks: SettingsReloadCallbacks = {
      loadSettings: async (): Promise<void> => {
        await this.loadSettings();
      },
      loadConversations: async (): Promise<void> => {
        await this.loadConversations();
      },
      loadChatHistory: async (): Promise<void> => {
        if (this.conversations.length > 0) {
          await this.loadChatHistory();
        }
      },
      handleEmptyConversations: async (): Promise<void> => {
        if (this.conversations.length === 0) {
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
        }
      }
    };

    this.settingsReloadService = new SettingsReloadService(reloadCallbacks);
  }

  async onPageShow() {
    const latestVersion = this.conversationsReloadVersion ?? 0;

    if (latestVersion !== this.handledReloadVersion) {
      hilog.info(DOMAIN, TAG,
        'Chat: onPageShow detected conversationsReloadVersion change -> %{public}d (handled=%{public}d)', latestVersion,
        this.handledReloadVersion);
      this.currentConversation = null;
      this.messages = [];
      this.notifyMessagesUpdated();
      this.conversations = [];
      this.handledReloadVersion = latestVersion;
      await this.settingsReloadService!.reload('conversationsReloadVersion');
      return;
    }

    if (this.isInitialized) {
      hilog.debug(DOMAIN, TAG, 'Chat: onPageShow triggered, reloading chat state due to settings version.');
      await this.settingsReloadService!.reload('onPageShow');
    }
  }

  aboutToRender() {
    this.settingsReloadService!.logState('aboutToRender before check', this.settingsVersion);
    this.settingsReloadService!.checkVersionChange(this.settingsVersion, this.isInitialized);
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

      // 首次使用：无配置时弹引导
      if (!this.hasSettings) {
        this.showSetupSheet = true;
      }
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

  /**
   * 等待最新设置加载完成（委托给 SettingsReloadService）
   */
  private async waitForLatestSettings(reason: string): Promise<void> {
    await this.settingsReloadService!.waitForLatest(reason, this.settingsVersion);
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

  // generateConversationTitle -> 已提取到 ChatStreamingService

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

  // initializeStreamingMessage, appendChunkToMessage, handleStreamComplete,
  // persistStreamedMessage -> 已提取到 ChatStreamingService

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

  // setupStreamEventHandlers, setupRegenerationStreamEventHandlers,
  // handleStreamError, updateStreamingMessageMetadata -> 已提取到 ChatStreamingService

  // 主函数 - 仅负责流程控制
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

      // 初始化流式消息（委托给 streamingService）
      const streamingResult = await this.streamingService!.initializeStreamingMessage(userMessage, targetConversationId);
      const streamingIndex = streamingResult.index;

      // 准备AI消息列表（委托给 streamingService）
      const messagesForAI = this.streamingService!.prepareMessagesForAPI(userMessage);

      // 检查搜索工具（委托给 streamingService）
      const tools = this.streamingService!.getSearchTools(this.enableWebSearch);

      // 发送流式请求
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

      // 设置事件处理（委托给 streamingService）
      this.streamingService!.setupStreamEventHandlers(
        emitter, streamingIndex, targetConversationId,
        this.currentConversation?.title ?? ''
      );

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

  // getSearchTools, prepareMessagesForAPI -> 已提取到 ChatStreamingService

  // handleToolCalls, continueConversationWithToolResult -> 已提取到 ChatStreamingService


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

      // 检查搜索工具（委托给 streamingService）
      const tools = this.streamingService!.getSearchTools(this.enableWebSearch);

      // 发送流式请求重新生成
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

      // 设置重新生成的事件处理（委托给 streamingService）
      this.streamingService!.setupRegenerationStreamEventHandlers(emitter, streamingMessageIndex, targetConversationId);

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
   */
  private updateGroupedConversations() {
    this.cachedGroupedConversations = groupConversationsByDate(this.conversations);
    this.cachedGroupedKeys = Object.keys(this.cachedGroupedConversations);
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

