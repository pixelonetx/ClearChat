/**
 * NetworkUtils.ets
 * 网络工具函数
 * 
 * 职责：提供网络相关的通用工具函数
 */

import { util } from '@kit.ArkTS';

/**
 * ArrayBuffer 转字符串 (UTF-8)
 * 使用 ArkTS 内置 TextDecoder
 */
export function arrayBufferToString(buffer: ArrayBuffer): string {
  const decoder = util.TextDecoder.create('utf-8');
  const uint8Array = new Uint8Array(buffer);
  return decoder.decodeToString(uint8Array);
}

/**
 * 字符串转 ArrayBuffer (UTF-8)
 * 使用 ArkTS 内置 TextEncoder
 */
export function stringToArrayBuffer(str: string): ArrayBuffer {
  const encoder = new util.TextEncoder();
  return encoder.encodeInto(str).buffer;
}

/**
 * URL 规范化
 * 确保 URL 格式正确
 */
export function normalizeUrl(url: string): string {
  if (!url) return '';
  
  let normalized = url.trim();
  
  // 移除末尾斜杠
  if (normalized.endsWith('/')) {
    normalized = normalized.slice(0, -1);
  }
  
  return normalized;
}

/**
 * 解析聊天完成 URL
 */
export function resolveChatCompletionsUrl(apiUrl: string): string {
  if (!apiUrl || apiUrl.trim().length === 0) {
    return apiUrl;
  }

  if (apiUrl.includes('/chat/completions')) {
    return apiUrl;
  }

  const sanitizedUrl = normalizeUrl(apiUrl);
  const hasV1 = sanitizedUrl.includes('/v1');
  const hasAliyunCompatV1 = sanitizedUrl.includes('/compatible-mode/v1');

  if (hasAliyunCompatV1 || hasV1) {
    return `${sanitizedUrl}/chat/completions`;
  }

  return `${sanitizedUrl}/v1/chat/completions`;
}

/**
 * 清理 API Key
 * 移除不可见字符
 */
export function sanitizeApiKey(apiKey: string): string {
  if (!apiKey) return '';
  return apiKey.replace(/[\u200B\u200C\u200D\uFEFF\u00A0]/g, '').trim();
}

/**
 * 清理标识符
 */
export function sanitizeIdentifier(input: string): string {
  if (!input) return '';
  return input.replace(/[\u200B\u200C\u200D\uFEFF\u00A0]/g, '').trim();
}

/**
 * HTTP 状态码转用户消息
 */
export function httpStatusToMessage(statusCode: number): string {
  const messages: Record<number, string> = {
    400: '请求参数错误',
    401: 'API密钥无效，请检查设置',
    403: 'API访问被拒绝',
    404: 'API接口不存在',
    429: '请求过于频繁，请稍后重试',
    500: '服务内部错误',
    502: '网关错误',
    503: '服务暂时不可用'
  };
  
  return messages[statusCode] || `请求失败 (${statusCode})`;
}

/**
 * 判断是否为网络错误
 */
export function isNetworkError(error: Error): boolean {
  const msg = error.message.toLowerCase();
  return msg.includes('network') || 
         msg.includes('connection') ||
         msg.includes('timeout') ||
         msg.includes('dns') ||
         msg.includes('enotfound') ||
         msg.includes('econnrefused');
}

/**
 * 重试配置
 */
export interface RetryConfig {
  maxRetries: number;
  baseDelay: number;
  maxDelay: number;
}

/**
 * 默认重试配置
 */
export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 3,
  baseDelay: 1000,
  maxDelay: 10000
};

/**
 * 计算指数退避延迟
 */
export function calculateBackoffDelay(attempt: number, config: RetryConfig = DEFAULT_RETRY_CONFIG): number {
  const delay = Math.min(
    config.baseDelay * Math.pow(2, attempt),
    config.maxDelay
  );
  // 添加随机抖动 (0-25%)
  return delay + Math.random() * delay * 0.25;
}

/**
 * 带重试的异步函数执行
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  config: RetryConfig = DEFAULT_RETRY_CONFIG,
  shouldRetry?: (error: Error) => boolean
): Promise<T> {
  let lastError: Error | null = null;
  
  for (let attempt = 0; attempt <= config.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      
      // 检查是否应该重试
      if (attempt === config.maxRetries) {
        break;
      }
      
      if (shouldRetry && !shouldRetry(lastError)) {
        break;
      }
      
      // 等待后重试
      const delay = calculateBackoffDelay(attempt, config);
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, delay));
    }
  }
  
  throw lastError || new Error('Unknown error');
}

/**
 * 节流函数
 * 在指定时间内只执行一次
 */
export function throttle<T extends (...args: ESObject[]) => void>(
  fn: T,
  delay: number
): T {
  let lastCall = 0;
  return ((...args: ESObject[]) => {
    const now = Date.now();
    if (now - lastCall >= delay) {
      lastCall = now;
      fn(...args);
    }
  }) as T;
}

/**
 * 防抖函数
 * 延迟执行，如果在延迟期间再次调用则重新计时
 */
export function debounce<T extends (...args: ESObject[]) => void>(
  fn: T,
  delay: number
): T {
  let timeoutId: number | null = null;
  return ((...args: ESObject[]) => {
    if (timeoutId !== null) {
      clearTimeout(timeoutId);
    }
    timeoutId = setTimeout(() => {
      fn(...args);
      timeoutId = null;
    }, delay);
  }) as T;
}
