/**
 * NetworkManagerV2.ets
 * 
 *  改进版网络管理器 - 使用事件驱动架构
 * 
 * 主要改进：
 * 1.  消除回调地狱 - 使用事件驱动
 * 2.  状态集中管理- StreamState
 * 3.  SSE 逻辑分离 - StreamProcessor
 * 4.  错误处理优雅 - 统一的错误流
 * 5.  支持 Promise/async-await - StreamEventPromise
 * 
 * 使用示例：
 * ```
 * const manager = new NetworkManagerV2();
 * const emitter = await manager.sendStreamChatRequestV2(
 *   apiUrl, apiKey, model, messages
 * );
 * 
 * // 方式 1: 事件监听
 * emitter.on(StreamEventType.DATA, (chunk) => {
 *   console.log(chunk);
 * });
 * emitter.on(StreamEventType.ERROR, (error) => {
 *   console.error(error);
 * });
 * 
 * // 方式 2: Promise 方式
 * const allData = await new StreamEventPromise(emitter).collectAllData();
 * ```
 */

import { http } from '@kit.NetworkKit';
import { Constants } from '../common/Constants';
import {
  ChatMessage,
  StreamMetadata,
  ChatRequestBody,
  RequestMessage,
  ReasoningContentItem,
  WebSearchTool,
  Citation,
  ExtendedStreamResponse,
  AIModel,
  ThinkingConfig
} from './DataModels';
import { AbortController } from '../interfaces/AbortController';
import { NetworkError } from '../common/ErrorHandler';
import { createLogger, LogDomain } from '../common/Logger';
import { inferApiFormat } from './PresetProviders';
import {
  StreamEventEmitter,
  StreamEventType,
  StreamEventPromise,
  ProgressData
} from './StreamEventEmitter';
import { StreamState } from './StreamState';
import { StreamProcessor, StreamProcessorOptions } from './StreamProcessor';
import { ApiFormat } from './DataModels';

const logger = createLogger('NetworkManagerV2', LogDomain.NETWORK);

// 请求体构建中使用的辅助接口
interface ThinkingParam {
  type: string;
  display?: string;
  budget_tokens?: number;
}

interface OutputConfigParam {
  effort: string;
}

interface AnthropicMessageParam {
  role: string;
  content: string;
}

interface GeminiPart {
  text: string;
}

interface GeminiMessageParam {
  role: string;
  parts: GeminiPart[];
}

interface GeminiThinkingConfigParam {
  thinkingBudget: number;
  includeThoughts: boolean;
}

interface GeminiSystemInstructionParam {
  parts: GeminiPart[];
}

/**
 * 消息内容接口
 */
interface MessageContent {
  content: string;
}

/**
 * 选择项接口
 */
interface ChatChoice {
  message: MessageContent;
}

/**
 * 聊天响应接口
 */
interface ChatResponse {
  choices?: Array<ChatChoice>;
}

/**
 * 错误信息接口
 */
interface ErrorInfo {
  message?: string;
}

/**
 * 错误响应接口
 */
interface ErrorResponse {
  error?: ErrorInfo;
}

/**
 * 流式请求配置
 */
export interface StreamRequestConfig {
  // 请求超时（毫秒）
  requestTimeout?: number;

  // 最大重试次数
  maxRetries?: number;

  // SSE 处理器选项
  processorOptions?: StreamProcessorOptions;

  // 中止控制器
  abortController?: AbortController;

  // 是否启用网络搜索
  enableWebSearch?: boolean;

  // OpenAI 格式的工具定义数组
  tools?: object[];

  // 模型级配置（从 AIModel 读取，替代硬编码值）
  temperature?: number;
  maxTokens?: number;
  thinkingConfig?: ThinkingConfig;
  apiFormat?: ApiFormat;
  providerType?: string;
}

/**
 * 超时状态容器
 */
interface TimeoutState {
  id: number | null;
}

/**
 * 改进版网络管理器
 */
export class NetworkManagerV2 {
  private static instance: NetworkManagerV2;

  private constructor() {
  }

  static getInstance(): NetworkManagerV2 {
    if (!NetworkManagerV2.instance) {
      NetworkManagerV2.instance = new NetworkManagerV2();
    }
    return NetworkManagerV2.instance;
  }

  /**
   * 规范化标识符
   */
  private sanitizeIdentifier(input: string): string {
    if (!input) {
      return '';
    }
    return input
      .replace(/[\u200B\u200C\u200D\uFEFF\u00A0]/g, '')
      .trim();
  }

  /**
   * 清洗 API Key
   */
  private sanitizeApiKey(input: string): string {
    if (!input) {
      return '';
    }
    return input.replace(/[\u200B\u200C\u200D\uFEFF\u00A0]/g, '').trim();
  }

  /**
   * 脱敏 URL 用于日志输出，防止 API Key 泄露（Gemini 等将 key 放在 query string 中）
   */
  private sanitizeUrlForLogging(url: string): string {
    return url.replace(/([?&]key=)[^&]*/i, '$1***');
  }

