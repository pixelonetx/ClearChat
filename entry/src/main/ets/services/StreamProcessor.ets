/**
 * StreamProcessor.ets
 * 
 *  SSE 处理逻辑分离 - 单一职责原则
 * 
 * 优势：
 * 1. 职责单一 - 只负责 SSE 解析
 * 2. 易于测试 - 可独立测试 SSE 解析逻辑
 * 3. 易于维护 - 修改不影响其他模块
 * 4. 易于复用 - 可在其他场景使用
 */

import { StreamState } from './StreamState';
import { StreamEventEmitter, StreamEventType } from './StreamEventEmitter';
import { StreamMetadata, ExtendedStreamResponse, ExtendedStreamDelta, Citation } from '../services/DataModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'StreamProcessor';

/**
 * SSE 处理器配置
 */
export interface StreamProcessorOptions {
  // 是否输出调试日志
  debug?: boolean;
  
  // 最大缓冲区大小（字节）
  maxBufferSize?: number;
  
  // 处理 SSE 事件的超时时间（毫秒）
  processTimeout?: number;
}

/**
 * SSE 流处理器
 */
export class StreamProcessor {
  private state: StreamState;
  private emitter: StreamEventEmitter;
  private options: Required<StreamProcessorOptions>;

  constructor(
    state: StreamState,
    emitter: StreamEventEmitter,
    options: StreamProcessorOptions = {}
  ) {
    this.state = state;
    this.emitter = emitter;
    this.options = {
      debug: options.debug ?? false,
      maxBufferSize: options.maxBufferSize ?? 1024 * 1024, // 1MB
      processTimeout: options.processTimeout ?? 30000
    };
  }

  /**
   * 处理 SSE 数据块
   * 
   * @param chunk 原始数据块
   * @throws Error 如果缓冲区超过最大大小
   */
  processChunk(chunk: string): void {
    if (!chunk || chunk.length === 0) {
      return;
    }

    // 标准化换行符
    const normalizedChunk = chunk.replace(/\r\n/g, '\n');

    // 追加到缓冲区
    this.state.appendToBuffer(normalizedChunk);

    // 检查缓冲区大小
    const bufferSize = this.state.getBufferContent().length;
    if (bufferSize > this.options.maxBufferSize) {
      const error = new Error(
        `缓冲区超过最大大小: ${bufferSize}/${this.options.maxBufferSize} 字节`
      );
      this.emitter.emit(StreamEventType.WARNING, `缓冲区警告: ${error.message}`);
    }

    // 解析 SSE 事件
    this.parseSSEEvents();
  }

  /**
   * 结束流处理（处理剩余缓冲区）
   */
  flush(): void {
    const remaining = this.state.getBufferContent().trim();
    if (remaining.length === 0) {
      return;
    }

    // 处理剩余的数据
    const dataMatch = remaining.match(/^data:\s?(.*)$/);
    if (dataMatch) {
      const dataStr = dataMatch[1].trim();
      this.handleSSEDataField(dataStr);
    }
  }

  /**
   * 解析缓冲区中的 SSE 事件
   * 
   * SSE 格式：
   * ```
   * data: {"key":"value"}
   * data: {"key":"value"}
   * 
   * data: {"key":"value"}
   * ```
   * 
   * 空行表示一个事件结束
   */
  private parseSSEEvents(): void {
    let buffer = this.state.getBufferContent();
    let newlineIndex = buffer.indexOf('\n');

    while (newlineIndex !== -1) {
      const line = buffer.substring(0, newlineIndex);
      buffer = buffer.substring(newlineIndex + 1);

      const trimmed = line.trimEnd();

      // 空行表示事件结束
      if (trimmed.length === 0) {
        const dataLines = this.state.clearDataLines();
        if (dataLines.length > 0) {
          const dataStr = dataLines.join('\n');
          this.handleSSEDataField(dataStr);
        }
      } else {
        // 解析 data: 行
        const dataMatch = line.match(/^data:\s?(.*)$/);
        if (dataMatch) {
          this.state.addDataLine(dataMatch[1]);
        }
      }

      newlineIndex = buffer.indexOf('\n');
    }

    // 更新缓冲区（保留未完整的行）
    this.state.clearBuffer();
    if (buffer.length > 0) {
      this.state.appendToBuffer(buffer);
    }
  }

