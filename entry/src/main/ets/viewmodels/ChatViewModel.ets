/**
 * ChatViewModel.ets
 * 聊天页面 ViewModel
 * 
 * 职责：管理聊天页面的业务逻辑和状态
 * 设计模式：MVVM - 分离UI和业务逻辑
 */

import { createLogger, LogDomain } from '../common/Logger';
import { ChatMessage, AppSettings, Citation, StreamMetadata, ChatMessageMetadataUpdate } from '../services/DataModels';
import { Conversation } from '../services/ConversationModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NetworkManagerV2 } from '../services/NetworkManagerV2';
import { StreamEventEmitter, StreamEventType, EventPayload, ToolCallData } from '../services/StreamEventEmitter';
import { TitleGenerationService } from '../services/TitleGenerationService';
import { SearchToolService } from '../services/search/SearchToolService';
import { SearchConfigManager } from '../services/search/SearchConfigManager';
import { AbortController, createAbortController } from '../interfaces/AbortController';
import { 
  ModelInfo, 
  StreamingMessageResult, 
  SearchToolArgs,
  SearchExecutionResult,
  ViewModelCallbacks,
  StreamRequestResult,
  DEFAULT_CHAT_CONFIG 
} from './ChatTypes';
import { 
  cloneChatMessage, 
  getFriendlyErrorMessage, 
  containsSuspiciousContent,
  shouldGenerateTitle
} from './ChatUtils';

const logger = createLogger('ChatViewModel', LogDomain.CHAT);

/**
 * 聊天 ViewModel
 * 管理聊天页面的所有业务逻辑
 */
export class ChatViewModel {
  // 服务实例
  private databaseManager: DatabaseManager;
  private networkManager: NetworkManagerV2;
  private titleGenerationService: TitleGenerationService;
  private searchToolService: SearchToolService;
  private searchConfigManager: SearchConfigManager;
  
  // 状态
  private _currentSettings: AppSettings | null = null;
  private _currentConversation: Conversation | null = null;
  private _messages: ChatMessage[] = [];
  private _conversations: Conversation[] = [];
  private _logicalTimestamp: number = Date.now();
  private _currentAbortController: AbortController | null = null;
  private _userAbortedGeneration: boolean = false;
  
  // 回调
  private onStateChange?: () => void;
  private onError?: (message: string) => void;
  private onToast?: (message: string, duration?: number) => void;

  constructor() {
    this.databaseManager = DatabaseManager.getInstance();
    this.networkManager = NetworkManagerV2.getInstance();
    this.titleGenerationService = new TitleGenerationService();
    this.searchToolService = SearchToolService.getInstance();
    this.searchConfigManager = SearchConfigManager.getInstance();
  }

  // Getters
  get currentSettings(): AppSettings | null {
    return this._currentSettings;
  }

  get currentConversation(): Conversation | null {
    return this._currentConversation;
  }

  get messages(): ChatMessage[] {
    return this._messages;
  }

  get conversations(): Conversation[] {
    return this._conversations;
  }

  get hasSettings(): boolean {
    return this._currentSettings !== null && 
           this._currentSettings.apiUrl.trim().length > 0 &&
           this._currentSettings.apiKey.trim().length > 0;
  }

  // Setters - 用于同步外部状态到 ViewModel
  setMessages(messages: ChatMessage[]): void {
    this._messages = messages;
  }

  setCurrentConversation(conversation: Conversation | null): void {
    this._currentConversation = conversation;
  }

  setCurrentSettings(settings: AppSettings | null): void {
    this._currentSettings = settings;
  }

  /**
   * 设置回调函数
   */
  setCallbacks(callbacks: ViewModelCallbacks): void {
    this.onStateChange = callbacks.onStateChange;
    this.onError = callbacks.onError;
    this.onToast = callbacks.onToast;
  }

  /**
   * 初始化
   */
  async initialize(context: Context): Promise<void> {
    try {
      await this.databaseManager.initDatabase(context);
      
      // 清理历史 tool 消息
      try {
        await this.databaseManager.cleanupToolMessages();
      } catch (e) {
        logger.warn('Failed to cleanup tool messages: %{public}s', String(e));
      }

      // 初始化搜索配置
      try {
        await this.searchConfigManager.init(context);
      } catch (e) {
        logger.warn('Failed to init search config: %{public}s', String(e));
      }

      await this.loadSettings();
      await this.loadConversations();
      await this.restoreLastConversation();
      await this.loadChatHistory();
      
    } catch (error) {
      logger.error('Initialize failed: %{public}s', String(error));
      const err: Error = error instanceof Error ? error : new Error(String(error));
      throw err;
    }
  }

