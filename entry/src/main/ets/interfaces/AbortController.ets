// 简单的AbortController类实现，用于ArkTS兼容性
export class AbortSignal {
  private listeners: (() => void)[] = [];

  addEventListener(type: string, listener: () => void): void {
    if (type === 'abort') {
      this.listeners.push(listener);
    }
  }

  // 触发所有监听器
  triggerAbort(): void {
    this.listeners.forEach(listener => listener());
  }
}

export class AbortController {
  signal: AbortSignal;
  private aborted: boolean = false;

  constructor() {
    this.signal = new AbortSignal();
  }

  abort(): void {
    if (!this.aborted) {
      this.aborted = true;
      this.signal.triggerAbort();
    }
  }
}

// 创建AbortController的工厂函数
export function createAbortController(): AbortController {
  return new AbortController();
}