  /**
   * 处理 SSE 数据字段
   */
  private handleSSEDataField(dataStr: string): void {
    const trimmed = (dataStr || '').trim();

    if (trimmed === '[DONE]') {
      this.log('SSE 流已完成，接收到 [DONE] 信号');
      // 处理推理内容的闭合
      if (this.state.getData().reasoningStarted) {
        this.emitter.emit(StreamEventType.DATA, '</reasoning_content>');
        this.state.markReasoningEnded();
      }

      // 检查是否有未分发的工具调用
      const toolCalls = this.state.getToolCalls();
      if (toolCalls.length > 0) {
        const payload = toolCalls as import('./StreamEventEmitter').ToolCallData[];
        this.emitter.emit(StreamEventType.TOOL_CALL, payload);
        this.state.clearToolCalls();
      }

      if (!this.state.isCompleted()) {
        this.state.markCompleted();
        this.emitter.emit(StreamEventType.COMPLETE, undefined);
      }
      return;
    }

    this.dispatchSSEPayload(trimmed);
  }

  /**
   * 分派 SSE 载荷
   */
  private dispatchSSEPayload(dataStr: string): void {
    try {
      const jsonData = JSON.parse(dataStr) as ExtendedStreamResponse;
      this.processStreamResponse(jsonData);
    } catch (parseError) {
      const errorMsg = `SSE JSON 解析失败: ${parseError}。原始数据: ${dataStr.substring(0, 100)}`;
      this.log(`警告: ${errorMsg}`);
      this.emitter.emit(StreamEventType.WARNING, errorMsg);
    }
  }

  /**
   * 处理流式响应
   */
  private processStreamResponse(response: ExtendedStreamResponse): void {
    // 发送元数据（仅一次）
    if (!this.state.isMetadataDispatched()) {
      const metadata: StreamMetadata = {
        id: response.id,
        created: response.created,
        model: response.model,
        systemFingerprint: response.system_fingerprint,
        choiceIndex: response.choices?.length > 0 ? response.choices[0].index : undefined,
        finishReason: response.choices?.length > 0 ? response.choices[0].finish_reason : undefined,
        citations: response.citations || response.references
      };
      this.emitter.emit(StreamEventType.METADATA, metadata);
      this.state.markMetadataDispatched();
    }

    // 处理选择项中的 delta
    if (response.choices && response.choices.length > 0) {
      const delta = response.choices[0].delta as ExtendedStreamDelta;

      // 处理推理内容
      if (delta.reasoning_content && typeof delta.reasoning_content === 'string' &&
          delta.reasoning_content.length > 0) {
        if (!this.state.getData().reasoningStarted) {
          this.emitter.emit(StreamEventType.DATA, '<reasoning_content>');
          this.state.markReasoningStarted();
        }
        this.emitter.emit(StreamEventType.DATA, delta.reasoning_content);
      }

      // 处理工具调用
      if (delta.tool_calls && delta.tool_calls.length > 0) {
        for (const toolCall of delta.tool_calls) {
          const index = toolCall.index ?? 0;
          this.state.accumulateToolCall(index, toolCall);
        }
      }

      // 处理常规内容
      if (delta.content) {
        // 从推理内容过渡到常规内容时，闭合推理标签
        if (this.state.getData().reasoningStarted) {
          this.emitter.emit(StreamEventType.DATA, '</reasoning_content>');
          this.state.markReasoningEnded();
        }
        this.emitter.emit(StreamEventType.DATA, delta.content);
      }

      // 处理引用信息
      if (delta.citations || delta.references) {
        this.emitter.emit(StreamEventType.METADATA, {
          citations: (delta.citations || delta.references) as Citation[]
        });
      }

      // 当 finish_reason 表示工具调用时，发送 TOOL_CALL 事件
      // 兼容性修复：有些模型（如 DeepSeek/Qwen）可能不返回 finish_reason='tool_calls'
      // 而是直接在流结束时检查是否有完整的 tool_calls
      if (response.choices[0].finish_reason === 'tool_calls' || 
          (delta.tool_calls && delta.tool_calls.length > 0 && response.choices[0].finish_reason === 'stop')) {
        // 这里的逻辑由 handleStreamComplete 或外部检查处理，这里只负责累积
      }
    }
  }