  /**
   * 解析聊天完成 URL
   */
  private resolveChatCompletionsUrl(apiUrl: string): string {
    if (!apiUrl || apiUrl.trim().length === 0) {
      return apiUrl;
    }

    if (apiUrl.includes('/chat/completions')) {
      return apiUrl;
    }

    const trimmed = apiUrl.trim();
    const sanitizedUrl = trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;

    const hasV1 = sanitizedUrl.includes('/v1');
    const hasAliyunCompatV1 = sanitizedUrl.includes('/compatible-mode/v1');

    if (hasAliyunCompatV1 || hasV1) {
      return `${sanitizedUrl}/chat/completions`;
    }

    return `${sanitizedUrl}/v1/chat/completions`;
  }

  /**
   * 根据 API 格式解析请求 URL
   */
  private resolveRequestUrl(
    apiUrl: string,
    apiFormat: ApiFormat,
    model: string,
    apiKey?: string,
    streaming: boolean = true
  ): string {
    const base = (apiUrl || '').trim().replace(/\/+$/, '');
    switch (apiFormat) {
      case 'anthropic':
        return `${base}/messages`;
      case 'gemini': {
        let url = `${base}/models/${encodeURIComponent(model)}:${streaming ? 'streamGenerateContent' : 'generateContent'}`;
        if (apiKey) {
          url += `?key=${encodeURIComponent(apiKey)}`;
        }
        return url;
      }
      default:
        return this.resolveChatCompletionsUrl(apiUrl);
    }
  }

  /**
   * 根据 API 格式构建认证头
   */
  private buildHeaders(apiKey: string, apiFormat: ApiFormat): Record<string, string> {
    switch (apiFormat) {
      case 'anthropic':
        return {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Accept': 'text/event-stream, application/json'
        };
      case 'gemini':
        return {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream, application/json'
        };
      default:
        return {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'text/event-stream, application/json',
          'Cache-Control': 'no-cache'
        };
    }
  }

  /**
   * 构建 OpenAI 兼容格式的请求体
   */
  private buildOpenAIBody(
    model: string, messages: RequestMessage[], temperature: number, maxTokens: number,
    thinkingConfig: ThinkingConfig | undefined, providerType: string | undefined,
    enableWebSearch: boolean | undefined, tools: object[] | undefined,
    streaming: boolean = true
  ): object {
    const body: Record<string, Object> = {};
    body['model'] = model;
    body['messages'] = messages;
    body['stream'] = streaming;
    body['max_tokens'] = maxTokens;
    body['temperature'] = temperature;
    if (enableWebSearch === true) { body['enable_search'] = true; }
    if (tools && tools.length > 0) { body['tools'] = tools; }
    if (!thinkingConfig || !thinkingConfig.enabled) { return body; }

    switch (providerType) {
      case 'deepseek': {
        const thinkParam: ThinkingParam = { type: 'enabled' };
        body['thinking'] = thinkParam;
        if (thinkingConfig.effort && (thinkingConfig.effort === 'high' || thinkingConfig.effort === 'max')) {
          body['reasoning_effort'] = thinkingConfig.effort;
        }
        break;
      }
      case 'zhipu': {
        const thinkParam: ThinkingParam = { type: 'enabled' };
        body['thinking'] = thinkParam;
        break;
      }
      case 'qwen':
      case 'siliconflow':
        body['enable_thinking'] = true;
        if (thinkingConfig.budgetTokens && thinkingConfig.budgetTokens > 0) {
          body['thinking_budget'] = thinkingConfig.budgetTokens;
        }
        break;
      default:
        if (thinkingConfig.effort) { body['reasoning_effort'] = thinkingConfig.effort; }
        break;
    }
    return body;
  }

  /**
   * 构建 Anthropic 格式的请求体 (/v1/messages)
   */
  private buildAnthropicBody(
    model: string, messages: RequestMessage[], temperature: number, maxTokens: number,
    thinkingConfig: ThinkingConfig | undefined, streaming: boolean = true
  ): object {
    const anthropicMessages: AnthropicMessageParam[] = [];
    let systemPrompt: string | undefined;
    for (const msg of messages) {
      if (msg.role === 'system') {
        systemPrompt = msg.content;
        continue;
      }
      const anthMsg: AnthropicMessageParam = {
        role: msg.role === 'assistant' ? 'assistant' : 'user',
        content: msg.content
      };
      anthropicMessages.push(anthMsg);
    }

    const body: Record<string, Object> = {};
    body['model'] = model;
    body['messages'] = anthropicMessages;
    body['max_tokens'] = maxTokens;
    body['stream'] = streaming;
    if (systemPrompt) { body['system'] = systemPrompt; }

    if (thinkingConfig && thinkingConfig.enabled && thinkingConfig.effort) {
      // Claude Opus 4.7+: adaptive thinking，不能传 temperature
      const thinkParam: ThinkingParam = { type: 'adaptive', display: 'summarized' };
      body['thinking'] = thinkParam;
      const outputCfg: OutputConfigParam = { effort: thinkingConfig.effort };
      body['output_config'] = outputCfg;
    } else {
      body['temperature'] = temperature;
      if (thinkingConfig && thinkingConfig.enabled && thinkingConfig.budgetTokens && thinkingConfig.budgetTokens > 0) {
        const thinkParam: ThinkingParam = { type: 'enabled', budget_tokens: thinkingConfig.budgetTokens };
        body['thinking'] = thinkParam;
      }
    }
    return body;
  }

