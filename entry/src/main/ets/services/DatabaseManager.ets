/**
 * DatabaseManager - 数据库管理服务
 * 
 * 功能说明：
 * - 管理应用的关系型数据库操作
 * - 提供对话、消息、设置、AI提供商等数据的CRUD操作
 * - 实现数据库版本管理和迁移
 * - 确保数据一致性和事务安全
 * 
 * 数据表结构：
 * - conversations: 对话记录表
 * - messages: 消息记录表
 * - settings: 应用设置表
 * - providers: AI提供商配置表
 * - models: AI模型配置表
 * 
 * 特性：
 * - 单例模式确保数据库连接唯一性
 * - 支持数据库版本升级和结构迁移
 * - 提供完整的错误处理和日志记录
 * - 优化查询性能和内存使用
 */

import { relationalStore } from '@kit.ArkData';
import { Constants } from '../components/Constants';
import { ChatMessage, AppSettings, ChatMessageMetadataUpdate, AIProvider, AIModel, Citation } from '../services/DataModels';
import { Conversation } from '../services/ConversationModels';
import { DatabaseError } from '../components/Errors';
import { TransactionManager } from '../services/TransactionManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG = 'DatabaseManager';

interface ProviderModelRecord {
  id?: string;
  name?: string;
  displayName?: string;
  maxTokens?: number;
  temperature?: number;
  supportsWebSearch?: boolean;
}

interface ProviderRecord {
  id?: string;
  name?: string;
  displayName?: string;
  apiUrl?: string;
  apiKey?: string;
  models?: ProviderModelRecord[];
  isActive?: boolean;
}

/**
 * 数据库管理器 - 单例模式
 * 负责应用所有数据的持久化存储和管理
 */
export class DatabaseManager {
  private static instance: DatabaseManager;
  private rdbStore: relationalStore.RdbStore | null = null;
  private transactionManager: TransactionManager | null = null;

  private constructor() {}

  /**
   * 获取数据库管理器单例实例
   * @returns DatabaseManager 数据库管理器实例
   */
  static getInstance(): DatabaseManager {
    if (!DatabaseManager.instance) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  /**
   * 初始化数据库连接和配置
   * @param context 应用上下文
   * @throws DatabaseError 数据库初始化失败时抛出
   */
  async initDatabase(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: Constants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S2, // 提升安全级别
      encrypt: true // 启用数据库加密
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      this.transactionManager = new TransactionManager(this.rdbStore);
      await this.createTables();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize database: %{public}s', String(error));
      throw new DatabaseError(`Failed to initialize database: ${error}`);
    }
  }

