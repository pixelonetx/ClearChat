/**
 * 聊天消息实体类
 */
export interface ChatMessageInit {
  conversationId?: string;
  modelName?: string;
  providerName?: string;
  timestamp?: number;
  providerMessageId?: string;
  providerCreatedAt?: number;
  systemFingerprint?: string;
}

export class ChatMessage {
  id?: number;
  content: string;
  role: 'user' | 'assistant'; // user: 用户消息, assistant: AI回复
  timestamp: number;
  conversationId: string;
  // 新增：AI消息的模型信息
  modelName?: string; // 使用的模型名称
  providerName?: string; // 使用的服务商名称
  providerMessageId?: string; // AI服务返回的消息ID
  providerCreatedAt?: number; // AI服务返回的创建时间（秒）
  systemFingerprint?: string; // AI服务返回的系统指纹

  constructor(content: string, role: 'user' | 'assistant', init?: ChatMessageInit) {
    this.content = content;
    this.role = role;
    this.timestamp = init?.timestamp ?? Date.now();
    this.conversationId = init?.conversationId ?? 'default';
    this.modelName = init?.modelName;
    this.providerName = init?.providerName;
    this.providerMessageId = init?.providerMessageId;
    this.providerCreatedAt = init?.providerCreatedAt;
    this.systemFingerprint = init?.systemFingerprint;
  }
}

export interface ChatMessageMetadataUpdate {
  timestamp?: number;
  providerMessageId?: string | null;
  providerCreatedAt?: number | null;
  systemFingerprint?: string | null;
  modelName?: string | null;
  providerName?: string | null;
}

/**
 * AI模型配置
 */
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
}

/**
 * AI服务商配置
 */
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
}

/**
 * 应用设置实体类
 */
export class AppSettings {
  id?: number;
  apiUrl: string;
  apiKey: string;
  modelName: string;
  // 新增字段，保持向后兼容
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
}

/**
 * 消息接口
 */
export interface MessageInterface {
  role: string;
  content: string;
}

/**
 * 请求消息接口
 */
export interface RequestMessage {
  role: string;
  content: string;
}

/**
 * 聊天请求体接口
 */
export interface ChatRequestBody {
  model: string;
  messages: RequestMessage[];
  stream: boolean;
  max_tokens: number;
  temperature: number;
}

/**
 * 选择项接口
 */
export interface ChoiceInterface {
  index: number;
  message: MessageInterface;
  finish_reason: string;
}

/**
 * 使用情况接口
 */
export interface UsageInterface {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
}

/**
 * API请求实体类
 */
export interface ChatRequest {
  model: string;
  messages: Array<MessageInterface>;
  max_tokens?: number;
  temperature?: number;
  stream?: boolean;
}

/**
 * API响应实体类
 */
export interface ChatResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: Array<ChoiceInterface>;
  usage: UsageInterface;
}

/**
 * 流式响应的Delta接口
 */
export interface ReasoningContentItem {
  type?: string;
  text?: string;
}

export type ReasoningContent = string | Array<ReasoningContentItem | string>;

export interface StreamDelta {
  content?: string;
  role?: string;
  reasoning_content?: ReasoningContent;  // 支持推理内容
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
  onMetadata?: (metadata: StreamMetadata) => void;
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
  system_fingerprint?: string;
}

export interface StreamMetadata {
  id?: string;
  created?: number;
  model?: string;
  systemFingerprint?: string;
  choiceIndex?: number;
  finishReason?: string;
}
