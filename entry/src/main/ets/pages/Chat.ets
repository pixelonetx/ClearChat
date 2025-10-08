import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';

import { ChatMessage, AppSettings, AIProvider, AIModel } from '../services/DataModels';
import { Conversation } from '../services/ConversationModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NetworkManager } from '../services/NetworkManager';
import { TitleGenerationService } from '../services/TitleGenerationService';
import { ClipboardManager } from '../components/ClipboardManager';
import { BrowserHelper } from '../services/BrowserHelper';
import { NativeDialogHelper } from '../components/NativeDialogHelper';
import { MessageItem } from '../components/MessageItem';
import { RenameConversationDialog } from '../components/RenameConversationDialog';
import { ModelSelectorSheet } from '../components/ModelSelectorDialog';
import { Constants } from '../components/Constants';

import inputMethod from '@ohos.inputMethod';

const uiContext: UIContext | undefined = AppStorage.get('uiContext');

// 定义模型信息接口
interface ModelInfo {
  modelName: string;
  providerName: string;
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

class RouterUrlOptions {
  url: string;

  constructor(url: string) {
    this.url = url;
  }
}

// 跳转页面入口函数
@Builder
export function ChatBuilder() {
  Chat();
}


@Entry()
@Component
struct Chat {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;
  @StorageProp('settingsVersion')
  settingsVersion: number = 0;
  @State showControlButton: boolean = true // 显示控制按钮开关
  @State showSideBar: boolean = false // 显示侧边栏开关

  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State isInitialized: boolean = false;
  @State hasSettings: boolean = false;
  @State currentConversation: Conversation | null = null;
  @State isSidebarVisible: boolean = false;
  @State sidebarOffset: number = -300;
  @State backgroundBlurRadius: number = 0; // 控制背景模糊程度
  @State conversations: Conversation[] = [];
  @State showModelSelectorSheet: boolean = false; // 控制半模态弹窗显示
  @State customPopup: boolean = false; // 更多按钮

  private databaseManager = DatabaseManager.getInstance();
  private networkManager = NetworkManager.getInstance();
  private titleGenerationService: TitleGenerationService = new TitleGenerationService();
  private scroller: Scroller = new Scroller();
  private currentSettings: AppSettings | null = null;
  private previousSettingsVersion: number = 0;
  private pendingSettingsReload: Promise<void> | null = null;
  private requestedSettingsVersion: number = 0;

