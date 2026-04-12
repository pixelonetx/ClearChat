/**
 * ChatStreamingService.ets
 * 流式消息处理服务
 *
 * 职责：
 * - 设置流式事件监听器（DATA / METADATA / COMPLETE / ERROR / TOOL_CALL）
 * - 处理重生成流式事件
 * - 处理工具调用（搜索）并继续对话
 * - 流式消息的初始化、追加、持久化
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage, ChatMessageMetadataUpdate, StreamMetadata, Citation } from './DataModels';
import { DatabaseManager } from './DatabaseManager';
import { NetworkManagerV2 } from './NetworkManagerV2';
import { StreamEventEmitter, StreamEventType, EventPayload, ToolCallData } from './StreamEventEmitter';
import { SearchToolService } from './search/SearchToolService';
import { SearchConfigManager } from './search/SearchConfigManager';
import { SearchResult } from './search/SearchModels';
import { AbortController, createAbortController } from '../interfaces/AbortController';
import { cloneChatMessage, getFriendlyErrorMessage, shouldGenerateTitle } from '../viewmodels/ChatUtils';
import { TitleGenerationService } from './TitleGenerationService';

const DOMAIN = 0x0000;
const TAG = 'ChatStreamingService';

// 搜索工具参数接口
interface SearchToolArgs {
  query: string;
  resultSize?: number;
}

// 流式消息初始化结果
export interface StreamingMessageResult {
  index: number;
  id: number;
}

// 模型信息接口
export interface ModelInfo {
  modelName: string;
  providerName: string;
}

// API 配置接口
export interface ApiConfig {
  apiUrl: string;
  apiKey: string;
  modelName: string;
}

/**
 * 流式消息的状态回调接口
 * 由 Chat 页面实现，ChatStreamingService 通过回调驱动 UI 状态更新
 */
export interface StreamingCallbacks {
  /** 替换指定索引的消息（创建克隆、更新、触发响应式刷新） */
  replaceMessageAt: (index: number, updater: (message: ChatMessage) => void) => void;

  /** 追加消息到列表末尾，返回索引 */
  appendMessage: (message: ChatMessage) => number;

  /** 获取消息列表 */
  getMessages: () => ChatMessage[];

  /** 获取当前对话 ID */
  getCurrentConversationId: () => string | undefined;

  /** 获取当前模型信息 */
  getCurrentModelInfo: () => ModelInfo;

  /** 获取递增逻辑时间戳 */
  getNextTimestamp: () => number;

  /** 显示 Toast */
  showToast: (message: string, duration?: number) => void;

  /** 滚动到底部 */
  scrollToBottom: () => void;

  /** 设置加载状态 */
  setLoadingState: (isLoading: boolean, isGenerating: boolean) => void;

  /** 设置 AbortController */
  setAbortController: (controller: AbortController | null) => void;

  /** 获取是否用户主动停止 */
  isUserAborted: () => boolean;

  /** 设置用户停止标记 */
  setUserAborted: (value: boolean) => void;

  /** 获取 API 配置 */
  getApiConfig: () => ApiConfig | null;

  /** 获取当前对话标题 */
  getCurrentConversationTitle: () => string;

  /** 通知标题已更新 */
  onTitleGenerated: (title: string) => Promise<void>;
}

export class ChatStreamingService {
  private databaseManager = DatabaseManager.getInstance();
  private networkManager = NetworkManagerV2.getInstance();
  private titleGenerationService: TitleGenerationService = new TitleGenerationService();
  private searchToolService = SearchToolService.getInstance();
  private searchConfigManager = SearchConfigManager.getInstance();
  private callbacks: StreamingCallbacks;

  constructor(callbacks: StreamingCallbacks) {
    this.callbacks = callbacks;
  }

  /**
   * 初始化流式 AI 消息并保存到数据库
   */
  async initializeStreamingMessage(
    userMessage: ChatMessage,
    conversationId: string
  ): Promise<StreamingMessageResult> {
    const modelInfo = this.callbacks.getCurrentModelInfo();
    const streamingMessage = new ChatMessage('', 'assistant', {
      conversationId: conversationId,
      modelName: modelInfo.modelName,
      providerName: modelInfo.providerName,
      timestamp: this.callbacks.getNextTimestamp()
    });

    const index = this.callbacks.appendMessage(streamingMessage);
    const id = await this.databaseManager.insertChatMessage(streamingMessage);

    this.callbacks.replaceMessageAt(index, (msg) => {
      msg.id = id;
    });

    return { index, id };
  }

