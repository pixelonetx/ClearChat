import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import promptAction from '@ohos.promptAction';

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

      console.info('ClipboardManager: Text copied to clipboard successfully');
      return true;
    } catch (error) {
      console.error('ClipboardManager: Failed to copy text', error);
      return false;
    }
  }

  /**
   * 清空剪贴板
   */
  async clear(): Promise<boolean> {
    try {
      // 创建空的剪贴板数据
      const emptyData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, '');
      await this.systemPasteboard.setData(emptyData);

      console.info('ClipboardManager: Clipboard cleared successfully');
      return true;
    } catch (error) {
      console.error('ClipboardManager: Failed to clear clipboard', error);
      return false;
    }
  }
}
