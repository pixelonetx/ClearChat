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
  SearchCommonOptions,
  SearchServiceOptions
} from './SearchModels';

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
  async init(context: Context): Promise<void> {
    this.context = context;
    
    // 先初始化默认配置
    this.initializeDefaultConfig();
    
    try {
      this.preferencesProxy = await preferences.getPreferences(context, this.PREFERENCES_NAME);
      await this.loadConfig();
      hilog.info(DOMAIN, TAG, 'SearchConfigManager initialized successfully');
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to initialize SearchConfigManager preferences: %{public}s', err.message);
      // 不抛出错误，使用默认配置继续运行
      hilog.warn(DOMAIN, TAG, 'Using default search config');
    }
  }

  /**
   * 加载配置
   */
  private async loadConfig(): Promise<void> {
    try {
      if (!this.preferencesProxy) {
        hilog.warn(DOMAIN, TAG, 'Preferences proxy not initialized, keeping default config');
        return;
      }

      const selectedIndex = this.preferencesProxy.getSync(this.KEY_SELECTED_INDEX, 0) as number;
      const enabledServicesJson = this.preferencesProxy.getSync(this.KEY_ENABLED_SERVICES, '[]') as string;
      const commonOptionsJson = this.preferencesProxy.getSync(this.KEY_COMMON_OPTIONS, '{}') as string;
      const webSearchEnabled = this.preferencesProxy.getSync(this.KEY_WEB_SEARCH_ENABLED, false) as boolean;

      this.config.selectedServiceIndex = selectedIndex;
      
      try {
        const servicesData = JSON.parse(enabledServicesJson) as Object[];
        this.config.enabledServices = servicesData.map((data: Object) => {
          return SearchServiceOptions.fromJson(data);
        });
        hilog.info(DOMAIN, TAG, 'Loaded %{public}d search services', this.config.enabledServices.length);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to parse enabled services: %{public}s', String(error));
        this.config.enabledServices = [];
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
        // 保持默认配置
      }

      this.config.enableWebSearch = webSearchEnabled;
      
      hilog.info(DOMAIN, TAG, 'Config loaded: enableWebSearch=%{public}s, services=%{public}d', 
        String(this.config.enableWebSearch), this.config.enabledServices.length);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to load config: %{public}s', err.message);
      // 不抛出错误，保持默认配置
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
      if (!this.preferencesProxy) return;

      const enabledServicesJson = JSON.stringify(
        this.config.enabledServices.map(s => s.toJson())
      );

      this.preferencesProxy.putSync(this.KEY_SELECTED_INDEX, this.config.selectedServiceIndex);
      this.preferencesProxy.putSync(this.KEY_ENABLED_SERVICES, enabledServicesJson);
      this.preferencesProxy.putSync(this.KEY_COMMON_OPTIONS, JSON.stringify(this.config.commonOptions));
      this.preferencesProxy.putSync(this.KEY_WEB_SEARCH_ENABLED, this.config.enableWebSearch);

      await this.preferencesProxy.flush();
      hilog.info(DOMAIN, TAG, 'Config saved successfully');
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
      hilog.warn(DOMAIN, TAG, 'Config not initialized, returning default config');
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
   */
  async testConnection(serviceId: string): Promise<boolean> {
    try {
      const service = this.config.enabledServices.find(s => s.id === serviceId);
      if (!service) {
        return false;
      }

      // TODO: 实现实际的连接测试逻辑
      // 这里只是一个占位符
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Connection test failed for %{public}s: %{public}s', serviceId, String(error));
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
      if (!this.preferencesProxy) return;
      await this.preferencesProxy.clear();
      this.initializeDefaultConfig();
      hilog.info(DOMAIN, TAG, 'Config cleared');
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      hilog.error(DOMAIN, TAG, 'Failed to clear config: %{public}s', err.message);
      throw err;
    }
  }
}
