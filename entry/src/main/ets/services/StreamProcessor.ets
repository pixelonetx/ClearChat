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
import { StreamMetadata, ExtendedStreamResponse, ExtendedStreamDelta, Citation, ApiFormat } from '../services/DataModels';
import { createLogger, LogDomain } from '../common/Logger';

/**
 * 错误详情接口
 */
interface ErrorDetail {
  message?: string;
  type?: string;
  code?: string | number;
}

/**
 * 错误响应数据接口
 */
interface ErrorResponseData {
  error?: ErrorDetail;
  message?: string;
  code?: string | number;
}

const logger = createLogger('StreamProcessor', LogDomain.STREAM);

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

  // API 格式（用于响应解析分支）
  apiFormat?: ApiFormat;
}

/**
 * SSE 流处理器
 */
export class StreamProcessor {
  private state: StreamState;
  private emitter: StreamEventEmitter;
  private options: Required<StreamProcessorOptions>;
  private apiFormat: ApiFormat;
  // Gemini 流式追踪（处理累积式响应）
  private geminiThoughtOffset: number = 0;
  private geminiTextOffset: number = 0;

  constructor(
    state: StreamState,
    emitter: StreamEventEmitter,
    options: StreamProcessorOptions = {}
  ) {
    this.state = state;
    this.emitter = emitter;
    this.apiFormat = options.apiFormat ?? 'openai';
    this.options = {
      debug: options.debug ?? false,
      maxBufferSize: options.maxBufferSize ?? 1024 * 1024, // 1MB
      processTimeout: options.processTimeout ?? 30000,
      apiFormat: options.apiFormat ?? 'openai'
    };
  }