  /**
   * 创建所有必要的数据表
   * @private
   * @throws DatabaseError 表创建失败时抛出
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
        provider_name TEXT,
        provider_message_id TEXT,
        provider_created_at INTEGER,
        system_fingerprint TEXT,
        citations_json TEXT,
        metadata TEXT
      )
    `;

    // 创建对话表
    const createConversationTable = `
      CREATE TABLE IF NOT EXISTS conversations (
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
        active_model_id TEXT,
        enable_web_search INTEGER DEFAULT 0
      )
    `;

    // 创建索引以优化查询性能
    const createChatIndexes = [
      `CREATE INDEX IF NOT EXISTS idx_messages_conv_ts ON ${Constants.CHAT_TABLE}(conversation_id, timestamp)`,
      `CREATE INDEX IF NOT EXISTS idx_messages_provider_msg_id ON ${Constants.CHAT_TABLE}(provider_message_id)`,
      `CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON ${Constants.CHAT_TABLE}(timestamp)`
    ];

    const createConversationIndexes = [
      `CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at)`,
      `CREATE INDEX IF NOT EXISTS idx_conversations_active ON conversations(is_active)`
    ];

    try {
      await this.rdbStore.executeSql(createChatTable);
      await this.rdbStore.executeSql(createConversationTable);
      await this.rdbStore.executeSql(createSettingsTable);

      // 兼容旧版本表结构：补充 messages.citations_json 列
      try {
        await this.rdbStore.executeSql(`ALTER TABLE ${Constants.CHAT_TABLE} ADD COLUMN citations_json TEXT`);
      } catch (e) {
        // 若已存在则忽略
      }

      // 兼容旧版本表结构：补充 messages.metadata 列（用于工具调用）
      try {
        await this.rdbStore.executeSql(`ALTER TABLE ${Constants.CHAT_TABLE} ADD COLUMN metadata TEXT`);
      } catch (e3) {
        // 若已存在则忽略
      }

      // 兼容旧版本设置表结构：补充 settings.enable_web_search 列
      try {
        await this.rdbStore.executeSql(`ALTER TABLE ${Constants.SETTINGS_TABLE} ADD COLUMN enable_web_search INTEGER DEFAULT 0`);
      } catch (e2) {
        // Column may already exist
      }

      // 创建索引
      for (const indexSql of createChatIndexes) {
        await this.rdbStore.executeSql(indexSql);
      }
      for (const indexSql of createConversationIndexes) {
        await this.rdbStore.executeSql(indexSql);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to create tables: %{public}s', String(error));
      throw new DatabaseError(`Failed to create tables: ${error}`);
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
      'provider_name': message.providerName || null,
      'provider_message_id': message.providerMessageId || null,
      'provider_created_at': message.providerCreatedAt !== undefined ? message.providerCreatedAt : null,
      'system_fingerprint': message.systemFingerprint || null,
      'citations_json': message.citations && message.citations.length > 0 ? JSON.stringify(message.citations) : null,
      'metadata': message.metadata || null
    };

    try {
      const rowId = await this.rdbStore.insert(Constants.CHAT_TABLE, valueBucket);
      return rowId;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to insert chat message: %{public}s', String(error));
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
      if (rowsAffected === 0) {
        throw new DatabaseError(`No message found with ID: ${messageId}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update chat message: %{public}s', String(error));
      throw new DatabaseError(`Failed to update chat message: ${error}`);
    }
  }

  /**
   * 更新聊天消息的元数据
   */
  async updateChatMessageMetadata(messageId: number, metadata: ChatMessageMetadataUpdate): Promise<void> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

  const valueBucket: relationalStore.ValuesBucket = {};

    if (metadata.timestamp !== undefined) {
      valueBucket['timestamp'] = metadata.timestamp;
    }
    if (metadata.providerMessageId !== undefined) {
      valueBucket['provider_message_id'] = metadata.providerMessageId;
    }
    if (metadata.providerCreatedAt !== undefined) {
      valueBucket['provider_created_at'] = metadata.providerCreatedAt;
    }
    if (metadata.systemFingerprint !== undefined) {
      valueBucket['system_fingerprint'] = metadata.systemFingerprint;
    }
    if (metadata.modelName !== undefined) {
      valueBucket['model_name'] = metadata.modelName;
    }
    if (metadata.providerName !== undefined) {
      valueBucket['provider_name'] = metadata.providerName;
    }
    if (metadata.citations !== undefined) {
      valueBucket['citations_json'] = metadata.citations ? JSON.stringify(metadata.citations) : null;
    }

    if (Object.keys(valueBucket).length === 0) {
      return;
    }

    const predicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
    predicates.equalTo('id', messageId);

