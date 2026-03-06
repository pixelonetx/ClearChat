/**
 * ChatUtils.ets
 * 聊天模块工具函数
 * 
 * 职责：提供聊天相关的纯函数工具
 */

import { ChatMessage } from '../services/DataModels';
import { 
  MaybeStringifiable, 
  ExtendedError, 
  ERROR_MESSAGES,
  GREETINGS 
} from './ChatTypes';

/**
 * 带有更新时间的对象接口
 */
export interface HasUpdatedAt {
  updatedAt: number;
}

/**
 * 克隆聊天消息
 * @param message 原始消息
 * @returns 克隆的消息对象
 */
export function cloneChatMessage(message: ChatMessage): ChatMessage {
  const clone = new ChatMessage(message.content, message.role, {
    conversationId: message.conversationId,
    modelName: message.modelName,
    providerName: message.providerName,
    timestamp: message.timestamp,
    providerMessageId: message.providerMessageId,
    providerCreatedAt: message.providerCreatedAt,
    systemFingerprint: message.systemFingerprint,
    toolCallId: message.toolCallId,
    toolCalls: message.toolCalls
  });
  clone.id = message.id;
  return clone;
}

/**
 * 获取用户友好的错误消息
 * @param error 原始错误
 * @returns 友好的错误消息
 */
export function getFriendlyErrorMessage(error: Error | null | undefined): string {
  if (!error) {
    return ERROR_MESSAGES['default'];
  }

  let rawMessage = (error.message ?? '').trim();

  if (!rawMessage) {
    const stringifiable = error as MaybeStringifiable;
    if (stringifiable.toString) {
      rawMessage = stringifiable.toString().trim();
    }
  }

  if (!rawMessage || rawMessage === '[object Object]') {
    const extendedError = error as ExtendedError;
    if (extendedError.name) {
      rawMessage = extendedError.name;
    } else if (extendedError.code) {
      rawMessage = `错误代码: ${extendedError.code}`;
    } else if (extendedError.response?.status) {
      rawMessage = `HTTP ${extendedError.response.status}`;
    }
  }

  if (!rawMessage || rawMessage === '[object Object]') {
    return ERROR_MESSAGES['default'];
  }

  const normalized = rawMessage.toLowerCase();

  // 错误类型匹配
  if (normalized.includes('timeout') || rawMessage.includes('超时')) {
    return ERROR_MESSAGES['timeout'];
  }

  if (normalized.includes('network') || normalized.includes('connection') || 
      normalized.includes('fetch') || rawMessage.includes('网络')) {
    return ERROR_MESSAGES['network'];
  }

  if (normalized.includes('unauthorized') || normalized.includes('forbidden') ||
      normalized.includes('invalid api key') || normalized.includes('401') || 
      normalized.includes('403') || rawMessage.includes('授权') || rawMessage.includes('认证')) {
    return ERROR_MESSAGES['unauthorized'];
  }

  if (normalized.includes('rate limit') || normalized.includes('too many')) {
    return ERROR_MESSAGES['rate_limit'];
  }

  if (normalized.includes('model') && (normalized.includes('not found') || 
      normalized.includes('does not exist') || normalized.includes('unknown'))) {
    return ERROR_MESSAGES['model_not_found'];
  }

  if (normalized.includes('ssl') || normalized.includes('certificate')) {
    return ERROR_MESSAGES['ssl'];
  }

  if (normalized.includes('content_filter') || normalized.includes('content policy') ||
      rawMessage.includes('内容过滤') || rawMessage.includes('违规')) {
    return ERROR_MESSAGES['content_filter'];
  }

  if (normalized.includes('quota') || normalized.includes('insufficient') ||
      rawMessage.includes('配额') || rawMessage.includes('余额')) {
    return ERROR_MESSAGES['quota'];
  }

  if (normalized.includes('service unavailable') || normalized.includes('502') ||
      normalized.includes('503') || rawMessage.includes('服务不可用')) {
    return ERROR_MESSAGES['service_unavailable'];
  }

  return `发送失败：${rawMessage}`;
}

/**
 * 检查内容是否包含可疑内容
 * @param content 内容
 * @returns 是否包含可疑内容
 */
export function containsSuspiciousContent(content: string): boolean {
  // 基础检查 - 可根据需求扩展
  const suspiciousPatterns = [
    /<script\b[^>]*>/i,
    /javascript:/i,
    /on\w+\s*=/i
  ];
  
  return suspiciousPatterns.some(pattern => pattern.test(content));
}

/**
 * 判断是否应该生成标题
 * @param messages 消息列表
 * @param currentTitle 当前标题
 * @returns 是否应该生成标题
 */
export function shouldGenerateTitle(messages: ChatMessage[], currentTitle: string): boolean {
  // 如果已经有自定义标题，不再生成
  if (currentTitle !== '新对话') {
    return false;
  }

  // 至少需要4条消息（2轮对话）
  if (messages.length < 4) {
    return false;
  }

  let userMessageCount = 0;
  let aiMessageCount = 0;
  let totalUserChars = 0;
  let totalAiChars = 0;
  let firstUserMessage: string | undefined;

  for (const msg of messages) {
    if (msg.role === 'user') {
      userMessageCount++;
      totalUserChars += msg.content.length;
      if (!firstUserMessage) {
        firstUserMessage = msg.content.toLowerCase().trim();
      }
    } else if (msg.role === 'assistant') {
      aiMessageCount++;
      totalAiChars += msg.content.length;
    }
  }

  // 检查是否是简单问候语
  if (firstUserMessage && GREETINGS.some(greeting =>
    firstUserMessage!.includes(greeting.toLowerCase()) && firstUserMessage!.length <= 10)) {
    
    if (totalAiChars >= 50) {
      return true;
    }
    return messages.length >= 6 && (totalUserChars >= 20 || totalAiChars >= 100);
  }

  if (totalUserChars >= 10 || totalAiChars >= 30) {
    return true;
  }

  return (totalUserChars + totalAiChars) >= 25;
}

/**
 * 格式化时间戳为日期分组
 * @param timestamp 时间戳
 * @returns 分组名称
 */
export function formatDateGroup(timestamp: number): string {
  const now = new Date();
  const date = new Date(timestamp);
  const diffDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));
  
  if (diffDays === 0) {
    return '今天';
  } else if (diffDays === 1) {
    return '昨天';
  } else if (diffDays <= 7) {
    return '最近7天';
  } else if (diffDays <= 30) {
    return '最近30天';
  } else {
    return '更早';
  }
}

/**
 * 按日期分组对话
 * @param conversations 对话列表
 * @returns 分组后的对话
 */
export function groupConversationsByDate(
  conversations: HasUpdatedAt[]
): Record<string, HasUpdatedAt[]> {
  const groups: Record<string, HasUpdatedAt[]> = {};
  
  for (const conv of conversations) {
    const group = formatDateGroup(conv.updatedAt);
    if (!groups[group]) {
      groups[group] = [];
    }
    groups[group].push(conv);
  }
  
  return groups;
}
