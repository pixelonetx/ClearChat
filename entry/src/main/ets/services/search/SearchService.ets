/**
 * SearchService.ets
 * 
 * 搜索服务基类
 * 支持多个搜索提供�?
 */

import { http } from '@kit.NetworkKit';
import {
  SearchResult,
  SearchCommonOptions,
  SearchServiceOptions
} from './SearchModels';

const DOMAIN = 0x0001;
const TAG = 'SearchService';

/**
 * 搜索服务基类
 */
export abstract class SearchService<T extends SearchServiceOptions> {
  // 服务名称
  abstract get name(): string;
  
  // 服务描述
  abstract get description(): string;
  
  /**
   * 执行搜索
   */
  abstract search(
    query: string,
    commonOptions: SearchCommonOptions,
    serviceOptions: T
  ): Promise<SearchResult>;
  
  /**
   * 网络请求辅助方法
   */
  protected async makeRequest(
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

