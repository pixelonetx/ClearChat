/**
 * TavilySearchService.ets
 * 
 * Tavily 搜索服务实现
 * https://tavily.com/
 */

import { http } from '@kit.NetworkKit';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  TavilyOptions
} from '../SearchModels';
import { createLogger, LogDomain } from '../../../common/Logger';

const logger = createLogger('TavilySearchService', LogDomain.SEARCH);

export class TavilySearchService extends SearchService<TavilyOptions> {
  private static instance: TavilySearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): TavilySearchService {
    if (!TavilySearchService.instance) {
      TavilySearchService.instance = new TavilySearchService();
    }
    return TavilySearchService.instance;
  }
  
  get name(): string {
    return 'Tavily';
  }
  
  get description(): string {
    return '为大型语言模型（LLMs）优化的 AI 搜索 API，提供高质量、相关的搜索结果';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: TavilyOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      const reqObj: Record<string, Object | string | number | boolean> = {};
      reqObj['query'] = query;
      reqObj['max_results'] = commonOptions.resultSize ?? 10;
      reqObj['include_answer'] = true;
      reqObj['topic'] = 'general';
      const requestBody: Record<string, Object | string | number | boolean> = reqObj;
      
      const headers: Record<string, string> = {
        'Authorization': `Bearer ${serviceOptions.apiKey}`,
        'Content-Type': 'application/json'
      };
      
      const response = await this.makeRequest(
        'https://api.tavily.com/search',
        http.RequestMethod.POST,
        headers,
        JSON.stringify(requestBody),
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`Tavily API 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | string | null>;
      
      const resultsArray = (dataObj['results'] as Object[]) ?? [];
      const items: SearchResultItem[] = resultsArray.map((item) => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['url'] as string) ?? '',
          text: (itemObj['content'] as string) ?? '',
          index: 0,
          source: 'Tavily'
        };
        return resultItem;
      });
      const resultObj: SearchResult = {
        answer: (dataObj['answer'] as string) ?? '',
        items: items,
        executionTime: Date.now() - startTime
      };
      return resultObj;
    } catch (error) {
      if (error instanceof Error) {
        logger.error( 'Tavily search failed: %{public}s', error.message);
        throw error;
      }
      throw new Error('Unknown error occurred');
    }
  }
}


