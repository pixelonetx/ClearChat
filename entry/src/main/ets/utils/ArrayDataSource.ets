// 轻量数组数据源，适配 ArkUI 的 LazyForEach 所需的 IDataSource 接口
// 仅使用 onDataReload 通知整体刷新，避免复杂的增删改事件维护

export interface DataChangeListener {
  onDataAdd?(index: number): void;
  onDataDelete?(index: number): void;
  onDataChange?(index: number): void;
  onDataReload?(): void;
}

export class ArrayDataSource<T> /* implements IDataSource */ {
  private data: T[];
  private listeners: Set<DataChangeListener> = new Set();
  private _totalCount: number = 0; // 缓存数组长度

  constructor(dataRef: T[]) {
    this.data = dataRef;
    this._totalCount = dataRef.length;
  }

  // 如果外部替换了数组引用，可调用该方法更新数据引用
  setDataRef(nextRef: T[]) {
    this.data = nextRef;
    this._totalCount = nextRef.length;
    this.notifyReload();
  }

  totalCount(): number {
    // 使用缓存的长度，避免频繁访问数组length属性
    return this._totalCount;
  }

  getData(index: number): T {
    // 添加边界检查以提升安全性
    if (index < 0 || index >= this._totalCount) {
      throw new Error(`Index ${index} out of bounds for array of length ${this._totalCount}`);
    }
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!listener) {
      return;
    }
    this.listeners.add(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    if (!listener) {
      return;
    }
    this.listeners.delete(listener);
  }

  // 对外提供的刷新通知
  notifyReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReload?.();
    });
  }
}