/**
 * SearchToolService.ets
 * 
 * 搜索工具服务 - 完整的联网搜索实现
 * 用于 AI 模型的工具调用集成
 * 兼容 OpenAI Tool Calling 格式
 * 
 * 功能:
 * - 多搜索引擎支持 (Bing, Tavily, SearXNG等)
 * - 工具定义生成 (OpenAI格式)
 * - 搜索执行和结果格式化
 * - 引用处理和去重
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchService } from './SearchService';
import { SearchServiceFactory } from './SearchServiceFactory';
import { SearchConfigManager, SearchConfig } from './SearchConfigManager';
import {
  SearchResult,
  SearchResultItem,
  SearchCommonOptions
} from './SearchModels';

const DOMAIN = 0x000A;
const TAG = 'SearchToolService';
/**
 * 工具参数属性
 */
export interface ToolPropertyDef {
  type: string;
  description: string;
}

/**
 * 工具参数定义
 */
export interface ToolParameters {
  type: string;
  properties: Record<string, object>;
  required: string[];
}

/**
 * 工具函数定义
 */
export interface ToolFunctionDef {
  name: string;
  description: string;
  parameters: ToolParameters;
}

/**
 * 搜索工具定义（OpenAI Tool Calling 格式）
 */
export interface SearchToolDefinition {
  type: 'function';
  function: ToolFunctionDef;
}

/**
 * 搜索工具结果
 */
export interface SearchToolResult {
  type: 'tool_result';
  tool_use_id: string;
  content: string;
  is_error?: boolean;
}

export class SearchToolService {
  private static instance: SearchToolService;
  private configManager: SearchConfigManager;

  private constructor() {
    this.configManager = SearchConfigManager.getInstance();
  }

  static getInstance(): SearchToolService {
    if (!SearchToolService.instance) {
      SearchToolService.instance = new SearchToolService();
    }
    return SearchToolService.instance;
  }

  /**
   * 获取搜索工具定义（OpenAI Tool Calling 格式）
   * 用于告诉 AI 模型有哪些工具可用
   */
  getToolDefinition(): SearchToolDefinition {
    const queryProp: ToolPropertyDef = {
      type: 'string',
      description: '搜索查询词'
    };
    
    const resultSizeProp: ToolPropertyDef = {
      type: 'number',
      description: '返回结果数量，默认 10'
    };
    
    const properties: Record<string, object> = {};
    properties['query'] = queryProp as object;
    properties['resultSize'] = resultSizeProp as object;
    
    const parameters: ToolParameters = {
      type: 'object',
      properties: properties,
      required: ['query']
    };
    
    const functionDef: ToolFunctionDef = {
      name: 'search_web',
      description: '在网络上搜索信息。当需要实时数据或最新信息时使用此工具。',
      parameters: parameters
    };
    
    const definition: SearchToolDefinition = {
      type: 'function',
      function: functionDef
    };
    
    return definition;
  }

  /**
   * 获取兼容 OpenAI function-calling 格式的工具定义
   * 返回与 getToolDefinition 相同的结构（已按 OpenAI 格式）
   */
  getToolDefinitionAsFunction(): object {
    return this.getToolDefinition() as object;
  }

  /**
   * 执行搜索
   */
  async executeSearch(
    query: string,
    resultSize?: number
  ): Promise<SearchResult> {
    try {
      const config = this.configManager.getConfig();
      const selectedService = this.configManager.getSelectedService();

      if (!selectedService) {
        const err = new Error('未配置搜索服务');
        throw err;
      }

      if (!config.enableWebSearch) {
        const err = new Error('网络搜索未启用');
        throw err;
      }

      const service = SearchServiceFactory.getService(selectedService);
      const commonOptions: SearchCommonOptions = {
        resultSize: resultSize ?? config.commonOptions.resultSize ?? 10,
        timeout: config.commonOptions.timeout ?? 10000
      };

      hilog.info(DOMAIN, TAG, 'Executing search with query: %{public}s', query);

      const result = await service.search(query, commonOptions, selectedService);

      // 为结果项添加 ID 和索引
      const updatedItems: SearchResultItem[] = [];
      for (let index = 0; index < result.items.length; index++) {
        const item = result.items[index];
        const newItem: SearchResultItem = {
          title: item.title,
          url: item.url,
          text: item.text,
          id: this.generateUUID(),
          index: index + 1,
          source: item.source
        };
        updatedItems.push(newItem);
      }
      result.items = updatedItems;

      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Search execution failed: %{public}s', String(error));
      const err = error instanceof Error ? error : new Error(String(error));
      throw err;
    }
  }

  /**
   * 执行搜索并返回工具结果格式
   */
  async executeSearchAsToolResult(
    query: string,
    toolUseId: string,
    resultSize?: number
  ): Promise<SearchToolResult> {
    try {
      const result = await this.executeSearch(query, resultSize);

      const formattedItems = result.items
        .map(item => {
          let text = `**${item.title}** [${item.index}:${item.id}]\n${item.url}\n${item.text}`;
          if (item.source) {
            text += `\n来源: ${item.source}`;
          }
          return text;
        })
        .join('\n\n---\n\n');

      let content = '';
      if (result.answer) {
        content += `**AI 摘要**: ${result.answer}\n\n---\n\n`;
      }
      content += `**搜索结果**:\n\n${formattedItems}`;

      if (result.executionTime) {
        content += `\n\n执行时间: ${result.executionTime}ms`;
      }

      return {
        type: 'tool_result',
        tool_use_id: toolUseId,
        content: content
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Search tool execution failed: %{public}s', String(error));
      return {
        type: 'tool_result',
        tool_use_id: toolUseId,
        content: `搜索失败: ${error}`,
        is_error: true
      };
    }
  }

  /**
   * 获取系统提示词
   */
  getSystemPrompt(): string {
    return `你是一个有网络搜索能力的 AI 助手。

## search_web 工具使用说明

当用户询问需要实时信息或最新数据的问题时，使用 search_web 工具进行搜索。

### 引用格式
- 搜索结果中会包含 index(搜索结果序号)和 id(搜索结果唯一标识符)，引用格式为：
  \`具体的引用内容 [citation](index:id)\`
- **引用必须紧跟在相关内容之后**，在标点符号后面，不得延后到回复结尾
- 正确格式：\`... [citation](index:id)\` \`... [citation](index:id) [citation](index:id)\`

### 使用规范
1. **使用时机**
   - 用户询问最新新闻、事件、数据
   - 需要查证事实信息
   - 需要获取技术文档、API 信息等

2. **引用要求**
   - 直接引用信息时必须引用来源
   - 引用必须准确，格式必须完整
   - 不能伪造引用

3. **禁止行为**
   - 不能声称查不到信息后仍作答
   - 不能虚假引用不存在的来源

### 常见场景
- 天气、股票等实时数据 → 直接调用搜索
- 最新新闻、事件 → 直接调用搜索
- 特定人物、地点的最新信息 → 直接调用搜索
- 技术文档更新 → 直接调用搜索
`;
  }

  /**
   * 生成 UUID
   */
  private generateUUID(): string {
    // 生成随机 UUID (简化版本)
    const chars = '0123456789abcdef';
    let uuid = '';
    for (let i = 0; i < 6; i++) {
      const randomIndex = Math.floor(Math.random() * 16);
      uuid += chars.charAt(randomIndex);
    }
    return uuid;
  }
}
