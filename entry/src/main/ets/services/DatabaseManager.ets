import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';
import {
  ChatMessage,
  AppSettings,
  AIProvider,
  AIProviderDTO,
  Constants,
  DatabaseError,
  Conversation,
  ConversationRecord
} from '../services/DataModels';


/**
 * 数据库管理器
 */
export class DatabaseManager {
  private static instance: DatabaseManager;
  private rdbStore: relationalStore.RdbStore | null = null;

  private constructor() {}

  static getInstance(): DatabaseManager {
    if (!DatabaseManager.instance) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  /**
   * 初始化数据库
   */
  async initDatabase(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: Constants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
      encrypt: false
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      await this.createTables();
      console.info('Database initialized successfully');
    } catch (error) {
      console.error('Failed to initialize database:', error);
      throw new DatabaseError(`Failed to initialize database: ${error}`);
    }
  }

  /**
   * 创建数据表
   */
  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    // 创建聊天消息表
    const createChatTable = `
      CREATE TABLE IF NOT EXISTS ${Constants.CHAT_TABLE} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        role TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        conversation_id TEXT NOT NULL DEFAULT 'default',
        model_name TEXT,
        provider_name TEXT
      )
    `;

    // 创建对话表
    const createConversationTable = `
      CREATE TABLE IF NOT EXISTS ${Constants.CONVERSATION_TABLE} (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        message_count INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 0
      )
    `;

    // 创建设置表
    const createSettingsTable = `
      CREATE TABLE IF NOT EXISTS ${Constants.SETTINGS_TABLE} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        api_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        model_name TEXT NOT NULL,
        providers_data TEXT,
        active_provider_id TEXT,
        active_model_id TEXT
      )
    `;

