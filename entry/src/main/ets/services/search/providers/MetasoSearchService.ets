/**
 * MetasoSearchService.ets
 * 
 * 秘塔 (Metaso) 搜索服务实现
 * https://metaso.cn/
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  MetasoOptions
} from '../SearchModels';

const DOMAIN = 0x0006;
const TAG = 'MetasoSearchService';

export class MetasoSearchService extends SearchService<MetasoOptions> {
  private static instance: MetasoSearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): MetasoSearchService {
    if (!MetasoSearchService.instance) {
      MetasoSearchService.instance = new MetasoSearchService();
    }
    return MetasoSearchService.instance;
  }
  
  get name(): string {
    return '秘塔';
  }
  
  get description(): string {
    return '秘塔中文搜索引擎。面向中文内容优化并提供 AI 能力。';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: MetasoOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      const reqObj: Record<string, Object | string | number | boolean> = {};
      reqObj['q'] = query;
      reqObj['scope'] = 'webpage';
      reqObj['size'] = commonOptions.resultSize ?? 10;
      reqObj['includeSummary'] = false;
      const requestBody: Record<string, Object | string | number | boolean> = reqObj;
      
      const headers: Record<string, string> = {
        'Authorization': `Bearer ${serviceOptions.apiKey}`,
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      };
      
      const response = await this.makeRequest(
        'https://metaso.cn/api/v1/search',
        http.RequestMethod.POST,
        headers,
        JSON.stringify(requestBody),
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`秘塔 API 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | null>;
      
      const resultsArray = (dataObj['webpages'] as Object[]) ?? [];
      const items: SearchResultItem[] = resultsArray.map((item) => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['link'] as string) ?? '',
          text: (itemObj['snippet'] as string) ?? '',
          index: 0,
          source: '秘塔'
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
        hilog.error(DOMAIN, TAG, 'Metaso search failed: %{public}s', error.message);
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
