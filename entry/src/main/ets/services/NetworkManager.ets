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

// 兼容部分厂商的错误结构，如 { code: 20013, message: "...", data: null }
interface VendorErrorResponse {
  code?: number | string;
  message?: string;
  data?: string | number | boolean | object | null;
}

// 扩展非流式正常响应形态，部分服务可能包含 system_fingerprint 字段
interface ChatResponseWithSysFp extends ChatResponse {
  system_fingerprint?: string;
}

interface StreamParseState {
  metadataDispatched: boolean;
  completed: boolean;
  // 当检测到错误并已通知回调时，避免重复上报
  errorDispatched: boolean;
}

interface StreamBufferState {
  pending: string;
  // 累计当前一个 SSE 事件中的多行 data: 片段
  eventDataLines?: string[];
}

/**
 * 网络请求管理器
 */
export class NetworkManager {
  private static instance: NetworkManager;

  private constructor() {
  }

  /**
   * 规范化标识符：去除前后空白、零宽字符和不换行空格，避免拷贝粘贴引入的不可见字符导致服务端解析失败
   */
  private sanitizeIdentifier(input: string): string {
    if (!input) return '';
    // 去除常见零宽字符: ZWSP(\u200B) ZWNJ(\u200C) ZWJ(\u200D) BOM(\uFEFF) 以及 NBSP(\u00A0)
    return input
      .replace(/[\u200B\u200C\u200D\uFEFF\u00A0]/g, '')
      .trim();
  }

  /**
   * 清洗 API Key：移除零宽字符与首尾空白，避免授权失败
   */
  private sanitizeApiKey(input: string): string {
    if (!input) return '';
    return input.replace(/[\u200B\u200C\u200D\uFEFF\u00A0]/g, '').trim();
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

    const trimmed = apiUrl.trim();
    const sanitizedUrl = trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;

    // 兼容常见的版本前缀。如果没有版本段，默认补 /v1
    const hasV1 = sanitizedUrl.includes('/v1');
    const hasAliyunCompatV1 = sanitizedUrl.includes('/compatible-mode/v1');

    if (hasAliyunCompatV1) {
      return `${sanitizedUrl}/chat/completions`;
    }

    if (hasV1) {
      return `${sanitizedUrl}/chat/completions`;
    }

    // 默认补 /v1/chat/completions
    return `${sanitizedUrl}/v1/chat/completions`;
  }