  /**
   * 构建 Gemini 格式的请求体
   */
  private buildGeminiBody(
    model: string, messages: RequestMessage[], temperature: number, maxTokens: number,
    thinkingConfig: ThinkingConfig | undefined
  ): object {
    const contents: GeminiMessageParam[] = [];
    let systemInstruction: string | undefined;
    for (const msg of messages) {
      if (msg.role === 'system') {
        systemInstruction = msg.content;
        continue;
      }
      const part: GeminiPart = { text: msg.content };
      const gMsg: GeminiMessageParam = {
        role: msg.role === 'assistant' ? 'model' : 'user',
        parts: [part]
      };
      contents.push(gMsg);
    }

    const generationConfig: Record<string, Object> = {};
    generationConfig['temperature'] = temperature;
    generationConfig['maxOutputTokens'] = maxTokens;
    if (thinkingConfig && thinkingConfig.enabled) {
      let budget: number = thinkingConfig.budgetTokens ?? (model.includes('flash') ? 0 : -1);
      const tcParam: GeminiThinkingConfigParam = { thinkingBudget: budget, includeThoughts: true };
      generationConfig['thinkingConfig'] = tcParam;
    }

    const body: Record<string, Object> = {};
    body['contents'] = contents;
    body['generationConfig'] = generationConfig;
    if (systemInstruction) {
      const siPart: GeminiPart = { text: systemInstruction };
      const si: GeminiSystemInstructionParam = { parts: [siPart] };
      body['systemInstruction'] = si as Object;
    }
    return body;
  }

  /**
   * 改进版流式聊天请求- 返回事件发射器
   * 
   * 使用事件驱动架构，完全消除回调地狱
   * 
   * @returns StreamEventEmitter 事件发射器
   */
  async sendStreamChatRequestV2(
    apiUrl: string,
    apiKey: string,
    model: string,
    messages: ChatMessage[],
    config?: StreamRequestConfig
  ): Promise<StreamEventEmitter> {
    // 创建事件发射器
    const emitter = new StreamEventEmitter();
    
    // 创建状态管理器
    const state = new StreamState(emitter);
    
    // 创建处理器
    const processor = new StreamProcessor(
      state,
      emitter,
      config?.processorOptions
    );

    // 根据 apiFormat 设置响应解析器
    if (config?.apiFormat) {
      processor.setApiFormat(config.apiFormat);
    }

    // 创建默认配置
    const finalConfig: StreamRequestConfig = config || {
      requestTimeout: 30000,
      maxRetries: 0,
      enableWebSearch: false
    };

    // 异步启动请求（不阻塞调用者）
    this.performStreamRequest(
      apiUrl,
      apiKey,
      model,
      messages,
      emitter,
      state,
      processor,
      finalConfig
    ).catch((error: Error) => {
      // 确保错误被发送
      if (!state.isErrorDispatched()) {
        emitter.emit(StreamEventType.ERROR, error);
        state.markErrorDispatched();
      }
    });

    return emitter;
  }

