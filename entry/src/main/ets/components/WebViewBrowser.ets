import webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserHelper } from '../services/BrowserHelper';

const DOMAIN = 0x0000;
const TAG = 'WebViewBrowser';

// 内置浏览器路由参数类型
export interface WebBrowserParam {
  url: string;
  title?: string;
}

// Web事件类型定义
interface TitleEvent {
  title: string;
}

interface PageBeginEvent {
  url: string;
}

// Web控制器扩展接口
interface WebControllerExtensions {
  accessBackward: () => boolean;
  backward: () => void;
}

// 跳转页面入口函数（系统路由表场景下，参数通过 onReady 获取）
@Builder
export function WebViewBrowserBuilder() {
  WebViewBrowser({ initialUrl: '', initialTitle: '' });
}

interface WebViewBrowserProps {
  initialUrl: string;
  initialTitle?: string;
}

@Component
export struct WebViewBrowser {
  // 接收参数
  initialUrl: string = '';
  initialTitle?: string;
  // 导航栈（用于无法后退时返回上一页），在 onReady 中从上下文获取
  private navPathStack?: NavPathStack;
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;
  // Web 控制器
  private controller: webview.WebviewController = new webview.WebviewController();
  // UI 状态
  @State currentUrl: string = '';
  @State pageTitle: string = '浏览器';
  @State canGoBack: boolean = false;
  // 简易历史栈（根据 onPageBegin 记录主框架 URL）
  private urlHistory: string[] = [];

  aboutToAppear(): void {
    this.currentUrl = this.initialUrl?.trim() || '';
    if (this.initialTitle && this.initialTitle.trim().length > 0) {
      this.pageTitle = this.initialTitle;
    }
  }

  private async openInSystemBrowser(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const success = await BrowserHelper.openUrl(ctx, this.currentUrl);
      if (!success) {
        promptAction.showToast({ message: '无法打开系统浏览器', duration: 2000 });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'openInSystemBrowser error: %{public}s', String(err));
      try {
        promptAction.showToast({ message: '打开失败', duration: 2000 });
      } catch {
      }
    }
  }

  private async goBackOrPop(): Promise<void> {
    // 优先使用 ArkWeb 控制器的后退能力；仅当不可后退时退出预览页
    try {
      // accessBackward() 返回是否可后退一页
      const extendedController = this.controller as WebControllerExtensions;
      if (extendedController.accessBackward && extendedController.accessBackward()) {
        if (extendedController.backward) {
          extendedController.backward();
        }
        return;
      }
    } catch (_) {
      // 忽略，进入回退方案
    }

    // 回退方案：若本地记录的历史可退，则使用 JS history.back()
    if (this.urlHistory.length > 1) {
      try {
        this.controller.runJavaScript('history.back()');
      } catch (_) {
      }
      this.urlHistory.pop();
      this.canGoBack = this.urlHistory.length > 1;
      return;
    }

    // 无历史再退出预览页
    try {
      this.navPathStack?.pop();
    } catch (_) {
    }
  }

  private refresh(): void {
    try {
      if (this.currentUrl) {
        this.controller.loadUrl(this.currentUrl);
      } else {
        this.controller.runJavaScript('location.reload()');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'refresh error: %{public}s', String(err));
    }
  }

  build() {
    NavDestination() {
      Column() {
        // Web 内容
        Web({ src: this.currentUrl, controller: this.controller })
          .javaScriptAccess(true)
          .zoomAccess(true)
          .onTitleReceive((event) => {
            const t: string = (event as TitleEvent).title;
            if (t && t.trim().length > 0) {
              this.pageTitle = t;
            }
          })
          .onPageBegin((event) => {
            const url: string = (event as PageBeginEvent).url;
            if (url) {
              this.currentUrl = url;
              // 记录主框架导航历史
              const last = this.urlHistory.length > 0 ? this.urlHistory[this.urlHistory.length - 1] : '';
              if (url !== last) {
                this.urlHistory.push(url);
                this.canGoBack = this.urlHistory.length > 1;
              }
            }
          })
          .onUrlLoadIntercept((_event) => {
            // 返回 false 表示不拦截，交由 WebView 默认处理
            return false;
          })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title(this.pageTitle || '浏览器')
    .menus([
      {
        value: '返回', icon: $r('app.media.arrow_go_back_line'), action: () => {
        this.goBackOrPop();
      }
      },
      {
        value: '刷新', icon: $r('app.media.arrow_clockwise'), action: () => {
        this.refresh();
      }
      },
      {
        value: '外部', icon: $r('app.media.worldclock'), action: () => {
        this.openInSystemBrowser();
      }
      }
    ])
    .hideTitleBar(false)
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight)
    })
    .backgroundColor($r('app.color.common_background'))
    .onBackPressed(() => {
      this.goBackOrPop();
      return true;
    })
    .onReady((ctx: NavDestinationContext) => {
      // 保存导航栈
      this.navPathStack = ctx.pathStack;
      // 通过路由参数初始化
      const p = ctx.pathInfo?.param as WebBrowserParam | string | undefined;
      if (typeof p === 'string' && p) {
        this.currentUrl = p;
      } else if (p && typeof p === 'object') {
        const url = p.url ?? '';
        const title = p.title ?? '';
        if (url && url.trim().length > 0) {
          this.currentUrl = url;
        }
        if (title && title.trim().length > 0) {
          this.pageTitle = title;
        }
      }

      // 首次加载
      if (this.currentUrl) {
        try {
          // 初始化历史栈
          this.urlHistory = [this.currentUrl];
          this.canGoBack = false;
          this.controller.loadUrl(this.currentUrl);
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'initial loadUrl error: %{public}s', String(err));
        }
      }
    })
  }
}

