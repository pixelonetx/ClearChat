/**
 * ToolCallHandler.ets
 * 
 * 工具调用处理器
 * 负责执行搜索工具调用、收集结果、继续对话
 * 独立的模块便于测试和重用
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchToolService } from './search/SearchToolService';
import { SearchResult } from './search/SearchModels';
import { ChatMessage } from './DataModels';
import { DatabaseManager } from './DatabaseManager';

const DOMAIN = 0xFF00;
const TAG = 'ToolCallHandler';

/**
 * 工具调用数据
 */
export interface ToolCall {
  id: string;
  name: string;
  arguments?: string;
}

/**
 * 搜索工具参数
 */
export interface SearchToolArgs {
  query: string;
  resultSize?: number;
}

/**
 * 工具调用执行结果
 */
export interface ToolCallResult {
  toolCallId: string;
  toolName: string;
  status: 'success' | 'error';
  result: string;
  metadata?: object;
}

export class ToolCallHandler {
  private searchToolService: SearchToolService;
  private databaseManager: DatabaseManager;
  private onSearchStart?: (query: string) => void;
  private onSearchComplete?: (query: string, resultCount: number, executionTime: number) => void;
  private onSearchError?: (query: string, error: string) => void;

  constructor(
    searchToolService: SearchToolService,
    databaseManager: DatabaseManager,
    callbacks?: {
      onSearchStart?: (query: string) => void;
      onSearchComplete?: (query: string, resultCount: number, executionTime: number) => void;
      onSearchError?: (query: string, error: string) => void;
    }
  ) {
    this.searchToolService = searchToolService;
    this.databaseManager = databaseManager;
    this.onSearchStart = callbacks?.onSearchStart;
    this.onSearchComplete = callbacks?.onSearchComplete;
    this.onSearchError = callbacks?.onSearchError;
  }

  /**
   * 执行工具调用
   */
  async executeToolCall(toolCall: ToolCall): Promise<ToolCallResult> {
    hilog.info(DOMAIN, TAG, '🔧 Executing tool call: %{public}s', toolCall.name);

    if (toolCall.name !== 'search_web') {
      return {
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        status: 'error',
        result: `不支持的工具: ${toolCall.name}`
      };
    }

    try {
      // 解析参数
      const argsStr = toolCall.arguments || '{}';
      let args: SearchToolArgs;
      try {
        args = JSON.parse(argsStr) as SearchToolArgs;
      } catch (e) {
        return {
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: 'error',
          result: `参数解析失败: ${String(e)}`
        };
      }

      const query = args.query;
      if (!query || query.trim().length === 0) {
        return {
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: 'error',
          result: '搜索查询不能为空'
        };
      }

      // 调用搜索开始回调
      this.onSearchStart?.(query);

      // 执行搜索
      const startTime = Date.now();
      hilog.info(DOMAIN, TAG, '🔍 Searching: %{public}s', query);

      const searchResult = await this.searchToolService.executeSearch(query, args.resultSize);

      const executionTime = Date.now() - startTime;

      // 调用搜索完成回调
      this.onSearchComplete?.(query, searchResult.items.length, executionTime);

      // 格式化结果
      const resultText = this.formatSearchResult(searchResult, query, executionTime);

      return {
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        status: 'success',
        result: resultText,
        metadata: {
          query: query,
          resultCount: searchResult.items.length,
          executionTime: executionTime
        }
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      hilog.error(DOMAIN, TAG, '❌ Tool execution failed: %{public}s', errorMsg);

      // 调用搜索错误回调
      const argsStr = toolCall.arguments || '{}';
      let query = '';
      try {
        const args = JSON.parse(argsStr) as SearchToolArgs;
        query = args.query;
      } catch (e) {
        // ignore
      }
      if (query) {
        this.onSearchError?.(query, errorMsg);
      }

      return {
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        status: 'error',
        result: `搜索失败: ${errorMsg}`
      };
    }
  }

  /**
   * 格式化搜索结果
   */
  private formatSearchResult(searchResult: SearchResult, query: string, executionTime: number): string {
    let resultText = '';

    // 添加摘要
    if (searchResult.answer) {
      resultText += `📋 AI 摘要:\n${searchResult.answer}\n\n`;
    }

    // 添加结果
    resultText += `📊 搜索结果 (${searchResult.items.length} 项，耗时 ${executionTime}ms):\n\n`;

    for (const item of searchResult.items) {
      resultText += `**${item.index}. ${item.title}** [${item.index}:${item.id}]\n`;
      resultText += `${item.url}\n`;
      resultText += `${item.text}\n`;
      if (item.source) {
        resultText += `来源: ${item.source}\n`;
      }
      resultText += '\n';
    }

    return resultText;
  }

  /**
   * 创建工具结果消息
   */
  createToolResultMessage(
    toolCallResult: ToolCallResult,
    conversationId: string
  ): ChatMessage {
    const message = new ChatMessage(
      toolCallResult.result,
      'tool',
      { conversationId: conversationId, timestamp: Date.now() }
    );

    message.metadata = JSON.stringify({
      tool_call_id: toolCallResult.toolCallId,
      tool_name: toolCallResult.toolName,
      status: toolCallResult.status,
      ...toolCallResult.metadata
    });

    return message;
  }

  /**
   * 创建搜索状态消息
   */
  createSearchStatusMessage(
    query: string,
    status: 'searching' | 'completed' | 'error',
    resultCount?: number,
    conversationId?: string
  ): ChatMessage {
    let content = '';
    switch (status) {
      case 'searching':
        content = `🔍 正在搜索: ${query}`;
        break;
      case 'completed':
        content = `✅ 搜索完成: ${query}\n返回 ${resultCount || 0} 条结果`;
        break;
      case 'error':
        content = `❌ 搜索失败: ${query}`;
        break;
    }

    return new ChatMessage(
      content,
      'assistant',
      { conversationId: conversationId || '', timestamp: Date.now() }
    );
  }
}
