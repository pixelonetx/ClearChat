import webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { Prompt } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserHelper } from '../services/BrowserHelper';

const DOMAIN = 0x0000;
const TAG = 'WebViewBrowser';

// 加载超时时间（毫秒）
const LOADING_TIMEOUT_MS = 15000;
// 加载完成后等待页面渲染的延迟（毫秒）
const RENDER_DELAY_MS = 300;
// 加载进度条的宽高
const LOADING_PROGRESS_SIZE = 50;
// 加载进度文字的大小
const LOADING_TEXT_FONT_SIZE = 14;
// 加载进度文字的上边距
const LOADING_TEXT_MARGIN_TOP = 16;
// 加载进度条的 Z 层级
const LOADING_PROGRESS_Z_INDEX = 999;

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
  @State isLoading: boolean = true;  // 初始为加载状态
  @State loadProgress: number = 0;  // 加载进度
  // 简易历史栈（根据 onPageBegin 记录主框架 URL）
  private urlHistory: string[] = [];
  // 用于跟踪页面加载的初始标题
  private initialPageTitle: string = '浏览器';
  // 加载超时定时器
  private loadingTimeoutId: number = -1;

  aboutToAppear(): void {
    this.currentUrl = this.initialUrl?.trim() || '';
    this.isLoading = true;  // 初始就设置为加载状态
    if (this.initialTitle && this.initialTitle.trim().length > 0) {
      this.pageTitle = this.initialTitle;
      this.initialPageTitle = this.initialTitle;
    }
  }

  /**
   * 组件销毁时清理资源
   */
  aboutToDisappear(): void {
    this.clearLoadingTimeout();
  }

  private async openInSystemBrowser(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const success = await BrowserHelper.openUrl(ctx, this.currentUrl);
      if (!success) {
        Prompt.showToast({ message: '无法打开系统浏览器', duration: 2000 });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'openInSystemBrowser error: %{public}s', String(err));
      try {
        Prompt.showToast({ message: '打开失败', duration: 2000 });
      } catch (toastErr) {
        hilog.error(DOMAIN, TAG, 'showToast error: %{public}s', String(toastErr));
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
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'accessBackward not supported: %{public}s', String(err));
    }

    // 回退方案：若本地记录的历史可退，则使用 JS history.back()
    if (this.urlHistory.length > 1) {
      try {
        this.controller.runJavaScript('history.back()');
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'runJavaScript history.back error: %{public}s', String(err));
      }
      this.urlHistory.pop();
      this.canGoBack = this.urlHistory.length > 1;
      return;
    }

    // 无历史再退出预览页
    try {
      this.navPathStack?.pop();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pop navigation error: %{public}s', String(err));
    }
  }

  private refresh(): void {
    try {
      this.startLoading(this.currentUrl);
      if (this.currentUrl) {
        this.controller.loadUrl(this.currentUrl);
      } else {
        this.controller.runJavaScript('location.reload()');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'refresh error: %{public}s', String(err));
      this.isLoading = false;
    }
  }

  /**
   * 开始加载页面
   * @param url 要加载的 URL
   */
  private startLoading(url: string): void {
    this.isLoading = true;
    this.loadProgress = 0;
    this.pageTitle = '浏览器';
    this.initialPageTitle = '浏览器';
    
    // 清除旧的超时
    this.clearLoadingTimeout();
    
    // 设置新的超时
    this.loadingTimeoutId = setTimeout(() => {
      this.isLoading = false;
      this.loadingTimeoutId = -1;
    }, LOADING_TIMEOUT_MS);
  }

  /**
   * 清除加载超时定时器
   */
  private clearLoadingTimeout(): void {
    if (this.loadingTimeoutId !== -1) {
      clearTimeout(this.loadingTimeoutId);
      this.loadingTimeoutId = -1;
    }
  }

  /**
   * 完成加载
   */
  private finishLoading(): void {
    // 延迟一小段时间确保页面渲染完成
    setTimeout(() => {
      this.isLoading = false;
      this.clearLoadingTimeout();
    }, RENDER_DELAY_MS);
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // Web 内容（一直存在，用 visibility 控制）
        Web({ src: this.currentUrl, controller: this.controller })
          .javaScriptAccess(true)
          .zoomAccess(true)
          .onTitleReceive((event) => {
            const t: string = (event as TitleEvent).title;
            // 更新标题
            if (t && t.trim().length > 0) {
              this.pageTitle = t;
            }
          })
          .onPageBegin((event) => {
            const url: string = (event as PageBeginEvent).url;
            if (url) {
              this.currentUrl = url;
              this.startLoading(url);
              
              // 记录主框架导航历史
              const last = this.urlHistory.length > 0 ? this.urlHistory[this.urlHistory.length - 1] : '';
              if (url !== last) {
                this.urlHistory.push(url);
                this.canGoBack = this.urlHistory.length > 1;
              }
            }
          })
          .onProgressChange((event) => {
            // 监听加载进度
            this.loadProgress = event.newProgress;
            // 当进度达到 100% 时，隐藏加载进度条
            if (event.newProgress >= 100) {
              this.finishLoading();
            }
          })
          .onUrlLoadIntercept((_event) => {
            // 返回 false 表示不拦截，交由 WebView 默认处理
            return false;
          })
          .onPageEnd((_event) => {
            // 页面加载结束时不立即隐藏加载条
            // 而是等待 onProgressChange 事件中进度达到 100% 后再隐藏
            // 这样可以确保页面完全渲染后才显示
          })
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.common_background'))
          .visibility(this.isLoading ? Visibility.Hidden : Visibility.Visible)
        
        // 加载进度条（始终存在，通过 opacity 控制可见性）
        Column() {
          LoadingProgress()
            .color($r('app.color.text_color'))
            .width(LOADING_PROGRESS_SIZE)
            .height(LOADING_PROGRESS_SIZE)
          
          Text(`加载中... ${this.loadProgress}%`)
            .fontSize(LOADING_TEXT_FONT_SIZE)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: LOADING_TEXT_MARGIN_TOP })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.common_background'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .opacity(this.isLoading ? 1 : 0)  // 通过 opacity 控制可见性，始终存在
        .zIndex(LOADING_PROGRESS_Z_INDEX)  // 确保加载条在最上层
        .enabled(this.isLoading)  // 加载完成后禁用触摸事件
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.common_background'))
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
          this.initialPageTitle = title;
        }
      }

      // 首次加载
      if (this.currentUrl) {
        try {
          // 初始化历史栈
          this.urlHistory = [this.currentUrl];
          this.canGoBack = false;
          this.startLoading(this.currentUrl);
          this.controller.loadUrl(this.currentUrl);
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'initial loadUrl error: %{public}s', String(err));
          this.isLoading = false;
          this.clearLoadingTimeout();
        }
      }
    })
  }
}

