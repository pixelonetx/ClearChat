/**
 * SearchConfigManager.ets
 *
 * 搜索配置管理器
 * 负责保存、加载和管理搜索服务配置
 */

import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Context } from '@ohos.abilityAccessCtrl';
import {
  SearchCommonOptions, SearchServiceOptions
} from './SearchModels';
import { SearchServiceFactory } from './SearchServiceFactory';
import { DatabaseManager } from '../DatabaseManager';

const DOMAIN = 0x0009;
const TAG = 'SearchConfigManager';

/**
 * 搜索配置
 */
export interface SearchConfig {
  // 启用的搜索服务列表
  enabledServices: SearchServiceOptions[];

  // 当前选中的搜索服务索引
  selectedServiceIndex: number;

  // 通用搜索选项
  commonOptions: SearchCommonOptions;

  // 是否启用网络搜索
  enableWebSearch: boolean;

  // 搜索连接状态（服务ID -> 连接状态）
  connectionStatus: Record<string, boolean>;
}

export class SearchConfigManager {
  private static instance: SearchConfigManager;
  private context: Context | null = null;
  private databaseManager: DatabaseManager | null = null;
  private preferencesProxy: preferences.Preferences | null = null;
  private config: SearchConfig = {
    enabledServices: [],
    selectedServiceIndex: 0,
    commonOptions: {
      resultSize: 10,
      timeout: 10000
    },
    enableWebSearch: false,
    connectionStatus: {}
  };
  private readonly PREFERENCES_NAME = 'search_config';
  private readonly KEY_CONFIG = 'search_config_data';
  private readonly KEY_ENABLED_SERVICES = 'search_enabled_services';
  private readonly KEY_SELECTED_INDEX = 'search_selected_index';
  private readonly KEY_COMMON_OPTIONS = 'search_common_options';
  private readonly KEY_WEB_SEARCH_ENABLED = 'search_web_search_enabled';
  private readonly KEY_MIGRATED = 'search_migrated_to_db';

  private constructor() {
  }

  static getInstance(): SearchConfigManager {
    if (!SearchConfigManager.instance) {
      SearchConfigManager.instance = new SearchConfigManager();
    }
    return SearchConfigManager.instance;
  }

  /**
   * 初始化配置管理器
   */
  async init(context: Context, databaseManager?: DatabaseManager): Promise<void> {
    this.context = context;
    this.databaseManager = databaseManager ?? DatabaseManager.getInstance();

    // 先初始化默认配置
    this.initializeDefaultConfig();

    try {
      this.preferencesProxy = await preferences.getPreferences(context, this.PREFERENCES_NAME);
      // 从旧格式迁移 API 密钥到加密数据库（一次性操作）
      await this.migrateApiKeysToDb();
      await this.loadConfig();
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to initialize SearchConfigManager: %{public}s', err.message);
      // 不抛出错误，使用默认配置继续运行
    }
  }

  /**
   * 将旧的 Preferences 中存储的 API 密钥迁移到加密数据库（一次性操作）
   */
  private async migrateApiKeysToDb(): Promise<void> {
    if (!this.preferencesProxy || !this.databaseManager) {
      return;
    }
    try {
      const migrated = this.preferencesProxy.getSync(this.KEY_MIGRATED, false) as boolean;
      if (migrated) {
        return;
      }
      const enabledServicesJson = this.preferencesProxy.getSync(this.KEY_ENABLED_SERVICES, '[]') as string;
      if (enabledServicesJson === '[]') {
        this.preferencesProxy.putSync(this.KEY_MIGRATED, true);
        await this.preferencesProxy.flush();
        return;
      }
      const servicesData = JSON.parse(enabledServicesJson) as Object[];
      for (const data of servicesData) {
        const jsonObj = data as Record<string, Object | string | number | boolean | null>;
        if (jsonObj['id'] && jsonObj['type']) {
          // 存储完整配置（含 API 密钥）到加密数据库
          await this.databaseManager.saveSearchServiceConfig(
            jsonObj['id'] as string,
            jsonObj['type'] as string,
            JSON.stringify(data)
          );
        }
      }
      this.preferencesProxy.putSync(this.KEY_MIGRATED, true);
      await this.preferencesProxy.flush();
      hilog.info(DOMAIN, TAG, 'Migrated %{public}d search configs to encrypted DB', servicesData.length);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Search config migration skipped: %{public}s', String(error));
    }
  }

