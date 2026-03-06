/**
 * ChatTypes.ets
 * 聊天模块类型定义
 * 
 * 职责：集中管理聊天相关的接口和类型定义
 */

import { ChatMessage, Citation, StreamMetadata } from '../services/DataModels';
import { Conversation } from '../services/ConversationModels';
import { ToolCallData, StreamEventEmitter } from '../services/StreamEventEmitter';
import { SearchResult } from '../services/search/SearchModels';
import { AbortController } from '../interfaces/AbortController';

/**
 * 模型信息接口
 */
export interface ModelInfo {
  modelName: string;
  providerName: string;
}

/**
 * 流式消息初始化结果
 */
export interface StreamingMessageResult {
  index: number;
  id: number;
}

/**
 * 搜索工具参数
 */
export interface SearchToolArgs {
  query: string;
  resultSize?: number;
}

/**
 * 搜索执行结果
 */
export interface SearchExecutionResult {
  result: SearchResult;
  citations: Citation[];
}

/**
 * 流式请求结果
 */
export interface StreamRequestResult {
  emitter: StreamEventEmitter;
  abortController: AbortController;
}

/**
 * 回调函数配置
 */
export interface ViewModelCallbacks {
  onStateChange?: () => void;
  onError?: (message: string) => void;
  onToast?: (message: string, duration?: number) => void;
}

/**
 * 可能可字符串化的对象
 */
export interface MaybeStringifiable {
  toString?: () => string;
}

/**
 * 响应信息
 */
export interface ResponseInfo {
  status?: number;
}

/**
 * 扩展错误类型
 */
export interface ExtendedError extends Error {
  code?: string | number;
  response?: ResponseInfo;
}

/**
 * 手势更新事件
 */
export interface PanUpdateEvent {
  offsetX: number;
}

/**
 * 聊天页面状态
 */
export interface ChatPageState {
  // UI 状态
  showControlButton: boolean;
  showSideBar: boolean;
  isSidebarVisible: boolean;
  sidebarOffset: number;
  backgroundBlurRadius: number;
  showModelSelectorSheet: boolean;
  customPopup: boolean;
  showScrollToBottomButton: boolean;
  shouldAutoScroll: boolean;
  
  // 数据状态
  messages: ChatMessage[];
  conversations: Conversation[];
  currentConversation: Conversation | null;
  inputText: string;
  
  // 应用状态
  isLoading: boolean;
  isGenerating: boolean;
  isInitialized: boolean;
  hasSettings: boolean;
  enableWebSearch: boolean;
  isSearching: boolean;
  searchQuery: string;
  searchResults: string;
}

/**
 * 聊天配置
 */
export interface ChatConfig {
  sidebarWidth: number;
  animationDuration: number;
  debounceDelay: number;
  maxMessageLength: number;
  maxHistoryMessages: number;
  requestTimeout: number;
}

/**
 * 默认聊天配置
 */
export const DEFAULT_CHAT_CONFIG: ChatConfig = {
  sidebarWidth: 300,
  animationDuration: 300,
  debounceDelay: 300,
  maxMessageLength: 10000,
  maxHistoryMessages: 10,
  requestTimeout: 60000
};

/**
 * Toast 配置
 */
export class ToastOptions {
  message: string;
  duration: number;

  constructor(message: string, duration: number = 2000) {
    this.message = message;
    this.duration = duration;
  }
}

/**
 * 错误消息映射
 */
export const ERROR_MESSAGES: Record<string, string> = {
  'timeout': '请求超时，请稍后重试',
  'network': '网络连接失败，请检查网络设置',
  'unauthorized': 'API密钥无效，请检查设置',
  'rate_limit': '请求过于频繁，请稍后再试',
  'model_not_found': '模型不可用，请检查模型ID',
  'ssl': 'SSL连接失败，请检查网络或证书配置',
  'content_filter': '消息内容不符合规范，请修改后重试',
  'quota': 'API配额不足，请检查账户余额',
  'service_unavailable': 'AI服务暂时不可用，请稍后重试',
  'default': '发送消息失败'
};

/**
 * 问候语列表
 */
export const GREETINGS: string[] = [
  '你好', 'hello', 'hi', '您好', '在吗', 
  '在不在', '早上好', '晚上好', '下午好'
];
