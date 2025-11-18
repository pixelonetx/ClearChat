/**
 * BraveSearchService.ets
 * 
 * Brave 搜索服务实现
 * https://api.search.brave.com/
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  BraveOptions
} from '../SearchModels';

const DOMAIN = 0x0005;
const TAG = 'BraveSearchService';

export class BraveSearchService extends SearchService<BraveOptions> {
  private static instance: BraveSearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): BraveSearchService {
    if (!BraveSearchService.instance) {
      BraveSearchService.instance = new BraveSearchService();
    }
    return BraveSearchService.instance;
  }
  
  get name(): string {
    return 'Brave';
  }
  
  get description(): string {
    return 'Brave 独立搜索引擎。注重隐私，无跟踪或画像。';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: BraveOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      const encodedQuery = encodeURIComponent(query);
      const url = `https://api.search.brave.com/res/v1/web/search?q=${encodedQuery}&count=${commonOptions.resultSize ?? 10}`;
      
      const headers: Record<string, string> = {
        'Accept': 'application/json',
        'X-Subscription-Token': serviceOptions.apiKey
      };
      
      const response = await this.makeRequest(
        url,
        http.RequestMethod.GET,
        headers,
        undefined,
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`Brave API 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | null>;
      const webObj = dataObj['web'] as Record<string, Object | null>;
      
      const resultsArray = (webObj?.['results'] as Object[]) ?? [];
      const items: SearchResultItem[] = resultsArray.map((item) => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['url'] as string) ?? '',
          text: (itemObj['description'] as string) ?? '',
          index: 0,
          source: 'Brave'
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
        hilog.error(DOMAIN, TAG, 'Brave search failed: %{public}s', error.message);
        throw error;
      }
      throw new Error('Unknown error occurred');
    }
  }
  
  protected makeRequest(
    url: string,
    method: http.RequestMethod = http.RequestMethod.GET,
    headers?: Record<string, string>,
    body?: string,
    timeout: number = 10000
  ): Promise<http.HttpResponse> {
    return new Promise<http.HttpResponse>((resolve, reject) => {
      const httpRequest = http.createHttp();
      
      const headersMap: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (HarmonyOS) ClearChat/1.0',
      };
      
      if (headers) {
        const keys: string[] = Object.keys(headers);
        for (let i = 0; i < keys.length; i++) {
          const key = keys[i];
          headersMap[key] = headers[key];
        }
      }
      
      const options: http.HttpRequestOptions = {
        method: method,
        header: headersMap,
        extraData: body,
        connectTimeout: timeout,
        readTimeout: timeout,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      
      httpRequest.request(url, options).then((response) => {
        resolve(response);
      }).catch((err: Error) => {
        reject(err);
      }).finally(() => {
        httpRequest.destroy();
      });
    });
  }
}