  /**
   * 加载配置
   */
  private async loadConfig(): Promise<void> {
    try {
      if (!this.preferencesProxy) {
        return;
      }

      const selectedIndex = this.preferencesProxy.getSync(this.KEY_SELECTED_INDEX, 0) as number;
      const commonOptionsJson = this.preferencesProxy.getSync(this.KEY_COMMON_OPTIONS, '{}') as string;
      const webSearchEnabled = this.preferencesProxy.getSync(this.KEY_WEB_SEARCH_ENABLED, false) as boolean;

      this.config.selectedServiceIndex = selectedIndex;

      // 优先从加密数据库加载服务配置（含 API 密钥）
      if (this.databaseManager) {
        try {
          const dbConfigs = await this.databaseManager.getAllSearchServiceConfigs();
          if (dbConfigs.length > 0) {
            this.config.enabledServices = dbConfigs.map((c) => {
              return SearchServiceOptions.fromJson(JSON.parse(c.configJson) as Object);
            });
          }
        } catch (dbError) {
          hilog.warn(DOMAIN, TAG, 'Failed to load search configs from DB: %{public}s', String(dbError));
        }
      }

      // 回退：如果 DB 中无数据，从 Preferences 加载（用于迁移前或 DB 故障时）
      if (this.config.enabledServices.length === 0) {
        const enabledServicesJson = this.preferencesProxy.getSync(this.KEY_ENABLED_SERVICES, '[]') as string;
        try {
          const servicesData = JSON.parse(enabledServicesJson) as Object[];
          this.config.enabledServices = servicesData.map((data: Object) => {
            return SearchServiceOptions.fromJson(data);
          });
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'Failed to parse enabled services from prefs: %{public}s', String(error));
          this.config.enabledServices = [];
        }
      }

      try {
        const optionsData = JSON.parse(commonOptionsJson) as Record<string, Object | number | boolean | null>;
        const optionsObj = optionsData as Record<string, Object | number | boolean | null>;
        const commonOpts: SearchCommonOptions = {
          resultSize: (optionsObj['resultSize'] as number) ?? 10,
          timeout: (optionsObj['timeout'] as number) ?? 10000
        };
        this.config.commonOptions = commonOpts;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to parse common options: %{public}s', String(error));
      }

      this.config.enableWebSearch = webSearchEnabled;

      hilog.info(DOMAIN, TAG, 'Config loaded: enableWebSearch=%{public}s, services=%{public}d',
        String(this.config.enableWebSearch), this.config.enabledServices.length);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to load config: %{public}s', err.message);
    }
  }

  /**
   * 初始化默认配置
   */
  private initializeDefaultConfig(): void {
    this.config = {
      enabledServices: [],
      selectedServiceIndex: 0,
      commonOptions: {
        resultSize: 10,
        timeout: 10000
      },
      enableWebSearch: false,
      connectionStatus: {}
    };
  }

  /**
   * 保存配置
   */
  async saveConfig(): Promise<void> {
    try {
      if (!this.preferencesProxy) {
        return;
      }

      // 非敏感数据存入 Preferences
      this.preferencesProxy.putSync(this.KEY_SELECTED_INDEX, this.config.selectedServiceIndex);
      this.preferencesProxy.putSync(this.KEY_COMMON_OPTIONS, JSON.stringify(this.config.commonOptions));
      this.preferencesProxy.putSync(this.KEY_WEB_SEARCH_ENABLED, this.config.enableWebSearch);
      // 向后兼容：同时保存一份到 Preferences（不含 API 密钥）
      const sanitizedServices = this.config.enabledServices.map(s => {
        const json = s.toJson();
        const record = json as Record<string, Object | string | number | boolean | null>;
        const sanitized: Record<string, Object | string | number | boolean | null> = {};
        const keys = Object.keys(record);
        for (let i = 0; i < keys.length; i++) {
          const k = keys[i];
          if (k !== 'apiKey' && k !== 'password') {
            sanitized[k] = record[k];
          }
        }
        return sanitized;
      });
      this.preferencesProxy.putSync(this.KEY_ENABLED_SERVICES, JSON.stringify(sanitizedServices));
      await this.preferencesProxy.flush();

      // 敏感数据（含 API 密钥）存入加密数据库
      if (this.databaseManager) {
        for (const service of this.config.enabledServices) {
          await this.databaseManager.saveSearchServiceConfig(
            service.id,
            service.type,
            JSON.stringify(service.toJson())
          );
        }
      }
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to save config: %{public}s', err.message);
      throw err;
    }
  }

  /**
   * 获取当前配置
   * 如果配置未初始化，返回默认配置
   */
  getConfig(): SearchConfig {
    // 如果配置为空或未初始化，使用默认配置
    if (!this.config || !this.config.commonOptions) {
      
      return {
        enabledServices: [],
        selectedServiceIndex: 0,
        commonOptions: {
          resultSize: 10,
          timeout: 10000
        },
        enableWebSearch: false,
        connectionStatus: {}
      };
    }
    return this.config;
  }

  /**
   * 添加搜索服务
   */
  async addService(service: SearchServiceOptions): Promise<void> {
    this.config.enabledServices.push(service);
    await this.saveConfig();
  }

  /**
   * 移除搜索服务
   */
  async removeService(serviceId: string): Promise<void> {
    const index = this.config.enabledServices.findIndex(s => s.id === serviceId);
    if (index >= 0) {
      this.config.enabledServices.splice(index, 1);
      if (this.config.selectedServiceIndex >= this.config.enabledServices.length) {
        this.config.selectedServiceIndex = Math.max(0, this.config.enabledServices.length - 1);
      }
      await this.saveConfig();
    }
  }

  /**
   * 更新搜索服务
   */
  async updateService(serviceId: string, service: SearchServiceOptions): Promise<void> {
    const index = this.config.enabledServices.findIndex(s => s.id === serviceId);
    if (index >= 0) {
      this.config.enabledServices[index] = service;
      await this.saveConfig();
    }
  }

  /**
   * 获取选中的搜索服务
   */
  getSelectedService(): SearchServiceOptions | null {
    if (this.config.selectedServiceIndex < 0 ||
      this.config.selectedServiceIndex >= this.config.enabledServices.length) {
      return null;
    }
    return this.config.enabledServices[this.config.selectedServiceIndex];
  }

  /**
   * 设置选中的搜索服务
   */
  async setSelectedService(index: number): Promise<void> {
    if (index >= 0 && index < this.config.enabledServices.length) {
      this.config.selectedServiceIndex = index;
      await this.saveConfig();
    }
  }

  /**
   * 设置通用搜索选项
   */
  async setCommonOptions(options: SearchCommonOptions): Promise<void> {
    this.config.commonOptions = options;
    await this.saveConfig();
  }

  /**
   * 设置网络搜索启用状态
   */
  async setWebSearchEnabled(enabled: boolean): Promise<void> {
    this.config.enableWebSearch = enabled;
    await this.saveConfig();
  }

  /**
   * 测试服务连接
   * 通过执行一个测试查询来验证 API 连接和凭证的有效性
   */
  async testConnection(serviceId: string): Promise<boolean> {
    try {
      const service = this.config.enabledServices.find(s => s.id === serviceId);
      if (!service) {
        return false;
      }
      
      // 直接使用静态导入的工厂类
      const searchService = SearchServiceFactory.getService(service);
      
      const result = await searchService.search('test', { resultSize: 1, timeout: 5000 }, service);
      const success = result && typeof result === 'object';
      
      this.setConnectionStatus(serviceId, success);
      
      if (!success) {
        hilog.error(DOMAIN, TAG, 'Connection test failed for service: %{public}s', serviceId);
      }
      
      return success;
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Connection test error for %{public}s: %{public}s', serviceId, err.message);
      this.setConnectionStatus(serviceId, false);
      return false;
    }
  }

  /**
   * 设置服务连接状态
   */
  setConnectionStatus(serviceId: string, connected: boolean): void {
    this.config.connectionStatus[serviceId] = connected;
  }

  /**
   * 获取服务连接状态
   */
  getConnectionStatus(serviceId: string): boolean | null {
    const status = this.config.connectionStatus[serviceId];
    return status !== undefined ? status : null;
  }

  /**
   * 清空所有配置
   */
  async clearConfig(): Promise<void> {
    try {
      if (!this.preferencesProxy) {
        return;
      }
      // 清除加密数据库中的搜索配置
      if (this.databaseManager) {
        for (const service of this.config.enabledServices) {
          try {
            await this.databaseManager.deleteSearchServiceConfig(service.id);
          } catch (e) {
            // 继续清除其他配置
          }
        }
      }
      await this.preferencesProxy.clear();
      this.initializeDefaultConfig();
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to clear config: %{public}s', err.message);
      throw err;
    }
  }
}

