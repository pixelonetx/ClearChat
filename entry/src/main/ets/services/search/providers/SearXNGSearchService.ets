/**
 * SearXNGSearchService.ets
 * 
 * SearXNG 搜索服务实现
 * https://searxng.github.io/
 */

import { http } from '@kit.NetworkKit';
import { createLogger, LogDomain } from '../../../common/Logger';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  SearXNGOptions
} from '../SearchModels';

const logger = createLogger('SearXNGSearchService', LogDomain.SEARCH);

export class SearXNGSearchService extends SearchService<SearXNGOptions> {
  private static instance: SearXNGSearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): SearXNGSearchService {
    if (!SearXNGSearchService.instance) {
      SearXNGSearchService.instance = new SearXNGSearchService();
    }
    return SearXNGSearchService.instance;
  }
  
  get name(): string {
    return 'SearXNG';
  }
  
  get description(): string {
    return '注重隐私的元搜索引擎。需自建实例，无跟踪';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: SearXNGOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      if (!serviceOptions.url) {
        throw new Error('SearXNG URL 不能为空');
      }
      
      const baseUrl: string = serviceOptions.url.trim().replace(/\/$/, '');
      const encodedQuery = encodeURIComponent(query);
      
      let url = `${baseUrl}/search?q=${encodedQuery}&format=json`;
      
      if (serviceOptions.engines) {
        url += `&engines=${encodeURIComponent(serviceOptions.engines)}`;
      }
      if (serviceOptions.language) {
        url += `&language=${encodeURIComponent(serviceOptions.language)}`;
      }
      
      const headers: Record<string, string> = {};
      
      // 如果有用户名和密码，添加基本认证
      if (serviceOptions.username && serviceOptions.password) {
        const credentials = `${serviceOptions.username}:${serviceOptions.password}`;
        const auth = this.encodeBase64(credentials);
        headers['Authorization'] = `Basic ${auth}`;
      }
      
      const response = await this.makeRequest(
        url,
        http.RequestMethod.GET,
        headers,
        undefined,
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`SearXNG 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | null>;
      
      const resultsArray = ((dataObj['results'] as Object[]) ?? [])
        .slice(0, commonOptions.resultSize ?? 10);
      const items: SearchResultItem[] = resultsArray.map((item: Object): SearchResultItem => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['url'] as string) ?? '',
          text: (itemObj['content'] as string) ?? '',
          index: 0,
          source: 'SearXNG'
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
        logger.error('SearXNG search failed: %{public}s', error.message);
        throw error;
      }
      throw new Error('Unknown error occurred');
    }
  }
  
  /**
   * 简单的 Base64 编码
   */
  private encodeBase64(str: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let encoded = '';
    let i = 0;
    
    while (i < str.length) {
      const a = str.charCodeAt(i++);
      const b = i < str.length ? str.charCodeAt(i++) : 0;
      const c = i < str.length ? str.charCodeAt(i++) : 0;
      
      const bitmap = (a << 16) | (b << 8) | c;
      
      encoded += chars.charAt((bitmap >> 18) & 63);
      encoded += chars.charAt((bitmap >> 12) & 63);
      encoded += i - 1 < str.length ? chars.charAt((bitmap >> 6) & 63) : '=';
      encoded += i < str.length ? chars.charAt(bitmap & 63) : '=';
    }
    
    return encoded;
  }
}


