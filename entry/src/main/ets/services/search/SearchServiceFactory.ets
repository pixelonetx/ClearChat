/**
 * SearchServiceFactory.ets
 * 
 * 搜索服务工厂
 * 负责根据配置创建相应的搜索服务实例
 */

import { SearchService } from './SearchService';
import { SearchServiceOptions } from './SearchModels';

// 导入所有搜索服务实例
import { TavilySearchService } from './providers/TavilySearchService';
import { ExaSearchService } from './providers/ExaSearchService';
import { ZhipuSearchService } from './providers/ZhipuSearchService';
import { SearXNGSearchService } from './providers/SearXNGSearchService';
import { BraveSearchService } from './providers/BraveSearchService';
import { MetasoSearchService } from './providers/MetasoSearchService';
import { GoogleCustomSearchService } from './providers/GoogleCustomSearchService';
import { createLogger, LogDomain } from '../../common/Logger';

const logger = createLogger('SearchServiceFactory', LogDomain.SEARCH);

/**
 * 搜索服务工厂�?
 */
export class SearchServiceFactory {
  /**
   * 根据服务选项获取相应的搜索服务实�?
   */
  static getService(options: SearchServiceOptions): SearchService<SearchServiceOptions> {
    try {
      // 根据服务类型返回相应的搜索服务实�?
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
          logger.error( 'Unknown service type: %{public}s', options.type);
          throw new Error(`Unsupported search service type: ${options.type}`);
      }
    } catch (error) {
      if (error instanceof Error) {
        logger.error( 'Failed to get service: %{public}s', error.message);
        throw error;
      }
      throw new Error('Failed to get search service');
    }
  }
}

