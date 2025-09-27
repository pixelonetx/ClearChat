// 常量定义
interface DatabaseConstants {
  DB_NAME: string;
  CHAT_TABLE: string;
  CONVERSATION_TABLE: string;
  SETTINGS_TABLE: string;
}

export const Constants: DatabaseConstants = {
  DB_NAME: 'clearchat.db',
  CHAT_TABLE: 'chat_messages',
  CONVERSATION_TABLE: 'conversations',
  SETTINGS_TABLE: 'app_settings'
};

// 自定义数据库异常
export class DatabaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DatabaseError';
  }
}

// 对话实体
export interface ConversationRecord {
  id?: string | number;
  title?: string;
  created_at?: number | string;
  updated_at?: number | string;
  message_count?: number | string;
  is_active?: number | string;
}

export class Conversation {
  id: string = '';
  title: string = '';
  createdAt: number = Date.now();
  updatedAt: number = Date.now();
  messageCount: number = 0;
  isActive: boolean = false;

  static fromRecord(record: ConversationRecord): Conversation {
    const conversation = new Conversation();
    conversation.id = String(record.id ?? '');
    conversation.title = String(record.title ?? '');
    conversation.createdAt = Number(record.created_at ?? Date.now());
    conversation.updatedAt = Number(record.updated_at ?? Date.now());
    conversation.messageCount = Number(record.message_count ?? 0);
    conversation.isActive = Number(record.is_active ?? 0) === 1;
    return conversation;
  }
}

// 聊天消息实体类
export class ChatMessage {
  id?: number;
  content: string;
  role: 'user' | 'assistant'; // user: 用户消息, assistant: AI回复
  timestamp: number;
  conversationId: string; // AI消息的模型信息
  modelName?: string; // 使用的模型名称
  providerName?: string; // 使用的服务商名称

  constructor(content: string, role: 'user' | 'assistant', conversationId: string = 'default', modelName?: string, providerName?: string) {
    this.content = content;
    this.role = role;
    this.timestamp = Date.now();
    this.conversationId = conversationId;
    this.modelName = modelName;
    this.providerName = providerName;
  }
}

// AI模型配置
export interface AIModelDTO {
  id?: string;
  name?: string;
  displayName?: string;
  maxTokens?: number;
  temperature?: number;
}

export interface SerializedAIModel {
  id: string;
  name: string;
  displayName: string;
  maxTokens: number;
  temperature: number;
}

export class AIModel {
  id: string;
  name: string;
  displayName: string;
  maxTokens: number;
  temperature: number;

  constructor(id: string, name: string, displayName: string, maxTokens: number = 4096, temperature: number = 0.7) {
    this.id = id;
    this.name = name;
    this.displayName = displayName;
    this.maxTokens = maxTokens;
    this.temperature = temperature;
  }

  static fromPlainObject(data: AIModelDTO): AIModel {
    const idValue = data.id ?? data.name ?? '';
    const nameValue = data.name ?? data.id ?? '';
    const displayNameValue = data.displayName ?? nameValue;
    const maxTokensValue = data.maxTokens ?? 4096;
    const temperatureValue = data.temperature ?? 0.7;

    return new AIModel(
      String(idValue),
      String(nameValue),
      String(displayNameValue),
      Number(maxTokensValue),
      Number(temperatureValue)
    );
  }

  toJSON(): SerializedAIModel {
    return {
      id: this.id,
      name: this.name,
      displayName: this.displayName,
      maxTokens: this.maxTokens,
      temperature: this.temperature
    };
  }
}

// AI服务商配置
export interface AIProviderDTO {
  id?: string;
  name?: string;
  displayName?: string;
  apiUrl?: string;
  apiKey?: string;
  isActive?: boolean | number;
  models?: Array<AIModelDTO>;
}

export interface SerializedAIProvider {
  id: string;
  name: string;
  displayName: string;
  apiUrl: string;
  apiKey: string;
  models: Array<SerializedAIModel>;
  isActive: boolean;
}

