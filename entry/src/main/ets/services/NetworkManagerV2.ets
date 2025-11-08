/**
 * NetworkManagerV2.ets
 * 
 * ✅ 改进版网络管理器 - 使用事件驱动架构
 * 
 * 主要改进：
 * 1. ✅ 消除回调地狱 - 使用事件驱动
 * 2. ✅ 状态集中管理 - StreamState
 * 3. ✅ SSE 逻辑分离 - StreamProcessor
 * 4. ✅ 错误处理优雅 - 统一的错误流
 * 5. ✅ 支持 Promise/async-await - StreamEventPromise
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
 * // 方式 2: Promise 链
 * const allData = await new StreamEventPromise(emitter).collectAllData();
 * ```
 */

import { http } from '@kit.NetworkKit';
import { Constants } from '../components/Constants';
import {
  ChatMessage,
  StreamMetadata,
  ChatRequestBody,
  RequestMessage,
  ReasoningContentItem,
  WebSearchTool,
  Citation,
  ExtendedStreamResponse
} from '../services/DataModels';
import { AbortController } from '../interfaces/AbortController';
import { NetworkError } from '../components/Errors';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { 
  StreamEventEmitter, 
  StreamEventType, 
  StreamEventPromise,
  ProgressData
} from './StreamEventEmitter';
import { StreamState } from './StreamState';
import { StreamProcessor, StreamProcessorOptions } from './StreamProcessor';

