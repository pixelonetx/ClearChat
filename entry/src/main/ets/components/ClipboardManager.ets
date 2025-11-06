import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ClipboardManager';

export class ClipboardManager {
  private static instance: ClipboardManager;
  private systemPasteboard: pasteboard.SystemPasteboard;

  private constructor() {
    this.systemPasteboard = pasteboard.getSystemPasteboard();
  }

  public static getInstance(): ClipboardManager {
    if (!ClipboardManager.instance) {
      ClipboardManager.instance = new ClipboardManager();
    }
    return ClipboardManager.instance;
  }

  /**
   * 复制文本到剪贴板（无需权限）
   */
  async copyText(text: string): Promise<boolean> {
    try {
      // 创建纯文本数据
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);

      // 写入剪贴板（无需权限）
      await this.systemPasteboard.setData(pasteData);

      hilog.info(DOMAIN, TAG, 'ClipboardManager: Text copied to clipboard successfully');
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'ClipboardManager: Failed to copy text: %{public}s', String(error));
      return false;
    }
  }
}