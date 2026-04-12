/**
 * StateManager.ets
 * 轻量级状态管理
 * 
 * 职责：
 * - 提供跨页面状态同步机制
 * - 封装 AppStorage 操作
 * - 实现发布-订阅模式
 */

import { StorageKeys } from './Constants';
import { createLogger, LogDomain } from './Logger';

const logger = createLogger('StateManager', LogDomain.APP);

/**
 * 状态变化监听器
 */
export type StateListener<T> = (newValue: T, oldValue: T) => void;

/**
 * 状态管理器
 * 基于 AppStorage 的轻量级状态管理
 */
export class StateManager {
  private static instance: StateManager;
  private listeners: Map<string, Set<StateListener<Object>>> = new Map();

  private constructor() {}

  static getInstance(): StateManager {
    if (!StateManager.instance) {
      StateManager.instance = new StateManager();
    }
    return StateManager.instance;
  }

  /**
   * 获取状态值
   */
  get<T>(key: string, defaultValue: T): T {
    const value = AppStorage.get<T>(key);
    return value !== undefined ? value : defaultValue;
  }

  /**
   * 设置状态值
   */
  set<T>(key: string, value: T): void {
    const oldValue = this.get(key, undefined);
    AppStorage.setOrCreate(key, value);
    this.notifyListeners(key, value as Object, oldValue as Object);
  }

  /**
   * 递增版本号（用于触发更新）
   */
  incrementVersion(key: string): number {
    const current = this.get<number>(key, 0);
    const next = current + 1;
    this.set(key, next);
    return next;
  }

  /**
   * 监听状态变化
   */
  subscribe<T extends Object>(key: string, listener: StateListener<T>): () => void {
    if (!this.listeners.has(key)) {
      this.listeners.set(key, new Set());
    }
    this.listeners.get(key)!.add(listener as StateListener<Object>);

    // 返回取消订阅函数
    return () => {
      this.listeners.get(key)?.delete(listener as StateListener<Object>);
    };
  }

  /**
   * 通知监听器
   */
  private notifyListeners(key: string, newValue: Object, oldValue: Object): void {
    const keyListeners = this.listeners.get(key);
    if (keyListeners) {
      keyListeners.forEach(listener => {
        try {
          listener(newValue, oldValue);
        } catch (e) {
          logger.error('StateManager listener error for key %{public}s: %{public}s', key, String(e));
        }
      });
    }
  }

  /**
   * 清除所有监听器
   */
  clearAllListeners(): void {
    this.listeners.clear();
  }

  /**
   * 清除指定键的监听器
   */
  clearListeners(key: string): void {
    this.listeners.delete(key);
  }
}

/**
 * 设置状态管理
 */
export class SettingsState {
  private static stateManager = StateManager.getInstance();

  /**
   * 通知设置已更新
   */
  static notifyUpdate(): void {
    this.stateManager.incrementVersion(StorageKeys.SETTINGS_VERSION);
  }

  /**
   * 获取设置版本
   */
  static getVersion(): number {
    return this.stateManager.get(StorageKeys.SETTINGS_VERSION, 0);
  }

  /**
   * 监听设置变化
   */
  static subscribe(listener: StateListener<number>): () => void {
    return this.stateManager.subscribe(StorageKeys.SETTINGS_VERSION, listener);
  }
}

/**
 * 对话状态管理
 */
export class ConversationsState {
  private static stateManager = StateManager.getInstance();

  /**
   * 通知对话列表已更新
   */
  static notifyUpdate(): void {
    this.stateManager.incrementVersion(StorageKeys.CONVERSATIONS_VERSION);
  }

  /**
   * 获取对话版本
   */
  static getVersion(): number {
    return this.stateManager.get(StorageKeys.CONVERSATIONS_VERSION, 0);
  }

  /**
   * 监听对话列表变化
   */
  static subscribe(listener: StateListener<number>): () => void {
    return this.stateManager.subscribe(StorageKeys.CONVERSATIONS_VERSION, listener);
  }
}

/**
 * 主题状态管理
 */
export class ThemeState {
  private static stateManager = StateManager.getInstance();

  /**
   * 设置主题模式
   */
  static setMode(mode: number): void {
    this.stateManager.set(StorageKeys.THEME_MODE, mode);
  }

  /**
   * 获取主题模式
   */
  static getMode(): number {
    return this.stateManager.get(StorageKeys.THEME_MODE, 0);
  }

  /**
   * 监听主题变化
   */
  static subscribe(listener: StateListener<number>): () => void {
    return this.stateManager.subscribe(StorageKeys.THEME_MODE, listener);
  }
}