const DOMAIN = 0x0000;
const TAG = 'NetworkManagerV2';

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
   * ✅ 改进版流式聊天请求 - 返回事件发射器
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
    
    // 创建状态管理
    const state = new StreamState(emitter);
    
    // 创建处理器
    const processor = new StreamProcessor(
      state,
      emitter,
      config?.processorOptions
    );

    // 创建默认配置
    const finalConfig: StreamRequestConfig = config || {
      requestTimeout: 30000,
      maxRetries: 0,
      enableWebSearch: false
    };

    // ✅ 异步启动请求（不阻塞调用者）
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
      // 确保错误被发射
      if (!state.isErrorDispatched()) {
        emitter.emit(StreamEventType.ERROR, error);
        state.markErrorDispatched();
      }
    });

    return emitter;
  }

  /**
   * ✅ 执行流式请求（内部方法）
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

    hilog.info(DOMAIN, TAG, 'Starting stream chat request (V2)...');

    try {
      // 1️⃣ 验证输入
      this.validateRequestInputs(sanitizedApiUrl, sanitizedApiKey, sanitizedModel);

      // 2️⃣ 准备请求
      const url = this.resolveChatCompletionsUrl(sanitizedApiUrl);
      const requestMessages: RequestMessage[] = messages.map((msg: ChatMessage): RequestMessage => {
        return {
          role: msg.role as 'user' | 'assistant' | 'system',
          content: msg.content
        };
      });

      const requestBody: ChatRequestBody = {
        model: sanitizedModel,
        messages: requestMessages,
        stream: true,
        max_tokens: 2000,
        temperature: 0.7,
        enable_search: config.enableWebSearch === true ? true : undefined
      };

      // 3️⃣ 创建 HTTP 请求
      const httpRequest = http.createHttp();
      
      // 使用对象包装 timeoutId，以便在闭包中修改
      const timeoutState: TimeoutState = { id: null };

      try {
        // 4️⃣ 设置超时处理（可被每次 dataReceive 事件重置）
        const setupTimeout = (): number => {
          if (timeoutState.id !== null) {
            clearTimeout(timeoutState.id);
          }
          const newId = setTimeout(() => {
            hilog.error(DOMAIN, TAG, 'Stream request timeout after %{public}d ms', config.requestTimeout ?? 30000);
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

        // 5️⃣ 设置中止处理
        if (config.abortController) {
          this.setupAbortHandler(
            config.abortController,
            state,
            httpRequest,
            emitter,
            processor
          );
        }

        // 6️⃣ 设置 HTTP 事件处理（非回调地狱方式）
        // 注意：不能 await，因为这会一直等到 HTTP 响应完成
        this.setupHTTPEventHandlers(
          httpRequest,
          emitter,
          state,
          processor,
          setupTimeout,
          timeoutState
        );

        // 7️⃣ 发起请求
        const responseCode = await this.performHTTPRequest(
          httpRequest,
          url,
          sanitizedApiKey,
          requestBody,
          config.requestTimeout ?? 30000
        );

        // 8️⃣ 处理响应
        this.handleHTTPResponse(
          responseCode,
          state,
          emitter,
          processor
        );

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
      hilog.error(DOMAIN, TAG, 'Stream request failed: %{public}s', err.message);
      
      if (!state.isErrorDispatched()) {
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
   * ✅ 验证请求输入
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
   * ✅ 设置超时处理
   */
  private setupTimeoutHandler(
    timeout: number,
    emitter: StreamEventEmitter,
    state: StreamState,
    httpRequest: http.HttpRequest,
    processor: StreamProcessor
  ): number {
    return setTimeout(() => {
      hilog.error(DOMAIN, TAG, 'Stream request timeout after %{public}d ms', timeout);
      httpRequest.destroy();
      
      const error = new Error('请求超时');
      if (!state.isErrorDispatched()) {
        emitter.emit(StreamEventType.ERROR, error);
        state.markErrorDispatched();
      }
    }, timeout);
  }

  /**
   * ✅ 设置中止处理
   */
  private setupAbortHandler(
    abortController: AbortController,
    state: StreamState,
    httpRequest: http.HttpRequest,
    emitter: StreamEventEmitter,
    processor: StreamProcessor
  ): void {
    abortController.signal.addEventListener('abort', () => {
      hilog.info(DOMAIN, TAG, 'Request aborted by user');
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
   * ✅ 设置 HTTP 事件处理
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
            // 处理 SSE 数据（不再是回调地狱）
            processor.processChunk(chunk);
          }

          // 累积可能的错误响应体
          if (!state.isMetadataDispatched() && !chunk.includes('data:')) {
            errorBody += chunk;
          }
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'Error processing chunk: %{public}s', String(error));
          emitter.emit(StreamEventType.WARNING, `处理数据块出错: ${error}`);
        }
      });

      // 数据接收完成事件
      httpRequest.on('dataEnd', () => {
        hilog.info(DOMAIN, TAG, 'HTTP stream data receive completed');
        
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
          hilog.error(DOMAIN, TAG, 'Error in dataEnd handler: %{public}s', String(error));
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
   * ✅ 执行 HTTP 请求
   */
  private async performHTTPRequest(
    httpRequest: http.HttpRequest,
    url: string,
    apiKey: string,
    requestBody: ChatRequestBody,
    timeout: number
  ): Promise<number> {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': `Bearer ${apiKey}`,
        'Accept': 'text/event-stream, application/json',
        'Cache-Control': 'no-cache'
      },
      extraData: JSON.stringify(requestBody),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeout,
      readTimeout: timeout,
      usingCache: false,
      priority: 1,
      usingProtocol: http.HttpProtocol.HTTP1_1
    };

    hilog.info(DOMAIN, TAG, 'Performing HTTP request to: %{public}s', url);

    return new Promise<number>((resolve, reject) => {
      httpRequest.requestInStream(url, options).then((responseCode: number) => {
        hilog.info(DOMAIN, TAG, 'HTTP response code: %{public}d', responseCode);
        resolve(responseCode);
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'HTTP request error: %{public}s', String(err));
        reject(err);
      });
    });
  }

  /**
   * ✅ 处理 HTTP 响应
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
   * ✅ 清理 HTTP 资源
   */
  private cleanupHTTPRequest(httpRequest: http.HttpRequest): void {
    try {
      httpRequest.off('dataReceive');
      httpRequest.off('dataSendProgress');
      httpRequest.off('dataReceiveProgress');
      httpRequest.off('dataEnd');
      httpRequest.destroy();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to cleanup HTTP request: %{public}s', String(error));
    }
  }

  /**
   * ✅ ArrayBuffer 转字符串
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
}
