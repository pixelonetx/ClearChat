import { http } from '@kit.NetworkKit';
import { Constants } from '../components/Constants';
import {
  ChatRequest,
  ChatResponse,
  ChatMessage,
  MessageInterface,
  StreamCallbacks,
  StreamResponse,
  RequestMessage,
  ChatRequestBody,
  ReasoningContentItem
} from '../services/DataModels';
import { NetworkError } from '../components/Errors';

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

interface StreamParseState {
  metadataDispatched: boolean;
  completed: boolean;
}

/**
 * 网络请求管理器
 */
export class NetworkManager {
  private static instance: NetworkManager;
  private streamBuffer: string = ''; // 用于累积流式数据

  private constructor() {
  }

  static getInstance(): NetworkManager {
    if (!NetworkManager.instance) {
      NetworkManager.instance = new NetworkManager();
    }
    return NetworkManager.instance;
  }

  private resolveChatCompletionsUrl(apiUrl: string): string {
    if (!apiUrl || apiUrl.trim().length === 0) {
      return apiUrl;
    }

    if (apiUrl.includes('/chat/completions')) {
      return apiUrl;
    }

    const sanitizedUrl = apiUrl.endsWith('/') ? apiUrl.slice(0, -1) : apiUrl;
    return `${sanitizedUrl}/chat/completions`;
  }

  /**
   * 发送流式聊天请求到AI服务
   */
  async sendStreamChatRequest(apiUrl: string, apiKey: string, model: string, messages: ChatMessage[], callbacks: StreamCallbacks): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      console.info('Starting stream chat request...');
      console.info('API URL:', apiUrl);
      console.info('Model:', model);
      console.info('Messages count:', messages.length);

      // 声明超时定时器变量
      let timeoutId: number | null = null;

      // 清空缓冲区确保新请求从干净状态开始
      this.streamBuffer = '';

      // 如果API URL已经包含完整路径，直接使用；否则拼接 /chat/completions
      const url = this.resolveChatCompletionsUrl(apiUrl);

      const requestMessages: RequestMessage[] = messages.map(msg => {
        const requestMsg: RequestMessage = {
          role: msg.role as 'user' | 'assistant' | 'system',
          content: msg.content
        };
        return requestMsg;
      });

      const requestBody: ChatRequestBody = {
        model: model,
        messages: requestMessages,
        stream: true,
        max_tokens: 2000,
        temperature: 0.7
      };

      const httpRequest = http.createHttp();

      console.info('Request URL:', url);
      console.info('Request body:', JSON.stringify(requestBody));

      // 创建包装的回调，包含超时处理
      const wrappedCallbacks: StreamCallbacks = {
        onData: (chunk: string) => {
          if (timeoutId) {
            clearTimeout(timeoutId);
            timeoutId = null;
          }
          callbacks.onData(chunk);
        },
        onComplete: () => {
          if (timeoutId) {
            clearTimeout(timeoutId);
            timeoutId = null;
          }
          callbacks.onComplete();
        },
        onError: (error: Error) => {
          if (timeoutId) {
            clearTimeout(timeoutId);
            timeoutId = null;
          }
          callbacks.onError(error);
        },
        onMetadata: callbacks.onMetadata
      };

      // 设置30秒超时
      timeoutId = setTimeout(() => {
        console.error('Stream request timeout');
        httpRequest.destroy();
        wrappedCallbacks.onError(new Error('请求超时'));
        reject(new Error('请求超时'));
      }, 30000);

      // 按需订阅HTTP流式响应事件
      const parseState: StreamParseState = { metadataDispatched: false, completed: false };

      // 订阅HTTP流式响应数据接收事件
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        // 将 ArrayBuffer 转换为字符串 - 使用 UTF-8 解码
        const uint8Array = new Uint8Array(data);
        let chunk = this.utf8ArrayToString(uint8Array);

        console.info('Received streaming data chunk, length:', chunk.length);
        console.info('Chunk preview:', chunk.substring(0, 200));

