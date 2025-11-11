/**
 * ExaSearchService.ets
 * 
 * Exa 搜索服务实现
 * https://exa.ai/
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  ExaOptions
} from '../SearchModels';

const DOMAIN = 0x0003;
const TAG = 'ExaSearchService';

export class ExaSearchService extends SearchService<ExaOptions> {
  private static instance: ExaSearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): ExaSearchService {
    if (!ExaSearchService.instance) {
      ExaSearchService.instance = new ExaSearchService();
    }
    return ExaSearchService.instance;
  }
  
  get name(): string {
    return 'Exa';
  }
  
  get description(): string {
    return '具备语义理解的神经搜索引擎。适合研究与查找特定内容。';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: ExaOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      const contentsObj: Record<string, Object | string | number | boolean> = {};
      contentsObj['text'] = true;
      const reqObj: Record<string, Object | string | number | boolean> = {};
      reqObj['query'] = query;
      reqObj['numResults'] = commonOptions.resultSize ?? 10;
      reqObj['contents'] = contentsObj;
      const requestBody: Record<string, Object | string | number | boolean> = reqObj;
      
      const headers: Record<string, string> = {
        'Authorization': `Bearer ${serviceOptions.apiKey}`,
        'Content-Type': 'application/json'
      };
      
      const response = await this.makeRequest(
        'https://api.exa.ai/search',
        http.RequestMethod.POST,
        headers,
        JSON.stringify(requestBody),
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`Exa API 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | null>;
      
      const resultsArray = (dataObj['results'] as Object[]) ?? [];
      const items: SearchResultItem[] = resultsArray.map((item) => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['url'] as string) ?? '',
          text: (itemObj['text'] as string) ?? '',
          index: 0,
          source: 'Exa'
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
        hilog.error(DOMAIN, TAG, 'Exa search failed: %{public}s', error.message);
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
