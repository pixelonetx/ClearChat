import { promptAction, UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Prompt } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { BrowserHelper } from '../../services/BrowserHelper';
import { createLogger, LogDomain } from '../../common/Logger';

const logger = createLogger('LinkActionSheet', LogDomain.UI);

/**
 * 链接操作工具类
 * 使用原生 ActionSheet 显示链接操作选项
 */
export class LinkActionHelper {

  /**
   * 显示链接操作选项
   * @param uiContext UI上下文
   * @param url 链接地址
   * @param context UI能力上下文
   */
  static showLinkActionSheet(uiContext: UIContext, url: string, context: common.UIAbilityContext): void {
    if (!url) {
      Prompt.showToast({
        message: '无效的链接地址',
        duration: 2000
      });
      return;
    }
    // 使用 UIContext 的 getPromptAction().showActionMenu
    uiContext.getPromptAction().showActionMenu({
      title: `链接操作: ${url.length > 30 ? url.substring(0, 30) + '...' : url}`,
      buttons: [
        {
          text: '使用浏览器打开',
          color: $r('app.color.text_color')
        },
        {
          text: '复制链接',
          color: $r('app.color.text_color')
        }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      switch (result.index) {
        case 0:
          // 使用浏览器打开
          LinkActionHelper.openInBrowser(url, context);
          break;
        case 1:
          // 复制链接
          LinkActionHelper.copyLink(url);
          break;
      }
    }).catch(() => {
      // 简化错误处理，不使用类型注解
      logger.error('ActionSheet error occurred');
    });
  }

  /**
   * 使用浏览器打开链接
   * @param url 链接地址
   * @param context UI能力上下文
   */
  private static openInBrowser(url: string, context: common.UIAbilityContext): void {
    const normalizedUrl = BrowserHelper.normalizeUrl(url);

    BrowserHelper.openUrl(context, normalizedUrl).then((success: boolean) => {
      if (!success) {
        Prompt.showToast({
          message: '无法打开浏览器',
          duration: 2000
        });
      }
    }).catch(() => {
      // 简化错误处理
      logger.error('Failed to open browser');
      Prompt.showToast({
        message: '打开浏览器失败',
        duration: 2000
      });
    });
  }

  /**
   * 复制链接到剪贴板
   * @param url 链接地址
   */
  private static async copyLink(url: string): Promise<void> {
    try {
      // 使用最新的剪贴板 API
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      const systemPasteboard = pasteboard.getSystemPasteboard();

      await systemPasteboard.setData(pasteData);
      Prompt.showToast({
        message: '链接已复制到剪贴板',
        duration: 2000
      });
    } catch (error) {
      // 简化错误处理
      logger.error('Copy link exception: %{public}s', JSON.stringify(error));
      Prompt.showToast({
        message: '复制链接失败',
        duration: 2000
      });
    }
  }
}