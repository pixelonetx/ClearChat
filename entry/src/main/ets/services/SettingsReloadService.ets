/**
 * SettingsReloadService.ets
 * 设置重载协调器
 *
 * 职责：
 * - 检测 settingsVersion 变化
 * - 协调设置重载流程（重试、去重）
 * - 提供 waitForLatestSettings() 等待机制
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SettingsReloadService';

/**
 * 重载操作回调接口
 * 由 Chat 页面实现，SettingsReloadService 通过回调驱动实际的数据加载
 */
export interface SettingsReloadCallbacks {
  loadSettings: () => Promise<void>;
  loadConversations: () => Promise<void>;
  loadChatHistory: () => Promise<void>;
  handleEmptyConversations: () => Promise<void>;
}

export class SettingsReloadService {
  private previousSettingsVersion: number = 0;
  private requestedSettingsVersion: number = 0;
  private pendingSettingsReload: Promise<void> | null = null;
  private callbacks: SettingsReloadCallbacks;

  constructor(callbacks: SettingsReloadCallbacks) {
    this.callbacks = callbacks;
  }

  /**
   * 初始化版本号
   */
  initialize(currentVersion: number): void {
    this.previousSettingsVersion = this.normalizeVersion(currentVersion);
    this.requestedSettingsVersion = this.previousSettingsVersion;
  }

  /**
   * 检查设置版本是否有变化，如果有则触发重载
   * @param currentVersion 当前 settingsVersion
   * @param isInitialized 应用是否已初始化
   * @returns 是否触发了重载
   */
  checkVersionChange(currentVersion: number, isInitialized: boolean): boolean {
    if (!isInitialized) {
      return false;
    }

    const normalized = this.normalizeVersion(currentVersion);
    if (normalized === this.previousSettingsVersion && !this.pendingSettingsReload) {
      return false;
    }

    hilog.info(DOMAIN, TAG, 'Detected settingsVersion change -> %{public}s', String(normalized));
    this.reload('settingsVersion change', normalized).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to refresh after settings change: %{public}s', String(error));
    });
    return true;
  }

  /**
   * 触发设置重载
   */
  async reload(reason: string = 'manual', targetVersion?: number): Promise<void> {
    const desiredVersion = targetVersion ?? this.previousSettingsVersion;
    this.requestedSettingsVersion = desiredVersion;

    if (!this.pendingSettingsReload) {
      this.pendingSettingsReload = this.performReload(reason);
    } else {
      hilog.warn(DOMAIN, TAG,
        'Reload already in progress, updated targetVersion=%{public}d, reason=%{public}s',
        this.requestedSettingsVersion, String(reason));
    }

    try {
      await this.pendingSettingsReload;
    } finally {
      // performReload 内部会清理 pendingSettingsReload
    }
  }

  /**
   * 等待最新设置加载完成
   * 在发送消息等操作前调用，确保设置是最新的
   */
  async waitForLatest(reason: string, currentVersion: number): Promise<void> {
    if (this.pendingSettingsReload) {
      hilog.debug(DOMAIN, TAG, 'Awaiting pending settings reload before %{public}s', String(reason));
      await this.pendingSettingsReload;
    }

    const normalized = this.normalizeVersion(currentVersion);
    if (normalized !== this.previousSettingsVersion) {
      hilog.info(DOMAIN, TAG,
        'Version mismatch during %{public}s, triggering reload to %{public}d', String(reason), normalized);
      await this.reload(reason, normalized);
    }
  }

  /**
   * 执行实际的设置重载（含重试循环）
   */
  private async performReload(initialReason: string): Promise<void> {
    let attempt = 0;
    try {
      while (true) {
        attempt += 1;
        const targetVersion = this.requestedSettingsVersion;
        hilog.info(DOMAIN, TAG,
          'Reload start [reason=%{public}s] attempt=%{public}d targetVersion=%{public}d',
          String(initialReason), attempt, targetVersion);

        await this.callbacks.loadSettings();
        await this.callbacks.loadConversations();
        await this.callbacks.handleEmptyConversations();
        await this.callbacks.loadChatHistory();

        this.previousSettingsVersion = targetVersion;
        this.logState('Reload completed');

        if (this.requestedSettingsVersion === targetVersion) {
          break;
        }

        hilog.debug(DOMAIN, TAG, 'Detected newer reload request during execution, repeating');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Reload failed: %{public}s', String(error));
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(String(error));
    } finally {
      this.pendingSettingsReload = null;
    }
  }

  /**
   * 标准化版本号
   */
  normalizeVersion(value: number): number {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    return 0;
  }

  /**
   * 记录版本状态日志
   */
  logState(prefix: string, currentVersion?: number): void {
    const current = currentVersion !== undefined ? this.normalizeVersion(currentVersion) : this.previousSettingsVersion;
    hilog.debug(DOMAIN, TAG, '%{public}s; currentVersion=%{public}d, previousVersion=%{public}d',
      String(prefix), current, this.previousSettingsVersion);
  }

  /**
   * 是否有进行中的重载
   */
  get isReloading(): boolean {
    return this.pendingSettingsReload !== null;
  }
}
