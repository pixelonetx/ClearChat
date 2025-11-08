/**
 * StreamEventEmitter.ets
 * 
 * ✅ 事件驱动架构 - 替代回调地狱
 * 
 * 优势：
 * 1. 事件驱动 - 解耦事件发送者和监听者
 * 2. 类型安全 - TypeScript 类型支持
 * 3. 易于扩展 - 添加新事件无需修改现有代码
 * 4. 易于测试 - 独立的事件单元
 */

export enum StreamEventType {
  // 数据事件
  DATA = 'data',
  
  // 元数据事件
  METADATA = 'metadata',
  
  // 完成事件
  COMPLETE = 'complete',
  
  // 错误事件
  ERROR = 'error',
  
  // 警告事件（非致命错误）
  WARNING = 'warning',
  
  // 状态变化事件
  STATE_CHANGED = 'stateChanged',
  
  // 进度事件
  PROGRESS = 'progress'
}

// 进度数据接口
export interface ProgressData {
  received: number;
  total?: number;
}

export interface StreamStateSnapshot {
  metadataDispatched: boolean;
  completed: boolean;
  errorDispatched: boolean;
  reasoningStarted: boolean;
  userAborted: boolean;
  bufferedDataSize: number;
}

// 统一的事件载荷类型
export type EventPayload = string | import('../services/DataModels').StreamMetadata | Error | StreamStateSnapshot | ProgressData | void;

export type StreamEventListener = (payload: EventPayload) => void;

/**
 * 类型安全的事件发射器
 */
export class StreamEventEmitter {
  private listeners: Map<string, Set<StreamEventListener>> = new Map();
  private once_listeners: Map<string, Set<StreamEventListener>> = new Map();

  /**
   * 添加事件监听器
   */
  on(eventType: StreamEventType, listener: StreamEventListener): void {
    const key = eventType as string;
    if (!this.listeners.has(key)) {
      this.listeners.set(key, new Set());
    }
    this.listeners.get(key)!.add(listener);
  }

  /**
   * 添加一次性事件监听器
   */
  once(eventType: StreamEventType, listener: StreamEventListener): void {
    const key = eventType as string;
    if (!this.once_listeners.has(key)) {
      this.once_listeners.set(key, new Set());
    }
    this.once_listeners.get(key)!.add(listener);
  }

  /**
   * 移除事件监听器
   */
  off(eventType: StreamEventType, listener: StreamEventListener): void {
    const key = eventType as string;
    const listeners = this.listeners.get(key);
    if (listeners) {
      listeners.delete(listener);
    }
    
    const onceListeners = this.once_listeners.get(key);
    if (onceListeners) {
      onceListeners.delete(listener);
    }
  }

  /**
   * 发射事件
   */
  emit(eventType: StreamEventType, payload: EventPayload): void {
    const key = eventType as string;
    
    // 发送常规监听器的事件
    const listeners = this.listeners.get(key);
    if (listeners) {
      listeners.forEach(listener => {
        try {
          listener(payload);
        } catch (error) {
          // 避免一个监听器的错误影响其他监听器
          console.error(`Error in listener for ${eventType}:`, error);
        }
      });
    }

    // 发送一次性监听器的事件，并移除
    const onceListeners = this.once_listeners.get(key);
    if (onceListeners) {
      const listenersArray: StreamEventListener[] = [];
      onceListeners.forEach(listener => {
        listenersArray.push(listener);
      });
      
      listenersArray.forEach(listener => {
        try {
          listener(payload);
        } catch (error) {
          console.error(`Error in once listener for ${eventType}:`, error);
        }
      });
      this.once_listeners.delete(key);
    }
  }

  /**
   * 获取特定事件的监听器数量
   */
  getListenerCount(eventType: StreamEventType): number {
    let count = 0;
    const listeners = this.listeners.get(eventType);
    if (listeners) {
      count += listeners.size;
    }
    const onceListeners = this.once_listeners.get(eventType);
    if (onceListeners) {
      count += onceListeners.size;
    }
    return count;
  }

  /**
   * 移除所有事件监听器
   */
  removeAllListeners(): void {
    this.listeners.clear();
    this.once_listeners.clear();
  }

  /**
   * 清理资源
   */
  dispose(): void {
    this.removeAllListeners();
  }
}

/**
 * Promise 包装器 - 将事件转化为 Promise
 * 
 * 使用场景：需要 async/await 风格处理
 */
export class StreamEventPromise {
  private emitter: StreamEventEmitter;

  constructor(emitter: StreamEventEmitter) {
    this.emitter = emitter;
  }

  /**
   * 等待特定事件
   */
  waitFor(eventType: StreamEventType): Promise<EventPayload> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.emitter.off(eventType, listener);
        reject(new Error(`Event ${eventType} timeout`));
      }, 60000); // 60 秒超时

      const listener: StreamEventListener = (payload: EventPayload) => {
        clearTimeout(timeout);
        this.emitter.off(eventType, listener);
        resolve(payload);
      };

      this.emitter.once(eventType, listener);
    });
  }

  /**
   * 等待完成或错误
   */
  waitForCompletion(): Promise<void> {
    return new Promise((resolve, reject) => {
      const onComplete: StreamEventListener = () => {
        this.emitter.off(StreamEventType.COMPLETE, onComplete);
        this.emitter.off(StreamEventType.ERROR, onError);
        resolve();
      };

      const onError: StreamEventListener = (payload: EventPayload) => {
        this.emitter.off(StreamEventType.COMPLETE, onComplete);
        this.emitter.off(StreamEventType.ERROR, onError);
        reject(payload as Error);
      };

      this.emitter.once(StreamEventType.COMPLETE, onComplete);
      this.emitter.once(StreamEventType.ERROR, onError);
    });
  }

  /**
   * 收集所有数据块
   */
  async collectAllData(): Promise<string> {
    return new Promise((resolve, reject) => {
      let allData = '';

      const onData: StreamEventListener = (payload: EventPayload) => {
        allData += payload as string;
      };

      const onComplete: StreamEventListener = () => {
        this.emitter.off(StreamEventType.DATA, onData);
        this.emitter.off(StreamEventType.ERROR, onError);
        resolve(allData);
      };

      const onError: StreamEventListener = (payload: EventPayload) => {
        this.emitter.off(StreamEventType.DATA, onData);
        this.emitter.off(StreamEventType.COMPLETE, onComplete);
        reject(payload as Error);
      };

      this.emitter.on(StreamEventType.DATA, onData);
      this.emitter.once(StreamEventType.COMPLETE, onComplete);
      this.emitter.once(StreamEventType.ERROR, onError);
    });
  }
}