  /**
   * 设置 API 格式（用于响应解析分支）
   */
  setApiFormat(format: ApiFormat): void {
    this.apiFormat = format;
    this.options.apiFormat = format;
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
    // 先排空 eventDataLines 中未处理的行（无空行边界时也会积累）
    const pendingLines = this.state.clearDataLines();
    if (pendingLines.length > 0) {
      const dataStr = pendingLines.join('\n');
      this.handleSSEDataField(dataStr);
    }

    // 再处理缓冲区中剩余的内容
    const remaining = this.state.getBufferContent().trim();
    if (remaining.length === 0) {
      return;
    }

    // 处理剩余的数据行
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
        // 解析 data: 字段
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
      const jsonData = JSON.parse(dataStr) as Object;
      switch (this.apiFormat) {
        case 'anthropic':
          this.processAnthropicEvent(jsonData);
          break;
        case 'gemini':
          this.processGeminiEvent(jsonData);
          break;
        default:
          this.processStreamResponse(jsonData as ExtendedStreamResponse);
          break;
      }
    } catch (parseError) {
      const errorMsg = `SSE JSON 解析失败: ${parseError}。原始数据: ${dataStr.substring(0, 100)}`;
      this.log(`警告: ${errorMsg}`);
      this.emitter.emit(StreamEventType.WARNING, errorMsg);
    }
  }

  /**
   * 处理 Anthropic 流式 SSE 事件
   *
   * Anthropic SSE 事件类型：
   * - message_start: 包含消息元数据
   * - content_block_start: 文本块/思考块开始
   * - content_block_delta: 文本/思考增量
   * - content_block_stop: 块结束
   * - message_delta: 包含 stop_reason
   * - message_stop: 流结束
   */
  private processAnthropicEvent(rawData: Object): void {
    const data = rawData as Record<string, Object>;
    const eventType = data['type'] as string | undefined;

    // 错误事件
    if (eventType === 'error') {
      const err = data['error'] as Record<string, Object> | undefined;
      const errMsg = (err ? err['message'] : undefined) as string || 'Anthropic API 错误';
      if (!this.state.isErrorDispatched()) {
        this.emitter.emit(StreamEventType.ERROR, new Error(errMsg));
        this.state.markErrorDispatched();
      }
      return;
    }

    switch (eventType) {
      case 'message_start': {
        const msg = data['message'] as Record<string, Object> | undefined;
        if (msg && !this.state.isMetadataDispatched()) {
          const metadata: StreamMetadata = {
            id: msg['id'] as string,
            model: msg['model'] as string
          };
          this.emitter.emit(StreamEventType.METADATA, metadata);
          this.state.markMetadataDispatched();
        }
        break;
      }

      case 'content_block_delta': {
        const delta = data['delta'] as Record<string, Object> | undefined;
        if (!delta) { break; }
        const deltaType = delta['type'] as string | undefined;

        if (deltaType === 'thinking_delta') {
          const thinking = delta['thinking'] as string | undefined;
          if (thinking && thinking.length > 0) {
            if (!this.state.getData().reasoningStarted) {
              this.emitter.emit(StreamEventType.DATA, '<reasoning_content>');
              this.state.markReasoningStarted();
            }
            this.emitter.emit(StreamEventType.DATA, thinking);
          }
        } else if (deltaType === 'text_delta') {
          const text = delta['text'] as string | undefined;
          if (text && text.length > 0) {
            if (this.state.getData().reasoningStarted) {
              this.emitter.emit(StreamEventType.DATA, '</reasoning_content>');
              this.state.markReasoningEnded();
            }
            this.emitter.emit(StreamEventType.DATA, text);
          }
        }
        break;
      }

      case 'message_delta': {
        const delta = data['delta'] as Record<string, Object> | undefined;
        if (delta && delta['stop_reason']) {
          // 记录 stop_reason 到元数据（可选更新）
          const metadata: StreamMetadata = { finishReason: delta['stop_reason'] as string };
          this.emitter.emit(StreamEventType.METADATA, metadata);
        }
        break;
      }

      case 'message_stop': {
        if (this.state.getData().reasoningStarted) {
          this.emitter.emit(StreamEventType.DATA, '</reasoning_content>');
          this.state.markReasoningEnded();
        }
        if (!this.state.isCompleted()) {
          this.state.markCompleted();
          this.emitter.emit(StreamEventType.COMPLETE, undefined);
        }
        break;
      }

      default:
        // content_block_start, content_block_stop, ping 等事件忽略
        break;
    }
  }

  /**
   * 处理 Gemini 流式 SSE 事件
   *
   * Gemini SSE 格式：每个 data: 行是一个完整的 JSON 对象
   * { candidates: [{ content: { parts: [{text: "..."}, {thought: "..."}], role: "model" }, finishReason: "STOP" }] }
   */
  private processGeminiEvent(rawData: Object): void {
    const data = rawData as Record<string, Object>;
    // 错误响应
    if (data['error']) {
      const err = data['error'] as Record<string, Object>;
      const errMsg = (err['message'] as string) || 'Gemini API 错误';
      if (!this.state.isErrorDispatched()) {
        this.emitter.emit(StreamEventType.ERROR, new Error(errMsg));
        this.state.markErrorDispatched();
      }
      return;
    }

    // 首次响应发送元数据
    if (!this.state.isMetadataDispatched()) {
      const metadata: StreamMetadata = {
        model: data['modelVersion'] as string
      };
      this.emitter.emit(StreamEventType.METADATA, metadata);
      this.state.markMetadataDispatched();
    }

    const candidates = data['candidates'] as Array<Record<string, Object>> | undefined;
    if (!candidates || candidates.length === 0) { return; }

    const candidate = candidates[0];
    // 安全检查：被安全过滤拦截的响应
    if (candidate['finishReason'] === 'SAFETY' || candidate['finishReason'] === 'RECITATION') {
      if (!this.state.isErrorDispatched()) {
        this.emitter.emit(StreamEventType.ERROR, new Error(`内容被安全策略拦截 (${candidate['finishReason']})`));
        this.state.markErrorDispatched();
      }
      return;
    }
    const content = candidate['content'] as Record<string, Object> | undefined;
    if (!content) { return; }
    let hasThought = false;

    if (content) {
      const parts = content['parts'] as Array<Record<string, Object>> | undefined;
      if (parts) {
        for (const part of parts) {
          if (part['thought']) {
            hasThought = true;
            const thoughtText = part['thought'] as string;
            if (thoughtText && thoughtText.length > this.geminiThoughtOffset) {
              const delta = thoughtText.substring(this.geminiThoughtOffset);
              this.geminiThoughtOffset = thoughtText.length;
              if (!this.state.getData().reasoningStarted) {
                this.emitter.emit(StreamEventType.DATA, '<reasoning_content>');
                this.state.markReasoningStarted();
              }
              this.emitter.emit(StreamEventType.DATA, delta);
            }
          }
          if (part['text']) {
            if (hasThought && this.state.getData().reasoningStarted) {
              this.emitter.emit(StreamEventType.DATA, '</reasoning_content>');
              this.state.markReasoningEnded();
              hasThought = false;
            }
            const textStr = part['text'] as string;
            if (textStr && textStr.length > this.geminiTextOffset) {
              const delta = textStr.substring(this.geminiTextOffset);
              this.geminiTextOffset = textStr.length;
              this.emitter.emit(StreamEventType.DATA, delta);
            }
          }
        }
      }
    }

    // 检查完成信号
    const finishReason = candidate['finishReason'] as string | undefined;
    if (finishReason && finishReason !== 'STOP' && finishReason !== 'MAX_TOKENS' && finishReason !== 'FINISH_REASON_UNSPECIFIED') {
      // 异常结束，记录但不报错
      this.log(`Gemini finish_reason: ${finishReason}`);
    }

    if (finishReason && !this.state.isCompleted()) {
      if (this.state.getData().reasoningStarted) {
        this.emitter.emit(StreamEventType.DATA, '</reasoning_content>');
        this.state.markReasoningEnded();
      }
      this.state.markCompleted();
      this.emitter.emit(StreamEventType.COMPLETE, undefined);
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

      // 当 finish_reason 表示工具调用时，外层会在流结束时处理 TOOL_CALL 事件
      // 兼容性修复：有些模型（如 DeepSeek/Qwen）可能不返回 finish_reason='tool_calls'
      // 而是直接在流结束时检查是否有完整的 tool_calls
      if (response.choices[0].finish_reason === 'tool_calls' || 
          (delta.tool_calls && delta.tool_calls.length > 0 && response.choices[0].finish_reason === 'stop')) {
        // 这里仅负责累积工具调用片段
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
      const parsedData: ExtendedStreamResponse | ErrorResponseData = JSON.parse(body) as ExtendedStreamResponse | ErrorResponseData;
      const data = parsedData;

      if (!isError) {
        // 处理为正常响应
        const responseData = data as ExtendedStreamResponse;
        if (responseData && responseData.choices && Array.isArray(responseData.choices)) {
          const response = responseData;
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

          // 发送完整内容
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
      const errorMsg = this.extractErrorMessage(data as ErrorResponseData);
      if (errorMsg) {
        this.emitter.emit(StreamEventType.ERROR, new Error(errorMsg));
        this.state.markErrorDispatched();
        return;
      }
    } catch (error) {
      this.log(`警告: 无法解析 JSON 响应: ${error}`);
    }

    // 作为纯文本传输
    if (body.trim().length > 0) {
      this.emitter.emit(StreamEventType.ERROR, new Error(body.trim()));
      this.state.markErrorDispatched();
    }
  }

  /**
   * 从错误响应中提取错误信息
   */
  private extractErrorMessage(data: ErrorResponseData): string | null {
    // OpenAI 格式
    const errorField: ErrorDetail | undefined = data.error;
    if (errorField && typeof errorField === 'object') {
      const messageField: string | undefined = errorField.message;
      if (messageField && typeof messageField === 'string') {
        return messageField;
      }
    }

    // 通用格式
    const messageField: string | undefined = data.message;
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
      logger.info( message);
    }
  }

  /**
   * 清理资源
   */
  dispose(): void {
    this.geminiThoughtOffset = 0;
    this.geminiTextOffset = 0;
    this.state.dispose();
  }
}