        this.streamBuffer += chunk;
        // 实时解析SSE格式的数据
        this.parseSSEChunk(wrappedCallbacks, parseState);
      });

      // 订阅HTTP流式响应数据接收完毕事件
      httpRequest.on('dataEnd', () => {
        console.info('HTTP stream data receive completed');
        // 处理剩余的缓冲区数据
        if (this.streamBuffer.trim()) {
          this.parseSSEChunk(wrappedCallbacks, parseState);
        }
        if (!parseState.completed) {
          parseState.completed = true;
          wrappedCallbacks.onComplete();
        }
      });

      // 订阅数据接收进度事件
      httpRequest.on('dataReceiveProgress', (progressInfo: http.DataReceiveProgressInfo) => {
        console.info('Data receive progress:', progressInfo.receiveSize, '/', progressInfo.totalSize);
      });

      // 发起HTTP流式请求
      const streamOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive'
        },
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 300000,
        readTimeout: 300000,
        usingCache: false,
        priority: 1,
        usingProtocol: http.HttpProtocol.HTTP1_1
      };

  httpRequest.requestInStream(url, streamOptions).then((responseCode: number) => {
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }
        console.info('Stream request completed with response code:', responseCode);
        if (responseCode === 200) {
          // 流式数据接收已在 dataReceive 和 dataEnd 事件中处理
          console.info('Stream request successful');
        } else {
          wrappedCallbacks.onError(new Error(`HTTP ${responseCode}`));
        }
        this.destroyStreamRequest(httpRequest);
        resolve();
      }).catch((err: Error) => {
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }
        console.error('Stream request error:', err);
        wrappedCallbacks.onError(new Error(`流式请求失败: ${err.message || err}`));
        this.destroyStreamRequest(httpRequest);
        reject(err);
      });
    });
  }

  /**
   * 销毁流式HTTP请求
   */
  private destroyStreamRequest(httpRequest: http.HttpRequest): void {
    // 取消订阅HTTP流式响应数据接收事件
    httpRequest.off('dataReceive');
    // 取消订阅HTTP流式响应数据发送进度事件
    httpRequest.off('dataSendProgress');
    // 取消订阅HTTP流式响应数据接收进度事件
    httpRequest.off('dataReceiveProgress');
    // 取消订阅HTTP流式响应数据接收完毕事件
    httpRequest.off('dataEnd');
    // 销毁请求
    httpRequest.destroy();
  }

  /**
   * 解析 Server-Sent Events (SSE) 格式的流数据块
   */
  private parseSSEChunk(callbacks: StreamCallbacks, state: StreamParseState): void {
    const lines = this.streamBuffer.split('\n');

    // 保留最后一行，因为它可能是不完整的
    this.streamBuffer = lines.pop() || '';

    for (const line of lines) {
      const trimmedLine = line.trim();
      if (trimmedLine === '') continue;

      // SSE 格式: data: {json}
      if (trimmedLine.startsWith('data: ')) {
        const dataStr = trimmedLine.substring(6).trim();

        // 检查是否是结束标志
        if (dataStr === '[DONE]') {
          console.info('SSE stream completed with [DONE]');
          if (!state.completed) {
            state.completed = true;
            callbacks.onComplete();
          }
          return;
        }

        try {
          const jsonData = JSON.parse(dataStr) as StreamResponse;
          if (!state.metadataDispatched) {
            callbacks.onMetadata?.({
              id: jsonData.id,
              created: jsonData.created,
              model: jsonData.model,
              systemFingerprint: jsonData.system_fingerprint,
              choiceIndex: jsonData.choices && jsonData.choices.length > 0 ? jsonData.choices[0].index : undefined,
              finishReason: jsonData.choices && jsonData.choices.length > 0 ? jsonData.choices[0].finish_reason : undefined
            });
            state.metadataDispatched = true;
          }
          if (jsonData.choices && jsonData.choices.length > 0) {
            const delta = jsonData.choices[0].delta;
            if (delta && delta.content) {
              console.info('Received SSE content chunk:', delta.content);
              // 立即触发回调，实现真正的实时输出
              callbacks.onData(delta.content);
            }
            // 处理推理内容（如果有）
            if (delta && delta.reasoning_content) {
              let reasoningChunk: string = '';
              const reasoningContent = delta.reasoning_content;
              if (typeof reasoningContent === 'string') {
                reasoningChunk = reasoningContent;
              } else if (Array.isArray(reasoningContent)) {
                const parts: Array<string> = [];
                reasoningContent.forEach((entry: string | ReasoningContentItem) => {
                  if (typeof entry === 'string') {
                    parts.push(entry);
                  } else if (entry && typeof entry.text === 'string') {
                    parts.push(entry.text);
                  }
                });
                reasoningChunk = parts.join('');
              }
              if (reasoningChunk && reasoningChunk.length > 0) {
                console.info('Received SSE reasoning content:', reasoningChunk);
                callbacks.onData(reasoningChunk);
              }
            }
          }
        } catch (parseError) {
          console.warn('Failed to parse SSE JSON:', parseError, 'Raw data:', dataStr);
          // 继续处理其他行，不因为一行解析失败而停止
        }
      }
    }
  }

  /**
   * 将 UTF-8 字节数组转换为字符串
   */
  private utf8ArrayToString(array: Uint8Array): string {
    let result = '';
    let i = 0;

    while (i < array.length) {
      let byte1 = array[i++];

      if (byte1 < 0x80) {
        // 单字节字符 (ASCII)
        result += String.fromCharCode(byte1);
      } else if ((byte1 & 0xE0) === 0xC0) {
        // 双字节字符
        if (i >= array.length) break;
        let byte2 = array[i++];
        result += String.fromCharCode(((byte1 & 0x1F) << 6) | (byte2 & 0x3F));
      } else if ((byte1 & 0xF0) === 0xE0) {
        // 三字节字符
        if (i + 1 >= array.length) break;
        let byte2 = array[i++];
        let byte3 = array[i++];
        result += String.fromCharCode(((byte1 & 0x0F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F));
      } else if ((byte1 & 0xF8) === 0xF0) {
        // 四字节字符 (代理对)
        if (i + 2 >= array.length) break;
        let byte2 = array[i++];
        let byte3 = array[i++];
        let byte4 = array[i++];
        let codePoint = ((byte1 & 0x07) << 18) | ((byte2 & 0x3F) << 12) | ((byte3 & 0x3F) << 6) | (byte4 & 0x3F);
        if (codePoint > 0xFFFF) {
          codePoint -= 0x10000;
          result += String.fromCharCode(0xD800 + (codePoint >> 10));
          result += String.fromCharCode(0xDC00 + (codePoint & 0x3FF));
        } else {
          result += String.fromCharCode(codePoint);
        }
      } else {
        // 无效的 UTF-8 字节，跳过
        continue;
      }
    }

    return result;
  }

  /**
   * 发送聊天请求到AI服务（非流式，保留兼容性）
   */
  async sendChatRequest(
    apiUrl: string,
    apiKey: string,
    modelName: string,
    messages: ChatMessage[]
  ): Promise<string> {
    console.info('NetworkManager: Starting chat request');
    console.info('API URL:', apiUrl);
    console.info('Model:', modelName);
    console.info('Messages count:', messages.length);
    console.info('API Key length:', apiKey.length);

    const requestUrl = this.resolveChatCompletionsUrl(apiUrl);
    console.info('Resolved chat endpoint:', requestUrl);

    return new Promise((resolve, reject) => {
      // 创建HTTP请求
      const httpRequest = http.createHttp();

      // 构建请求体
      const requestMessages: MessageInterface[] = messages.map((msg: ChatMessage): MessageInterface => {
        return {
          role: msg.role,
          content: msg.content
        };
      });

      const requestBody: ChatRequest = {
        model: modelName,
        messages: requestMessages,
        max_tokens: 2000,
        temperature: 0.7,
        stream: false
      };

      // 设置请求选项
      const requestHeaders: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      };

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: requestHeaders,
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: Constants.DEFAULT_TIMEOUT,
        readTimeout: Constants.DEFAULT_TIMEOUT
      };

  console.info('Sending chat request to:', requestUrl);
      console.info('Request body:', JSON.stringify(requestBody, null, 2));

      // 发送请求
  httpRequest.request(requestUrl, options, (err: Error, data: http.HttpResponse) => {
        if (err) {
          console.error('HTTP request failed:', err);
          httpRequest.destroy();
          reject(new NetworkError(`网络请求失败: ${err.message || err}`));
          return;
        }

        try {
          if (data.responseCode === 200) {
            const responseData = data.result as string;
            console.info('Received response:', responseData);

            const response: ChatResponse = JSON.parse(responseData);

            if (response.choices && response.choices.length > 0) {
              const content = response.choices[0].message.content;
              httpRequest.destroy();
              resolve(content);
            } else {
              httpRequest.destroy();
              reject(new NetworkError('AI服务返回的响应格式不正确'));
            }
          } else {
            let errorMessage = `请求失败，状态码: ${data.responseCode}`;

            try {
              const errorData = JSON.parse(data.result as string) as ErrorResponse;
              if (errorData.error && errorData.error.message) {
                errorMessage = errorData.error.message;
              }
            } catch (e) {
              // 解析错误信息失败，使用默认错误消息
            }

            console.error('HTTP request failed with status:', data.responseCode);
            httpRequest.destroy();
            reject(new NetworkError(errorMessage));
          }
        } catch (parseError) {
          console.error('Failed to parse response:', parseError);
          httpRequest.destroy();
          reject(new NetworkError(`响应解析失败: ${parseError}`));
        }
      });
    });
  }

  /**
   * 测试API连接
   */
  async testConnection(apiUrl: string, apiKey: string, modelName: string): Promise<boolean> {
    try {
      const testMessage = new ChatMessage('Hello', 'user');
      await this.sendChatRequest(apiUrl, apiKey, modelName, [testMessage]);
      return true;
    } catch (error) {
      console.error('Connection test failed:', error);
      return false;
    }
  }
}