  /**
   * 发送流式聊天请求到AI服务
   */
  async sendStreamChatRequest(apiUrl: string, apiKey: string, model: string, messages: ChatMessage[], callbacks: StreamCallbacks): Promise<void> {
    return new Promise<void>((resolve, reject) => {
  const sanitizedApiUrl = (apiUrl || '').trim();
  const sanitizedModel = this.sanitizeIdentifier(model || '');
  const sanitizedApiKey = this.sanitizeApiKey(apiKey || '');

      console.info('Starting stream chat request...');
      console.info('API URL:', sanitizedApiUrl);
      console.info('Model:', sanitizedModel);
      console.info('Messages count:', messages.length);

      // 声明超时定时器变量
      let timeoutId: number | null = null;

      // 如果API URL已经包含完整路径，直接使用；否则拼接 /chat/completions
  const url = this.resolveChatCompletionsUrl(sanitizedApiUrl);

      const requestMessages: RequestMessage[] = messages.map(msg => {
        const requestMsg: RequestMessage = {
          role: msg.role as 'user' | 'assistant' | 'system',
          content: msg.content
        };
        return requestMsg;
      });

      const requestBody: ChatRequestBody = {
        model: sanitizedModel,
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
  const parseState: StreamParseState = { metadataDispatched: false, completed: false, errorDispatched: false };
  const bufferState: StreamBufferState = { pending: '' };
  // 捕获非 SSE 的错误响应体（如 HTTP 4xx/5xx 返回 JSON 文本）
  let rawErrorBody: string = '';

      // 订阅HTTP流式响应数据接收事件
  httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        // 将 ArrayBuffer 转换为字符串 - 使用 UTF-8 解码
        const uint8Array = new Uint8Array(data);
        let chunk = this.utf8ArrayToString(uint8Array);
        // 标准化换行，兼容 CRLF
        if (chunk && chunk.length > 0) {
          chunk = chunk.replace(/\r\n/g, '\n');
        }

        console.info('Received streaming data chunk, length:', chunk.length);
        console.info('Chunk preview:', chunk.substring(0, 200));

        // 若未能检测到 SSE 前缀（含或不含空格），且尚未派发元信息，则尝试累积为错误体
        // 注意：正常 SSE 数据以 `data: {json}` 的行格式出现，允许 `data:` 或 `data: `
        if (!parseState.metadataDispatched && chunk.search(/\ndata:\s?/g) === -1 && !/^data:\s?/m.test(chunk)) {
          rawErrorBody += chunk;
        }

        // 实时解析SSE格式的数据
        this.processSSEChunk(bufferState, chunk, wrappedCallbacks, parseState);
      });

      // 订阅HTTP流式响应数据接收完毕事件
      httpRequest.on('dataEnd', () => {
        console.info('HTTP stream data receive completed');
        // 处理剩余的缓冲区数据
        this.flushSSEBuffer(bufferState, wrappedCallbacks, parseState);

        // 如果到结束都没有完成且没有元信息，尝试回退：
        // 1) 可能服务端未按 SSE 返回，而是一次性 JSON 正常响应（非错误）
        // 2) 若为错误体，解析错误并上报
        if (!parseState.completed && rawErrorBody && rawErrorBody.trim().length > 0) {
          const body = rawErrorBody.trim();
          // 先尝试解析为正常 ChatResponse
          try {
            const possible: ChatResponse = JSON.parse(body) as ChatResponse;
            if (possible && possible.choices && Array.isArray(possible.choices)) {
              // 派发一次元数据（用 StreamMetadata 明确字段）
              if (!parseState.metadataDispatched) {
                const withSys: ChatResponseWithSysFp = possible as ChatResponseWithSysFp;
                wrappedCallbacks.onMetadata?.({
                  id: possible.id,
                  created: possible.created,
                  model: possible.model,
                  systemFingerprint: withSys.system_fingerprint,
                  choiceIndex: possible.choices.length > 0 ? possible.choices[0].index : undefined,
                  finishReason: possible.choices.length > 0 ? possible.choices[0].finish_reason : undefined
                });
                parseState.metadataDispatched = true;
              }

              // 拼接完整内容
              let fullText = '';
              const firstChoice = possible.choices[0];
              if (firstChoice && firstChoice.message && typeof firstChoice.message.content === 'string') {
                fullText = firstChoice.message.content;
              }

              if (fullText && fullText.length > 0) {
                wrappedCallbacks.onData(fullText);
              }

              parseState.completed = true;
              wrappedCallbacks.onComplete();
              return;
            }
          } catch {
            // 非正常 JSON，继续按错误体解析
          }

          // 解析为错误体
          try {
            const maybeJson = JSON.parse(body) as (ErrorResponse | VendorErrorResponse);
            let errMsg: string | undefined;
            if (maybeJson && typeof maybeJson === 'object') {
              const errResp = maybeJson as ErrorResponse;
              if (errResp.error && typeof errResp.error.message === 'string') {
                errMsg = errResp.error.message;
              }
              if (!errMsg) {
                const vendor = maybeJson as VendorErrorResponse;
                if (typeof vendor.message === 'string') {
                  if (typeof vendor.code !== 'undefined') {
                    errMsg = `${vendor.message} (code: ${String(vendor.code)})`;
                  } else {
                    errMsg = vendor.message;
                  }
                }
              }
            }
            if (errMsg && errMsg.length > 0) {
              console.error('Stream error body parsed message:', errMsg);
              parseState.errorDispatched = true;
              parseState.completed = true;
              wrappedCallbacks.onError(new Error(errMsg));
              return;
            }
          } catch {
            // 非 JSON，则作为原始文本透传
            console.warn('Failed to parse error body as JSON, pass-through text');
            parseState.errorDispatched = true;
            parseState.completed = true;
            wrappedCallbacks.onError(new Error(body));
            return;
          }
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
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Bearer ${sanitizedApiKey}`,
          // 同时声明接受 SSE 与 JSON，便于服务端在错误场景下返回 JSON
          'Accept': 'text/event-stream, application/json',
          'Cache-Control': 'no-cache',
          // 不主动设置 Connection，避免在 HTTP/2 下产生歧义
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
          // 如果先前已经根据错误体上报过更具体的信息，则不再重复覆盖
          if (!parseState.errorDispatched) {
            wrappedCallbacks.onError(new Error(`HTTP ${responseCode}`));
          }
        }
        this.destroyStreamRequest(httpRequest);
        resolve();
  }).catch((err: Error) => {
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }
        console.error('Stream request error:', err);
        if (!parseState.errorDispatched) {
          wrappedCallbacks.onError(new Error(`流式请求失败: ${err.message || err}`));
        }
        try {
          this.destroyStreamRequest(httpRequest);
        } catch {
          console.warn('Failed to destroy stream request after error');
        }
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
  private processSSEChunk(buffer: StreamBufferState, chunk: string | null, callbacks: StreamCallbacks, state: StreamParseState): void {
    if (chunk && chunk.length > 0) {
      buffer.pending += chunk;
    }

    if (!buffer.eventDataLines) {
      buffer.eventDataLines = [];
    }

    let newlineIndex = buffer.pending.indexOf('\n');
    while (newlineIndex !== -1) {
      const line = buffer.pending.substring(0, newlineIndex);
      buffer.pending = buffer.pending.substring(newlineIndex + 1);

      // 原样行（不 trim 首尾，避免丢失空行结束标记）
      const rawLine = line;
      const trimmed = rawLine.trimEnd(); // 保留前导空格以防 data: 后的单个空格被误处理

      // 空行表示一个 SSE 事件结束，派发累计的 data 片段
      if (trimmed.length === 0) {
        if (buffer.eventDataLines.length > 0) {
          const dataStr = buffer.eventDataLines.join('\n');
          buffer.eventDataLines = [];
          this.handleSSEDataField(dataStr, callbacks, state);
        }
        newlineIndex = buffer.pending.indexOf('\n');
        continue;
      }

      // 只处理 data: 开头，允许可选空格（如 data:xxx / data: xxx）
      const dataMatch = rawLine.match(/^data:\s?(.*)$/);
      if (dataMatch) {
        buffer.eventDataLines.push(dataMatch[1]);
      }

      newlineIndex = buffer.pending.indexOf('\n');
    }

    // flush: 若 chunk === null，表示流结束，处理遗留的数据
    if (chunk === null) {
      if (buffer.eventDataLines.length > 0) {
        const dataStr = buffer.eventDataLines.join('\n');
        buffer.eventDataLines = [];
        this.handleSSEDataField(dataStr, callbacks, state);
      }
      const remaining = buffer.pending.trim();
      buffer.pending = '';
      if (remaining.length > 0) {
        const dataMatch = remaining.match(/^data:\s?(.*)$/);
        if (dataMatch) {
          const dataStr = dataMatch[1].trim();
          this.handleSSEDataField(dataStr, callbacks, state);
        }
      }
    }
  }

  // 根据 data 字段内容派发事件，处理 [DONE] 或 JSON Payload
  private handleSSEDataField(dataStr: string, callbacks: StreamCallbacks, state: StreamParseState): void {
    const trimmed = (dataStr || '').trim();
    if (trimmed === '[DONE]') {
      console.info('SSE stream completed with [DONE]');
      if (!state.completed) {
        state.completed = true;
        callbacks.onComplete();
      }
      return;
    }
    this.dispatchSSEPayload(trimmed, callbacks, state);
  }

  private flushSSEBuffer(buffer: StreamBufferState, callbacks: StreamCallbacks, state: StreamParseState): void {
    this.processSSEChunk(buffer, null, callbacks, state);
  }

  private dispatchSSEPayload(dataStr: string, callbacks: StreamCallbacks, state: StreamParseState): void {
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
          callbacks.onData(delta.content);
        }
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
  const sanitizedApiUrl = (apiUrl || '').trim();
  const sanitizedModel = this.sanitizeIdentifier(modelName || '');
  const sanitizedApiKey = this.sanitizeApiKey(apiKey || '');

    console.info('NetworkManager: Starting chat request');
    console.info('API URL:', sanitizedApiUrl);
    console.info('Model:', sanitizedModel);
    console.info('Messages count:', messages.length);
    console.info('API Key length:', apiKey.length);

    const requestUrl = this.resolveChatCompletionsUrl(sanitizedApiUrl);
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
        model: sanitizedModel,
        messages: requestMessages,
        max_tokens: 2000,
        temperature: 0.7,
        stream: false
      };

      // 设置请求选项
      const requestHeaders: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${sanitizedApiKey}`,
        'Accept': 'application/json'
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
              console.error('HTTP error response body:', data.result as string);
            } catch (_) {}

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
