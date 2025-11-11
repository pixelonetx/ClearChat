/**
 * SearchIntegrationExample.ets
 * 
 * 搜索模块集成示例
 * 展示如何在你的 ClearChat 应用中使用搜索功能
 */

import { router } from '@kit.ArkUI';
import { SearchToolService } from './SearchToolService';
import { SearchConfigManager } from './SearchConfigManager';
import { SearchServiceFactory } from './SearchServiceFactory';
import {
  SearchResult,
  TavilyOptions,
  ExaOptions,
  ZhipuOptions,
  SearchCommonOptions
} from './SearchModels';

/**
 * 示例 1: 基本搜索执行
 */
export async function exampleBasicSearch(): Promise<void> {
  try {
    const configManager = SearchConfigManager.getInstance();
    
    // 获取选中的搜索服务
    const selectedService = configManager.getSelectedService();
    if (!selectedService) {
      console.error('未配置搜索服务');
      return;
    }

    // 获取搜索服务实例
    const service = SearchServiceFactory.getService(selectedService);
    
    // 定义搜索选项
    const commonOptions: SearchCommonOptions = {
      resultSize: 10,
      timeout: 10000
    };

    // 执行搜索
    const result: SearchResult = await service.search(
      'HarmonyOS 开发',
      commonOptions,
      selectedService
    );

    // 处理结果
    console.log(`执行时间: ${result.executionTime}ms`);
    console.log(`找到 ${result.items.length} 个结果`);
    
    if (result.answer) {
      console.log(`AI 摘要: ${result.answer}`);
    }

    result.items.forEach(item => {
      console.log(`- ${item.title}`);
      console.log(`  URL: ${item.url}`);
      console.log(`  摘要: ${item.text}`);
    });

  } catch (error) {
    console.error('搜索失败:', error);
  }
}

/**
 * 示例 2: AI 工具集成
 */
export async function exampleAIToolIntegration(): Promise<void> {
  try {
    const toolService = SearchToolService.getInstance();

    // 获取工具定义（发送给 AI 模型）
    const toolDef = toolService.getToolDefinition();
    console.log('工具定义:', JSON.stringify(toolDef, null, 2));

    // 获取系统提示词
    const systemPrompt = toolService.getSystemPrompt();
    console.log('系统提示词:', systemPrompt);

    // 模拟 AI 调用搜索工具
    const searchResult = await toolService.executeSearchAsToolResult(
      '最新的 AI 发展趋势',
      'tool-call-001'
    );

    console.log('工具结果:', searchResult);

  } catch (error) {
    console.error('AI 集成失败:', error);
  }
}

/**
 * 示例 3: 配置管理
 */
export async function exampleConfigManagement(context: any): Promise<void> {
  try {
    const configManager = SearchConfigManager.getInstance();

    // 初始化（首次使用）
    if (!configManager.getConfig()) {
      await configManager.init(context);
    }

    // 添加 Tavily 服务
    const tavilyService = new TavilyOptions(
      'tavily-1',
      'your-tavily-api-key'
    );
    await configManager.addService(tavilyService);

    // 添加 Exa 服务
    const exaService = new ExaOptions(
      'exa-1',
      'your-exa-api-key'
    );
    await configManager.addService(exaService);

    // 添加智谱服务
    const zhipuService = new ZhipuOptions(
      'zhipu-1',
      'your-zhipu-api-key'
    );
    await configManager.addService(zhipuService);

    // 设置选中的服务（使用第一个）
    await configManager.setSelectedService(0);

    // 设置搜索选项
    await configManager.setCommonOptions({
      resultSize: 15,
      timeout: 15000
    });

    // 启用网络搜索
    await configManager.setWebSearchEnabled(true);

    console.log('配置已保存');

  } catch (error) {
    console.error('配置管理失败:', error);
  }
}

/**
 * 示例 4: 多个搜索服务的对比搜索
 */