    try {
      const rowsAffected = await this.rdbStore.update(valueBucket, predicates);
      if (rowsAffected === 0) {
        throw new DatabaseError(`No message found with ID: ${messageId}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update chat message metadata: %{public}s', String(error));
      throw new DatabaseError(`Failed to update chat message metadata: ${error}`);
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
      .notEqualTo('role', 'tool')  // 🔥 过滤掉tool消息，不加载到前端显示
      .orderByAsc('timestamp')
      .limitAs(limit);

    try {
      const resultSet = await this.rdbStore.query(predicates);
      const messages: ChatMessage[] = [];

      if (resultSet.goToFirstRow()) {
        const contentIndex = resultSet.getColumnIndex('content');
        const roleIndex = resultSet.getColumnIndex('role');
        const conversationIdIndex = resultSet.getColumnIndex('conversation_id');
        const modelNameIndex = resultSet.getColumnIndex('model_name');
        const providerNameIndex = resultSet.getColumnIndex('provider_name');
        const providerMessageIdIndex = resultSet.getColumnIndex('provider_message_id');
        const providerCreatedAtIndex = resultSet.getColumnIndex('provider_created_at');
        const systemFingerprintIndex = resultSet.getColumnIndex('system_fingerprint');
        const timestampIndex = resultSet.getColumnIndex('timestamp');
        const citationsIndex = resultSet.getColumnIndex('citations_json');
        const metadataIndex = resultSet.getColumnIndex('metadata');
        const idIndex = resultSet.getColumnIndex('id');

        do {
          const content = resultSet.getString(contentIndex);
          const role = resultSet.getString(roleIndex) as 'user' | 'assistant' | 'tool';
          const conversationId = resultSet.getString(conversationIdIndex);
          const modelName = resultSet.isColumnNull(modelNameIndex) ? undefined : resultSet.getString(modelNameIndex);
          const providerName = resultSet.isColumnNull(providerNameIndex) ? undefined : resultSet.getString(providerNameIndex);
          const providerMessageId = resultSet.isColumnNull(providerMessageIdIndex) ? undefined : resultSet.getString(providerMessageIdIndex);
          const providerCreatedAt = resultSet.isColumnNull(providerCreatedAtIndex) ? undefined : resultSet.getLong(providerCreatedAtIndex);
          const systemFingerprint = resultSet.isColumnNull(systemFingerprintIndex) ? undefined : resultSet.getString(systemFingerprintIndex);
          const timestampValue = resultSet.getLong(timestampIndex);
          const metadata = (metadataIndex >= 0 && !resultSet.isColumnNull(metadataIndex)) ? resultSet.getString(metadataIndex) : undefined;

          let citations: Citation[] | undefined = undefined;
          if (citationsIndex >= 0 && !resultSet.isColumnNull(citationsIndex)) {
            const json = resultSet.getString(citationsIndex);
            try {
              const parsed = JSON.parse(json) as Citation[];
              if (Array.isArray(parsed)) {
                citations = parsed;
              }
            } catch {}
          }

          const message = new ChatMessage(content, role, {
            conversationId,
            modelName,
            providerName,
            timestamp: timestampValue,
            providerMessageId,
            providerCreatedAt,
            systemFingerprint,
            citations
          });
          message.id = resultSet.getLong(idIndex);
          if (metadata) {
            message.metadata = metadata;
          }
          messages.push(message);
        } while (resultSet.goToNextRow());
      }

      resultSet.close();
      return messages;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get chat messages: %{public}s', String(error));
      throw new DatabaseError(`Failed to get chat messages: ${error}`);
    }
  }

  /**
   * 批量获取对话消息数量
   */
  async getConversationMessageCounts(conversationIds?: string[]): Promise<Record<string, number>> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const params: Array<string> = [];
    let sql = `SELECT conversation_id, COUNT(*) AS message_count FROM ${Constants.CHAT_TABLE}`;

    if (conversationIds && conversationIds.length > 0) {
      const placeholders = conversationIds.map(() => '?').join(', ');
      sql += ` WHERE conversation_id IN (${placeholders})`;
      params.push(...conversationIds);
    }

    sql += ' GROUP BY conversation_id';

    try {
      const resultSet = await this.rdbStore.querySql(sql, params);
      const counts: Record<string, number> = {};

      if (resultSet.goToFirstRow()) {
        const conversationIdIndex = resultSet.getColumnIndex('conversation_id');
        const messageCountIndex = resultSet.getColumnIndex('message_count');

        do {
          const conversationId = resultSet.getString(conversationIdIndex);
          const count = resultSet.getLong(messageCountIndex);
          counts[conversationId] = count;
        } while (resultSet.goToNextRow());
      }

      resultSet.close();
      return counts;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to query conversation message counts: %{public}s', String(error));
      throw new DatabaseError(`Failed to query conversation message counts: ${error}`);
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
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear chat history: %{public}s', String(error));
      throw new DatabaseError(`Failed to clear chat history: ${error}`);
    }
  }

  // /**
  //  * 清空所有对话及聊天记录
  //  */
  // async clearAllConversations(): Promise<void> {
  //   if (!this.rdbStore) {
  //     throw new DatabaseError('Database not initialized');
  //   }
  //
  //   try {
  //     await this.rdbStore.executeSql(`DELETE FROM ${Constants.CHAT_TABLE}`);
  //     await this.rdbStore.executeSql('DELETE FROM conversations');
  //     console.info('All conversations and chat history cleared');
  //   } catch (error) {
  //     console.error('Failed to clear all conversations:', error);
  //     throw new DatabaseError(`Failed to clear all conversations: ${error}`);
  //   }
  // }

  /**
   * 🔥 清理所有tool类型的消息（修复历史数据）
   * 这些消息不应该被保存到数据库，仅在内存中使用
   */
  async cleanupToolMessages(): Promise<number> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
    predicates.equalTo('role', 'tool');

    try {
      const deletedCount = await this.rdbStore.delete(predicates);
      return deletedCount;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to cleanup tool messages: %{public}s', String(error));
      throw new DatabaseError(`Failed to cleanup tool messages: ${error}`);
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
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete message: %{public}s', String(error));
      throw new DatabaseError(`Failed to delete message: ${error}`);
    }
  }

  /**
   * 保存应用设置
   * 使用事务保证原子性，防止配置丢失
   */
  async saveSettings(settings: AppSettings): Promise<void> {
    if (!this.rdbStore || !this.transactionManager) {
      throw new DatabaseError('Database not initialized');
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'api_url': settings.apiUrl,
      'api_key': settings.apiKey,
      'model_name': settings.modelName,
      'providers_data': JSON.stringify(settings.providers ?? []),
      'active_provider_id': settings.activeProviderId ?? '',
      'active_model_id': settings.activeModelId ?? '',
      'enable_web_search': settings.enableWebSearch ? 1 : 0
    };

    try {
      await this.transactionManager.executeInTransaction(async () => {
        // 尝试更新现有设置（而不是删除后插入）
        const predicates = new relationalStore.RdbPredicates(Constants.SETTINGS_TABLE);
        const updated = await this.rdbStore!.update(valueBucket, predicates);

        // 如果没有现有记录，则插入新记录
        if (updated === 0) {
          await this.rdbStore!.insert(Constants.SETTINGS_TABLE, valueBucket);
          hilog.info(DOMAIN, TAG, 'Settings inserted successfully');
        } else {
          hilog.info(DOMAIN, TAG, 'Settings updated successfully');
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save settings: %{public}s', String(error));
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

      if (resultSet.goToFirstRow()) {
        const resolvedSettings = new AppSettings(
          resultSet.getString(resultSet.getColumnIndex('api_url')),
          resultSet.getString(resultSet.getColumnIndex('api_key')),
          resultSet.getString(resultSet.getColumnIndex('model_name'))
        );
        resolvedSettings.id = resultSet.getLong(resultSet.getColumnIndex('id'));

        const providersDataIndex = resultSet.getColumnIndex('providers_data');
        const activeProviderIdIndex = resultSet.getColumnIndex('active_provider_id');
        const activeModelIdIndex = resultSet.getColumnIndex('active_model_id');
        const enableWebSearchIndex = resultSet.getColumnIndex('enable_web_search');

        if (providersDataIndex < 0) {
          hilog.warn(DOMAIN, TAG, 'Settings record missing providers_data column; using legacy configuration');
          resultSet.close();
          return null;
        }

        const providersJson = resultSet.isColumnNull(providersDataIndex)
          ? ''
          : resultSet.getString(providersDataIndex);
        const hydratedProviders = this.parseProvidersJson(providersJson);

        if (hydratedProviders.length === 0) {
          hilog.warn(DOMAIN, TAG, 'Settings record contains no valid providers; treating as unconfigured');
          resultSet.close();
          return null;
        }

        resolvedSettings.providers = hydratedProviders;

        if (activeProviderIdIndex >= 0 && !resultSet.isColumnNull(activeProviderIdIndex)) {
          resolvedSettings.activeProviderId = resultSet.getString(activeProviderIdIndex) ?? '';
        } else {
          resolvedSettings.activeProviderId = '';
        }

        if (activeModelIdIndex >= 0 && !resultSet.isColumnNull(activeModelIdIndex)) {
          resolvedSettings.activeModelId = resultSet.getString(activeModelIdIndex) ?? '';
        } else {
          resolvedSettings.activeModelId = '';
        }

        const activeProvider = resolvedSettings.providers.find(provider => provider.id === resolvedSettings.activeProviderId)
          ?? resolvedSettings.providers[0];
          resolvedSettings.activeProviderId = activeProvider.id;

        let activeModel: AIModel | undefined;
        if (activeProvider.models.length > 0) {
          activeModel = activeProvider.models.find(model => model.id === resolvedSettings.activeModelId) ?? activeProvider.models[0];
          resolvedSettings.activeModelId = activeModel.id;
          resolvedSettings.modelName = activeModel.name;
        } else {
          resolvedSettings.activeModelId = '';
          resolvedSettings.modelName = '';
        }

        resolvedSettings.apiUrl = activeProvider.apiUrl;
        resolvedSettings.apiKey = activeProvider.apiKey;

        // 读取 enable_web_search（若缺失则默认为 false）
        if (enableWebSearchIndex >= 0 && !resultSet.isColumnNull(enableWebSearchIndex)) {
          const flag = resultSet.getLong(enableWebSearchIndex);
          resolvedSettings.enableWebSearch = flag === 1;
        } else {
          resolvedSettings.enableWebSearch = false;
        }

        settings = resolvedSettings;
      }

      resultSet.close();
      return settings;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get settings: %{public}s', String(error));
      throw new DatabaseError(`Failed to get settings: ${error}`);
    }
  }

  /**
   * 获取所有对话，按更新时间倒序排列
   */
  async getAllConversations(): Promise<Conversation[]> {
    if (!this.rdbStore) {
      throw new DatabaseError('Database not initialized');
    }

    const predicates = new relationalStore.RdbPredicates('conversations');
    predicates.orderByDesc('updated_at');

    try {
      const resultSet = await this.rdbStore.query(predicates);
      const conversations: Conversation[] = [];

      if (resultSet.goToFirstRow()) {
        const idIndex = resultSet.getColumnIndex('id');
        const titleIndex = resultSet.getColumnIndex('title');
        const createdAtIndex = resultSet.getColumnIndex('created_at');
        const updatedAtIndex = resultSet.getColumnIndex('updated_at');
        const messageCountIndex = resultSet.getColumnIndex('message_count');
        const isActiveIndex = resultSet.getColumnIndex('is_active');

        do {
          const conversation = new Conversation();
          conversation.id = resultSet.getString(idIndex);
          conversation.title = resultSet.getString(titleIndex);
          conversation.createdAt = resultSet.getLong(createdAtIndex);
          conversation.updatedAt = resultSet.getLong(updatedAtIndex);
          conversation.messageCount = resultSet.getLong(messageCountIndex);
          conversation.isActive = resultSet.getLong(isActiveIndex) === 1;
          conversations.push(conversation);
        } while (resultSet.goToNextRow());
      }

      resultSet.close();
      return conversations;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get conversations: %{public}s', String(error));
      throw new DatabaseError(`Failed to get conversations: ${error}`);
    }
  }

  /**
   * 删除对话及其所有消息
   * 使用事务保证原子性
   */
  async deleteConversation(conversationId: string): Promise<void> {
    if (!this.rdbStore || !this.transactionManager) {
      throw new DatabaseError('Database not initialized');
    }

    try {
      await this.transactionManager.executeInTransaction(async () => {
        // 删除所有相关消息
        const messagePredicates = new relationalStore.RdbPredicates(Constants.CHAT_TABLE);
        messagePredicates.equalTo('conversation_id', conversationId);
        await this.rdbStore!.delete(messagePredicates);

        // 删除对话记录
        const conversationPredicates = new relationalStore.RdbPredicates('conversations');
        conversationPredicates.equalTo('id', conversationId);
        await this.rdbStore!.delete(conversationPredicates);

        hilog.info(DOMAIN, TAG, 'Conversation deleted successfully: %{public}s', conversationId);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete conversation: %{public}s', String(error));
      throw new DatabaseError(`Failed to delete conversation: ${error}`);
    }
  }

  /**
   * 更新对话消息计数
   * 使用事务保证查询和更新的原子性
   */
  async updateConversationMessageCount(conversationId: string): Promise<void> {
    if (!this.rdbStore || !this.transactionManager) {
      throw new DatabaseError('Database not initialized');
    }

    try {
      await this.transactionManager.executeInTransaction(async () => {
        // 在事务中查询消息数（这样可以避免在查询和更新之间消息被修改）
        const countSql = `SELECT COUNT(*) as message_count FROM ${Constants.CHAT_TABLE} WHERE conversation_id = ?`;
        const resultSet = await this.rdbStore!.querySql(countSql, [conversationId]);

        let messageCount = 0;
        if (resultSet.goToFirstRow()) {
          messageCount = resultSet.getLong(resultSet.getColumnIndex('message_count'));
        }
        resultSet.close();

        // 更新对话的消息计数
        const valueBucket: relationalStore.ValuesBucket = {
          'message_count': messageCount,
          'updated_at': Date.now()
        };

        const predicates = new relationalStore.RdbPredicates('conversations');
        predicates.equalTo('id', conversationId);
        await this.rdbStore!.update(valueBucket, predicates);

        hilog.info(DOMAIN, TAG, 'Conversation message count updated: conversationId=%{public}s, count=%{public}d',
          conversationId, messageCount);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update conversation message count: %{public}s', String(error));
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
      await this.rdbStore.insert('conversations', valueBucket);
      return conversation;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to create conversation: %{public}s', String(error));
      throw new DatabaseError(`Failed to create conversation: ${error}`);
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

    const predicates = new relationalStore.RdbPredicates('conversations');
    predicates.equalTo('id', conversationId);

    try {
      await this.rdbStore.update(valueBucket, predicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update conversation title: %{public}s', String(error));
      throw new DatabaseError(`Failed to update conversation title: ${error}`);
    }
  }

  /**
   * 生成唯一ID
   */
  private generateId(): string {
    return Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
  }

  private parseProvidersJson(providersJson: string | undefined): AIProvider[] {
    if (!providersJson || providersJson.trim().length === 0) {
      return [];
    }

    let parsedValue: ProviderRecord[];
    try {
      const parsed = JSON.parse(providersJson) as ProviderRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      parsedValue = parsed;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to parse providers data: %{public}s', String(error));
      return [];
    }

    const providers: AIProvider[] = [];
    for (const record of parsedValue) {
      const provider = this.hydrateProvider(record);
      if (provider) {
        providers.push(provider);
      }
    }
    return providers;
  }

  private hydrateModel(raw: ProviderModelRecord | null | undefined): AIModel | null {
    if (!raw) {
      return null;
    }

    const idSource = raw.id;
    const nameSource = raw.name;
    const displayNameSource = raw.displayName;
    const maxTokensSource = raw.maxTokens;
    const temperatureSource = raw.temperature;
    const supportsWebSearchSource = raw.supportsWebSearch;

    const id = typeof idSource === 'string' && idSource.trim().length > 0
      ? idSource
      : (typeof nameSource === 'string' && nameSource.trim().length > 0 ? nameSource : '');
    const name = typeof nameSource === 'string' && nameSource.trim().length > 0 ? nameSource : id;

    if (!id || !name) {
      return null;
    }

    const displayName = typeof displayNameSource === 'string' && displayNameSource.trim().length > 0
      ? displayNameSource
      : name;

    const maxTokensNumber = Number(maxTokensSource);
    const maxTokens = Number.isFinite(maxTokensNumber) && maxTokensNumber > 0 ? maxTokensNumber : 4096;

    const temperatureNumber = Number(temperatureSource);
    const temperature = Number.isFinite(temperatureNumber) ? temperatureNumber : 0.7;

    const supportsWebSearch = Boolean(supportsWebSearchSource);

    return new AIModel(id, name, displayName, maxTokens, temperature, supportsWebSearch);
  }

  private hydrateProvider(raw: ProviderRecord | null | undefined): AIProvider | null {
    if (!raw) {
      return null;
    }

    const idSource = raw.id;
    const nameSource = raw.name;
    const displayNameSource = raw.displayName;
    const apiUrlSource = raw.apiUrl;
    const apiKeySource = raw.apiKey;
    const modelsSource = raw.models;
    const isActiveSource = raw.isActive;

    const id = typeof idSource === 'string' && idSource.trim().length > 0 ? idSource : '';
    const name = typeof nameSource === 'string' && nameSource.trim().length > 0 ? nameSource : '';
    const displayName = typeof displayNameSource === 'string' && displayNameSource.trim().length > 0
      ? displayNameSource
      : (name || id);
    const apiUrl = typeof apiUrlSource === 'string' && apiUrlSource.trim().length > 0 ? apiUrlSource : '';
    const apiKey = typeof apiKeySource === 'string' ? apiKeySource : '';

    if (!id || !name || !displayName || !apiUrl) {
      return null;
    }

    const provider = new AIProvider(id, name, displayName, apiUrl, apiKey);
    provider.isActive = Boolean(isActiveSource);

    const hydratedModels: AIModel[] = [];
    if (Array.isArray(modelsSource)) {
      for (const modelRecord of modelsSource) {
        const hydratedModel = this.hydrateModel(modelRecord);
        if (hydratedModel) {
          hydratedModels.push(hydratedModel);
        }
      }
    }

    provider.models = hydratedModels;

    return provider;
  }
}