  /**
   * 执行流式请求（内部方法）
   * 
   * 使用 async/await 替代嵌套回调
   */
  private async performStreamRequest(
    apiUrl: string,
    apiKey: string,
    model: string,
    messages: ChatMessage[],
    emitter: StreamEventEmitter,
    state: StreamState,
    processor: StreamProcessor,
    config: StreamRequestConfig
  ): Promise<void> {
    const sanitizedApiUrl = (apiUrl || '').trim();
    const sanitizedModel = this.sanitizeIdentifier(model || '');
    const sanitizedApiKey = this.sanitizeApiKey(apiKey || '');

    try {
      // 1验证输入
      this.validateRequestInputs(sanitizedApiUrl, sanitizedApiKey, sanitizedModel);

      // 2准备请求
      const apiFormat: ApiFormat = config.apiFormat || 'openai';
      const providerType: string | undefined = config.providerType;
      const effectiveMaxTokens: number = config.maxTokens ?? 2000;
      const effectiveTemperature: number = config.temperature ?? 0.7;
      const thinkingConfig: ThinkingConfig | undefined = config.thinkingConfig;

      const url = this.resolveRequestUrl(
        sanitizedApiUrl,
        apiFormat,
        sanitizedModel,
        apiFormat === 'gemini' ? sanitizedApiKey : undefined,
        true
      );

      const requestMessages: RequestMessage[] = messages.map((msg: ChatMessage): RequestMessage => {
        const requestMsg: RequestMessage = {
          role: msg.role,
          content: msg.content
        };

        // 工具消息必须包含 tool_call_id
        if (msg.role === 'tool') {
          if (!msg.toolCallId) {
            logger.error( 'Tool message missing toolCallId, this will cause API error');
            throw new Error('工具调用消息缺少必需的 tool_call_id 字段');
          }
          requestMsg.tool_call_id = msg.toolCallId;
        }

        // assistant 消息可能包含 tool_calls
        if (msg.role === 'assistant' && msg.toolCalls && msg.toolCalls.length > 0) {
          requestMsg.tool_calls = msg.toolCalls;
        }

        return requestMsg;
      });

      let requestBody: object;
      const requestHeaders: Record<string, string> = this.buildHeaders(sanitizedApiKey, apiFormat);

      switch (apiFormat) {
        case 'anthropic':
          requestBody = this.buildAnthropicBody(sanitizedModel, requestMessages, effectiveTemperature, effectiveMaxTokens, thinkingConfig, true);
          break;
        case 'gemini':
          requestBody = this.buildGeminiBody(sanitizedModel, requestMessages, effectiveTemperature, effectiveMaxTokens, thinkingConfig);
          break;
        default:
          requestBody = this.buildOpenAIBody(sanitizedModel, requestMessages, effectiveTemperature, effectiveMaxTokens, thinkingConfig, providerType, config.enableWebSearch, config.tools, true);
          break;
      }

      // 3创建 HTTP 请求
      const httpRequest = http.createHttp();
      
      // 使用对象包装 timeoutId，以便在闭包中修改
      const timeoutState: TimeoutState = { id: null };

      try {
        // 4设置超时处理（可被每次 dataReceive 事件重置）
        const setupTimeout = (): number => {
          if (timeoutState.id !== null) {
            clearTimeout(timeoutState.id);
          }
          const newId = setTimeout(() => {
            logger.warn( 'Stream request timeout after %{public}d ms', config.requestTimeout ?? 30000);
            httpRequest.destroy();
            
            const error = new Error('请求超时');
            if (!state.isErrorDispatched()) {
              emitter.emit(StreamEventType.ERROR, error);
              state.markErrorDispatched();
            }
          }, config.requestTimeout ?? 30000);
          timeoutState.id = newId;
          return newId;
        };

        timeoutState.id = setupTimeout();

        // 5设置中止处理
        if (config.abortController) {
          this.setupAbortHandler(
            config.abortController,
            state,
            httpRequest,
            emitter,
            processor
          );
        }

        // 6设置 HTTP 事件处理，并等待流结束/错误/中止后再清理连接
        const httpEventsPromise = this.setupHTTPEventHandlers(
          httpRequest,
          emitter,
          state,
          processor,
          setupTimeout,
          timeoutState
        );
        const streamFinalizedPromise = this.waitForStreamFinalization(emitter, httpEventsPromise);

        // 7发起请求
        const responseCode = await this.performHTTPRequest(
          httpRequest,
          url,
          sanitizedApiKey,
          requestBody,
          config.requestTimeout ?? 30000,
          requestHeaders
        );

        // 8处理响应
        this.handleHTTPResponse(
          responseCode,
          state,
          emitter,
          processor
        );
        await streamFinalizedPromise;

      } finally {
        // 清理超时定时器
        if (timeoutState.id !== null) {
          clearTimeout(timeoutState.id);
          timeoutState.id = null;
        }
        // 清理 HTTP 资源
        this.cleanupHTTPRequest(httpRequest);
      }

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error( 'Stream request failed: %{public}s', err.message);
      
      if (!state.isErrorDispatched() && !state.isUserAborted()) {
        emitter.emit(StreamEventType.ERROR, err);
        state.markErrorDispatched();
      }
    } finally {
      // 刷新处理器缓冲区
      processor.flush();
      
      // 清理资源
      processor.dispose();
    }
  }

  /**
   * 验证请求输入
   */
  private validateRequestInputs(apiUrl: string, apiKey: string, model: string): void {
    if (!apiUrl) {
      throw new Error('API URL 不能为空');
    }
    if (!apiKey) {
      throw new Error('API Key 不能为空');
    }
    if (!model) {
      throw new Error('Model 不能为空');
    }
  }

  /**
   * 设置超时处理
   */
  private setupTimeoutHandler(
    timeout: number,
    emitter: StreamEventEmitter,
    state: StreamState,
    httpRequest: http.HttpRequest,
    processor: StreamProcessor
  ): number {
    return setTimeout(() => {
      logger.warn( 'Stream request timeout after %{public}d ms', timeout);
      httpRequest.destroy();
      
      const error = new Error('请求超时');
      if (!state.isErrorDispatched()) {
        emitter.emit(StreamEventType.ERROR, error);
        state.markErrorDispatched();
      }
    }, timeout);
  }

  /**
   * 设置中止处理
   */
  private setupAbortHandler(
    abortController: AbortController,
    state: StreamState,
    httpRequest: http.HttpRequest,
    emitter: StreamEventEmitter,
    processor: StreamProcessor
  ): void {
    abortController.signal.addEventListener('abort', () => {
      logger.info( 'Request aborted by user');
      state.markUserAborted();
      httpRequest.destroy();
      
      // 调用 onComplete 而不是 onError，保留已生成内容
      if (!state.isCompleted()) {
        state.markCompleted();
        emitter.emit(StreamEventType.COMPLETE, undefined);
      }
    });
  }