  private cloneChatMessage(message: ChatMessage): ChatMessage {
    const clone = new ChatMessage(message.content, message.role, {
      conversationId: message.conversationId,
      modelName: message.modelName,
      providerName: message.providerName,
      timestamp: message.timestamp,
      providerMessageId: message.providerMessageId,
      providerCreatedAt: message.providerCreatedAt,
      systemFingerprint: message.systemFingerprint
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
  }

  private appendMessage(message: ChatMessage): number {
    this.messages = [...this.messages, message];
    return this.messages.length - 1;
  }

  private removeMessageAt(index: number): void {
    if (index < 0 || index >= this.messages.length) {
      return;
    }
    const nextMessages = [...this.messages];
    nextMessages.splice(index, 1);
    this.messages = nextMessages;
  }

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

    if (normalized.includes('timeout') || rawMessage.includes('超时')) {
      return '请求超时，请稍后重试';
    }

    if (normalized.includes('network') || normalized.includes('connection') || normalized.includes('fetch') || rawMessage.includes('网络')) {
      return '网络连接失败，请检查网络设置';
    }

    if (normalized.includes('unauthorized') || normalized.includes('forbidden') || normalized.includes('invalid api key') || normalized.includes('401') || normalized.includes('403') || rawMessage.includes('授权') || rawMessage.includes('认证')) {
      return 'API密钥无效，请检查设置';
    }

    if (normalized.includes('rate limit') || normalized.includes('too many')) {
      return '请求过于频繁，请稍后再试';
    }

    if (normalized.includes('model') && (normalized.includes('not found') || normalized.includes('does not exist') || normalized.includes('unknown'))) {
      return '模型不可用，请检查模型ID';
    }

    if (normalized.startsWith('http ') || rawMessage.startsWith('HTTP') || /http\s\d+/.test(normalized)) {
      return `服务返回错误：${rawMessage}`;
    }

    if (normalized.includes('ssl') || normalized.includes('certificate')) {
      return 'SSL连接失败，请检查网络或证书配置';
    }

    return `发送失败：${rawMessage}`;
  }


  build() {
    NavDestination() {
      Column() {
        Stack() {
          // 主内容区域
          Column() {
            // 主界面
            Column() {
              // 标题栏
              Row() {
                Button() {
                  Image($r('app.media.close_sidebar'))
                    .size({ width: 24, height: 24 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                }
                .type(ButtonType.Circle)
                .backgroundColor($r('sys.color.button_background_color_transparent'))
                .size({ width: 40, height: 40 })
                .onClick(() => {
                  this.showSidebar();
                })

                Text(this.currentConversation?.title || '聊天助手')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 14, right: 14 })

                Button() {
                  Image($r('app.media.square_and_pencil'))
                    .size({ width: 24, height: 24 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                }
                .type(ButtonType.Circle)
                .size({ width: 40, height: 40 })
                .backgroundColor($r('sys.color.button_background_color_transparent'))
                .onClick(() => {
                  this.createNewConversation();
                })
                .margin({right:8})

                Button() {
                  Image($r('app.media.more_fill'))
                    .size({ width: 24, height: 24 })
                    .fillColor($r('sys.color.ohos_id_color_text_primary'))
                }
                .type(ButtonType.Circle)
                .size({ width: 40, height: 40 })
                .backgroundColor($r('sys.color.button_background_color_transparent'))
                .onClick(() => {
                  this.customPopup = !this.customPopup;
                })
                .bindPopup(this.customPopup, {
                  builder: this.MoreOptionsPopup,
                  // placement: Placement.BottomRight,
                  // maskColor: Color.Transparent,
                  // popupColor: Color.Transparent,
                  enableArrow: true,
                  showInSubWindow: true,
                  onStateChange: (e) => {
                    if (!e.isVisible) {
                      this.customPopup = false;
                    }
                  }
                })
              }
              .margin( {top: this.getUIContext().px2vp(this.topRectHeight)} )
              .width('100%')
              .height(56)
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
                        .borderRadius(24)
                        .padding({ left: 20, right: 20 })
                        .height(48)
                        .margin({ top: 16 })
                        .onClick(() => {
                          this.pathStack.pushPathByName("Settings", null, false);
                          this.hideKeyboard();
                        })
                    }
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                } else {
                  // 消息列表
                  Scroll(this.scroller) {
                    Column() {
                      ForEach(this.messages, (message: ChatMessage, index: number) => {
                        MessageItem({
                          message: message,
                          onCopy: (msg: ChatMessage): Promise<void> => this.copyMessage(msg),
                          onEdit: (msg: ChatMessage): void => { this.editMessage(msg); },
                          onDelete: (msg: ChatMessage): Promise<void> => this.deleteMessage(msg),
                          onRegenerate: (msg: ChatMessage): Promise<void> => this.regenerateMessage(msg)
                        })
                      }, (message: ChatMessage, index: number) => {
                        // 简化的 key 生成策略
                        if (message.id !== undefined) {
                          // 已保存的消息使用 ID + 内容长度
                          return `saved_${message.id}_${message.content.length}`;
                        } else {
                          // 临时消息使用索引 + 角色 + 内容长度 + 时间戳的一部分
                          return `temp_${index}_${message.role}_${message.content.length}_${message.timestamp % 10000}`;
                        }
                      })
                    }
                    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
                    .width('100%')
                    .alignItems(HorizontalAlign.Center)
                    .justifyContent(FlexAlign.Start)
                  }
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

              // 输入区域
              Row() {
                TextArea({ placeholder: '输入你的消息...', text: this.inputText })
                  .layoutWeight(1)
                  .constraintSize({
                    minHeight: 40,
                    maxHeight: 999 // 最大高度
                  })
                  .fontSize(16)
                  .maxLines(5)
                  .borderRadius(20)
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .border({ width: 1 })
                  .onChange((value: string) => {
                    this.inputText = value;
                  })

                Button() {
                  if (this.isLoading) {
                    LoadingProgress()
                      .width(24)
                      .height(24)
                      .color(Color.Red)
                  } else {
                    Image($r('app.media.send_plane_line'))
                      .size({ width: 24, height: 24 })
                      .fillColor($r('sys.color.ohos_id_color_text_primary'))
                  }
                }
                .type(ButtonType.Circle)
                .backgroundColor($r('sys.color.button_background_color_transparent'))
                .size({ width: 40, height: 40 })
                .margin({ left: 12 })
                .enabled(this.inputText.trim() !== '' && !this.isLoading)
                .onClick(() => {
                  this.sendMessage();
                })
              }
              .margin( {bottom: this.getUIContext().px2vp(this.bottomRectHeight)} )
              .width('100%')
              .padding({ left: 12, right: 12, top: 12, bottom: 12 })
              .alignItems(VerticalAlign.Bottom)
            }
            .width('100%')
            .height('100%')
          }
          .width('100%')
          .height('100%')
          .blur(this.backgroundBlurRadius)

          // 侧边栏
          if (this.isSidebarVisible) {
            Row() {
              this.SidebarContent()

              // 右侧透明区域，点击关闭侧边栏
              Column()
                .layoutWeight(1)
                .height('100%')
                .onClick(() => {
                  this.hideSidebar();
                })
            }
            .width('100%')
            .height('100%')
            .translate({ x: this.sidebarOffset })
            .justifyContent(FlexAlign.Start)
          }
        }
        .width('100%')
        .height('100%')
        .onClick(() => {
          // 点击空白区域时隐藏键盘
          this.hideKeyboard();
        })
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
      promptAction.showToast(options);
    } catch (toastError) {
      console.error('Failed to show toast:', toastError);
    }
  }

  async aboutToAppear() {
    await this.initializeApp();
    this.previousSettingsVersion = this.normalizeSettingsVersion(this.settingsVersion);
    this.requestedSettingsVersion = this.previousSettingsVersion;
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE) // 设置键盘避让模式
  }

  async onPageShow() {
    // 页面显示时重新加载设置（从设置页面返回时）
    if (this.isInitialized) {
      console.info('Chat: onPageShow triggered, reloading chat state');
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

      // 加载设置
      await this.loadSettings();

      // 加载对话列表
      await this.loadConversations();

      // 恢复最后使用的对话
      await this.restoreLastConversation();

      // 加载聊天记录
      await this.loadChatHistory();

      this.isInitialized = true;
    } catch (error) {
      console.error('Failed to initialize app:', error);
      this.showToast('应用初始化失败');
    }
  }

  async loadSettings() {
    try {
      const settings = await this.databaseManager.getSettings();
      this.currentSettings = settings;

      if (!settings) {
        this.hasSettings = false;
        console.info('No settings configured yet.');
        return;
      }

      console.info('Loaded settings with provider count:', settings.providers.length);

      const activeProvider = settings.providers.find(provider => provider.id === settings.activeProviderId);
      if (!activeProvider) {
        console.warn('Active provider not found in settings, marking configuration as incomplete.');
        this.hasSettings = false;
        return;
      }

      const activeModel = activeProvider.models.find(model => model.id === settings.activeModelId);
      if (!activeModel) {
        console.warn('Active model not found for current provider, marking configuration as incomplete.');
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

        console.info('Active provider resolved:', {
          providerId: activeProvider.id,
          providerName: activeProvider.displayName,
          modelId: activeModel.id,
          modelName: activeModel.name
        });
      } else {
        console.warn('Configuration exists but required API信息未填写完整。');
      }
    } catch (error) {
      console.error('Failed to load settings:', error);
      this.hasSettings = false;
    }
  }

  private async reloadChatState(reason: string = 'manual', targetVersion?: number): Promise<void> {
    const desiredVersion = targetVersion ?? this.normalizeSettingsVersion(this.settingsVersion);
    this.requestedSettingsVersion = desiredVersion;

    if (!this.pendingSettingsReload) {
      this.pendingSettingsReload = this.performSettingsReload(reason);
    } else {
      console.info(`Chat: settings reload already in progress, updated targetVersion=${this.requestedSettingsVersion}, reason=${reason}`);
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
        console.info(`Chat: reloadChatState start [reason=${initialReason}] attempt=${attempt} targetVersion=${targetVersion}`);
        await this.loadSettings();
        await this.loadConversations();

        if (this.conversations.length === 0) {
          this.currentConversation = null;
          this.messages = [];
        } else {
          await this.loadChatHistory();
        }

        this.previousSettingsVersion = targetVersion;
        this.logSettingsVersionState('Chat: reloadChatState completed');

        if (this.requestedSettingsVersion === targetVersion) {
          break;
        }

        console.info('Chat: detected newer settings reload request during execution, repeating with latest targetVersion');
      }
    } catch (error) {
      console.error('Chat: reloadChatState failed:', error);
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

    console.info('Chat: detected settingsVersion change ->', currentVersion);
    this.reloadChatState('settingsVersion change', currentVersion).catch((error: Error) => {
      console.error('Failed to refresh chat after settings change:', error);
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
    console.info(`${prefix}; currentVersion=${current}, previousVersion=${this.previousSettingsVersion}`);
  }

  private async waitForLatestSettings(reason: string): Promise<void> {
    if (this.pendingSettingsReload) {
      console.info(`Chat: awaiting pending settings reload before ${reason}`);
      await this.pendingSettingsReload;
    }

    const currentVersion = this.normalizeSettingsVersion(this.settingsVersion);
    if (currentVersion !== this.previousSettingsVersion) {
      console.info(`Chat: settings version mismatch detected during ${reason}, triggering reload to ${currentVersion}`);
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

      // 滚动到底部
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);
    } catch (error) {
      console.error('Failed to load chat history:', error);
      this.showToast('加载聊天记录失败');
    }
  }

  async loadConversations() {
    try {
      this.conversations = await this.databaseManager.getAllConversations();
    } catch (error) {
      console.error('Failed to load conversations:', error);
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
        console.info('Restored last conversation:', this.currentConversation.id, this.currentConversation.title);
      } else {
        console.info('No conversations found, will start with empty state');
        this.currentConversation = null;
      }
    } catch (error) {
      console.error('Failed to restore last conversation:', error);
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
          console.info('Found empty conversation:', conversation.id, conversation.title);
          return conversation;
        }
      }
      console.info('No empty conversations found');
      return null;
    } catch (error) {
      console.error('Failed to find empty conversation:', error);
      return null;
    }
  }