  /**
   * 加载设置
   */
  async loadSettings(): Promise<void> {
    try {
      const settings = await this.databaseManager.getSettings();
      this._currentSettings = settings;
      
      if (settings && settings.providers.length > 0) {
        const activeProvider = settings.providers.find(p => p.id === settings.activeProviderId);
        if (activeProvider) {
          const activeModel = activeProvider.models.find(m => m.id === settings.activeModelId);
          if (activeModel) {
            settings.apiUrl = activeProvider.apiUrl;
            settings.apiKey = activeProvider.apiKey;
            settings.modelName = activeModel.name;
          }
        }
      }
    } catch (error) {
      logger.error('Load settings failed: %{public}s', String(error));
    }
  }

  /**
   * 加载对话列表
   */
  async loadConversations(): Promise<void> {
    try {
      this._conversations = await this.databaseManager.getAllConversations();
    } catch (error) {
      logger.error('Load conversations failed: %{public}s', String(error));
    }
  }

  /**
   * 恢复最后使用的对话
   */
  async restoreLastConversation(): Promise<void> {
    try {
      if (this._conversations.length > 0) {
        const conversationsCopy: Conversation[] = [];
        for (let i = 0; i < this._conversations.length; i++) {
          conversationsCopy.push(this._conversations[i]);
        }
        const sorted = conversationsCopy.sort((a, b) =>
          new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
        );
        this._currentConversation = sorted[0];
      } else {
        const newConv = await this.databaseManager.createConversation('新对话');
        this._currentConversation = newConv;
        this._conversations.push(newConv);
      }
    } catch (error) {
      logger.error('Restore conversation failed: %{public}s', String(error));
    }
  }

  /**
   * 加载聊天历史
   */
  async loadChatHistory(): Promise<void> {
    try {
      if (this._currentConversation) {
        this._messages = await this.databaseManager.getChatMessages(this._currentConversation.id);
      } else {
        this._messages = [];
      }

      // 同步逻辑时间戳
      if (this._messages.length > 0) {
        let maxTs = 0;
        for (const msg of this._messages) {
          if (msg.timestamp > maxTs) {
            maxTs = msg.timestamp;
          }
        }
        this._logicalTimestamp = maxTs;
      }
    } catch (error) {
      logger.error('Load chat history failed: %{public}s', String(error));
    }
  }

  /**
   * 获取下一个逻辑时间戳
   */
  getNextTimestamp(): number {
    const now = Date.now();
    if (now > this._logicalTimestamp) {
      this._logicalTimestamp = now;
    } else {
      this._logicalTimestamp += 1;
    }
    return this._logicalTimestamp;
  }

  /**
   * 获取当前模型信息
   */
  getCurrentModelInfo(): ModelInfo {
    if (!this._currentSettings || this._currentSettings.providers.length === 0) {
      return { modelName: 'unknown', providerName: 'unknown' };
    }

    const provider = this._currentSettings.providers.find(
      p => p.id === this._currentSettings!.activeProviderId
    );
    
    if (!provider) {
      return { modelName: 'unknown', providerName: 'unknown' };
    }

    const model = provider.models.find(
      m => m.id === this._currentSettings!.activeModelId
    ) ?? provider.models[0];

    return {
      modelName: model?.displayName || model?.name || '未配置模型',
      providerName: provider.displayName || provider.name
    };
  }

  /**
   * 创建新对话
   */
  async createNewConversation(): Promise<Conversation> {
    // 检查是否有空对话
    const empty = await this.findEmptyConversation();
    if (empty) {
      this._currentConversation = empty;
      this._messages = [];
      return empty;
    }

    const newConv = await this.databaseManager.createConversation('新对话');
    this._currentConversation = newConv;
    this._messages = [];
    const newConversations: Conversation[] = [newConv];
    for (let i = 0; i < this._conversations.length; i++) {
      newConversations.push(this._conversations[i]);
    }
    this._conversations = newConversations;
    return newConv;
  }

  /**
   * 查找空对话
   */
  async findEmptyConversation(): Promise<Conversation | null> {
    const ids = this._conversations.map(c => c.id);
    const counts = await this.databaseManager.getConversationMessageCounts(ids);
    
    for (const conv of this._conversations) {
      if ((counts[conv.id] ?? 0) === 0) {
        return conv;
      }
    }
    return null;
  }

