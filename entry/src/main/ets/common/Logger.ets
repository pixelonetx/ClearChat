/**
 * Logger.ets
 * 统一日志管理
 * 
 * 职责：
 * - 提供统一的日志接口
 * - 支持日志级别控制
 * - 支持模块标签
 * - 生产环境自动降低日志级别
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 日志级别
 */
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  FATAL = 4,
  OFF = 5
}

/**
 * 日志域常量
 */
export class LogDomain {
  static readonly APP = 0x0000;
  static readonly NETWORK = 0x0001;
  static readonly DATABASE = 0x0002;
  static readonly UI = 0x0003;
  static readonly STREAM = 0x0004;
  static readonly SEARCH = 0x000A;
  static readonly CHAT = 0x0010;
  static readonly SETTINGS = 0x0011;
}

/**
 * 日志配置
 */
interface LoggerConfig {
  minLevel: LogLevel;
  enableConsole: boolean;
  enableHilog: boolean;
}

/**
 * 默认配置（生产环境建议设置为 INFO 或 WARN）
 */
const DEFAULT_CONFIG: LoggerConfig = {
  minLevel: LogLevel.DEBUG, // 开发时使用 DEBUG，生产时改为 INFO 或 WARN
  enableConsole: false,
  enableHilog: true
};

/**
 * 日志管理器
 */
class LoggerManager {
  private config: LoggerConfig = DEFAULT_CONFIG;
  private static instance: LoggerManager | null = null;

  private constructor() {}

  static getInstance(): LoggerManager {
    if (!LoggerManager.instance) {
      LoggerManager.instance = new LoggerManager();
    }
    return LoggerManager.instance;
  }

  /**
   * 设置日志配置
   */
  setConfig(config: Partial<LoggerConfig>): void {
    if (config.minLevel !== undefined) {
      this.config.minLevel = config.minLevel;
    }
    if (config.enableConsole !== undefined) {
      this.config.enableConsole = config.enableConsole;
    }
    if (config.enableHilog !== undefined) {
      this.config.enableHilog = config.enableHilog;
    }
  }

  /**
   * 设置最小日志级别
   */
  setMinLevel(level: LogLevel): void {
    this.config.minLevel = level;
  }

  /**
   * 获取当前配置
   */
  getConfig(): LoggerConfig {
    const copy: LoggerConfig = {
      minLevel: this.config.minLevel,
      enableConsole: this.config.enableConsole,
      enableHilog: this.config.enableHilog
    };
    return copy;
  }

  /**
   * 检查是否应该记录此级别的日志
   */
  shouldLog(level: LogLevel): boolean {
    return level >= this.config.minLevel;
  }

  /**
   * 是否启用 hilog
   */
  isHilogEnabled(): boolean {
    return this.config.enableHilog;
  }
}

/**
 * 模块日志器
 * 为每个模块创建独立的日志器实例
 */
export class Logger {
  private readonly domain: number;
  private readonly tag: string;
  private readonly manager: LoggerManager;

  constructor(tag: string, domain: number = LogDomain.APP) {
    this.tag = tag;
    this.domain = domain;
    this.manager = LoggerManager.getInstance();
  }

  /**
   * 调试日志 - 开发时的详细信息
   */
  debug(message: string, ...args: ESObject[]): void {
    if (!this.manager.shouldLog(LogLevel.DEBUG)) return;
    
    if (this.manager.isHilogEnabled()) {
      hilog.debug(this.domain, this.tag, message, ...args);
    }
  }

  /**
   * 信息日志 - 正常流程的关键节点
   */
  info(message: string, ...args: ESObject[]): void {
    if (!this.manager.shouldLog(LogLevel.INFO)) return;
    
    if (this.manager.isHilogEnabled()) {
      hilog.info(this.domain, this.tag, message, ...args);
    }
  }

  /**
   * 警告日志 - 可恢复的异常情况
   */
  warn(message: string, ...args: ESObject[]): void {
    if (!this.manager.shouldLog(LogLevel.WARN)) return;
    
    if (this.manager.isHilogEnabled()) {
      hilog.warn(this.domain, this.tag, message, ...args);
    }
  }

  /**
   * 错误日志 - 需要关注的错误
   */
  error(message: string, ...args: ESObject[]): void {
    if (!this.manager.shouldLog(LogLevel.ERROR)) return;
    
    if (this.manager.isHilogEnabled()) {
      hilog.error(this.domain, this.tag, message, ...args);
    }
  }

  /**
   * 致命错误日志 - 严重的系统错误
   */
  fatal(message: string, ...args: ESObject[]): void {
    if (!this.manager.shouldLog(LogLevel.FATAL)) return;
    
    if (this.manager.isHilogEnabled()) {
      hilog.fatal(this.domain, this.tag, message, ...args);
    }
  }
}

/**
 * 创建模块日志器的工厂函数
 */
export function createLogger(tag: string, domain?: number): Logger {
  return new Logger(tag, domain);
}

/**
 * 获取日志管理器（用于配置）
 */
export function getLoggerManager(): LoggerManager {
  return LoggerManager.getInstance();
}

/**
 * 设置全局日志级别
 */
export function setLogLevel(level: LogLevel): void {
  LoggerManager.getInstance().setMinLevel(level);
}

/**
 * 预定义的模块日志器
 */
export const ChatLogger = createLogger('Chat', LogDomain.CHAT);
export const NetworkLogger = createLogger('Network', LogDomain.NETWORK);
export const DatabaseLogger = createLogger('Database', LogDomain.DATABASE);
export const SearchLogger = createLogger('Search', LogDomain.SEARCH);
export const SettingsLogger = createLogger('Settings', LogDomain.SETTINGS);
export const UILogger = createLogger('UI', LogDomain.UI);