  /**
   * 处理非 SSE 的 JSON 正常响应
   * 
   * 用于服务器返回普通 JSON 而不是 SSE 流的场景
   */
  handleNormalJSONResponse(body: string, isError: boolean = false): void {
    try {
      // 明确类型转换以避免 any 类型
      const parsedData: ESObject = JSON.parse(body) as ESObject;
      const data: ESObject = parsedData;

      if (!isError) {
        // 处理为正常响应
        if (data && data.choices && Array.isArray(data.choices)) {
          const response = data as ExtendedStreamResponse;
          // 发送元数据
          if (!this.state.isMetadataDispatched()) {
            const metadata: StreamMetadata = {
              id: response.id,
              created: response.created,
              model: response.model,
              systemFingerprint: response.system_fingerprint,
              choiceIndex: response.choices[0]?.index,
              finishReason: response.choices[0]?.finish_reason
            };
            this.emitter.emit(StreamEventType.METADATA, metadata);
            this.state.markMetadataDispatched();
          }

          // 发送完整内容（注：流式响应中 choices[0].delta.content 包含内容）
          const firstChoice = response.choices[0];
          if (firstChoice && firstChoice.delta) {
            const deltaContent = (firstChoice.delta as ExtendedStreamDelta).content || '';
            if (deltaContent.length > 0) {
              this.emitter.emit(StreamEventType.DATA, deltaContent);
            }
          }

          this.state.markCompleted();
          this.emitter.emit(StreamEventType.COMPLETE, undefined);
          return;
        }
      }

      // 处理错误响应
      const errorMsg = this.extractErrorMessage(data as ESObject);
      if (errorMsg) {
        this.emitter.emit(StreamEventType.ERROR, new Error(errorMsg));
        this.state.markErrorDispatched();
        return;
      }
    } catch (error) {
      this.log(`警告: 无法解析 JSON 响应: ${error}`);
    }

    // 作为纯文本传递
    if (body.trim().length > 0) {
      this.emitter.emit(StreamEventType.ERROR, new Error(body.trim()));
      this.state.markErrorDispatched();
    }
  }

  /**
   * 从错误响应中提取错误信息
   */
  private extractErrorMessage(data: ESObject): string | null {
    // OpenAI 格式
    const errorField: ESObject | undefined = data.error as ESObject | undefined;
    if (errorField && typeof errorField === 'object') {
      const errorObj: ESObject = errorField as ESObject;
      const messageField: string | undefined = errorObj.message as string | undefined;
      if (messageField && typeof messageField === 'string') {
        return messageField;
      }
    }

    // 通用格式
    const messageField: string | undefined = data.message as string | undefined;
    if (messageField && typeof messageField === 'string') {
      if (data.code !== undefined) {
        return `${messageField} (code: ${data.code})`;
      }
      return messageField;
    }

    return null;
  }

  /**
   * 中止流处理
   */
  abort(): void {
    this.state.markUserAborted();
    this.log('流处理已中止');
  }

  /**
   * 获取处理统计信息
   */
  getStats() {
    return this.state.getStats();
  }

  /**
   * 获取处理状态快照
   */
  getStateSnapshot() {
    return this.state.getSnapshot();
  }

  /**
   * 调试日志
   */
  private log(message: string): void {
    if (this.options.debug) {
      hilog.info(DOMAIN, TAG, message);
    }
  }

  /**
   * 清理资源
   */
  dispose(): void {
    this.state.dispose();
  }
}