  /**
   * 将流式数据块追加到消息中
   */
  appendChunkToMessage(messageIndex: number, chunk: string, conversationId: string): void {
    if (this.callbacks.getCurrentConversationId() !== conversationId) {
      return;
    }
    const messages = this.callbacks.getMessages();
    if (messageIndex < messages.length) {
      this.callbacks.replaceMessageAt(messageIndex, (msg) => {
        msg.content += chunk;
      });
    }
  }

  /**
   * 更新流式消息的元数据
   */
  updateStreamingMessageMetadata(
    streamingMessageIndex: number,
    meta: StreamMetadata,
    conversationId: string
  ): void {
    if (this.callbacks.getCurrentConversationId() !== conversationId) {
      return;
    }
    const messages = this.callbacks.getMessages();
    if (streamingMessageIndex >= messages.length) {
      return;
    }

    let metadataChanged = false;
    this.callbacks.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
      if (meta.id && message.providerMessageId !== meta.id) {
        message.providerMessageId = meta.id;
        metadataChanged = true;
      }
      if (meta.systemFingerprint && message.systemFingerprint !== meta.systemFingerprint) {
        message.systemFingerprint = meta.systemFingerprint;
        metadataChanged = true;
      }
      if (meta.created !== undefined) {
        const createdTimestamp = meta.created * 1000;
        if (message.timestamp < createdTimestamp) {
          message.timestamp = createdTimestamp;
          message.providerCreatedAt = meta.created;
          metadataChanged = true;
        } else if (message.providerCreatedAt !== meta.created) {
          message.providerCreatedAt = meta.created;
          metadataChanged = true;
        }
      }
    });

    if (metadataChanged) {
      const persistedMessage = this.callbacks.getMessages()[streamingMessageIndex];
      if (persistedMessage?.id !== undefined) {
        const update: ChatMessageMetadataUpdate = {
          timestamp: persistedMessage.timestamp,
          providerMessageId: persistedMessage.providerMessageId ?? null,
          providerCreatedAt: persistedMessage.providerCreatedAt ?? null,
          systemFingerprint: persistedMessage.systemFingerprint ?? null,
          modelName: persistedMessage.modelName ?? null,
          providerName: persistedMessage.providerName ?? null
        };
        if (meta && meta.citations) {
          update.citations = meta.citations as Citation[];
          this.callbacks.replaceMessageAt(streamingMessageIndex, (message: ChatMessage) => {
            if (update.citations) {
              message.citations = update.citations as Citation[];
            }
          });
        }
        this.databaseManager.updateChatMessageMetadata(persistedMessage.id, update)
          .catch(() => {});
      }
    }
  }

  /**
   * 处理流式请求完成，通过回调重置 UI 状态
   */
  handleStreamComplete(): void {
    this.callbacks.setLoadingState(false, false);
    this.callbacks.setAbortController(null);
    this.callbacks.setUserAborted(false);
  }

  /**
   * 异步持久化流式消息到数据库
   */
  async persistStreamedMessage(
    messageIndex: number,
    conversationId: string,
    currentConversationTitle: string
  ): Promise<void> {
    const messages = this.callbacks.getMessages();
    if (messageIndex >= messages.length) {
      return;
    }

    const message = messages[messageIndex];
    if (!message.id) {
      return;
    }

    try {
      await this.databaseManager.updateChatMessage(message.id, message.content);

      if (!this.callbacks.isUserAborted() && shouldGenerateTitle(messages, currentConversationTitle)) {
        await this.generateConversationTitle();
      }

      await this.databaseManager.updateConversationMessageCount(conversationId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Error persisting message: %{public}s', String(error));
    }
  }

  /**
   * 处理流式请求错误
   */
  handleStreamError(messageIndex: number, error: Error, isToolContinuation: boolean = false): void {
    const friendlyError = getFriendlyErrorMessage(error);

    if (!this.callbacks.isUserAborted()) {
      const messages = this.callbacks.getMessages();
      if (messageIndex < messages.length) {
        this.callbacks.replaceMessageAt(messageIndex, (msg) => {
          if (msg.content.length === 0) {
            msg.content = `[错误] ${friendlyError}`;
          } else {
            const errorPrefix = isToolContinuation ? '继续生成失败' : '生成过程中出现错误';
            msg.content += `\n\n[错误] ${errorPrefix}: ${friendlyError}`;
          }
        });
      }
    }

    this.callbacks.setLoadingState(false, false);
    this.callbacks.setAbortController(null);
    this.callbacks.setUserAborted(false);
    this.callbacks.showToast(friendlyError);
  }

  /**
   * 设置流式事件处理器
   */
  setupStreamEventHandlers(
    emitter: StreamEventEmitter,
    streamingMessageIndex: number,
    conversationId: string,
    currentConversationTitle: string,
    isToolContinuation: boolean = false
  ): void {
    hilog.info(DOMAIN, TAG,
      'Setting up stream event handlers for message index: %{public}d, isToolContinuation=%{public}s',
      streamingMessageIndex, String(isToolContinuation));

    let toolCallHandled = false;

    emitter.on(StreamEventType.DATA, (payload: EventPayload) => {
      const chunk = payload as string;
      this.appendChunkToMessage(streamingMessageIndex, chunk, conversationId);
    });

    emitter.on(StreamEventType.METADATA, (payload: EventPayload) => {
      const meta = payload as StreamMetadata;
      this.updateStreamingMessageMetadata(streamingMessageIndex, meta, conversationId);
    });

    emitter.once(StreamEventType.COMPLETE, () => {
      hilog.info(DOMAIN, TAG, 'Received COMPLETE event for message index: %{public}d, toolCallHandled=%{public}s',
        streamingMessageIndex, String(toolCallHandled));

      if (!toolCallHandled) {
        this.handleStreamComplete();
        this.persistStreamedMessage(streamingMessageIndex, conversationId, currentConversationTitle)
          .catch(() => {});
      }
    });

    emitter.on(StreamEventType.ERROR, (payload: EventPayload) => {
      const error = payload as Error;
      hilog.error(DOMAIN, TAG, 'Received ERROR event: %{public}s', String(error));
      this.handleStreamError(streamingMessageIndex, error, isToolContinuation);
    });

    emitter.on(StreamEventType.WARNING, () => {});

    emitter.once(StreamEventType.TOOL_CALL, (payload: EventPayload) => {
      const toolCalls = payload as ToolCallData[];
      toolCallHandled = true;

      this.handleToolCalls(toolCalls, streamingMessageIndex, conversationId)
        .catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to handle tool calls: %{public}s', String(err));
        });
    });
  }

  /**
   * 设置重生成流式事件处理器
   */
  setupRegenerationStreamEventHandlers(
    emitter: StreamEventEmitter,
    streamingMessageIndex: number,
    conversationId: string
  ): void {
    emitter.on(StreamEventType.DATA, (payload: EventPayload) => {
      const chunk = payload as string;
      if (this.callbacks.getCurrentConversationId() !== conversationId) {
        return;
      }
      const messages = this.callbacks.getMessages();
      if (streamingMessageIndex >= messages.length || !messages[streamingMessageIndex]) {
        return;
      }

      this.callbacks.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
        regeneratedMessage.content += chunk;
      });

      hilog.debug(DOMAIN, TAG, 'Regenerated content length=%{public}d',
        this.callbacks.getMessages()[streamingMessageIndex].content.length);
    });

    emitter.on(StreamEventType.METADATA, (payload: EventPayload) => {
      const meta = payload as StreamMetadata;
      this.updateStreamingMessageMetadata(streamingMessageIndex, meta, conversationId);
    });

    emitter.once(StreamEventType.COMPLETE, () => {
      this.callbacks.setLoadingState(false, false);
      this.callbacks.setAbortController(null);

      (async () => {
        try {
          if (this.callbacks.getCurrentConversationId() === conversationId) {
            const messages = this.callbacks.getMessages();
            if (streamingMessageIndex < messages.length && messages[streamingMessageIndex]) {
              const regeneratedMessage = messages[streamingMessageIndex];

              if (regeneratedMessage.id !== undefined) {
                await this.databaseManager.updateChatMessage(regeneratedMessage.id, regeneratedMessage.content);
                hilog.info(DOMAIN, TAG, 'Regenerated message updated in DB ID=%{public}s',
                  String(regeneratedMessage.id));
              } else {
                const savedId = await this.databaseManager.insertChatMessage(regeneratedMessage);
                this.callbacks.replaceMessageAt(streamingMessageIndex, (messageToPersist: ChatMessage) => {
                  messageToPersist.id = savedId;
                });
              }
              setTimeout(() => {
                this.callbacks.scrollToBottom();
              }, 100);
            }
          }
        } catch (dbError) {
          hilog.error(DOMAIN, TAG, 'Error during regeneration database operations: %{public}s', String(dbError));
        }
      })();
    });

    emitter.on(StreamEventType.ERROR, (payload: EventPayload) => {
      const error = payload as Error;

      if (this.callbacks.getCurrentConversationId() === conversationId) {
        const messages = this.callbacks.getMessages();
        if (streamingMessageIndex < messages.length && messages[streamingMessageIndex]) {
          this.callbacks.replaceMessageAt(streamingMessageIndex, (regeneratedMessage: ChatMessage) => {
            regeneratedMessage.content = `重新生成失败: ${error.message || error}`;
          });
        }
      }

      this.callbacks.setLoadingState(false, false);
      this.callbacks.setAbortController(null);
      this.callbacks.showToast('重新生成失败');
    });
  }

  /**
   * 获取联网搜索工具定义数组
   */
  getSearchTools(enableWebSearch: boolean): object[] {
    if (!enableWebSearch) {
      return [];
    }
    try {
      const searchConfig = this.searchConfigManager.getConfig();
      if (searchConfig && searchConfig.enabledServices.length > 0) {
        const selectedService = this.searchConfigManager.getSelectedService();
        if (selectedService) {
          const toolDef = this.searchToolService.getToolDefinition();
          hilog.info(DOMAIN, TAG, 'Web search enabled with service: %{public}s', selectedService.type);
          return [toolDef as object];
        }
      }
    } catch (configError) {
      hilog.warn(DOMAIN, TAG, 'Search config error: %{public}s', String(configError));
    }
    return [];
  }

  /**
   * 准备 API 消息列表（最近 10 条上下文）
   */
  prepareMessagesForAPI(userMessage: ChatMessage): ChatMessage[] {
    const messages = this.callbacks.getMessages();
    const endIndex = messages.length - 1;
    const startIndex = Math.max(0, endIndex - 10);
    const messagesForAI = messages.slice(startIndex, endIndex);
    if (messagesForAI.length === 0) {
      messagesForAI.push(cloneChatMessage(userMessage));
    }
    return messagesForAI;
  }

  /**
   * 处理工具调用
   */
  private async handleToolCalls(
    toolCalls: ToolCallData[],
    assistantMessageIndex: number,
    conversationId: string
  ): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Handling %{public}d tool calls', toolCalls.length);

    const messages = this.callbacks.getMessages();
    if (assistantMessageIndex < messages.length) {
      const formattedToolCalls: import('./DataModels').ToolCall[] =
        toolCalls.map((tc): import('./DataModels').ToolCall => {
          const toolFunction: import('./DataModels').ToolFunction = {
            name: tc.name,
            arguments: tc.arguments
          };
          return {
            id: tc.id,
            type: tc.type || 'function',
            function: toolFunction
          };
        });

      this.callbacks.replaceMessageAt(assistantMessageIndex, (msg) => {
        msg.toolCalls = formattedToolCalls;
      });

      hilog.info(DOMAIN, TAG, 'Saved %{public}d tool calls to assistant message', formattedToolCalls.length);
    }

    for (const toolCall of toolCalls) {
      hilog.info(DOMAIN, TAG, 'Processing tool call: id=%{public}s, name=%{public}s, type=%{public}s',
        String(toolCall.id || 'MISSING'), String(toolCall.name), String(toolCall.type));

      if (toolCall.name === 'search_web' && toolCall.arguments) {
        try {
          if (!toolCall.id) {
            hilog.error(DOMAIN, TAG, 'Tool call missing required ID field');
            throw new Error('工具调用缺少必需的 ID 字段，无法继续处理');
          }

          const args = JSON.parse(toolCall.arguments) as SearchToolArgs;
          const query = args.query;

          hilog.info(DOMAIN, TAG, 'Executing search for query: %{public}s with toolCallId: %{public}s',
            query, toolCall.id);

          const searchResult = await this.searchToolService.executeSearch(query, args.resultSize);

          // 保存搜索结果到 AI 消息的 citations
          if (assistantMessageIndex < this.callbacks.getMessages().length) {
            const assistantMessage = this.callbacks.getMessages()[assistantMessageIndex];
            const citations: Citation[] = searchResult.items.map((item): Citation => ({
              title: item.title,
              url: item.url,
              snippet: item.text
            }));

            this.callbacks.replaceMessageAt(assistantMessageIndex, (msg) => {
              msg.citations = citations;
            });

            if (assistantMessage.id) {
              const update: ChatMessageMetadataUpdate = {
                timestamp: assistantMessage.timestamp,
                providerMessageId: assistantMessage.providerMessageId ?? null,
                providerCreatedAt: assistantMessage.providerCreatedAt ?? null,
                systemFingerprint: assistantMessage.systemFingerprint ?? null,
                modelName: assistantMessage.modelName ?? null,
                providerName: assistantMessage.providerName ?? null,
                citations: citations
              };
              await this.databaseManager.updateChatMessageMetadata(assistantMessage.id, update);
            }
          }

          await this.continueConversationWithToolResult(
            conversationId, assistantMessageIndex, searchResult, toolCall.id, toolCall.name
          );

        } catch (error) {
          hilog.error(DOMAIN, TAG, 'Tool execution failed: %{public}s', String(error));
          const err = error instanceof Error ? error : new Error(String(error));

          let errorMessage = '搜索失败';
          if (err.message.includes('未配置') || err.message.includes('未启用') ||
              err.message.includes('未选择') || err.message.includes('缺少')) {
            errorMessage = err.message;
          } else {
            errorMessage = `搜索失败: ${err.message}`;
          }

          if (assistantMessageIndex < this.callbacks.getMessages().length) {
            this.callbacks.replaceMessageAt(assistantMessageIndex, (msg) => {
              if (msg.content.length === 0) {
                msg.content = `[搜索失败] ${errorMessage}\n\n请检查搜索配置或稍后重试。`;
              } else {
                msg.content += `\n\n[搜索失败] ${errorMessage}\n请检查搜索配置或稍后重试。`;
              }
            });
          }

          this.callbacks.setLoadingState(false, false);
          this.callbacks.setAbortController(null);
          continue;
        }
      }
    }
  }

  /**
   * 工具执行后继续对话
   */
  private async continueConversationWithToolResult(
    conversationId: string,
    assistantMessageIndex: number,
    searchResult: SearchResult | undefined,
    toolCallId: string,
    toolName: string | undefined
  ): Promise<void> {
    if (this.callbacks.getCurrentConversationId() !== conversationId) {
      return;
    }

    this.callbacks.setLoadingState(true, true);
    const abortController = createAbortController();
    this.callbacks.setAbortController(abortController);

    hilog.info(DOMAIN, TAG, 'Starting continueConversationWithToolResult');

    try {
      const apiConfig = this.callbacks.getApiConfig();
      if (!apiConfig) {
        throw new Error('API 配置不可用');
      }

      // 构建工具结果内容
      let toolContent = '';
      if (searchResult) {
        if (searchResult.answer) {
          toolContent = `搜索摘要: ${searchResult.answer}\n\n`;
        }
        toolContent += '详细搜索结果:\n';
        for (const item of searchResult.items) {
          toolContent += `[${item.index || 0}] 标题: ${item.title}\n内容: ${item.text}\nURL: ${item.url}\n\n`;
        }
      }

      if (!toolCallId) {
        hilog.error(DOMAIN, TAG, 'Tool call ID is missing, cannot create tool message');
        throw new Error('工具调用ID缺失，无法继续对话');
      }

      const toolResultMessage = new ChatMessage(
        toolContent,
        'tool',
        { conversationId: conversationId, timestamp: this.callbacks.getNextTimestamp(), toolCallId: toolCallId }
      );
      toolResultMessage.id = -toolContent.length - Math.floor(Math.random() * 10000);

      const messages = this.callbacks.getMessages();
      const previousAssistantMsg = messages[assistantMessageIndex];

      const contextMessages = messages.slice(0, assistantMessageIndex + 1);
      contextMessages.push(toolResultMessage);

      const modelInfo = this.callbacks.getCurrentModelInfo();
      this.callbacks.replaceMessageAt(assistantMessageIndex, (msg) => {
        msg.content = '';
        msg.modelName = modelInfo.modelName;
        msg.providerName = modelInfo.providerName;
        msg.timestamp = this.callbacks.getNextTimestamp();
        msg.toolCalls = previousAssistantMsg.toolCalls ? [...previousAssistantMsg.toolCalls] : [];
      });

      const streamingIndex = assistantMessageIndex;
      const messagesForAI = contextMessages.slice(Math.max(0, contextMessages.length - 20));

      hilog.info(DOMAIN, TAG, 'Continuing conversation. Context length: %{public}d', messagesForAI.length);

      for (let i = 0; i < messagesForAI.length; i++) {
        const msg = messagesForAI[i];
        hilog.info(DOMAIN, TAG,
          'Message[%{public}d]: role=%{public}s, hasToolCallId=%{public}s, hasToolCalls=%{public}s, contentLength=%{public}d',
          i, msg.role, String(!!msg.toolCallId), String(!!(msg.toolCalls && msg.toolCalls.length > 0)),
          msg.content.length);
      }

      const tools = this.getSearchTools(true);

      hilog.info(DOMAIN, TAG, 'Request params: apiUrl=%{public}s, model=%{public}s, messageCount=%{public}d',
        apiConfig.apiUrl.substring(0, 30), apiConfig.modelName, messagesForAI.length);

      const emitter = await this.networkManager.sendStreamChatRequestV2(
        apiConfig.apiUrl,
        apiConfig.apiKey,
        apiConfig.modelName,
        messagesForAI,
        {
          tools: tools.length > 0 ? tools : undefined,
          abortController: abortController,
          requestTimeout: 60000
        }
      );

      // 设置事件处理器
      this.setupStreamEventHandlers(
        emitter, streamingIndex, conversationId,
        this.callbacks.getCurrentConversationTitle(), true
      );

      // 超时保护
      const timeoutId = setTimeout(() => {
        if (true) { // 检查是否仍在加载 — 通过回调判断
          hilog.error(DOMAIN, TAG, 'Stream timeout after 60s, forcing state reset');
          this.callbacks.setLoadingState(false, false);
          this.callbacks.setAbortController(null);
          this.callbacks.showToast('请求超时，请重试');

          if (streamingIndex < this.callbacks.getMessages().length) {
            this.callbacks.replaceMessageAt(streamingIndex, (msg) => {
              if (!msg.content || msg.content.length === 0) {
                msg.content = '[超时] 未收到响应，请检查网络或重试';
              } else {
                msg.content += '\n\n[超时] 响应中断';
              }
            });
          }
        }
      }, 60000);

      emitter.once(StreamEventType.COMPLETE, () => {
        clearTimeout(timeoutId);

        this.callbacks.setLoadingState(false, false);
        this.callbacks.setAbortController(null);

        this.persistStreamedMessage(
          streamingIndex, conversationId, this.callbacks.getCurrentConversationTitle()
        ).catch((err: Error) => {
            hilog.error(DOMAIN, TAG, 'Failed to persist message after tool continuation: %{public}s', String(err));
          });
      });

      emitter.once(StreamEventType.ERROR, () => {
        clearTimeout(timeoutId);
      });

    } catch (error) {
      this.callbacks.setLoadingState(false, false);
      this.callbacks.setAbortController(null);
      const friendlyError = getFriendlyErrorMessage(error instanceof Error ? error : new Error(String(error)));

      const streamingIndex = assistantMessageIndex;
      if (streamingIndex < this.callbacks.getMessages().length) {
        this.callbacks.replaceMessageAt(streamingIndex, (msg) => {
          if (msg.content.length === 0) {
            msg.content = `[错误] ${friendlyError}`;
          } else {
            msg.content += `\n\n[错误] 继续生成失败: ${friendlyError}`;
          }
        });
      }

      this.callbacks.showToast(friendlyError);
    }
  }

  /**
   * 自动生成对话标题
   */
  private async generateConversationTitle(): Promise<void> {
    const apiConfig = this.callbacks.getApiConfig();
    if (!apiConfig) {
      return;
    }

    try {
      const messages = this.callbacks.getMessages();
      const title: string = await this.titleGenerationService.generateTitle(
        messages, apiConfig.apiKey, apiConfig.apiUrl, apiConfig.modelName
      );
      if (title) {
        await this.callbacks.onTitleGenerated(title);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to generate conversation title: %{public}s', String(error));
    }
  }
}
