import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

import {
  ChatRequest,
  ChatResponse,
  ChatMessage,
  MessageInterface,
  StreamCallbacks,
  StreamResponse,
  RequestMessage,
  ChatRequestBody
} from '../services/DataModels';

interface HttpHeaderOptions {
  'Content-Type'?: string;
  Authorization?: string;
  Accept?: string;
  'Cache-Control'?: string;
  Connection?: string;
}

const LOG_TAG: string = '[Sample_HttpRequestDemo]';
const TARGET_URL: string = '';

// 网络请求管理器
export class NetworkManager {
  private static instance: NetworkManager;
  private streamBuffer: string = ''; // 用于累积流式数据
  private currentStreamRequest: http.HttpRequest | null = null;
  private streamCompleted: boolean = false;

  private constructor() {
  }

  static getInstance(): NetworkManager {
    if (!NetworkManager.instance) {
      NetworkManager.instance = new NetworkManager();
    }
    return NetworkManager.instance;
  }

  // 发送流式聊天请求到AI服务
  async sendStreamChatRequest(apiUrl: string, apiKey: string, model: string, messages: ChatMessage[],
    callbacks: StreamCallbacks): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      console.info('Starting stream chat request...');
      console.info('API URL:', apiUrl);
      console.info('Model:', model);
      console.info('Messages count:', messages.length);

      // 声明超时定时器变量
      let timeoutId: number | null = null;

      // 清空缓冲区确保新请求从干净状态开始
      this.streamBuffer = '';
      this.streamCompleted = false;

