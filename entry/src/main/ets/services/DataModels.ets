/**
 * DataModels - 数据模型定义
 * 
 * 功能说明：
 * - 定义应用中所有数据实体的结构和类型
 * - 包含聊天消息、AI模型、提供商、设置等核心数据模型
 * - 提供类型安全和数据验证
 * - 支持数据序列化和反序列化
 * 
 * 主要模型：
 * - ChatMessage: 聊天消息实体
 * - AIModel: AI模型配置
 * - AIProvider: AI服务提供商
 * - AppSettings: 应用设置
 * - Conversation: 对话会话
 * 
 * 设计原则：
 * - 强类型定义确保数据一致性
 * - 可选参数支持灵活配置
 * - 接口和类结合使用提供最佳实践
 */

/**
 * 聊天消息初始化参数接口
 * 用于创建ChatMessage实例时的可选配置
 */
export interface ChatMessageInit {
  /** 对话ID，默认为'default' */
  conversationId?: string;
  /** 使用的AI模型名称 */
  modelName?: string;
  /** AI服务提供商名称 */
  providerName?: string;
  /** 消息时间戳，默认为当前时间 */
  timestamp?: number;
  /** AI服务返回的消息ID */
  providerMessageId?: string;
  /** AI服务返回的创建时间（秒） */
  providerCreatedAt?: number;
  /** AI服务返回的系统指纹 */
  systemFingerprint?: string;
  /** 引用资料（如联网搜索返回的参考链接） */
  citations?: Citation[];
}

/**
 * 聊天消息实体类
 * 表示用户和AI之间的单条消息记录
 */
export class ChatMessage {
  /** 数据库主键ID */
  id?: number;
  /** 消息内容 */
  content: string;
  /** 消息角色：user(用户) | assistant(AI助手) | tool(工具结果) */
  role: 'user' | 'assistant' | 'tool';
  /** 消息时间戳 */
  timestamp: number;
  /** 所属对话ID */
  conversationId: string;
  /** 使用的AI模型名称 */
  modelName?: string;
  /** AI服务提供商名称 */
  providerName?: string;
  /** AI服务返回的消息ID */
  providerMessageId?: string;
  /** AI服务返回的创建时间（秒） */
  providerCreatedAt?: number;
  /** AI服务返回的系统指纹 */
  systemFingerprint?: string;
  /** 引用资料列表（用于展示与持久化） */
  citations?: Citation[];
  /** 元数据（用于存储工具调用等额外信息） */
  metadata?: string;

  /**
   * 构造函数
   * @param content 消息内容
   * @param role 消息角色
   * @param init 可选的初始化参数
   */
  constructor(content: string, role: 'user' | 'assistant' | 'tool', init?: ChatMessageInit) {
    this.content = content;
    this.role = role;
    this.timestamp = init?.timestamp ?? Date.now();
    this.conversationId = init?.conversationId ?? 'default';
    this.modelName = init?.modelName;
    this.providerName = init?.providerName;
    this.providerMessageId = init?.providerMessageId;
    this.providerCreatedAt = init?.providerCreatedAt;
    this.systemFingerprint = init?.systemFingerprint;
    this.citations = init?.citations;
  }
}

/**
 * 联网搜索引用条目
 */
export interface Citation {
  title?: string;
  url: string;
  snippet?: string;
  source?: string; // 额外来源标识（如引擎名/站点）
}

/**
 * 聊天消息元数据更新接口
 * 用于更新消息的附加信息，不包含核心内容
 */
export interface ChatMessageMetadataUpdate {
  /** 更新时间戳 */
  timestamp?: number;
  /** AI服务消息ID */
  providerMessageId?: string | null;
  /** AI服务创建时间 */
  providerCreatedAt?: number | null;
  /** 系统指纹 */
  systemFingerprint?: string | null;
  /** 模型名称 */
  modelName?: string | null;
  /** 提供商名称 */
  providerName?: string | null;
  /** 引用资料（JSON持久化） */
  citations?: Citation[] | null;
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
  /** 该模型是否支持内置联网搜索功能（如阿里云通义千问） */
  supportsWebSearch: boolean;

  constructor(id: string, name: string, displayName: string, maxTokens: number = 4096, temperature: number = 0.7, supportsWebSearch: boolean = false) {
    this.id = id;
    this.name = name;
    this.displayName = displayName;
    this.maxTokens = maxTokens;
    this.temperature = temperature;
    this.supportsWebSearch = supportsWebSearch;
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
  /** 是否启用联网搜索（对支持的提供商生效，如阿里云通义千问） */
  enableWebSearch?: boolean;

  constructor(apiUrl: string = '', apiKey: string = '', modelName: string = '') {
    this.apiUrl = apiUrl;
    this.apiKey = apiKey;
    this.modelName = modelName;
    this.providers = [];
    this.activeProviderId = '';
    this.activeModelId = '';
    this.enableWebSearch = false;
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
  // 供应商特定扩展字段（例如阿里云通义千问的联网搜索）
  enable_search?: boolean;
  // OpenAI 格式的工具定义（支持 function calling）
  tools?: object[];
}

/**
 * 联网搜索工具声明（用于供应商扩展字段）
 */
export interface WebSearchTool {
  type: 'web_search';
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

/**
 * 工具函数定义接口
 */
export interface ToolFunction {
  name?: string;
  arguments?: string;  // JSON string
}

/**
 * 工具调用接口（OpenAI Tool Calling 格式）
 */
export interface ToolCall {
  id?: string;
  type?: string;  // 通常是 'function'
  function?: ToolFunction;
  index?: number;  // 流式响应中的增量索引
}

export interface StreamDelta {
  content?: string;
  role?: string;
  reasoning_content?: ReasoningContent;  // 支持推理内容
  tool_calls?: ToolCall[];  // 支持工具调用
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
  citations?: Citation[]; // 承载供应商返回的引用信息
}

/**
 * 扩展：支持供应商在响应顶层返回引用
 */
export interface ExtendedStreamResponse extends StreamResponse {
  citations?: Citation[];
  references?: Citation[];
}

/**
 * 扩展：支持供应商在 delta 中返回引用
 */
export interface ExtendedStreamDelta extends StreamDelta {
  citations?: Citation[];
  references?: Citation[];
}

/**
 * 流式请求选项（例如：是否开启联网搜索）
 */
export interface StreamRequestOptions {
  enableWebSearch?: boolean;
}
