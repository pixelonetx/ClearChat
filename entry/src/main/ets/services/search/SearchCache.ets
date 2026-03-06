/**
 * SearchCache.ets
 * 
 * 搜索结果缓存
 * 避免重复搜索相同查询，提升性能
 */

import { SearchResult } from './SearchModels';
import { createLogger, LogDomain } from '../../common/Logger';

const logger = createLogger('SearchCache', LogDomain.SEARCH);

/**
 * 缓存条目
 */
interface CacheEntry {
  result: SearchResult;
  timestamp: number;
  query: string;
  serviceType: string;
}

/**
 * 缓存配置
 */
export interface SearchCacheConfig {
  // 最大缓存条目数
  maxEntries: number;
  // 缓存过期时间（毫秒）
  ttlMs: number;
  // 是否启用缓存
  enabled: boolean;
}

/**
 * 缓存统计信息
 */
export interface CacheStats {
  size: number;
  maxSize: number;
  hitRate: string;
}

/**
 * 默认缓存配置
 */
export const DEFAULT_CACHE_CONFIG: SearchCacheConfig = {
  maxEntries: 50,
  ttlMs: 5 * 60 * 1000, // 5 分钟
  enabled: true
};

/**
 * 搜索缓存管理器
 */
export class SearchCache {
  private static instance: SearchCache;
  private cache: Map<string, CacheEntry> = new Map();
  private config: SearchCacheConfig = {
    maxEntries: DEFAULT_CACHE_CONFIG.maxEntries,
    ttlMs: DEFAULT_CACHE_CONFIG.ttlMs,
    enabled: DEFAULT_CACHE_CONFIG.enabled
  };

  private constructor() {}

  static getInstance(): SearchCache {
    if (!SearchCache.instance) {
      SearchCache.instance = new SearchCache();
    }
    return SearchCache.instance;
  }

  /**
   * 设置缓存配置
   */
  setConfig(config: Partial<SearchCacheConfig>): void {
    if (config.maxEntries !== undefined) {
      this.config.maxEntries = config.maxEntries;
    }
    if (config.ttlMs !== undefined) {
      this.config.ttlMs = config.ttlMs;
    }
    if (config.enabled !== undefined) {
      this.config.enabled = config.enabled;
    }
    logger.info('Cache config updated: maxEntries=%{public}d, ttlMs=%{public}d, enabled=%{public}s',
      this.config.maxEntries, this.config.ttlMs, String(this.config.enabled));
  }

  /**
   * 获取缓存配置
   */
  getConfig(): SearchCacheConfig {
    const copy: SearchCacheConfig = {
      maxEntries: this.config.maxEntries,
      ttlMs: this.config.ttlMs,
      enabled: this.config.enabled
    };
    return copy;
  }

  /**
   * 生成缓存键
   */
  private generateKey(query: string, serviceType: string, resultSize: number): string {
    return `${serviceType}:${query.toLowerCase().trim()}:${resultSize}`;
  }

  /**
   * 获取缓存的搜索结果
   */
  get(query: string, serviceType: string, resultSize: number): SearchResult | null {
    if (!this.config.enabled) {
      return null;
    }

    const key = this.generateKey(query, serviceType, resultSize);
    const entry = this.cache.get(key);

    if (!entry) {
      return null;
    }

    // 检查是否过期
    const now = Date.now();
    if (now - entry.timestamp > this.config.ttlMs) {
      this.cache.delete(key);
      logger.info('Cache entry expired: %{public}s', key);
      return null;
    }

    logger.info('Cache hit: %{public}s', key);
    return entry.result;
  }

  /**
   * 设置缓存的搜索结果
   */
  set(query: string, serviceType: string, resultSize: number, result: SearchResult): void {
    if (!this.config.enabled) {
      return;
    }

    // 检查缓存大小，必要时清理
    if (this.cache.size >= this.config.maxEntries) {
      this.evictOldest();
    }

    const key = this.generateKey(query, serviceType, resultSize);
    const entry: CacheEntry = {
      result: result,
      timestamp: Date.now(),
      query: query,
      serviceType: serviceType
    };

    this.cache.set(key, entry);
    logger.info('Cache set: %{public}s, size=%{public}d', key, this.cache.size);
  }

  /**
   * 清除最旧的缓存条目
   */
  private evictOldest(): void {
    let oldestKey: string | null = null;
    let oldestTimestamp = Date.now();
    const keys = Array.from(this.cache.keys());
    
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const entry = this.cache.get(key);
      if (entry && entry.timestamp < oldestTimestamp) {
        oldestTimestamp = entry.timestamp;
        oldestKey = key;
      }
    }

    if (oldestKey) {
      this.cache.delete(oldestKey);
      logger.info('Evicted oldest cache entry: %{public}s', oldestKey);
    }
  }

  /**
   * 清除所有缓存
   */
  clear(): void {
    const size = this.cache.size;
    this.cache.clear();
    logger.info('Cache cleared: %{public}d entries removed', size);
  }

  /**
   * 清除指定服务类型的缓存
   */
  clearByServiceType(serviceType: string): void {
    const keysToDelete: string[] = [];
    const keys = Array.from(this.cache.keys());
    
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const entry = this.cache.get(key);
      if (entry && entry.serviceType === serviceType) {
        keysToDelete.push(key);
      }
    }

    for (let i = 0; i < keysToDelete.length; i++) {
      this.cache.delete(keysToDelete[i]);
    }

    logger.info('Cleared %{public}d entries for service: %{public}s', 
      keysToDelete.length, serviceType);
  }

  /**
   * 清除过期的缓存条目
   */
  cleanupExpired(): number {
    const now = Date.now();
    const keysToDelete: string[] = [];
    const ttlMs = this.config.ttlMs;
    const keys = Array.from(this.cache.keys());

    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const entry = this.cache.get(key);
      if (entry && now - entry.timestamp > ttlMs) {
        keysToDelete.push(key);
      }
    }

    for (let i = 0; i < keysToDelete.length; i++) {
      this.cache.delete(keysToDelete[i]);
    }

    if (keysToDelete.length > 0) {
      logger.info('Cleanup removed %{public}d expired entries', keysToDelete.length);
    }

    return keysToDelete.length;
  }

  /**
   * 获取缓存统计信息
   */
  getStats(): CacheStats {
    const stats: CacheStats = {
      size: this.cache.size,
      maxSize: this.config.maxEntries,
      hitRate: 'N/A'
    };
    return stats;
  }
}