      // 如果API URL已经包含完整路径，直接使用；否则拼接 /chat/completions
      let url = apiUrl;
      if (!apiUrl.includes('/chat/completions')) {
        url = `${apiUrl}/chat/completions`;
      }

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
  this.currentStreamRequest = httpRequest;

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
        }
      };

      // 设置30秒超时
      timeoutId = setTimeout(() => {
        console.error('Stream request timeout');
        httpRequest.destroy();
        wrappedCallbacks.onError(new Error('请求超时'));
        reject(new Error('请求超时'));
      }, 30000);

      // 按需订阅HTTP流式响应事件
      let responseBuffer = new ArrayBuffer(0);

      // 订阅HTTP流式响应数据接收事件
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const newBuffer = new ArrayBuffer(responseBuffer.byteLength + data.byteLength);
        const bufferView = new Uint8Array(newBuffer);
        bufferView.set(new Uint8Array(responseBuffer));
        bufferView.set(new Uint8Array(data), responseBuffer.byteLength);
        responseBuffer = newBuffer;

        // 将 ArrayBuffer 转换为字符串 - 使用 UTF-8 解码
        const uint8Array = new Uint8Array(data);
        const rawChunk = this.utf8ArrayToString(uint8Array);

        console.info('Received streaming data chunk, length:', rawChunk.length);
        console.info('Chunk preview:', rawChunk.substring(0, 200));

        this.appendAndProcessStreamChunk(rawChunk, wrappedCallbacks);
      });

      // 订阅HTTP流式响应数据接收完毕事件
      httpRequest.on('dataEnd', () => {
        console.info('HTTP stream data receive completed');
        if (this.streamBuffer.trim()) {
          this.appendAndProcessStreamChunk('\n\n', wrappedCallbacks, true);
        }
        if (!this.streamCompleted) {
          this.streamCompleted = true;
          wrappedCallbacks.onComplete();
        }
      });

      // 订阅数据接收进度事件
      httpRequest.on('dataReceiveProgress', (progressInfo: http.DataReceiveProgressInfo) => {
        console.info('Data receive progress:', progressInfo.receiveSize, '/', progressInfo.totalSize);
      });

      // 发起HTTP流式请求
      const streamHeaders: HttpHeaderOptions = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive'
      };

      const streamOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: streamHeaders,
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 300000,
        readTimeout: 300000,
        usingCache: false
      };

      httpRequest.requestInStream(url, streamOptions).then((responseCode: number) => {
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }
        console.info('Stream request completed with response code:', responseCode);
        if (responseCode === 200) {
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
   * 取消当前流式请求
   */
  cancelCurrentStreamRequest(): void {
    if (this.currentStreamRequest) {
      console.info('Cancelling current stream request');
      this.destroyStreamRequest(this.currentStreamRequest);
    }
  }

  /**
   * 非流式请求，用于连接测试等场景
   */
  async sendChatRequest(apiUrl: string, apiKey: string, model: string, messages: ChatMessage[]): Promise<ChatResponse> {
    const requestMessages: RequestMessage[] = messages.map((msg: ChatMessage) => {
      const requestMsg: RequestMessage = {
        role: msg.role,
        content: msg.content
      };
      return requestMsg;
    });

    let url = apiUrl;
    if (!apiUrl.includes('/chat/completions')) {
      url = `${apiUrl}/chat/completions`;
    }

    const requestBody: ChatRequestBody = {
      model: model,
      messages: requestMessages,
      stream: false,
      max_tokens: 512,
      temperature: 0.7
    };

    const httpRequest = http.createHttp();
    const headers: HttpHeaderOptions = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    };

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(requestBody),
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: 30000,
      readTimeout: 30000
    };

    try {
      const responseCode = await httpRequest.request(url, options);
      if (responseCode.responseCode !== http.ResponseCode.OK) {
        throw new Error(`HTTP ${responseCode.responseCode}`);
      }

      const responseData = responseCode.result as string;
      return JSON.parse(responseData) as ChatResponse;
    } catch (error) {
      const bizError = error as BusinessError;
      const message = bizError?.message ?? JSON.stringify(error);
      console.error('Non-stream chat request failed:', message);
      throw new Error(`非流式请求失败: ${message}`);
    } finally {
      this.destroyStreamRequest(httpRequest);
    }
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
    if (this.currentStreamRequest === httpRequest) {
      this.currentStreamRequest = null;
    }
    this.streamBuffer = '';
    this.streamCompleted = false;
  }

  // 将 UTF-8 字节数组转换为字符串
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
   * 将接收到的流式片段写入缓冲区并解析
   */
  private appendAndProcessStreamChunk(chunk: string, callbacks: StreamCallbacks, forceFlush: boolean = false): void {
    this.streamBuffer += chunk.replace(/\r\n/g, '\n');

    let separatorIndex = this.streamBuffer.indexOf('\n\n');
    while (separatorIndex !== -1) {
      const rawEvent = this.streamBuffer.substring(0, separatorIndex);
      this.streamBuffer = this.streamBuffer.substring(separatorIndex + 2);
      this.handleSSEEvent(rawEvent, callbacks);
      separatorIndex = this.streamBuffer.indexOf('\n\n');
    }

    if (forceFlush && this.streamBuffer.trim()) {
      const remainder = this.streamBuffer;
      this.streamBuffer = '';
      this.handleSSEEvent(remainder, callbacks);
    }
  }

  /**
   * 解析单个SSE事件
   */
  private handleSSEEvent(rawEvent: string, callbacks: StreamCallbacks): void {
    if (!rawEvent) {
      return;
    }

    const dataPayloadLines = rawEvent
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.startsWith('data:'))
      .map(line => line.substring(5).trim());

    if (dataPayloadLines.length === 0) {
      return;
    }

    const dataPayload = dataPayloadLines.join('\n');

    if (dataPayload === '[DONE]') {
      if (!this.streamCompleted) {
        this.streamCompleted = true;
        callbacks.onComplete();
      }
      if (this.currentStreamRequest) {
        this.destroyStreamRequest(this.currentStreamRequest);
      }
      return;
    }

    try {
      const streamResponse: StreamResponse = JSON.parse(dataPayload);
      const textParts: string[] = [];

      streamResponse.choices?.forEach(choice => {
        if (choice.delta?.content) {
          textParts.push(choice.delta.content);
        }
        if (choice.delta?.reasoning_content) {
          textParts.push(choice.delta.reasoning_content);
        }
      });

      if (textParts.length > 0) {
        callbacks.onData(textParts.join(''));
      }
    } catch (error) {
      console.error('Failed to parse SSE event:', error, dataPayload);
    }
  }
}