    try {
      await this.rdbStore.executeSql(createChatTable);
      await this.rdbStore.executeSql(createConversationTable);
      await this.rdbStore.executeSql(createSettingsTable);

      // 升级现有表结构以支持模型信息
      await this.upgradeTableStructure();

      console.info('Database tables created successfully');
    } catch (error) {
      console.error('Failed to create tables:', error);
      throw new DatabaseError(`Failed to create tables: ${error}`);
    }
  }

  /**
   * 升级表结构
   */
  private async upgradeTableStructure(): Promise<void> {
    try {
      // 检查并添加模型相关字段
      await this.addColumnIfNotExists(Constants.CHAT_TABLE, 'model_name', 'TEXT');
      await this.addColumnIfNotExists(Constants.CHAT_TABLE, 'provider_name', 'TEXT');
      console.info('Table structure upgraded successfully');
    } catch (error) {
      console.error('Failed to upgrade table structure:', error);
      // 升级失败不应该影响应用启动，只记录错误
    }
  }

  /**
   * 如果列不存在则添加列
   */
  private async addColumnIfNotExists(tableName: string, columnName: string, columnType: string): Promise<void> {
    if (!this.rdbStore) {
      console.error('Database not initialized');
      return;
    }

    try {
      // 尝试添加列，如果已存在会抛出异常
      const alterSql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnType}`;
      await this.rdbStore.executeSql(alterSql);
      console.info(`Added column ${columnName} to table ${tableName}`);
    } catch (error) {
      // 列可能已存在，忽略错误
      console.info(`Column ${columnName} already exists in table ${tableName} or failed to add:`, error);
    }
  }

  /**
   * 插入聊天消息
   */
  async insertChatMessage(message: ChatMessage): Promise<number> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'content': message.content,
      'role': message.role,
      'timestamp': message.timestamp,
      'conversation_id': message.conversationId,
      'model_name': message.modelName || null,
      'provider_name': message.providerName || null
    };

    try {
      const rowId = await this.rdbStore.insert(Constants.CHAT_TABLE, valueBucket);
      console.info('Chat message inserted with ID:', rowId);
      return rowId;
    } catch (error) {
      console.error('Failed to insert chat message:', error);
      throw new DatabaseError(`Failed to insert chat message: ${error}`);
    }
  }

  /**
   * 更新聊天消息内容
   */
  async updateChatMessage(messageId: number, newContent: string): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'content': newContent
    };

    const predicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
    predicates.equalTo('id', messageId);

    try {
      const rowsAffected = await this.rdbStore.update(valueBucket, predicates);
      console.info('Chat message updated, rows affected:', rowsAffected);
      if (rowsAffected === 0) {
        throw new DatabaseError(`No message found with ID: ${messageId}`);
      }
    } catch (error) {
      console.error('Failed to update chat message:', error);
      throw new DatabaseError(`Failed to update chat message: ${error}`);
    }
  }

  /**
   * 获取聊天消息列表
   */
  async getChatMessages(conversationId: string = 'default', limit: number = 100): Promise<ChatMessage[]> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
    predicates.equalTo('conversation_id', conversationId)
      .orderByAsc('timestamp')
      .limitAs(limit);

    try {
      const resultSet = await this.rdbStore.query(predicates);
      const messages: ChatMessage[] = [];

      if (resultSet.goToFirstRow()) {
        do {
          const content = resultSet.getString(resultSet.getColumnIndex('content'));
          const role = resultSet.getString(resultSet.getColumnIndex('role')) as 'user' | 'assistant';
          const conversationIdValue = resultSet.getString(resultSet.getColumnIndex('conversation_id'));

          // 读取模型信息（可能为null）
          let modelName: string | undefined;
          let providerName: string | undefined;
          const modelNameIndex = this.getColumnIndexSafe(resultSet, 'model_name');
          const providerNameIndex = this.getColumnIndexSafe(resultSet, 'provider_name');
          if (modelNameIndex >= 0 && !resultSet.isColumnNull(modelNameIndex)) {
            modelName = resultSet.getString(modelNameIndex);
          }
          if (providerNameIndex >= 0 && !resultSet.isColumnNull(providerNameIndex)) {
            providerName = resultSet.getString(providerNameIndex);
          }

          const message = new ChatMessage(content, role, conversationIdValue, modelName, providerName);
          message.id = resultSet.getLong(resultSet.getColumnIndex('id'));
          message.timestamp = resultSet.getLong(resultSet.getColumnIndex('timestamp'));
          messages.push(message);
        } while (resultSet.goToNextRow());
      }

      resultSet.close();
      return messages;
    } catch (error) {
      console.error('Failed to get chat messages:', error);
      throw new DatabaseError(`Failed to get chat messages: ${error}`);
    }
  }

  /**
   * 删除聊天记录
   */
  async clearChatHistory(conversationId: string = 'default'): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
    predicates.equalTo('conversation_id', conversationId);

    try {
      await this.rdbStore.delete(predicates);
      console.info('Chat history cleared for conversation:', conversationId);
    } catch (error) {
      console.error('Failed to clear chat history:', error);
      throw new DatabaseError(`Failed to clear chat history: ${error}`);
    }
  }

  /**
   * 删除单条消息
   */
  async deleteMessage(messageId: number): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
    predicates.equalTo('id', messageId);

    try {
      await this.rdbStore.delete(predicates);
      console.info('Message deleted:', messageId);
    } catch (error) {
      console.error('Failed to delete message:', error);
      throw new DatabaseError(`Failed to delete message: ${error}`);
    }
  }

  /**
   * 保存应用设置
   */
  async saveSettings(settings: AppSettings): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    console.info('Saving settings:', {
      apiUrl: settings.apiUrl,
      modelName: settings.modelName,
      apiKeyLength: settings.apiKey.length,
      providersCount: settings.providers?.length || 0,
      activeProviderId: settings.activeProviderId,
      activeModelId: settings.activeModelId
    });

    let apiUrl = settings.apiUrl;
    let apiKey = settings.apiKey;
    let modelName = settings.modelName;

    const activeProvider = settings.providers?.find(provider => provider.id === settings.activeProviderId);
    if (activeProvider) {
      if (!apiUrl) {
        apiUrl = activeProvider.apiUrl;
      }
      if (!apiKey) {
        apiKey = activeProvider.apiKey;
      }

      const activeModel = activeProvider.models.find(model => model.id === settings.activeModelId || model.name === settings.activeModelId);
      if (activeModel && !modelName) {
        modelName = activeModel.name;
      }
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'api_url': apiUrl || '',
      'api_key': apiKey || '',
      'model_name': modelName || settings.activeModelId || ''
    };

    // 添加新版本字段
    if (settings.providers && settings.providers.length > 0) {
      const serializedProviders = settings.providers.map(provider => provider.toJSON());
      valueBucket['providers_data'] = JSON.stringify(serializedProviders);
    }
    if (settings.activeProviderId) {
      valueBucket['active_provider_id'] = settings.activeProviderId;
    }
    if (settings.activeModelId) {
      valueBucket['active_model_id'] = settings.activeModelId;
    }

    try {
      // 首先删除现有设置
      await this.rdbStore.executeSql(`DELETE FROM ${Constants.SETTINGS_TABLE}`);
      console.info('Deleted existing settings');

      // 插入新设置
      const rowId = await this.rdbStore.insert(Constants.SETTINGS_TABLE, valueBucket);
      console.info('Settings saved successfully with ID:', rowId);
    } catch (error) {
      console.error('Failed to save settings:', error);
      throw new DatabaseError(`Failed to save settings: ${error}`);
    }
  }

  /**
   * 获取应用设置
   */
  async getSettings(): Promise<AppSettings | null> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates(Constants.SETTINGS_TABLE);

    try {
      const resultSet = await this.rdbStore.query(predicates);
      let settings: AppSettings | null = null;

      console.info('Query settings result count:', resultSet.rowCount);

      if (resultSet.goToFirstRow()) {
        settings = new AppSettings(
          resultSet.getString(resultSet.getColumnIndex('api_url')),
          resultSet.getString(resultSet.getColumnIndex('api_key')),
          resultSet.getString(resultSet.getColumnIndex('model_name'))
        );
        settings.id = resultSet.getLong(resultSet.getColumnIndex('id'));

        // 读取新版本字段
        try {
          const providersDataIndex = resultSet.getColumnIndex('providers_data');
          if (providersDataIndex >= 0) {
            const providersJson = resultSet.getString(providersDataIndex);
            if (providersJson) {
              const parsedProviders = JSON.parse(providersJson) as Array<AIProviderDTO>;
              settings.providers = parsedProviders.map(item => AIProvider.fromPlainObject(item));
            }
          }
        } catch (e) {
          console.warn('Failed to parse providers data:', e);
        }

        try {
          const activeProviderIdIndex = resultSet.getColumnIndex('active_provider_id');
          if (activeProviderIdIndex >= 0) {
            settings.activeProviderId = resultSet.getString(activeProviderIdIndex);
          }
        } catch (e) {
          console.warn('No active_provider_id column found');
        }

        try {
          const activeModelIdIndex = resultSet.getColumnIndex('active_model_id');
          if (activeModelIdIndex >= 0) {
            settings.activeModelId = resultSet.getString(activeModelIdIndex);
          }
        } catch (e) {
          console.warn('No active_model_id column found');
        }

        if (settings && settings.providers.length > 0) {
          const currentSettings = settings;
          if (currentSettings.activeProviderId) {
            currentSettings.providers.forEach(provider => {
              provider.isActive = provider.id === currentSettings.activeProviderId;
            });
          } else {
            currentSettings.providers.forEach(provider => provider.isActive = false);
          }

          if (!currentSettings.activeProviderId) {
            const firstProvider = currentSettings.providers[0];
            currentSettings.activeProviderId = firstProvider.id;
            firstProvider.isActive = true;
          }

          const activeProvider = currentSettings.providers.find(provider => provider.isActive)
            ?? currentSettings.providers[0];

          if (activeProvider && !currentSettings.activeModelId && activeProvider.models.length > 0) {
            currentSettings.activeModelId = activeProvider.models[0].id;
          }
        }

        console.info('Retrieved settings:', {
          id: settings.id,
          apiUrl: settings.apiUrl,
          modelName: settings.modelName,
          apiKeyLength: settings.apiKey.length,
          providersCount: settings.providers?.length || 0,
          activeProviderId: settings.activeProviderId,
          activeModelId: settings.activeModelId
        });
      } else {
        console.info('No settings found in database');
      }

      resultSet.close();
      return settings;
    } catch (error) {
      console.error('Failed to get settings:', error);
      throw new DatabaseError(`Failed to get settings: ${error}`);
    }
  }

  /**
   * 删除对话及其所有消息
   */
  async deleteConversation(conversationId: string): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    try {
      // 删除对话中的所有消息
      const messagePredicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
      messagePredicates.equalTo('conversation_id', conversationId);
      await this.rdbStore.delete(messagePredicates);

    // 删除对话记录
    const conversationPredicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
      conversationPredicates.equalTo('id', conversationId);
      await this.rdbStore.delete(conversationPredicates);

      console.info('Conversation deleted:', conversationId);
    } catch (error) {
      console.error('Failed to delete conversation:', error);
      throw new DatabaseError(`Failed to delete conversation: ${error}`);
    }
  }

  /**
   * 设置活跃对话
   */
  async setActiveConversation(conversationId: string): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    try {
      // 将所有对话设置为非活跃
    const deactivateAll: relationalStore.ValuesBucket = { 'is_active': 0 };
    const allPredicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
      await this.rdbStore.update(deactivateAll, allPredicates);

      // 设置指定对话为活跃
    const activateOne: relationalStore.ValuesBucket = { 'is_active': 1, 'updated_at': Date.now() };
    const activePredicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
      activePredicates.equalTo('id', conversationId);
      await this.rdbStore.update(activateOne, activePredicates);

      console.info('Active conversation set:', conversationId);
    } catch (error) {
      console.error('Failed to set active conversation:', error);
      throw new DatabaseError(`Failed to set active conversation: ${error}`);
    }
  }

  /**
   * 获取活跃对话
   */
  async getActiveConversation(): Promise<Conversation | null> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
    predicates.equalTo('is_active', 1);

    try {
      const resultSet = await this.rdbStore.query(predicates);
      let conversation: Conversation | null = null;

      if (resultSet.goToFirstRow()) {
        const record: ConversationRecord = {
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          created_at: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          updated_at: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
          message_count: resultSet.getLong(resultSet.getColumnIndex('message_count')),
          is_active: 1
        };
        conversation = Conversation.fromRecord(record);
      }

      resultSet.close();
      return conversation;
    } catch (error) {
      console.error('Failed to get active conversation:', error);
      throw new DatabaseError(`Failed to get active conversation: ${error}`);
    }
  }

  /**
   * 更新对话消息计数
   */
  async updateConversationMessageCount(conversationId: string): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    try {
      // 计算对话中的消息数量
      const countPredicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
      countPredicates.equalTo('conversation_id', conversationId);
      const resultSet = await this.rdbStore.query(countPredicates);
      const messageCount = resultSet.rowCount;
      resultSet.close();

      // 更新对话记录
      const valueBucket: relationalStore.ValuesBucket = {
        'message_count': messageCount,
        'updated_at': Date.now()
      };

  const predicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
      predicates.equalTo('id', conversationId);
      await this.rdbStore.update(valueBucket, predicates);

      console.info('Conversation message count updated:', conversationId, messageCount);
    } catch (error) {
      console.error('Failed to update conversation message count:', error);
      throw new DatabaseError(`Failed to update conversation message count: ${error}`);
    }
  }

  /**
   * 创建新对话
   */
  async createConversation(title: string): Promise<Conversation> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const conversation = new Conversation();
    conversation.id = this.generateId();
    conversation.title = title;
    conversation.createdAt = Date.now();
    conversation.updatedAt = Date.now();
    conversation.messageCount = 0;
    conversation.isActive = true;

    const valueBucket: relationalStore.ValuesBucket = {
      'id': conversation.id,
      'title': conversation.title,
      'created_at': conversation.createdAt,
      'updated_at': conversation.updatedAt,
      'message_count': conversation.messageCount,
      'is_active': 1
    };

    try {
  await this.rdbStore.insert(Constants.CONVERSATION_TABLE, valueBucket);
      console.info('Conversation created:', conversation.id);
      return conversation;
    } catch (error) {
      console.error('Failed to create conversation:', error);
      throw new DatabaseError(`Failed to create conversation: ${error}`);
    }
  }

  /**
   * 获取所有对话列表
   */
  async getAllConversations(): Promise<Conversation[]> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

  const predicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
    predicates.orderByDesc('updated_at');

    try {
      const resultSet = await this.rdbStore.query(predicates);
      const conversations: Conversation[] = [];

      if (resultSet.goToFirstRow()) {
        do {
          const record: ConversationRecord = {
            id: resultSet.getString(resultSet.getColumnIndex('id')),
            title: resultSet.getString(resultSet.getColumnIndex('title')),
            created_at: resultSet.getLong(resultSet.getColumnIndex('created_at')),
            updated_at: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
            message_count: resultSet.getLong(resultSet.getColumnIndex('message_count')),
            is_active: resultSet.getLong(resultSet.getColumnIndex('is_active'))
          };
          conversations.push(Conversation.fromRecord(record));
        } while (resultSet.goToNextRow());
      }

      resultSet.close();
      return conversations;
    } catch (error) {
      console.error('Failed to get conversations:', error);
      throw new DatabaseError(`Failed to get conversations: ${error}`);
    }
  }

  /**
   * 更新对话标题
   */
  async updateConversationTitle(conversationId: string, title: string): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'title': title,
      'updated_at': Date.now()
    };

  const predicates = new relationalStore.RdbPredicates(Constants.CONVERSATION_TABLE);
    predicates.equalTo('id', conversationId);

    try {
      await this.rdbStore.update(valueBucket, predicates);
      console.info('Conversation title updated:', conversationId, title);
    } catch (error) {
      console.error('Failed to update conversation title:', error);
      throw new DatabaseError(`Failed to update conversation title: ${error}`);
    }
  }

  private getColumnIndexSafe(resultSet: relationalStore.ResultSet, columnName: string): number {
    try {
      return resultSet.getColumnIndex(columnName);
    } catch (error) {
      console.info(`Column ${columnName} not found in resultSet`);
      return -1;
    }
  }

  /**
   * 生成唯一ID
   */
  private generateId(): string {
    return Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
  }
}