export class AIProvider {
  id: string;
  name: string;
  displayName: string;
  apiUrl: string;
  apiKey: string;
  models: AIModel[];
  isActive: boolean;

  constructor(id: string, name: string, displayName: string, apiUrl: string = '', apiKey: string = '') {
    this.id = id;
    this.name = name;
    this.displayName = displayName;
    this.apiUrl = apiUrl;
    this.apiKey = apiKey;
    this.models = [];
    this.isActive = false;
  }

  static fromPlainObject(data: AIProviderDTO): AIProvider {
    const provider = new AIProvider(
      String(data.id ?? ''),
      String(data.name ?? ''),
      String(data.displayName ?? data.name ?? ''),
      String(data.apiUrl ?? ''),
      String(data.apiKey ?? '')
    );
    const isActiveRaw = data.isActive;
    provider.isActive = typeof isActiveRaw === 'boolean' ? isActiveRaw : Boolean(isActiveRaw);

    const modelsData = data.models;
    if (modelsData && modelsData.length > 0) {
      provider.models = modelsData.map(model => AIModel.fromPlainObject(model));
    }

    return provider;
  }

  toJSON(): SerializedAIProvider {
    return {
      id: this.id,
      name: this.name,
      displayName: this.displayName,
      apiUrl: this.apiUrl,
      apiKey: this.apiKey,
      models: this.models.map(model => model.toJSON()),
      isActive: this.isActive
    };
  }
}

// 应用设置实体类
export interface SerializedAppSettings {
  id?: number;
  apiUrl: string;
  apiKey: string;
  modelName: string;
  providers: Array<SerializedAIProvider>;
  activeProviderId: string;
  activeModelId: string;
}

export class AppSettings {
  id?: number;
  apiUrl: string;
  apiKey: string;
  modelName: string;
  providers: AIProvider[];
  activeProviderId: string;
  activeModelId: string;

  constructor(apiUrl: string = '', apiKey: string = '', modelName: string = '') {
    this.apiUrl = apiUrl;
    this.apiKey = apiKey;
    this.modelName = modelName;
    this.providers = [];
    this.activeProviderId = '';
    this.activeModelId = '';
  }

  toJSON(): SerializedAppSettings {
    return {
      id: this.id,
      apiUrl: this.apiUrl,
      apiKey: this.apiKey,
      modelName: this.modelName,
      providers: this.providers.map(provider => provider.toJSON()),
      activeProviderId: this.activeProviderId,
      activeModelId: this.activeModelId
    };
  }
}

// 消息接口
export interface MessageInterface {
  role: string;
  content: string;
}

// 请求消息接口
export interface RequestMessage {
  role: string;
  content: string;
}

// 聊天请求体接口
export interface ChatRequestBody {
  model: string;
  messages: RequestMessage[];
  stream: boolean;
  max_tokens: number;
  temperature: number;
}

// 选择项接口
export interface ChoiceInterface {
  index: number;
  message: MessageInterface;
  finish_reason: string;
}

// 使用情况接口
export interface UsageInterface {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

// API请求实体类
export interface ChatRequest {
  model: string;
  messages: Array<MessageInterface>;
  max_tokens?: number;
  temperature?: number;
  stream?: boolean;
}

// API响应实体类
export interface ChatResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: Array<ChoiceInterface>;
  usage: UsageInterface;
}

// 流式响应的Delta接口
export interface StreamDelta {
  content?: string;
  role?: string;
  reasoning_content?: string;  // 支持推理内容
}

/**
 * 流式响应的选择项接口
 */
export interface StreamChoice {
  index: number;
  delta: StreamDelta;
  finish_reason?: string;
}

/**
 * 流式回调函数接口
 */
export interface StreamCallbacks {
  onData: (chunk: string) => void;
  onComplete: () => void;
  onError: (error: Error) => void;
}

/**
 * 流式响应接口
 */
export interface StreamResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: Array<StreamChoice>;
}
