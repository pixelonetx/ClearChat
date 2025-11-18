import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Prompt } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG = 'BrowserHelper';

/**
 * 浏览器启动工具类
 * 用于启动系统默认浏览器打开指定URL
 */
export class BrowserHelper {

  /**
   * 启动浏览器打开指定URL
   * @param context UI能力上下文
   * @param url 要打开的网址
   * @returns Promise<boolean> 是否成功启动
   */
  static async openUrl(context: common.UIAbilityContext, url: string): Promise<boolean> {
    try {
      const normalizedUrl = BrowserHelper.normalizeUrl(url);

      // 验证URL格式
      if (!normalizedUrl || !BrowserHelper.isValidUrl(normalizedUrl)) {
        try {
          Prompt.showToast({
            message: '无效的网址格式',
            duration: 2000
          });
        } catch (toastErr) {
          
        }
        return false;
      }

      // 根据HarmonyOS官方文档的推荐方式
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: normalizedUrl,
        parameters: {
          'ohos.ability.params.showDefaultPicker': true
        }
      };

      await context.startAbility(want);
      

      try {
        Prompt.showToast({
          message: '正在启动浏览器...',
          duration: 1500
        });
      } catch (toastErr) {
        
      }

      return true;

    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to start browser. Code: %{public}d, message: %{public}s', error.code, error.message);

      try {
        Prompt.showToast({
          message: '无法打开浏览器',
          duration: 2000
        });
      } catch (toastErr) {
        
      }

      return false;
    }
  }

  /**
   * 验证URL格式是否有效
   * @param url 要验证的URL
   * @returns boolean 是否为有效URL
   */
  static isValidUrl(url: string): boolean {
    if (!url || typeof url !== 'string') {
      return false;
    }

    const pattern = /^(https?:\/\/)([\w-]+(\.[\w-]+)+)(:[0-9]+)?(\/[^\s]*)?$/i;
    return pattern.test(url.trim());
  }

  /**
   * 规范化URL格式
   * 自动添加协议前缀
   * @param url 原始URL
   * @returns string 规范化后的URL
   */
  static normalizeUrl(url: string): string {
    if (!url || typeof url !== 'string') {
      return '';
    }

    // 移除首尾空格
    url = url.trim();

    // 如果已经有协议，直接返回
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    // 如果以www开头，添加https://
    if (url.startsWith('www.')) {
      return 'https://' + url;
    }

    // 其他情况默认添加https://
    return 'https://' + url;
  }

  /**
   * 从文本中提取URL链接
   * @param text 包含链接的文本
   * @returns string[] 提取到的URL数组
   */
  static extractUrls(text: string): string[] {
    if (!text || typeof text !== 'string') {
      return [];
    }

    // URL匹配正则表达式
    const urlRegex = /(https?:\/\/[^\s]+|www\.[^\s]+|[a-zA-Z0-9-]+\.[a-zA-Z]{2,}[^\s]*)/gi;
    const matches = text.match(urlRegex);

    if (!matches) {
      return [];
    }

    // 规范化提取到的URL
    return matches.map(url => BrowserHelper.normalizeUrl(url)).filter(url => BrowserHelper.isValidUrl(url));
  }
}

