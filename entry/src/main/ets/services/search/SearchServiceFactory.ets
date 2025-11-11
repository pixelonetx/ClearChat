/**
 * SearchServiceFactory.ets
 * 
 * 搜索服务工厂
 * 负责根据配置创建相应的搜索服务实例
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchService } from './SearchService';
import { SearchServiceOptions } from './SearchModels';

// 导入所有搜索服务实现
import { TavilySearchService } from './providers/TavilySearchService';
import { ExaSearchService } from './providers/ExaSearchService';
import { ZhipuSearchService } from './providers/ZhipuSearchService';
import { SearXNGSearchService } from './providers/SearXNGSearchService';
import { BraveSearchService } from './providers/BraveSearchService';
import { MetasoSearchService } from './providers/MetasoSearchService';
import { GoogleCustomSearchService } from './providers/GoogleCustomSearchService';

const DOMAIN = 0x000A;
const TAG = 'SearchServiceFactory';

/**
 * 搜索服务工厂类
 */
export class SearchServiceFactory {
  /**
   * 根据服务选项获取相应的搜索服务实例
   */
  static getService(options: SearchServiceOptions): SearchService<SearchServiceOptions> {
    try {
      // 根据服务类型返回相应的搜索服务实例
      switch (options.type) {
        case 'tavily':
          return TavilySearchService.getInstance();
        case 'exa':
          return ExaSearchService.getInstance();
        case 'zhipu':
          return ZhipuSearchService.getInstance();
        case 'searxng':
          return SearXNGSearchService.getInstance();
        case 'brave':
          return BraveSearchService.getInstance();
        case 'metaso':
          return MetasoSearchService.getInstance();
        case 'google_custom_search':
          return GoogleCustomSearchService.getInstance();
        default:
          hilog.error(DOMAIN, TAG, 'Unknown service type: %{public}s', options.type);
          throw new Error(`Unsupported search service type: ${options.type}`);
      }
    } catch (error) {
      if (error instanceof Error) {
        hilog.error(DOMAIN, TAG, 'Failed to get service: %{public}s', error.message);
        throw error;
      }
      throw new Error('Failed to get search service');
    }
  }
}