// @Entry
// @Component
// struct HttpRequestPage {
//   @State html: string = "";
//
//   build() {
//     Column({ space: 10 }) {
//       Button("读取百度网页")
//         .onClick(() => {
//           //this.sendStreamHttpRequest();
//         })
//       Text(this.html)
//     }
//     .width('100%')
//     .height('100%')
//     .padding(10)
//   }
//
//
// }













  // // 封装流式 HTTP 请求逻辑
  // private sendStreamHttpRequest(): void {
  //   let httpRequest = http.createHttp();
  //   let res = new ArrayBuffer(0);
  //
  //   // 订阅HTTP流式响应数据接收事件
  //   httpRequest.on('dataReceive', (data: ArrayBuffer) => {
  //     const newRes = new ArrayBuffer(res.byteLength + data.byteLength);
  //     const resView = new Uint8Array(newRes);
  //     resView.set(new Uint8Array(res));
  //     resView.set(new Uint8Array(data), res.byteLength);
  //     res = newRes;
  //     console.info('res length: ' + res.byteLength);
  //   });
  //
  //   // 订阅HTTP流式响应数据接收完毕事件
  //   httpRequest.on('dataEnd', () => {
  //     console.info('No more data in response, data receive end');
  //   });
  //
  //   class Data {
  //     public receiveSize: number = 0;
  //     public totalSize: number = 0;
  //   }
  //
  //   // 订阅HTTP流式响应数据接收进度事见
  //   httpRequest.on('dataReceiveProgress', (data: Data) => {
  //     console.info("dataReceiveProgress receiveSize:" + data.receiveSize + ", totalSize:" + data.totalSize);
  //   });
  //
  //   // 订阅HTTP流式响应数据发送进度事件，向服务器上传数据时，可以通过该回调获取数据上传进度
  //   httpRequest.on('dataSendProgress', (data: http.DataSendProgressInfo) => {
  //     console.log("dataSendProgress receiveSize:" + data.sendSize + ", totalSize:" + data.totalSize);
  //   });
  //
  //   let streamInfo: http.HttpRequestOptions = {
  //     method: http.RequestMethod.POST, // 使用POST请求
  //     header: {
  //       'contentType': 'application/json'
  //     },
  //     extraData: 'data to send', // 请求体内容
  //     expectDataType: http.HttpDataType.STRING, // 指定返回数据的类型
  //     usingCache: true, // 使用缓存
  //     priority: 1, // 请求优先级
  //     connectTimeout: 60000, // 连接超时
  //     readTimeout: 60000, // 读取超时
  //     usingProtocol: http.HttpProtocol.HTTP1_1 // 协议类型
  //   };
  //
  //   // 发送流式请求
  //   httpRequest.requestInStream("huawei.com", streamInfo)
  //     .then((data: number) => {
  //       console.info("requestInStream OK!");
  //       console.info('ResponseCode :' + JSON.stringify(data));
  //       // 取消订阅步骤3中订阅的事件，并调用destroy方法主动销毁。
  //       this.destroyRequest(httpRequest);
  //     }).catch((err: Error) => {
  //     console.error("requestInStream ERROR : err = " + JSON.stringify(err));
  //     // 取消订阅步骤3中订阅的事件，并调用destroy方法主动销毁。
  //     this.destroyRequest(httpRequest);
  //     });
  //
  // };
  //
  // public destroyRequest(httpRequest: http.HttpRequest) {
  //   // 取消订阅HTTP流式响应数据接收事件。
  //   httpRequest.off('dataReceive');
  //   // 取消订阅HTTP流式响应数据发送进度事件。
  //   httpRequest.off('dataSendProgress');
  //   // 取消订阅HTTP流式响应数据接收进度事件。
  //   httpRequest.off('dataReceiveProgress');
  //   // 取消订阅HTTP流式响应数据接收完毕事件。
  //   httpRequest.off('dataEnd');
  //   // 当该请求使用完毕时，调用destroy方法主动销毁。
  //   httpRequest.destroy();
  // }
