/**
 * GoogleCustomSearchService.ets
 * 
 * Google Custom Search 搜索服务实现
 * https://developers.google.com/custom-search
 */

import { http } from '@kit.NetworkKit';
import { createLogger, LogDomain } from '../../../common/Logger';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  GoogleCustomSearchOptions
} from '../SearchModels';

const logger = createLogger('GoogleCustomSearchService', LogDomain.SEARCH);

export class GoogleCustomSearchService extends SearchService<GoogleCustomSearchOptions> {
  private static instance: GoogleCustomSearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): GoogleCustomSearchService {
    if (!GoogleCustomSearchService.instance) {
      GoogleCustomSearchService.instance = new GoogleCustomSearchService();
    }
    return GoogleCustomSearchService.instance;
  }
  
  get name(): string {
    return 'Google Custom Search';
  }
  
  get description(): string {
    return 'Google 自定义搜索 API。提供精准的搜索结果';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: GoogleCustomSearchOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      const encodedQuery = encodeURIComponent(query);
      const url = `https://www.googleapis.com/customsearch/v1?q=${encodedQuery}&cx=${serviceOptions.searchEngineId}&num=${commonOptions.resultSize ?? 10}`;

      const headers: Record<string, string> = {
        'Accept': 'application/json',
        'X-Goog-Api-Key': serviceOptions.apiKey
      };
      
      const response = await this.makeRequest(
        url,
        http.RequestMethod.GET,
        headers,
        undefined,
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`Google Custom Search API 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | null>;
      
      const resultsArray = (dataObj['items'] as Object[]) ?? [];
      const items: SearchResultItem[] = resultsArray.map((item: Object): SearchResultItem => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['link'] as string) ?? '',
          text: (itemObj['snippet'] as string) ?? '',
          index: 0,
          source: 'Google'
        };
        return resultItem;
      });
      
      const result: SearchResult = {
        items: items,
        executionTime: Date.now() - startTime
      };
      return result;
    } catch (error) {
      if (error instanceof Error) {
        logger.error('Google Custom Search failed: %{public}s', error.message);
        throw error;
      }
      throw new Error('Unknown error occurred');
    }
  }
}