  showSidebar() {
    // 显示侧栏时隐藏键盘
    this.hideKeyboard();

    this.isSidebarVisible = true;
    animateTo({
      duration: 300,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.sidebarOffset = 0;
      this.backgroundBlurRadius = 15; // 增加模糊强度
    });
  }

  hideSidebar() {
    // 关闭侧边栏时隐藏键盘
    this.hideKeyboard();

    animateTo({
      duration: 300,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.sidebarOffset = -300;
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
      console.info('Creating new conversation...');
      const newConversation = await this.databaseManager.createConversation('新对话');
      console.info('New conversation created:', newConversation);

      this.currentConversation = newConversation;
      this.messages = [];

      // 等待数据库操作完成
      await this.loadConversations();

      this.hideSidebar();
      this.showToast('已创建新对话');

      // 确保加载状态被重置
      this.isLoading = false;

      console.info('New conversation setup completed');
    } catch (error) {
      console.error('Failed to create new conversation:', error);
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
      console.error('Failed to select conversation:', error);
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
        console.info('User cancelled conversation deletion');
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
        } else {
          this.currentConversation = null;
          this.messages = [];
        }
      }

      this.showToast('对话已删除');
    } catch (error) {
      console.error('Failed to delete conversation:', error);
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
    if (!this.currentSettings) return;

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

        // 保存到数据库
        await this.databaseManager.saveSettings(this.currentSettings);

        this.showToast(`已切换到${provider.displayName}的${model.displayName}`, 2000);
      }

