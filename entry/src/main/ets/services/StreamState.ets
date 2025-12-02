/**
 * StreamState.ets
 * 
 *  状态管理 - 集中式状态容器
 * 
 * 优势：
 * 1. 单一源头 - 所有状态在一个地方
 * 2. 可观测 - 支持状态变化通知
 * 3. 不可变性 - 防止意外修改
 * 4. 易于调试 - 快照和历史追踪
 */

import { StreamEventEmitter, StreamEventType, StreamStateSnapshot } from './StreamEventEmitter';

/**
 * 累积的工具调用数据接口
 */
export interface AccumulatedToolCall {
  id?: string;
  type?: string;
  name?: string;
  arguments?: string;
}

/**
 * 流式请求的完整状态
 */
export interface StreamStateData {
  // 解析状态
  metadataDispatched: boolean;
  completed: boolean;
  errorDispatched: boolean;
  userAborted: boolean;

  // 推理内容状态
  reasoningStarted: boolean;

  // 工具调用累积状态
  pendingToolCalls: Map<number, AccumulatedToolCall>;

  // 缓冲区状态
  bufferPending: string;
  eventDataLines: string[];

  // 统计信息
  totalDataSize: number;
  chunkCount: number;
  startTime: number;

  // 错误信息
  lastError?: Error;
}

/**
 * 初始状态工厂函数
 */
function createInitialState(): StreamStateData {
  return {
    metadataDispatched: false,
    completed: false,
    errorDispatched: false,
    userAborted: false,
    reasoningStarted: false,
    pendingToolCalls: new Map(),
    bufferPending: '',
    eventDataLines: [],
    totalDataSize: 0,
    chunkCount: 0,
    startTime: Date.now()
  };
}

/**
 * 统计信息接口
 */
export interface StreamStatistics {
  totalDataSize: number;
  chunkCount: number;
  elapsedTime: number;
  avgChunkSize: number;
}

/**
 * 集中式状态管理容器
 */
export class StreamState {
  private data: StreamStateData;
  private emitter: StreamEventEmitter;
  private history: StreamStateData[] = [];
  private maxHistorySize: number = 100;

  constructor(emitter: StreamEventEmitter) {
    this.data = createInitialState();
    this.emitter = emitter;
  }

  /**
   * 获取当前状态快照（只读）
   */
  getSnapshot(): StreamStateSnapshot {
    const snapshot: StreamStateSnapshot = {
      metadataDispatched: this.data.metadataDispatched,
      completed: this.data.completed,
      errorDispatched: this.data.errorDispatched,
      reasoningStarted: this.data.reasoningStarted,
      userAborted: this.data.userAborted,
      bufferedDataSize: this.data.bufferPending.length
    };
    return snapshot;
  }

  /**
   * 获取完整数据（用于内部使用）
   */
  getData(): StreamStateData {
    const dataCopy: StreamStateData = {
      metadataDispatched: this.data.metadataDispatched,
      completed: this.data.completed,
      errorDispatched: this.data.errorDispatched,
      userAborted: this.data.userAborted,
      reasoningStarted: this.data.reasoningStarted,
      pendingToolCalls: new Map(this.data.pendingToolCalls),
      bufferPending: this.data.bufferPending,
      eventDataLines: this.data.eventDataLines.slice(),
      totalDataSize: this.data.totalDataSize,
      chunkCount: this.data.chunkCount,
      startTime: this.data.startTime,
      lastError: this.data.lastError
    };
    return dataCopy;
  }

  /**
   * 更新状态 - 保存历史
   */
  private updateState(updates: StreamStateData): void {
    const oldState: StreamStateData = this.getData();
    
    // 应用更新
    if (updates.metadataDispatched !== undefined) {
      this.data.metadataDispatched = updates.metadataDispatched;
    }
    if (updates.completed !== undefined) {
      this.data.completed = updates.completed;
    }
    if (updates.errorDispatched !== undefined) {
      this.data.errorDispatched = updates.errorDispatched;
    }
    if (updates.userAborted !== undefined) {
      this.data.userAborted = updates.userAborted;
    }
    if (updates.reasoningStarted !== undefined) {
      this.data.reasoningStarted = updates.reasoningStarted;
    }
    if (updates.bufferPending !== undefined) {
      this.data.bufferPending = updates.bufferPending;
    }
    if (updates.eventDataLines !== undefined) {
      this.data.eventDataLines = updates.eventDataLines;
    }
    if (updates.totalDataSize !== undefined) {
      this.data.totalDataSize = updates.totalDataSize;
    }
    if (updates.chunkCount !== undefined) {
      this.data.chunkCount = updates.chunkCount;
    }
    if (updates.lastError !== undefined) {
      this.data.lastError = updates.lastError;
    }

    // 记录历史（用于调试）
    if (this.history.length >= this.maxHistorySize) {
      this.history.shift();
    }
    this.history.push(oldState);

    // 发射状态变化事件
    this.emitter.emit(StreamEventType.STATE_CHANGED, this.getSnapshot());
  }

  /**
   * 标记元数据已发送
   */
  markMetadataDispatched(): void {
    const updates: StreamStateData = this.getData();
    updates.metadataDispatched = true;
    this.updateState(updates);
  }

  /**
   * 标记已完成
   */
  markCompleted(): void {
    const updates: StreamStateData = this.getData();
    updates.completed = true;
    this.updateState(updates);
  }

  /**
   * 标记错误已发送
   */
  markErrorDispatched(): void {
    const updates: StreamStateData = this.getData();
    updates.errorDispatched = true;
    this.updateState(updates);
  }

