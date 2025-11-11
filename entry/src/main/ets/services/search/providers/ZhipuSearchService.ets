/**
 * ZhipuSearchService.ets
 * 
 * 智谱 AI 搜索服务实现
 * https://zhipu.ai/
 */

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchService } from '../SearchService';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions,
  ZhipuOptions
} from '../SearchModels';

const DOMAIN = 0x0004;
const TAG = 'ZhipuSearchService';

export class ZhipuSearchService extends SearchService<ZhipuOptions> {
  private static instance: ZhipuSearchService;
  
  private constructor() {
    super();
  }
  
  static getInstance(): ZhipuSearchService {
    if (!ZhipuSearchService.instance) {
      ZhipuSearchService.instance = new ZhipuSearchService();
    }
    return ZhipuSearchService.instance;
  }
  
  get name(): string {
    return '智谱';
  }
  
  get description(): string {
    return '智谱 AI 旗下中文 AI 搜索服务，针对中文内容与查询进行了优化。';
  }
  
  async search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: ZhipuOptions
  ): Promise<SearchResult> {
    try {
      const startTime = Date.now();
      
      const reqObj: Record<string, Object | string | number | boolean> = {};
      reqObj['search_query'] = query;
      reqObj['search_engine'] = 'search_std';
      reqObj['count'] = commonOptions.resultSize ?? 10;
      const requestBody: Record<string, Object | string | number | boolean> = reqObj;
      
      const headers: Record<string, string> = {
        'Authorization': `Bearer ${serviceOptions.apiKey}`,
        'Content-Type': 'application/json'
      };
      
      const response = await this.makeRequest(
        'https://open.bigmodel.cn/api/paas/v4/web_search',
        http.RequestMethod.POST,
        headers,
        JSON.stringify(requestBody),
        commonOptions.timeout ?? 10000
      );
      
      if (response.responseCode !== 200) {
        throw new Error(`智谱 API 返回错误: ${response.responseCode}`);
      }
      
      const data = JSON.parse(response.result as string) as Object;
      const dataObj = data as Record<string, Object | null>;
      
      const resultsArray = (dataObj['search_result'] as Object[]) ?? [];
      const items: SearchResultItem[] = resultsArray.map((item) => {
        const itemObj = item as Record<string, Object | string | null>;
        const resultItem: SearchResultItem = {
          title: (itemObj['title'] as string) ?? '',
          url: (itemObj['link'] as string) ?? '',
          text: (itemObj['content'] as string) ?? '',
          index: 0,
          source: '智谱'
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
        hilog.error(DOMAIN, TAG, 'Zhipu search failed: %{public}s', error.message);
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