  /**
   * 设置 HTTP 事件处理
   * 
   * 使用 Promise 包装，避免深层嵌套回调
   * 每次收到数据时重置超时计时器，以支持长时间流式传输
   */
  private setupHTTPEventHandlers(
    httpRequest: http.HttpRequest,
    emitter: StreamEventEmitter,
    state: StreamState,
    processor: StreamProcessor,
    setupTimeout?: () => number,
    timeoutState?: TimeoutState
  ): Promise<void> {
    return new Promise<void>((resolve) => {
      let errorBody = '';

      // 数据接收事件
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        try {
          // 每次收到数据时重置超时计时器
          if (setupTimeout && timeoutState) {
            setupTimeout();
          }

          const chunk = this.arrayBufferToString(data);
          if (chunk && chunk.length > 0) {
            // 处理 SSE 数据
            processor.processChunk(chunk);
          }

          // 累积可能的错误响应体
          if (!state.isMetadataDispatched() && !chunk.includes('data:')) {
            errorBody += chunk;
          }
        } catch (error) {
          logger.error( 'Error processing chunk: %{public}s', String(error));
          emitter.emit(StreamEventType.WARNING, `处理数据块出错: ${error}`);
        }
      });

      // 数据接收完成事件
      httpRequest.on('dataEnd', () => {
        logger.info( 'HTTP stream data receive completed');
        
        // 清理超时计时器
        if (timeoutState && timeoutState.id !== null) {
          clearTimeout(timeoutState.id);
          timeoutState.id = null;
        }
        
        try {
          // 处理缓冲区剩余数据
          processor.flush();

          // 如果没有接收到有效的 SSE 数据，尝试解析为 JSON
          if (!state.isCompleted() && errorBody.trim().length > 0) {
            processor.handleNormalJSONResponse(errorBody, false);
          }
        } catch (error) {
          logger.error( 'Error in dataEnd handler: %{public}s', String(error));
        }

        // 确保完成
        if (!state.isCompleted()) {
          state.markCompleted();
          emitter.emit(StreamEventType.COMPLETE, undefined);
        }

        resolve();
      });

      // 进度事件
      httpRequest.on('dataReceiveProgress', (progressInfo: http.DataReceiveProgressInfo) => {
        const progress: ProgressData = {
          received: progressInfo.receiveSize,
          total: progressInfo.totalSize
        };
        emitter.emit(StreamEventType.PROGRESS, progress);
      });
    });
  }

  /**
   * 等待流式请求真正结束。
   *
   * requestInStream 的 Promise 只代表请求已发起/收到响应码，不代表 SSE 数据已消费完。
   * 这里把 dataEnd、COMPLETE、ERROR 合并为统一的生命周期结束信号，避免过早 destroy 连接。
   */
  private waitForStreamFinalization(
    emitter: StreamEventEmitter,
    httpEventsPromise: Promise<void>
  ): Promise<void> {
    return new Promise<void>((resolve) => {
      let resolved = false;
      const finish = (): void => {
        if (resolved) {
          return;
        }
        resolved = true;
        emitter.off(StreamEventType.COMPLETE, onComplete);
        emitter.off(StreamEventType.ERROR, onError);
        resolve();
      };

      const onComplete = (): void => {
        finish();
      };
      const onError = (): void => {
        finish();
      };

      emitter.once(StreamEventType.COMPLETE, onComplete);
      emitter.once(StreamEventType.ERROR, onError);
      httpEventsPromise.then(() => {
        finish();
      }).catch(() => {
        finish();
      });
    });
  }

  /**
   * 执行 HTTP 请求
   */
  private async performHTTPRequest(
    httpRequest: http.HttpRequest,
    url: string,
    _apiKey: string,
    requestBody: object,
    timeout: number,
    headers: Record<string, string>
  ): Promise<number> {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(requestBody),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeout,
      readTimeout: timeout,
      usingCache: false,
      priority: 1,
      usingProtocol: http.HttpProtocol.HTTP1_1
    };

    logger.info( 'Performing HTTP request to: %{public}s', this.sanitizeUrlForLogging(url));

      return new Promise<number>((resolve, reject) => {
        httpRequest.requestInStream(url, options).then((responseCode: number) => {
          resolve(responseCode);
        }).catch((err: Error) => {
        logger.error( 'HTTP request error: %{public}s', String(err));
        reject(err);
      });
    });
  }

  /**
   * 处理 HTTP 响应
   */
  private handleHTTPResponse(
    responseCode: number,
    state: StreamState,
    emitter: StreamEventEmitter,
    processor: StreamProcessor
  ): void {
    if (responseCode !== 200) {
      if (!state.isErrorDispatched() && !state.isUserAborted()) {
        const error = new Error(`HTTP ${responseCode}`);
        emitter.emit(StreamEventType.ERROR, error);
        state.markErrorDispatched();
      }
    }
  }

  /**
   * 清理 HTTP 资源
   */
  private cleanupHTTPRequest(httpRequest: http.HttpRequest): void {
    try {
      httpRequest.off('dataReceive');
      httpRequest.off('dataSendProgress');
      httpRequest.off('dataReceiveProgress');
      httpRequest.off('dataEnd');
      httpRequest.destroy();
    } catch (error) {
      logger.warn( 'Failed to cleanup HTTP request: %{public}s', String(error));
    }
  }

  /**
   * ArrayBuffer 转字符串
   */
  private arrayBufferToString(data: ArrayBuffer): string {
    const uint8Array = new Uint8Array(data);
    let result = '';
    let i = 0;

    while (i < uint8Array.length) {
      let byte1 = uint8Array[i++];

      if (byte1 < 0x80) {
        result += String.fromCharCode(byte1);
      } else if ((byte1 & 0xE0) === 0xC0) {
        if (i >= uint8Array.length) break;
        let byte2 = uint8Array[i++];
        result += String.fromCharCode(((byte1 & 0x1F) << 6) | (byte2 & 0x3F));
      } else if ((byte1 & 0xF0) === 0xE0) {
        if (i + 1 >= uint8Array.length) break;
        let byte2 = uint8Array[i++];
        let byte3 = uint8Array[i++];
        result += String.fromCharCode(
          ((byte1 & 0x0F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F)
        );
      } else if ((byte1 & 0xF8) === 0xF0) {
        if (i + 2 >= uint8Array.length) break;
        let byte2 = uint8Array[i++];
        let byte3 = uint8Array[i++];
        let byte4 = uint8Array[i++];
        let codePoint =
          ((byte1 & 0x07) << 18) | ((byte2 & 0x3F) << 12) |
          ((byte3 & 0x3F) << 6) | (byte4 & 0x3F);
        if (codePoint > 0xFFFF) {
          codePoint -= 0x10000;
          result += String.fromCharCode(0xD800 + (codePoint >> 10));
          result += String.fromCharCode(0xDC00 + (codePoint & 0x3FF));
        } else {
          result += String.fromCharCode(codePoint);
        }
      }
    }

    return result;
  }

  /**
   * 非流式聊天请求（用于标题生成、连接测试等场景）
   * 
   * @param apiUrl API 基础 URL
   * @param apiKey API 密钥
   * @param modelName 模型名称
   * @param messages 消息列表
   * @returns Promise<string> AI 回复内容
   */
  async sendChatRequest(
    apiUrl: string,
    apiKey: string,
    modelName: string,
    messages: ChatMessage[],
    apiFormat: ApiFormat = 'openai',
    requestTimeout: number = 30000
  ): Promise<string> {
    const sanitizedApiUrl = (apiUrl || '').trim();
    const sanitizedModel = this.sanitizeIdentifier(modelName || '');
    const sanitizedApiKey = this.sanitizeApiKey(apiKey || '');

    logger.info( 'Starting non-streaming chat request');
    
    // 验证输入
    this.validateRequestInputs(sanitizedApiUrl, sanitizedApiKey, sanitizedModel);

    const requestUrl = this.resolveRequestUrl(
      sanitizedApiUrl,
      apiFormat,
      sanitizedModel,
      apiFormat === 'gemini' ? sanitizedApiKey : undefined,
      false
    );

    return new Promise((resolve, reject) => {
      const httpRequest = http.createHttp();

      // 构建请求消息
      const requestMessages: RequestMessage[] = messages.map((msg: ChatMessage): RequestMessage => {
        return {
          role: msg.role,
          content: msg.content
        };
      });

      let requestBody: object;
      switch (apiFormat) {
        case 'anthropic':
          requestBody = this.buildAnthropicBody(sanitizedModel, requestMessages, 0.7, 4096, undefined, false);
          break;
        case 'gemini':
          requestBody = this.buildGeminiBody(sanitizedModel, requestMessages, 0.7, 4096, undefined);
          break;
        default:
          const openAiBody: ChatRequestBody = {
            model: sanitizedModel,
            messages: requestMessages,
            stream: false,
            max_tokens: 4096,
            temperature: 0.7
          };
          requestBody = openAiBody;
          break;
      }

      // 设置请求选项
      const requestHeaders: Record<string, string> = this.buildHeaders(sanitizedApiKey, apiFormat);
      requestHeaders['Accept'] = 'application/json';

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: requestHeaders,
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: requestTimeout,
        readTimeout: requestTimeout
      };

      logger.info( 'Sending non-streaming request to: %{public}s', this.sanitizeUrlForLogging(requestUrl));

      // 发送请求
      httpRequest.request(requestUrl, options, (err: Error, data: http.HttpResponse) => {
        if (err) {
          logger.error( 'HTTP request failed: %{public}s', String(err));
          httpRequest.destroy();
          const errorMessage = this.getNetworkErrorMessage(err);
          reject(new NetworkError(errorMessage));
          return;
        }

        try {
          if (data.responseCode === 200) {
            const responseData = data.result as string;
            const content = this.extractChatResponseText(apiFormat, responseData);
            httpRequest.destroy();
            resolve(content);
          } else {
            let errorMessage = `请求失败，状态码: ${data.responseCode}`;
            
            try {
              logger.error( 'HTTP error response body: %{public}s', data.result as string);
              const errorData: ErrorResponse = JSON.parse(data.result as string);
              if (errorData.error && errorData.error.message) {
                errorMessage = this.getApiErrorMessage(errorData.error.message, data.responseCode);
              }
            } catch (e) {
              errorMessage = this.getHttpErrorMessage(data.responseCode);
            }

            logger.error( 'HTTP request failed with status: %{public}d', data.responseCode);
            httpRequest.destroy();
            reject(new NetworkError(errorMessage));
          }
        } catch (parseError) {
          logger.error( 'Failed to parse response: %{public}s', String(parseError));
          httpRequest.destroy();
          reject(new NetworkError(`响应解析失败: ${parseError}`));
        }
      });
    });
  }

  /**
   * 解析非流式响应内容
   */
  private extractChatResponseText(apiFormat: ApiFormat, responseData: string): string {
    const body = JSON.parse(responseData) as Record<string, Object>;

    switch (apiFormat) {
      case 'anthropic': {
        const content = body['content'] as Array<Object> | undefined;
        if (!content || !Array.isArray(content)) {
          throw new NetworkError('AI服务返回的响应格式不正确');
        }
        const text = content
          .map((part: Object) => String((part as Record<string, Object>)['text'] ?? ''))
          .join('')
          .trim();
        if (!text) {
          throw new NetworkError('AI服务返回的响应格式不正确');
        }
        return text;
      }
      case 'gemini': {
        const candidates = body['candidates'] as Array<Object> | undefined;
        if (!candidates || !Array.isArray(candidates) || candidates.length === 0) {
          throw new NetworkError('AI服务返回的响应格式不正确');
        }
        const candidate = candidates[0] as Record<string, Object>;
        const content = candidate['content'] as Record<string, Object> | undefined;
        const parts = content ? (content['parts'] as Array<Object> | undefined) : undefined;
        const text = parts
          ? parts.map((part: Object) => String((part as Record<string, Object>)['text'] ?? '')).join('').trim()
          : '';
        if (!text) {
          throw new NetworkError('AI服务返回的响应格式不正确');
        }
        return text;
      }
      default: {
        const choices = body['choices'] as Array<Object> | undefined;
        if (!choices || !Array.isArray(choices) || choices.length === 0) {
          throw new NetworkError('AI服务返回的响应格式不正确');
        }
        const choice = choices[0] as Record<string, Object>;
        const message = choice['message'] as Record<string, Object> | undefined;
        const text = message ? String(message['content'] ?? '') : '';
        if (!text) {
          throw new NetworkError('AI服务返回的响应格式不正确');
        }
        return text;
      }
    }
  }

  /**
   * 获取网络错误的用户友好消息
   */
  private getNetworkErrorMessage(error: Error): string {
    const errorStr = error.message || String(error);
    
    if (errorStr.includes('timeout') || errorStr.includes('TIMEOUT')) {
      return '请求超时，请检查网络连接或稍后重试';
    }
    if (errorStr.includes('ENOTFOUND') || errorStr.includes('DNS')) {
      return '无法连接到服务器，请检查网络设置或API地址';
    }
    if (errorStr.includes('ECONNREFUSED')) {
      return '服务器拒绝连接，请检查API地址是否正确';
    }
    if (errorStr.includes('certificate') || errorStr.includes('SSL')) {
      return 'SSL证书验证失败，请检查网络安全设置';
    }
    
    return `网络请求失败: ${errorStr}`;
  }

  /**
   * 获取 API 错误的用户友好消息
   */
  private getApiErrorMessage(apiError: string, statusCode: number): string {
    if (statusCode === 401) {
      return 'API密钥无效或已过期，请检查密钥设置';
    }
    if (statusCode === 403) {
      return 'API访问被拒绝，请检查权限设置';
    }
    if (statusCode === 429) {
      return 'API调用频率超限，请稍后重试';
    }
    if (statusCode === 500) {
      return 'AI服务内部错误，请稍后重试';
    }
    
    return apiError || `API错误 (${statusCode})`;
  }

  /**
   * 获取 HTTP 状态码对应的用户友好消息
   */
  private getHttpErrorMessage(statusCode: number): string {
    switch (statusCode) {
      case 400:
        return '请求参数错误，请检查输入内容';
      case 401:
        return 'API密钥无效，请检查密钥设置';
      case 403:
        return 'API访问被拒绝，请检查权限';
      case 404:
        return 'API接口不存在，请检查API地址';
      case 429:
        return 'API调用频率超限，请稍后重试';
      case 500:
        return 'AI服务内部错误，请稍后重试';
      case 502:
        return 'AI服务网关错误，请稍后重试';
      case 503:
        return 'AI服务暂时不可用，请稍后重试';
      default:
        return `请求失败，状态码: ${statusCode}`;
    }
  }

  /**
   * 从 API 获取模型列表。
   * 支持 OpenAI、Anthropic、Gemini 三种 API 格式。
   */
  async fetchModels(apiUrl: string, apiKey: string, apiFormat: ApiFormat = 'openai'): Promise<AIModel[]> {
    const baseUrl = (apiUrl || '').trim().replace(/\/+$/, '');
    const key = (apiKey || '').trim();
    if (!baseUrl) throw new Error('API 地址不能为空');
    if (!key) throw new Error('API 密钥不能为空');

    if (apiFormat === 'gemini') return await this.fetchModelsGemini(baseUrl, key);
    if (apiFormat === 'anthropic') return await this.fetchModelsAnthropic(baseUrl, key);
    return await this.fetchModelsOpenAI(baseUrl, key);
  }

  /** OpenAI 格式: GET {baseUrl}/models, Authorization: Bearer */
  private async fetchModelsOpenAI(baseUrl: string, apiKey: string): Promise<AIModel[]> {
    const url = `${baseUrl}/models`;
    return new Promise<AIModel[]>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': `Bearer ${apiKey}`, 'Accept': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      }, (err: Error, data: http.HttpResponse) => {
        if (err) { httpRequest.destroy(); reject(new NetworkError(`获取模型列表失败: ${err.message}`)); return; }
        try {
          if (data.responseCode !== 200) {
            httpRequest.destroy();
            reject(new NetworkError(`获取模型列表失败 (HTTP ${data.responseCode})`));
            return;
          }
          const body = JSON.parse(data.result as string) as Object;
          httpRequest.destroy();
          resolve(this.parseOpenAIModelsResponse(body));
        } catch (e) {
          httpRequest.destroy();
          reject(new NetworkError(`解析模型列表失败: ${e}`));
        }
      });
    });
  }

  /** Anthropic 格式: GET {baseUrl}/models, x-api-key + anthropic-version */
  private async fetchModelsAnthropic(baseUrl: string, apiKey: string): Promise<AIModel[]> {
    const url = `${baseUrl}/models?limit=1000`;
    return new Promise<AIModel[]>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      }, (err: Error, data: http.HttpResponse) => {
        if (err) { httpRequest.destroy(); reject(new NetworkError(`获取模型列表失败: ${err.message}`)); return; }
        try {
          if (data.responseCode !== 200) {
            httpRequest.destroy();
            reject(new NetworkError(`获取模型列表失败 (HTTP ${data.responseCode})`));
            return;
          }
          const body = JSON.parse(data.result as string) as Object;
          httpRequest.destroy();
          resolve(this.parseAnthropicModelsResponse(body));
        } catch (e) {
          httpRequest.destroy();
          reject(new NetworkError(`解析模型列表失败: ${e}`));
        }
      });
    });
  }

  /** Gemini 格式: GET {baseUrl}/models?key=xxx */
  private async fetchModelsGemini(baseUrl: string, apiKey: string): Promise<AIModel[]> {
    const url = `${baseUrl}/models?key=${encodeURIComponent(apiKey)}`;
    return new Promise<AIModel[]>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      }, (err: Error, data: http.HttpResponse) => {
        if (err) { httpRequest.destroy(); reject(new NetworkError(`获取模型列表失败: ${err.message}`)); return; }
        try {
          if (data.responseCode !== 200) {
            httpRequest.destroy();
            reject(new NetworkError(`获取模型列表失败 (HTTP ${data.responseCode})`));
            return;
          }
          const body = JSON.parse(data.result as string) as Object;
          httpRequest.destroy();
          resolve(this.parseGeminiModelsResponse(body));
        } catch (e) {
          httpRequest.destroy();
          reject(new NetworkError(`解析模型列表失败: ${e}`));
        }
      });
    });
  }

  /** 解析 OpenAI /v1/models 响应 */
  private parseOpenAIModelsResponse(body: Object): AIModel[] {
    const data = (body as Record<string, Object>)['data'] as Array<Object> | undefined;
    if (!data || !Array.isArray(data)) throw new Error('模型列表响应格式异常');
    return data
      .map((item: Object) => {
        const id = String((item as Record<string, Object>)['id'] ?? '');
        return new AIModel(id, id, id, 131072, 0.7, false);
      })
      .filter(m => !!m.id);
  }

  /** 解析 Anthropic /v1/models 响应 */
  private parseAnthropicModelsResponse(body: Object): AIModel[] {
    const data = (body as Record<string, Object>)['data'] as Array<Object> | undefined;
    if (!data || !Array.isArray(data)) throw new Error('模型列表响应格式异常');
    return data
      .map((item: Object) => {
        const id = String((item as Record<string, Object>)['id'] ?? '');
        const displayName = String((item as Record<string, Object>)['display_name'] ?? id);
        return new AIModel(id, id, displayName, 128000, 0.7, false);
      })
      .filter(m => !!m.id);
  }

  /** 解析 Gemini /v1beta/models 响应 */
  private parseGeminiModelsResponse(body: Object): AIModel[] {
    const models = (body as Record<string, Object>)['models'] as Array<Object> | undefined;
    if (!models || !Array.isArray(models)) throw new Error('模型列表响应格式异常');
    return models
      .filter((item: Object) => {
        const methods = (item as Record<string, Object>)['supportedGenerationMethods'] as string[] | undefined;
        return methods && methods.includes('generateContent');
      })
      .map((item: Object) => {
        const fullName = String((item as Record<string, Object>)['name'] ?? '');
        const displayName = String((item as Record<string, Object>)['displayName'] ?? fullName);
        return new AIModel(fullName, fullName, displayName, 131072, 0.7, false);
      })
      .filter(m => !!m.id);
  }

  /**
   * 测试API连接
   *
   * @param apiUrl API 基础 URL
   * @param apiKey API 密钥
   * @param modelName 模型名称
   * @returns Promise<boolean> 连接是否成功
   */
  async testConnection(apiUrl: string, apiKey: string, modelName: string): Promise<boolean> {
    try {
      const testMessage = new ChatMessage('Hello', 'user');
      await this.sendChatRequest(apiUrl, apiKey, modelName, [testMessage], inferApiFormat(apiUrl));
      return true;
    } catch (error) {
      logger.error( 'Connection test failed: %{public}s', String(error));
      return false;
    }
  }
}