export async function exampleComparisonSearch(query: string): Promise<void> {
  try {
    const configManager = SearchConfigManager.getInstance();
    const config = configManager.getConfig();

    console.log(`使用 ${config.enabledServices.length} 个搜索服务对比搜索: "${query}"`);

    const results: Map<string, SearchResult> = new Map();

    // 逐个搜索服务执行搜索
    for (const service of config.enabledServices) {
      try {
        const searchService = SearchServiceFactory.getService(service);
        const result = await searchService.search(
          query,
          config.commonOptions,
          service
        );

        results.set(service.id, result);
        console.log(`✓ ${service.id}: 获得 ${result.items.length} 个结果`);

      } catch (error) {
        console.error(`✗ ${service.id} 搜索失败:`, error);
      }
    }

    // 汇总结果
    console.log('\n搜索结果汇总:');
    results.forEach((result, serviceId) => {
      console.log(`\n来自 ${serviceId} 的结果:`);
      result.items.slice(0, 3).forEach((item, index) => {
        console.log(`  ${index + 1}. ${item.title}`);
      });
    });

  } catch (error) {
    console.error('对比搜索失败:', error);
  }
}

/**
 * 示例 5: 与 NetworkManagerV2 集成
 * （为聊天流中添加搜索功能）
 */
export async function exampleIntegrationWithChat(
  query: string
): Promise<void> {
  try {
    const toolService = SearchToolService.getInstance();
    const configManager = SearchConfigManager.getInstance();

    // 检查网络搜索是否启用
    if (!configManager.getConfig().enableWebSearch) {
      console.log('网络搜索未启用');
      return;
    }

    // 执行搜索
    const searchResult = await toolService.executeSearch(query, 5);

    // 格式化搜索结果为聊天消息
    const formattedResult = {
      type: 'web_search',
      query: query,
      answer: searchResult.answer,
      items: searchResult.items.map(item => ({
        title: item.title,
        url: item.url,
        text: item.text,
        source: item.source,
        index: item.index,
        id: item.id
      })),
      executionTime: searchResult.executionTime
    };

    console.log('搜索结果已准备好集成到聊天消息中:');
    console.log(JSON.stringify(formattedResult, null, 2));

    // 这个结果可以在 Chat.ets 中使用
    // 用于展示搜索结果或提供给 AI 模型

  } catch (error) {
    console.error('集成失败:', error);
  }
}

/**
 * 示例 6: 错误处理最佳实践
 */
export async function exampleErrorHandling(query: string): Promise<void> {
  try {
    const configManager = SearchConfigManager.getInstance();
    const selectedService = configManager.getSelectedService();

    if (!selectedService) {
      throw new Error('未配置任何搜索服务。请先配置至少一个搜索提供商。');
    }

    if (!configManager.getConfig().enableWebSearch) {
      throw new Error('网络搜索功能未启用。请先启用它。');
    }

    if (!query || query.trim().length === 0) {
      throw new Error('搜索查询不能为空。');
    }

    const service = SearchServiceFactory.getService(selectedService);

    const result = await service.search(
      query,
      configManager.getConfig().commonOptions,
      selectedService
    );

    if (result.items.length === 0) {
      console.warn(`未找到与 "${query}" 相关的结果`);
      return;
    }

    console.log(`成功找到 ${result.items.length} 个结果`);

  } catch (error) {
    // 细粒度错误处理
    if (error instanceof Error) {
      const message = error.message.toLowerCase();

      if (message.includes('api')) {
        console.error('API 错误 - 请检查 API 密钥是否正确');
      } else if (message.includes('超时')) {
        console.error('搜索超时 - 网络连接可能较慢');
      } else if (message.includes('未配置')) {
        console.error('配置错误 - 请先配置搜索服务');
      } else if (message.includes('未启用')) {
        console.error('功能未启用 - 请启用网络搜索功能');
      } else {
        console.error('搜索失败:', error.message);
      }
    } else {
      console.error('未知错误:', error);
    }
  }
}

/**
 * 使用这些示例：
 * 
 * 1. 在 Chat.ets 中启用搜索：
 * ```typescript
 * import { exampleBasicSearch } from './SearchIntegrationExample';
 * 
 * // 在用户输入或 AI 调用时
 * if (userQuery.includes('搜索')) {
 *   await exampleBasicSearch();
 * }
 * ```
 * 
 * 2. 在 Settings.ets 中配置搜索：
 * ```typescript
 * import { exampleConfigManagement } from './SearchIntegrationExample';
 * 
 * // 在设置页面初始化时
 * await exampleConfigManagement(this.context);
 * ```
 * 
 * 3. 在消息处理中集成搜索：
 * ```typescript
 * import { exampleAIToolIntegration } from './SearchIntegrationExample';
 * 
 * // 在准备工具定义时
 * const tools = await exampleAIToolIntegration();
 * ```
 */
