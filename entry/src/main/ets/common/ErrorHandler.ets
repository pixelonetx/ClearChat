/**
 * ErrorHandler.ets
 * 统一错误处理模块
 * 
 * 职责：
 * - 定义标准错误类型
 * - 提供错误转换和友好提示
 * - 统一错误日志记录
 */

import { createLogger, LogDomain } from './Logger';

const logger = createLogger('ErrorHandler', LogDomain.APP);

/**
 * 应用错误码枚举
 */
export enum ErrorCode {
  // 网络错误 1xxx
  NETWORK_ERROR = 1001,
  NETWORK_TIMEOUT = 1002,
  NETWORK_OFFLINE = 1003,
  SSL_ERROR = 1004,
  
  // API错误 2xxx
  API_UNAUTHORIZED = 2001,
  API_FORBIDDEN = 2002,
  API_NOT_FOUND = 2003,
  API_RATE_LIMIT = 2004,
  API_QUOTA_EXCEEDED = 2005,
  API_INVALID_REQUEST = 2006,
  API_SERVICE_UNAVAILABLE = 2007,
  
  // 数据错误 3xxx
  DATA_PARSE_ERROR = 3001,
  DATA_VALIDATION_ERROR = 3002,
  DATA_NOT_FOUND = 3003,
  
  // 数据库错误 4xxx
  DB_CONNECTION_ERROR = 4001,
  DB_QUERY_ERROR = 4002,
  DB_WRITE_ERROR = 4003,
  
  // 业务错误 5xxx
  CONTENT_FILTER = 5001,
  MODEL_NOT_FOUND = 5002,
  SETTINGS_NOT_CONFIGURED = 5003,
  
  // 未知错误
  UNKNOWN = 9999
}

/**
 * 应用错误类
 */
export class AppError extends Error {
  code: ErrorCode;
  originalError?: Error;
  timestamp: number;

  constructor(code: ErrorCode, message: string, originalError?: Error) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.originalError = originalError;
    this.timestamp = Date.now();
  }

  /**
   * 获取用户友好的错误消息
   */
  getUserMessage(): string {
    return getErrorUserMessage(this.code) || this.message;
  }

  /**
   * 转换为日志字符串
   */
  toLogString(): string {
    let log = `[${this.code}] ${this.message}`;
    if (this.originalError) {
      log += ` | Original: ${this.originalError.message}`;
    }
    return log;
  }
}

/**
 * 错误码对应的用户友好消息
 */
function getErrorUserMessage(code: ErrorCode): string {
  switch (code) {
    case ErrorCode.NETWORK_ERROR:
      return '网络连接失败，请检查网络设置';
    case ErrorCode.NETWORK_TIMEOUT:
      return '请求超时，请稍后重试';
    case ErrorCode.NETWORK_OFFLINE:
      return '网络已断开，请检查网络连接';
    case ErrorCode.SSL_ERROR:
      return 'SSL连接失败，请检查网络或证书配置';
    case ErrorCode.API_UNAUTHORIZED:
      return 'API密钥无效，请检查设置';
    case ErrorCode.API_FORBIDDEN:
      return '访问被拒绝，请检查API权限';
    case ErrorCode.API_NOT_FOUND:
      return '请求的资源不存在';
    case ErrorCode.API_RATE_LIMIT:
      return '请求过于频繁，请稍后再试';
    case ErrorCode.API_QUOTA_EXCEEDED:
      return 'API配额不足，请检查账户余额';
    case ErrorCode.API_INVALID_REQUEST:
      return '请求参数错误';
    case ErrorCode.API_SERVICE_UNAVAILABLE:
      return 'AI服务暂时不可用，请稍后重试';
    case ErrorCode.DATA_PARSE_ERROR:
      return '数据解析失败';
    case ErrorCode.DATA_VALIDATION_ERROR:
      return '数据验证失败';
    case ErrorCode.DATA_NOT_FOUND:
      return '数据不存在';
    case ErrorCode.DB_CONNECTION_ERROR:
      return '数据库连接失败';
    case ErrorCode.DB_QUERY_ERROR:
      return '数据查询失败';
    case ErrorCode.DB_WRITE_ERROR:
      return '数据保存失败';
    case ErrorCode.CONTENT_FILTER:
      return '消息内容不符合规范，请修改后重试';
    case ErrorCode.MODEL_NOT_FOUND:
      return '模型不可用，请检查模型ID';
    case ErrorCode.SETTINGS_NOT_CONFIGURED:
      return '请先配置API设置';
    case ErrorCode.UNKNOWN:
    default:
      return '发生未知错误，请稍后重试';
  }
}