  /**
   * 标记用户中止
   */
  markUserAborted(): void {
    const updates: StreamStateData = this.getData();
    updates.userAborted = true;
    this.updateState(updates);
  }

  /**
   * 标记推理内容开始
   */
  markReasoningStarted(): void {
    const updates: StreamStateData = this.getData();
    updates.reasoningStarted = true;
    this.updateState(updates);
  }

  /**
   * 标记推理内容结束
   */
  markReasoningEnded(): void {
    const updates: StreamStateData = this.getData();
    updates.reasoningStarted = false;
    this.updateState(updates);
  }

  /**
   * 添加到缓冲区
   */
  appendToBuffer(chunk: string): void {
    const updates: StreamStateData = this.getData();
    updates.bufferPending = this.data.bufferPending + chunk;
    updates.totalDataSize = this.data.totalDataSize + chunk.length;
    updates.chunkCount = this.data.chunkCount + 1;
    this.updateState(updates);
  }

  /**
   * 清空缓冲区
   */
  clearBuffer(): void {
    const updates: StreamStateData = this.getData();
    updates.bufferPending = '';
    this.updateState(updates);
  }

  /**
   * 获取缓冲区内容
   */
  getBufferContent(): string {
    return this.data.bufferPending;
  }

  /**
   * 添加数据行
   */
  addDataLine(line: string): void {
    const newLines = this.data.eventDataLines.slice();
    newLines.push(line);
    const updates: StreamStateData = this.getData();
    updates.eventDataLines = newLines;
    this.updateState(updates);
  }

  /**
   * 清空数据行
   */
  clearDataLines(): string[] {
    const lines = this.data.eventDataLines.slice();
    const updates: StreamStateData = this.getData();
    updates.eventDataLines = [];
    this.updateState(updates);
    return lines;
  }

  /**
   * 记录错误
   */
  setError(error: Error): void {
    const updates: StreamStateData = this.getData();
    updates.lastError = error;
    this.updateState(updates);
  }

  /**
   * 获取错误信息
   */
  getError(): Error | undefined {
    return this.data.lastError;
  }

  /**
   * 累积工具调用数据（用于流式响应）
   */
  accumulateToolCall(
    index: number,
    toolCallDelta: import('./DataModels').ToolCall
  ): void {
    let current = this.data.pendingToolCalls.get(index);
    if (!current) {
      current = { arguments: '' };
    }
    
    if (toolCallDelta.id) {
      current.id = toolCallDelta.id;
    }
    if (toolCallDelta.type) {
      current.type = toolCallDelta.type;
    }
    if (toolCallDelta.function?.name) {
      current.name = toolCallDelta.function.name;
    }
    if (toolCallDelta.function?.arguments) {
      current.arguments = (current.arguments || '') + toolCallDelta.function.arguments;
    }
    
    this.data.pendingToolCalls.set(index, current);
  }

  /**
   * 获取完整的工具调用列表
   */
  getToolCalls(): AccumulatedToolCall[] {
    const result: AccumulatedToolCall[] = [];
    
    this.data.pendingToolCalls.forEach((value) => {
      result.push(value);
    });
    
    return result;
  }

  /**
   * 清空工具调用累积数据
   */
  clearToolCalls(): void {
    this.data.pendingToolCalls.clear();
  }

  /**
   * 检查是否已完成
   */
  isCompleted(): boolean {
    return this.data.completed;
  }

  /**
   * 检查是否有错误已发送
   */
  isErrorDispatched(): boolean {
    return this.data.errorDispatched;
  }

  /**
   * 检查是否用户已中止
   */
  isUserAborted(): boolean {
    return this.data.userAborted;
  }

  /**
   * 检查是否已发送元数据
   */
  isMetadataDispatched(): boolean {
    return this.data.metadataDispatched;
  }

  /**
   * 获取执行时间（毫秒）
   */
  getElapsedTime(): number {
    return Date.now() - this.data.startTime;
  }

  /**
   * 获取统计信息
   */
  getStats(): StreamStatistics {
    const elapsedTime = this.getElapsedTime();
    const avgChunkSize = this.data.chunkCount > 0 ? this.data.totalDataSize / this.data.chunkCount : 0;
    
    const stats: StreamStatistics = {
      totalDataSize: this.data.totalDataSize,
      chunkCount: this.data.chunkCount,
      elapsedTime: elapsedTime,
      avgChunkSize: avgChunkSize
    };
    return stats;
  }

  /**
   * 获取状态历史（用于调试）
   */
  getHistory(): StreamStateData[] {
    return [...this.history];
  }

  /**
   * 重置状态
   */
  reset(): void {
    this.data = createInitialState();
    this.history = [];
  }

  /**
   * 清理资源
   */
  dispose(): void {
    this.data = createInitialState();
    this.history = [];
  }
}

/**
 * 便捷状态查询类
 */
export class StreamStateQuery {
  private state: StreamState;

  constructor(state: StreamState) {
    this.state = state;
  }
  /**
   * 检查流是否正在处理中
   */
  isProcessing(): boolean {
    return !this.state.isCompleted() && !this.state.isErrorDispatched();
  }

  /**
   * 检查流是否处于空闲状态
   */
  isIdle(): boolean {
    return !this.isProcessing();
  }

  /**
   * 检查缓冲区是否有待处理数据
   */
  hasBufferedData(): boolean {
    return this.state.getBufferContent().length > 0 || 
           this.state.getData().eventDataLines.length > 0;
  }

  /**
   * 获取缓冲区大小（字节）
   */
  getBufferedSize(): number {
    return this.state.getBufferContent().length;
  }
}