  /**
   * 选择对话
   */
  async selectConversation(conversation: Conversation): Promise<void> {
    this._currentConversation = conversation;
    await this.loadChatHistory();
  }

  /**
   * 删除对话
   */
  async deleteConversation(conversationId: string): Promise<void> {
    await this.databaseManager.deleteConversation(conversationId);
    this._conversations = await this.databaseManager.getAllConversations();

    if (this._currentConversation?.id === conversationId) {
      if (this._conversations.length > 0) {
        this._currentConversation = this._conversations[0];
        this._messages = await this.databaseManager.getChatMessages(this._currentConversation.id);
      } else {
        const newConv = await this.databaseManager.createConversation('新对话');
        this._currentConversation = newConv;
        this._conversations = [newConv];
        this._messages = [];
      }
    }
  }

  /**
   * 重命名对话
   */
  async renameConversation(conversationId: string, newTitle: string): Promise<void> {
    await this.databaseManager.updateConversationTitle(conversationId, newTitle);
    
    // 更新当前对话标题
    if (this._currentConversation?.id === conversationId) {
      this._currentConversation.title = newTitle;
    }
    
    // 刷新对话列表
    await this.loadConversations();
  }

  /**
   * 验证消息输入
   */
  validateMessageInput(text: string): string | null {
    const trimmed = text.trim();
    
    if (!trimmed) {
      return null;
    }

    if (trimmed.length > DEFAULT_CHAT_CONFIG.maxMessageLength) {
      this.onToast?.(`消息内容不能超过${DEFAULT_CHAT_CONFIG.maxMessageLength}个字符`);
      return null;
    }

    if (containsSuspiciousContent(trimmed)) {
      this.onToast?.('消息内容包含不当内容，请修改后重试');
      return null;
    }

    if (!this.hasSettings) {
      this.onToast?.('请先配置API设置');
      return null;
    }

    return trimmed;
  }

  /**
   * 添加消息
   */
  appendMessage(message: ChatMessage): number {
    const newMessages: ChatMessage[] = [];
    for (let i = 0; i < this._messages.length; i++) {
      newMessages.push(this._messages[i]);
    }
    newMessages.push(message);
    this._messages = newMessages;
    return this._messages.length - 1;
  }

  /**
   * 更新消息
   */
  updateMessageAt(index: number, updater: (msg: ChatMessage) => void): void {
    if (index < 0 || index >= this._messages.length) return;

    const cloned = cloneChatMessage(this._messages[index]);
    updater(cloned);
    
    const newMessages: ChatMessage[] = [];
    for (let i = 0; i < this._messages.length; i++) {
      if (i === index) {
        newMessages.push(cloned);
      } else {
        newMessages.push(this._messages[i]);
      }
    }
    this._messages = newMessages;
  }

  /**
   * 停止生成
   */
  stopGeneration(): void {
    if (this._currentAbortController) {
      this._userAbortedGeneration = true;
      try {
        this._currentAbortController.abort();
      } catch (e) {
        // ignore
      }
    }
  }

  /**
   * 生成对话标题
   */
  async generateConversationTitle(): Promise<void> {
    if (!this._currentConversation || !this._currentSettings) return;
    if (!shouldGenerateTitle(this._messages, this._currentConversation.title)) return;

    try {
      const title = await this.titleGenerationService.generateTitle(
        this._messages,
        this._currentSettings.apiKey,
        this._currentSettings.apiUrl,
        this._currentSettings.modelName
      );

      if (title && title !== this._currentConversation.title) {
        await this.databaseManager.updateConversationTitle(this._currentConversation.id, title);
        this._currentConversation.title = title;
        await this.loadConversations();
      }
    } catch (error) {
      logger.error('Generate title failed: %{public}s', String(error));
    }
  }

  /**
   * 切换模型
   */
  async changeModel(providerId: string, modelId: string): Promise<void> {
    if (!this._currentSettings) return;

    this._currentSettings.activeProviderId = providerId;
    this._currentSettings.activeModelId = modelId;

    const provider = this._currentSettings.providers.find(p => p.id === providerId);
    const model = provider?.models.find(m => m.id === modelId);

    if (provider && model) {
      this._currentSettings.apiUrl = provider.apiUrl;
      this._currentSettings.apiKey = provider.apiKey;
      this._currentSettings.modelName = model.name;

      for (const p of this._currentSettings.providers) {
        p.isActive = (p.id === providerId);
      }

      await this.databaseManager.saveSettings(this._currentSettings);
    }
  }