/**
 * 错误处理器
 */
export class ErrorHandler {
  private static instance: ErrorHandler;
  
  private constructor() {}

  static getInstance(): ErrorHandler {
    if (!ErrorHandler.instance) {
      ErrorHandler.instance = new ErrorHandler();
    }
    return ErrorHandler.instance;
  }

  /**
   * 将原始错误转换为 AppError
   */
  parseError(error: Error | string | AppError): AppError {
    // 已经是 AppError
    if (error instanceof AppError) {
      return error;
    }

    // Error 实例
    if (error instanceof Error) {
      const code = this.inferErrorCode(error);
      return new AppError(code, error.message, error);
    }

    // 字符串错误
    if (typeof error === 'string') {
      const code = this.inferErrorCodeFromMessage(error);
      return new AppError(code, error);
    }

    // 其他类型
    return new AppError(ErrorCode.UNKNOWN, String(error));
  }

  /**
   * 从 Error 对象推断错误码
   */
  private inferErrorCode(error: Error): ErrorCode {
    return this.inferErrorCodeFromMessage(error.message);
  }

  /**
   * 从错误消息推断错误码
   */
  private inferErrorCodeFromMessage(message: string): ErrorCode {
    const normalized = message.toLowerCase();

    // 网络错误
    if (normalized.includes('timeout') || message.includes('超时')) {
      return ErrorCode.NETWORK_TIMEOUT;
    }
    if (normalized.includes('network') || normalized.includes('connection') ||
        normalized.includes('fetch') || message.includes('网络')) {
      return ErrorCode.NETWORK_ERROR;
    }
    if (normalized.includes('ssl') || normalized.includes('certificate')) {
      return ErrorCode.SSL_ERROR;
    }

    // API错误
    if (normalized.includes('unauthorized') || normalized.includes('401') ||
        normalized.includes('invalid api key') || message.includes('认证')) {
      return ErrorCode.API_UNAUTHORIZED;
    }
    if (normalized.includes('forbidden') || normalized.includes('403')) {
      return ErrorCode.API_FORBIDDEN;
    }
    if (normalized.includes('not found') || normalized.includes('404')) {
      return ErrorCode.API_NOT_FOUND;
    }
    if (normalized.includes('rate limit') || normalized.includes('too many') ||
        normalized.includes('429')) {
      return ErrorCode.API_RATE_LIMIT;
    }
    if (normalized.includes('quota') || normalized.includes('insufficient') ||
        message.includes('配额') || message.includes('余额')) {
      return ErrorCode.API_QUOTA_EXCEEDED;
    }
    if (normalized.includes('service unavailable') || normalized.includes('502') ||
        normalized.includes('503')) {
      return ErrorCode.API_SERVICE_UNAVAILABLE;
    }

    // 内容错误
    if (normalized.includes('content_filter') || normalized.includes('content policy') ||
        message.includes('内容过滤') || message.includes('违规')) {
      return ErrorCode.CONTENT_FILTER;
    }

    // 模型错误
    if (normalized.includes('model') && 
        (normalized.includes('not found') || normalized.includes('unknown'))) {
      return ErrorCode.MODEL_NOT_FOUND;
    }

    return ErrorCode.UNKNOWN;
  }

  /**
   * 处理并记录错误
   */
  handle(error: Error | string | AppError, context?: string): AppError {
    const appError = this.parseError(error);
    
    // 记录日志
    const logContext = context ? `[${context}] ` : '';
    logger.error('%{public}s%{public}s', logContext, appError.toLogString());

    return appError;
  }

  /**
   * 获取用户友好的错误消息
   */
  getUserMessage(error: Error | string | AppError): string {
    const appError = this.parseError(error);
    return appError.getUserMessage();
  }
}

/**
 * 快捷函数：处理错误并获取用户消息
 */
export function handleError(error: Error | string | AppError, context?: string): string {
  const handler = ErrorHandler.getInstance();
  const appError = handler.handle(error, context);
  return appError.getUserMessage();
}

/**
 * 快捷函数：创建指定类型的错误
 */
export function createError(code: ErrorCode, message?: string): AppError {
  const defaultMessage = getErrorUserMessage(code) || 'Unknown error';
  return new AppError(code, message || defaultMessage);
}

/**
 * 数据库错误类（向后兼容）
 * @deprecated 请使用 AppError 配合 ErrorCode.DB_* 错误码
 */
export class DatabaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DatabaseError';
  }
}

/**
 * 网络错误类（向后兼容）
 * @deprecated 请使用 AppError 配合 ErrorCode.NETWORK_* 错误码
 */
export class NetworkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NetworkError';
  }
}
