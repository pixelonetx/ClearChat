/**
 * SearchModels.ets
 * 
 * 搜索模块数据模型定义
 * 支持多个搜索提供商的通用数据结构
 */

/**
 * 搜索结果�?
 */
export interface SearchResultItem {
  // 结果标题
  title: string;
  
  // 结果 URL
  url: string;
  
  // 结果文本/摘要
  text: string;
  
  // 唯一 ID（用于引用）
  id?: string;
  
  // 索引号（用于引用�?
  index?: number;
  
  // 来源
  source?: string;
}

/**
 * 搜索结果
 */
export interface SearchResult {
  // AI 生成的答案摘要（如果提供商支持）
  answer?: string;
  
  // 搜索结果项列�?
  items: SearchResultItem[];
  
  // 原始响应（用于调试）
  rawResponse?: Object;
  
  // 执行时间（毫秒）
  executionTime?: number;
}

/**
 * 通用搜索选项
 */
export interface SearchCommonOptions {
  // 返回结果数量
  resultSize?: number;
  
  // 超时时间（毫秒）
  timeout?: number;
}

/**
 * 搜索服务配置基类
 */
export abstract class SearchServiceOptions {
  // 服务ID（唯一标识�?
  id: string;
  
  // 服务类型
  abstract type: string;
  
  constructor(id: string) {
    this.id = id;
  }
  
  abstract toJson(): Object;
  
  static fromJson(json: Object): SearchServiceOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    const type = jsonObj['type'] as string;
    switch (type) {
      case 'tavily':
        return TavilyOptions.fromJson(json);
      case 'exa':
        return ExaOptions.fromJson(json);
      case 'zhipu':
        return ZhipuOptions.fromJson(json);
      case 'searxng':
        return SearXNGOptions.fromJson(json);
      case 'brave':
        return BraveOptions.fromJson(json);
      case 'metaso':
        return MetasoOptions.fromJson(json);
      case 'google_custom_search':
        return GoogleCustomSearchOptions.fromJson(json);
      default:
        throw new Error(`未知的搜索服务类�? ${type}`);
    }
  }
}

/**
 * Tavily 搜索服务配置
 */
export class TavilyOptions extends SearchServiceOptions {
  type = 'tavily';
  
  // API Key
  apiKey: string;
  
  constructor(id: string, apiKey: string) {
    super(id);
    this.apiKey = apiKey;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['apiKey'] = this.apiKey;
    return result;
  }
  
  static fromJson(json: Object): TavilyOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new TavilyOptions(
      jsonObj['id'] as string,
      jsonObj['apiKey'] as string,
    );
  }
}

/**
 * Exa 搜索服务配置
 */
export class ExaOptions extends SearchServiceOptions {
  type = 'exa';
  
  // API Key
  apiKey: string;
  
  constructor(id: string, apiKey: string) {
    super(id);
    this.apiKey = apiKey;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['apiKey'] = this.apiKey;
    return result;
  }
  
  static fromJson(json: Object): ExaOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new ExaOptions(
      jsonObj['id'] as string,
      jsonObj['apiKey'] as string,
    );
  }
}

/**
 * 智谱搜索服务配置
 */
export class ZhipuOptions extends SearchServiceOptions {
  type = 'zhipu';
  
  // API Key
  apiKey: string;
  
  constructor(id: string, apiKey: string) {
    super(id);
    this.apiKey = apiKey;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['apiKey'] = this.apiKey;
    return result;
  }
  
  static fromJson(json: Object): ZhipuOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new ZhipuOptions(
      jsonObj['id'] as string,
      jsonObj['apiKey'] as string,
    );
  }
}

/**
 * SearXNG 搜索服务配置
 */
export class SearXNGOptions extends SearchServiceOptions {
  type = 'searxng';
  
  // 实例 URL
  url: string;
  
  // 搜索引擎（可选）
  engines: string;
  
  // 语言（可选）
  language: string;
  
  // 用户名（可选）
  username: string;
  
  // 密码（可选）
  password: string;
  
  constructor(
    id: string,
    url: string,
    engines: string = '',
    language: string = '',
    username: string = '',
    password: string = ''
  ) {
    super(id);
    this.url = url;
    this.engines = engines;
    this.language = language;
    this.username = username;
    this.password = password;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['url'] = this.url;
    result['engines'] = this.engines;
    result['language'] = this.language;
    result['username'] = this.username;
    result['password'] = this.password;
    return result;
  }
  
  static fromJson(json: Object): SearXNGOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new SearXNGOptions(
      jsonObj['id'] as string,
      jsonObj['url'] as string,
      (jsonObj['engines'] as string) ?? '',
      (jsonObj['language'] as string) ?? '',
      (jsonObj['username'] as string) ?? '',
      (jsonObj['password'] as string) ?? ''
    );
  }
}

/**
 * Brave 搜索服务配置
 */
export class BraveOptions extends SearchServiceOptions {
  type = 'brave';
  
  // API Key
  apiKey: string;
  
  constructor(id: string, apiKey: string) {
    super(id);
    this.apiKey = apiKey;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['apiKey'] = this.apiKey;
    return result;
  }
  
  static fromJson(json: Object): BraveOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new BraveOptions(
      jsonObj['id'] as string,
      jsonObj['apiKey'] as string,
    );
  }
}

/**
 * Metaso (秘塔) 搜索服务配置
 */
export class MetasoOptions extends SearchServiceOptions {
  type = 'metaso';
  
  // API Key
  apiKey: string;
  
  constructor(id: string, apiKey: string) {
    super(id);
    this.apiKey = apiKey;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['apiKey'] = this.apiKey;
    return result;
  }
  
  static fromJson(json: Object): MetasoOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new MetasoOptions(
      jsonObj['id'] as string,
      jsonObj['apiKey'] as string,
    );
  }
}

/**
 * Google Custom Search 服务配置
 */
export class GoogleCustomSearchOptions extends SearchServiceOptions {
  type = 'google_custom_search';
  
  // API Key
  apiKey: string;
  
  // Search Engine ID
  searchEngineId: string;
  
  constructor(id: string, apiKey: string, searchEngineId: string) {
    super(id);
    this.apiKey = apiKey;
    this.searchEngineId = searchEngineId;
  }
  
  toJson(): Object {
    const result: Record<string, Object | string> = {};
    result['type'] = this.type;
    result['id'] = this.id;
    result['apiKey'] = this.apiKey;
    result['searchEngineId'] = this.searchEngineId;
    return result;
  }
  
  static fromJson(json: Object): GoogleCustomSearchOptions {
    const jsonObj = json as Record<string, Object | string | number | boolean | null>;
    return new GoogleCustomSearchOptions(
      jsonObj['id'] as string,
      jsonObj['apiKey'] as string,
      jsonObj['searchEngineId'] as string
    );
  }
}