  /**
   * 保存联网搜索设置
   */
  async saveWebSearchSetting(enabled: boolean): Promise<void> {
    if (!this._currentSettings) return;
    
    this._currentSettings.enableWebSearch = enabled;
    await this.databaseManager.saveSettings(this._currentSettings);
  }

  /**
   * 获取搜索工具定义
   */
  getSearchToolDefinition(): object | null {
    try {
      const config = this.searchConfigManager.getConfig();
      if (config && config.enabledServices.length > 0) {
        const selected = this.searchConfigManager.getSelectedService();
        if (selected) {
          return this.searchToolService.getToolDefinition();
        }
      }
    } catch (e) {
      logger.warn('Get search tool failed: %{public}s', String(e));
    }
    return null;
  }

  /**
   * 执行搜索
   */
  async executeSearch(query: string, resultSize?: number): Promise<SearchExecutionResult> {
    const result = await this.searchToolService.executeSearch(query, resultSize);
    
    const citations: Citation[] = [];
    for (let i = 0; i < result.items.length; i++) {
      const item = result.items[i];
      const citation: Citation = {
        title: item.title,
        url: item.url,
        snippet: item.text
      };
      citations.push(citation);
    }

    const executionResult: SearchExecutionResult = { 
      result: result, 
      citations: citations 
    };
    return executionResult;
  }

  /**
   * 创建流式请求
   */
  async createStreamRequest(
    messagesForAI: ChatMessage[],
    enableWebSearch: boolean
  ): Promise<StreamRequestResult> {
    const abortController = createAbortController();
    this._currentAbortController = abortController;

    let tools: object[] = [];

    if (enableWebSearch) {
      const toolDef = this.getSearchToolDefinition();
      if (toolDef) {
        tools = [toolDef];
      }
    }

    const emitter = await this.networkManager.sendStreamChatRequestV2(
      this._currentSettings!.apiUrl,
      this._currentSettings!.apiKey,
      this._currentSettings!.modelName,
      messagesForAI,
      {
        tools: tools.length > 0 ? tools : undefined,
        abortController: abortController,
        requestTimeout: DEFAULT_CHAT_CONFIG.requestTimeout
      }
    );

    const streamResult: StreamRequestResult = { emitter: emitter, abortController: abortController };
    return streamResult;
  }

  /**
   * 插入用户消息到数据库
   */
  async insertUserMessage(message: ChatMessage): Promise<number> {
    return await this.databaseManager.insertChatMessage(message);
  }

  /**
   * 插入AI消息到数据库
   */
  async insertAIMessage(message: ChatMessage): Promise<number> {
    return await this.databaseManager.insertChatMessage(message);
  }

  /**
   * 更新消息内容
   */
  async updateMessageContent(messageId: number, content: string): Promise<void> {
    await this.databaseManager.updateChatMessage(messageId, content);
  }

  /**
   * 更新消息元数据
   */
  async updateMessageMetadata(messageId: number, metadata: ChatMessageMetadataUpdate): Promise<void> {
    await this.databaseManager.updateChatMessageMetadata(messageId, metadata);
  }

  /**
   * 更新对话消息计数
   */
  async updateConversationMessageCount(conversationId: string): Promise<void> {
    await this.databaseManager.updateConversationMessageCount(conversationId);
  }

  /**
   * 准备发送给API的消息列表
   */
  prepareMessagesForAPI(): ChatMessage[] {
    const endIndex = this._messages.length;
    const startIndex = Math.max(0, endIndex - DEFAULT_CHAT_CONFIG.maxHistoryMessages);
    return this._messages.slice(startIndex, endIndex);
  }

  /**
   * 重置生成状态
   */
  resetGenerationState(): void {
    this._currentAbortController = null;
    this._userAbortedGeneration = false;
  }

  /**
   * 获取用户中止状态
   */
  get userAbortedGeneration(): boolean {
    return this._userAbortedGeneration;
  }

  /**
   * 清理资源
   */
  dispose(): void {
    this.stopGeneration();
    this._currentAbortController = null;
  }
}

/**
 * 创建 ChatViewModel 单例
 */
let chatViewModelInstance: ChatViewModel | null = null;

export function getChatViewModel(): ChatViewModel {
  if (!chatViewModelInstance) {
    chatViewModelInstance = new ChatViewModel();
  }
  return chatViewModelInstance;
}