      // 模型切换完成后，弹窗会自动关闭
    } catch (error) {
      console.error('Failed to change model:', error);
      this.showToast('切换模型失败', 2000);
    }
  }

  async generateConversationTitle() {
    if (!this.currentConversation || !this.currentSettings) return;

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
      console.error('Failed to generate conversation title:', error);
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

    const activeProvider = this.currentSettings.providers.find(provider => provider.id === this.currentSettings!.activeProviderId);
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

    // 分别获取用户消息和AI回复
    const userMessages = this.messages.filter(msg => msg.role === 'user');
    const aiMessages = this.messages.filter(msg => msg.role === 'assistant');

    const totalUserChars = userMessages.reduce((total, msg) => total + msg.content.length, 0);
    const totalAiChars = aiMessages.reduce((total, msg) => total + msg.content.length, 0);

    // 检查是否包含常见的简单问候语
    const greetings = ['你好', 'hello', 'hi', '您好', '在吗', '在不在', '早上好', '晚上好', '下午好'];
    const firstUserMessage = userMessages[0]?.content.toLowerCase().trim();

    // 如果第一条消息是简单问候语
    if (firstUserMessage && greetings.some(greeting =>
    firstUserMessage.includes(greeting.toLowerCase()) && firstUserMessage.length <= 10)) {

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

  async sendMessage() {
    if (!this.inputText.trim() || this.isLoading) {
      return;
    }

    await this.waitForLatestSettings('sendMessage');

    // 发送消息后自动收起键盘
    this.hideKeyboard();
    this.scrollToBottom();

    if (!this.hasSettings) {
      this.showToast('请先配置API设置');
      this.pathStack.pushPathByName("Settings", null, false);
      this.hideKeyboard();
      return;
    }

    if (!this.currentSettings) {
      this.showToast('设置加载失败，请重新配置');
      return;
    }

    // 如果没有当前对话，创建一个新对话
    if (!this.currentConversation) {
      console.info('No current conversation found, creating new one...');
      try {
        const newConversation = await this.databaseManager.createConversation('新对话');
        this.currentConversation = newConversation;
        await this.loadConversations();
        console.info('Auto-created conversation:', newConversation.id);

        // 等待一小段时间确保对话创建完全完成
        await new Promise<void>(resolve => setTimeout(resolve, 100));
      } catch (error) {
        console.error('Failed to create conversation for message:', error);
        this.showToast('创建对话失败');
        return;
      }
    }

    // 验证当前对话是否有效
    if (!this.currentConversation || !this.currentConversation.id) {
      console.error('Invalid current conversation:', this.currentConversation);
      this.showToast('对话状态异常，请重新创建对话');
      return;
    }

    console.info('Sending message in conversation:', this.currentConversation.id);

    // 锁定当前对话ID，防止在等待AI回复期间切换对话导致回复错乱
    const targetConversationId = this.currentConversation.id;
    const userMessage = new ChatMessage(this.inputText.trim(), 'user', {
      conversationId: targetConversationId
    });

    let userMessageIndex: number = -1;
    let userMessageId: number | undefined;
    let streamingMessageIndex: number = -1;
    let streamingMessageId: number | undefined;

    let failureHandled = false;
    const handleFailure = async (errorParam: Error): Promise<void> => {
      if (failureHandled) {
        return;
      }
      failureHandled = true;

      const toastMessage = this.getFriendlySendErrorMessage(errorParam);
      const assistantErrorContent = toastMessage.startsWith('发送失败') ? toastMessage : `发送失败：${toastMessage}`;

      console.error('Message send failed:', errorParam);

      if (this.currentConversation && this.currentConversation.id === targetConversationId) {
        let effectiveIndex = streamingMessageIndex;
        if (effectiveIndex < 0 || effectiveIndex >= this.messages.length) {
          const fallbackMessage = new ChatMessage('', 'assistant', {
            conversationId: targetConversationId
          });
          effectiveIndex = this.appendMessage(fallbackMessage);
          streamingMessageIndex = effectiveIndex;
        }

        if (effectiveIndex >= 0 && effectiveIndex < this.messages.length) {
          this.replaceMessageAt(effectiveIndex, (message: ChatMessage) => {
            message.content = assistantErrorContent;
            message.modelName = undefined;
            message.providerName = undefined;
            message.providerMessageId = undefined;
            message.providerCreatedAt = undefined;
            message.systemFingerprint = undefined;
            message.timestamp = Date.now();
          });

          const failedMessage = this.messages[effectiveIndex];
          if (failedMessage?.id !== undefined) {
            try {
              await this.databaseManager.updateChatMessage(failedMessage.id, failedMessage.content);
              await this.databaseManager.updateChatMessageMetadata(failedMessage.id, {
                timestamp: failedMessage.timestamp,
                providerMessageId: null,
                providerCreatedAt: null,
                systemFingerprint: null,
                modelName: null,
                providerName: null
              });
            } catch (persistError) {
              console.error('Failed to persist failed streaming message:', persistError);
            }
          } else if (streamingMessageId !== undefined) {
            try {
              await this.databaseManager.deleteMessage(streamingMessageId);
            } catch (deleteError) {
              console.error('Failed to delete pending AI message after failure:', deleteError);
            }
          }

        }
      }

      if (this.inputText.trim().length === 0) {
        this.inputText = userMessage.content;
      }

      try {
        await this.databaseManager.updateConversationMessageCount(targetConversationId);
      } catch (countError) {
        console.error('Failed to update conversation message count after failure:', countError);
      }

      this.isLoading = false;
      this.showToast(toastMessage);
    };

    try {
      this.isLoading = true;
      console.info('Started sending message, isLoading set to true');

      // 添加用户消息到界面和数据库
      userMessageIndex = this.appendMessage(userMessage);
      console.info('Added user message to UI, total messages:', this.messages.length);
      userMessageId = await this.databaseManager.insertChatMessage(userMessage);
      this.replaceMessageAt(userMessageIndex, (message: ChatMessage) => {
        message.id = userMessageId!;
      });

      // 清空输入框
      this.inputText = '';

      // 立即创建一个空的AI消息用于实时更新，并包含模型信息
      const modelInfo = this.getCurrentModelInfo();
      const streamingAiMessage = new ChatMessage('', 'assistant', {
        conversationId: targetConversationId,
        modelName: modelInfo.modelName,
        providerName: modelInfo.providerName
      });

      // 将流式消息添加到界面，后续会实时更新内容
      streamingMessageIndex = this.appendMessage(streamingAiMessage);
      console.info('Added streaming AI message, index:', streamingMessageIndex, 'total messages:', this.messages.length);

      // 立即保存空的AI消息到数据库，获取ID
      streamingMessageId = await this.databaseManager.insertChatMessage(streamingAiMessage);
      this.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
        message.id = streamingMessageId!;
      });
      console.info('Created streaming AI message in database with ID:', streamingMessageId);

      // 准备发送给AI的消息列表（不包括刚创建的空AI消息，取最近10条）
      const endIndex = this.messages.length - 1;
      const startIndex = Math.max(0, endIndex - 10);
      const messagesForAI = this.messages.slice(startIndex, endIndex);
      if (messagesForAI.length === 0) {
        messagesForAI.push(this.cloneChatMessage(userMessage));
      }

      console.info('Sending message to AI...');
      console.info('API URL:', this.currentSettings.apiUrl);
      console.info('Model:', this.currentSettings.modelName);
      console.info('Messages count:', messagesForAI.length);
      console.info('Target conversation ID:', targetConversationId);

      // 发送流式请求，立即更新UI
      if (!this.currentSettings || !this.currentSettings.apiUrl || !this.currentSettings.apiKey || !this.currentSettings.modelName) {
        console.error('Current settings are incomplete or null');
        return;
      }
      await this.networkManager.sendStreamChatRequest(
        this.currentSettings.apiUrl,
        this.currentSettings.apiKey,
        this.currentSettings.modelName,
        messagesForAI,
        {
          onMetadata: (meta) => {
            if (!this.currentConversation || this.currentConversation.id !== targetConversationId) {
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
                this.databaseManager.updateChatMessageMetadata(persistedMessage.id, {
                  timestamp: persistedMessage.timestamp,
                  providerMessageId: persistedMessage.providerMessageId ?? null,
                  providerCreatedAt: persistedMessage.providerCreatedAt ?? null,
                  systemFingerprint: persistedMessage.systemFingerprint ?? null,
                  modelName: persistedMessage.modelName ?? null,
                  providerName: persistedMessage.providerName ?? null
                }).catch((metadataError: Error) => {
                  console.error('Failed to persist streaming metadata:', metadataError);
                });
              }
            }
          },
          // onData: 立即显示接收到的数据，无延迟
          onData: (chunk: string) => {
            console.info('Received chunk immediately:', chunk);
            console.info('Current conversation ID:', this.currentConversation?.id);
            console.info('Target conversation ID:', targetConversationId);
            console.info('Streaming message index:', streamingMessageIndex);
            console.info('Total messages:', this.messages.length);

            // 检查当前显示的对话是否还是发送消息时的对话
            if (this.currentConversation && this.currentConversation.id === targetConversationId) {
              if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
                this.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
                  message.content += chunk;
                });
                console.info('Updated message content, new length:', this.messages[streamingMessageIndex].content.length);
              }
            }
          },

          // onComplete: 流式请求完成
          onComplete: async () => {
            console.info('Stream completed');

            if (this.currentConversation && this.currentConversation.id === targetConversationId) {
              if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
                const streamingMessage = this.messages[streamingMessageIndex];

                // 流式消息应该已经有ID（在开始时创建），更新数据库中的内容
                if (streamingMessage.id !== undefined) {
                  console.info('Updating streaming AI response in database, ID:', streamingMessage.id);
                  await this.databaseManager.updateChatMessage(streamingMessage.id, streamingMessage.content);
                  console.info('AI response updated in database');
                } else {
                  console.warn('Streaming message has no ID, this should not happen');
                  // 兜底方案：如果没有ID，保存到数据库
                  const savedId = await this.databaseManager.insertChatMessage(streamingMessage);
                  this.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
                    message.id = savedId;
                  });
                  console.info('AI response saved with ID:', savedId);
                }
              }

              // 生成对话标题
              if (this.shouldGenerateTitle()) {
                await this.generateConversationTitle();
              }

            }

            // 更新对话的消息计数
            await this.databaseManager.updateConversationMessageCount(targetConversationId);

            console.info('AI response processed successfully');

            // 设置加载状态为false
            this.isLoading = false;
          },

          // onError: 处理错误
          onError: (error: Error) => {
            handleFailure(error).catch((failureError: Error) => {
              console.error('Failed to handle streaming error:', failureError);
            });
          }
        }
      );

    } catch (error) {
      await handleFailure(error instanceof Error ? error : new Error(String(error)));
    } finally {
      // 不在这里设置isLoading = false，因为流式请求的回调是异步的
      console.info('Message sending request initiated');
    }
  }

  scrollToBottom() {
    if (this.scroller) {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (error) {
        console.error('Failed to scroll to bottom:', error);
        // 备用方案：尝试使用scrollTo方法
        try {
          const currentOffset = this.scroller.currentOffset();
          if (currentOffset) {
            this.scroller.scrollTo({ xOffset: 0, yOffset: (currentOffset.yOffset || 0) + 1000 });
          }
        } catch (scrollError) {
          console.error('Backup scroll method also failed:', scrollError);
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
        console.info('Message copied successfully:', message.content);
      } else {
        this.showToast('复制失败');
      }
    } catch (error) {
      console.error('Failed to copy message:', error);
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

      this.showToast('消息已删除');
    } catch (error) {
      console.error('Failed to delete message:', error);
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
      console.info('Created new database record for regeneration with ID:', newMessageId);

      // 设置为重新生成模式
      this.isLoading = true;
      const targetConversationId = this.currentConversation.id;
      const streamingMessageIndex = messageIndex;

      // 滚动到重新生成的消息位置
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);

      // 准备发送给AI的消息列表（不包括当前正在重新生成的消息）
      const messagesForAI = this.messages.slice(0, messageIndex);

      console.info('Regenerating AI message at index:', streamingMessageIndex);

      // 发送流式请求重新生成
      await this.networkManager.sendStreamChatRequest(
        this.currentSettings?.apiUrl || '',
        this.currentSettings?.apiKey || '',
        this.currentSettings?.modelName || '',
        messagesForAI,
        {
          onMetadata: (meta) => {
            if (!this.currentConversation || this.currentConversation.id !== targetConversationId) {
              return;
            }
            if (streamingMessageIndex >= this.messages.length) {
              return;
            }
            if (!this.messages[streamingMessageIndex]) {
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
                  console.error('Failed to persist regenerated metadata:', metadataError);
                });
              }
            }
          },
          // 实时更新重新生成的消息
          onData: (chunk: string) => {
            console.info('Received regenerated chunk:', chunk);

            if (this.currentConversation && this.currentConversation.id === targetConversationId) {
              if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
                this.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
                  regeneratedMessage.content += chunk;
                });
                console.info('After update - regenerated message content length:', this.messages[streamingMessageIndex].content.length);
              }
            }
          },

          // 重新生成完成
          onComplete: async () => {
            console.info('Regeneration completed');

            if (this.currentConversation && this.currentConversation.id === targetConversationId) {
              if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
                const regeneratedMessage = this.messages[streamingMessageIndex];

                // 更新数据库中的消息内容（消息已在开始时创建）
                if (regeneratedMessage.id !== undefined) {
                  await this.databaseManager.updateChatMessage(regeneratedMessage.id, regeneratedMessage.content);
                  console.info('Regenerated message updated in database with ID:', regeneratedMessage.id);
                } else {
                  // 兜底方案：如果没有ID，保存到数据库
                  const savedId = await this.databaseManager.insertChatMessage(regeneratedMessage);
                  this.replaceMessageAt(streamingMessageIndex, (messageToPersist: ChatMessage) => {
                    messageToPersist.id = savedId;
                  });
                  console.info('Regenerated message saved with new ID:', savedId);
                }
                // 滚动到底部
                setTimeout(() => {
                  if (this.scroller) {
                    this.scroller.scrollEdge(Edge.Bottom);
                  }
                }, 100);
              }
            }

            this.isLoading = false;
            this.showToast('消息已重新生成');
          },

          // 重新生成错误处理
          onError: async (error: Error) => {
            console.error('Regeneration failed:', error);

            if (this.currentConversation && this.currentConversation.id === targetConversationId) {
              if (streamingMessageIndex < this.messages.length && this.messages[streamingMessageIndex]) {
                this.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
                  regeneratedMessage.content = `重新生成失败: ${error.message || error}`;
                });
              }
            }

            this.isLoading = false;
            this.showToast('重新生成失败');
          }
        }
      );

    } catch (error) {
      console.error('Failed to regenerate message:', error);
      this.isLoading = false;
      this.showToast('重新生成失败');
    }
  }

  async clearHistory() {
    try {
      await this.databaseManager.clearChatHistory();
      this.messages = [];
      this.showToast('聊天记录已清空');
    } catch (error) {
      console.error('Failed to clear history:', error);
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
          console.info('Keyboard hidden successfully');
        })
        .catch((error: Error) => {
          console.error('Failed to hide keyboard:', error);
        });
    } catch (error) {
      console.error('Error getting input method controller:', error);
    }
  }

  @Builder
  buildGroupedConversations() {
    ForEach(this.getGroupedConversationKeys(), (dateKey: string) => {
      // 日期分组标题
      Text(this.formatDateGroup(dateKey))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .padding({ left: 4, top: 16, bottom: 8 })
        .textAlign(TextAlign.Start)

      // 该日期下的对话列表
      List({ space: 4 }) {
        ForEach(this.getConversationsForDate(dateKey), (conversation: Conversation, index: number) => {
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

  // 获取分组对话的日期键数组
  private getGroupedConversationKeys(): string[] {
    const groupedConversations = this.groupConversationsByDate();
    return Object.keys(groupedConversations);
  }

  // 获取指定日期的对话列表
  private getConversationsForDate(dateKey: string): Conversation[] {
    const groupedConversations = this.groupConversationsByDate();
    return groupedConversations[dateKey] || [];
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
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);

    const conversationDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const todayDate = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const yesterdayDate = new Date(yesterday.getFullYear(), yesterday.getMonth(), yesterday.getDate());

    if (conversationDate.getTime() === todayDate.getTime()) {
      return 'today';
    } else if (conversationDate.getTime() === yesterdayDate.getTime()) {
      return 'yesterday';
    } else {
      // 超过昨天的按月份分组
      const currentYear = today.getFullYear();
      const conversationYear = date.getFullYear();

      if (conversationYear === currentYear) {
        // 今年的显示月份
        return `${conversationYear}-${(date.getMonth() + 1).toString().padStart(2, '0')}`;
      } else {
        // 往年的显示年份
        return conversationYear.toString();
      }
    }
  }

  // 格式化日期分组显示文本
  private formatDateGroup(dateKey: string): string {
    if (dateKey === 'today') {
      return '今天';
    } else if (dateKey === 'yesterday') {
      return '昨天';
    } else if (dateKey.includes('-')) {
      // 月份格式 YYYY-MM
      const dateParts = dateKey.split('-');
      const year = dateParts[0];
      const month = dateParts[1];
      const monthNames = ['一月', '二月', '三月', '四月', '五月', '六月',
        '七月', '八月', '九月', '十月', '十一月', '十二月'];
      const currentYear = new Date().getFullYear();

      if (parseInt(year) === currentYear) {
        return monthNames[parseInt(month) - 1];
      } else {
        return `${year}年${monthNames[parseInt(month) - 1]}`;
      }
    } else {
      // 年份格式
      return `${dateKey}年`;
    }
  }

  @Builder
  SidebarContent() {
    Column() {
      // 侧边栏标题
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
        .backgroundColor($r('sys.color.button_background_color_transparent'))
        .onClick(() => {
          this.hideSidebar();
        })
      }
      .margin( {top: this.getUIContext().px2vp(this.topRectHeight)} )
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

      // 对话列表
      if (this.conversations.length === 0) {
        Column() {
          Text('还没有对话记录')
            .fontSize(14)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
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
        .layoutWeight(1)
        .width('100%')
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }

      // 底部功能按钮
      Column() {
        Divider()
          .margin({ bottom: 12 })

        // 设置按钮
        Button('设置')
          .fontColor($r('app.color.text_color'))
          .width('90%')
          .backgroundColor($r('sys.color.button_background_color_transparent'))
          .borderRadius(24)
          .onClick(() => {
            this.pathStack.pushPathByName("Settings", null, false);
            this.hideKeyboard();
            this.hideSidebar();
          })
        }
        .margin( {bottom: this.getUIContext().px2vp(this.bottomRectHeight)} )
        .width('100%')
        .justifyContent(FlexAlign.End)
    }
    .width(300)
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
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
  MoreOptionsPopup() {
    Column({ space: 4 }) {
      Button() {
        Row() {
          Text('切换模型')
            .fontSize(14)
            .fontColor($r('app.color.text_color'))
        }
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width(140)
      .height(40)
      .backgroundColor($r('app.color.dialog_button_bac_color'))
      .onClick(() => {
        this.customPopup = false;
        this.switchModel();
      })
    }
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
          .margin({ top: 4 })
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(64)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(8)
    .onClick(() => {
      this.selectConversation(conversation);
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
      console.error('Failed to rename conversation:', error);
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
}