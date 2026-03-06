import { pasteboard } from '@kit.BasicServicesKit';
import { createLogger, LogDomain } from '../../common/Logger';

const logger = createLogger('ClipboardManager', LogDomain.UI);

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

      logger.debug('Text copied to clipboard successfully');
      return true;
    } catch (error) {
      logger.error('Failed to copy text: %{public}s', String(error));
      return false;
    }
  }
}