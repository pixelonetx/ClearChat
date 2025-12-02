import { Prompt } from '@kit.ArkUI';
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { AppSettings } from '../services/DataModels';
import { BrowserHelper } from '../services/BrowserHelper';
import { ClipboardManager } from '../components/ClipboardManager';
import { AboutSheetBuilder } from '../components/AboutSheet';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebBrowserParam } from '../components/WebViewBrowser';
import { ThemeMode, AppPreferences } from '../services/AppPreferences';
const DOMAIN = 0x0000;
const TAG = 'Settings';

// 跳转页面入口函数
@Builder
export function SettingsBuilder() {
  Settings();
}

@Entry
@Component
struct Settings {
  // 控制跳转的对象
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;

  @State appSettings: AppSettings | null = null;
  @State qqGroupNumber: string = '428701303';
  @State showAboutSheet: boolean = false;
  @State showThemeModeMenu: boolean = false;
  
  // 主题模式
  @StorageLink('themeMode') currentThemeMode: number = ThemeMode.AUTO;
  
  private uiContent: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    // 不需要额外初始化，AppStorage 已在 EntryAbility 中设置
  }

  /**
   * 处理主题模式选择
   */
  private handleThemeModeSelected(mode: ThemeMode): void {
    AppPreferences.setTheme(this.uiContent, mode);
    
    try {
      Prompt.showToast({
        message: `已切换到${AppPreferences.getDisplayName(mode)}`,
        duration: 2000
      });
    } catch (err) {
      
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 设置列表
        Scroll() {
          Column() {
            // 通用设置
            this.SettingGroup('通用设置', [
              {
                title: '主题模式',
                onClick: () => {
                  // 使用 bindMenu，点击事件留空
                }
              }
            ]);

            // 模型设置
            this.SettingGroup('模型设置', [
              {
                title: '模型提供方',
                onClick: () => {
                  this.pathStack.pushPathByName("ModelSettings", null);
                }
              },
              {
                title: '搜索服务',
                onClick: () => {
                  this.pathStack.pushPathByName("SearchServices", null);
                }
              }
            ]);

            // // 数据设置
            // this.SettingGroup('数据设置', [
            //   {
            //     title: '清空聊天记录',
            //     onClick: () => {
            //       this.showClearDataDialog();
            //     },
            //     isDestructive: true
            //   }
            // ]);

            // 帮助与支持
            this.SettingGroup('帮助与支持', [
              {
                title: '隐私政策',
                onClick: () => {
                  this.openUrl('https://legal.zkytx.xyz/');
                }
              }
            ]);

            // 关于
            this.SettingGroup('关于', [
              {
                title: '关于',
                onClick: () => {
                  this.showAboutSheet = true;
                }
              },
              {
                title: 'QQ交流群',
                onClick: () => {
                  this.copyToClipboard(this.qqGroupNumber);
                  startQQGroupAbility(this.uiContent, Number(this.qqGroupNumber));
                }
              },
              {
                title: '意见反馈',
                onClick: () => {
                  this.openUrl('https://www.wjx.top/vm/P9ruqRM.aspx');
                }
              }
            ]);
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .padding({ left: 16, right: 16})
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        .margin({ top: 12 });
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
    .backgroundColor($r('app.color.common_background'))
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
    })
    .title('设置')
    .bindSheet(
      $$this.showAboutSheet,
      AboutSheetBuilder,
      {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        dragBar: true,
      }
    )
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  @Builder
  SettingGroup(title: string, items: SettingItem[]) {
    Column() {
      // 分组标题
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 6, top: 8 })

      // 设置项列表
      Column() {
        ForEach(items, (item: SettingItem, index: number) => {
          this.SettingItem(item, index, items.length);

          // 分割线（除了最后一项）
          if (index < items.length - 1) {
            Divider()
              .height(1)
              .color(Color.Gray)
              // .margin({ left: 16, right: 16 })
          }
        })
      }
      .borderRadius(16)
      .clip(true)
      .margin({ bottom: 10 })
      .shadow({
        radius: 18,
        color: 'rgba(16, 24, 40, 0.08)',
        offsetX: 0,
        offsetY: 6
      });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 2, right: 2 });
  }

  @Builder
  SettingItem(item: SettingItem, index: number, total: number) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Normal)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start);
        
        // 显示副标题（如果有）
        if (item.subtitle) {
          Text(item.subtitle)
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 4 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding({ right: 12 })

      // 右侧区域：主题模式特殊处理
      if (item.title === '主题模式') {
        Row({ space: 8 }) {
          Text(AppPreferences.getDisplayName(this.currentThemeMode))
            .fontSize(14)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
        }
        .padding(12)
        .margin({ top: -10, bottom: -10 })
        .bindMenu([
          {
            value: AppPreferences.getDisplayName(ThemeMode.AUTO),
            action: () => {
              this.handleThemeModeSelected(ThemeMode.AUTO);
            }
          },
          {
            value: AppPreferences.getDisplayName(ThemeMode.LIGHT),
            action: () => {
              this.handleThemeModeSelected(ThemeMode.LIGHT);
            }
          },
          {
            value: AppPreferences.getDisplayName(ThemeMode.DARK),
            action: () => {
              this.handleThemeModeSelected(ThemeMode.DARK);
            }
          }
        ])
        .hitTestBehavior(HitTestMode.Default)
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .margin({ right: 12 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
    .borderRadius({
      topLeft: (index === 0) ? 12 : 0,
      topRight: (index === 0) ? 12 : 0,
      bottomLeft: (index === (total - 1)) ? 12 : 0,
      bottomRight: (index === (total - 1)) ? 12 : 0
    })
    .onClick(() => {
      // 主题模式项不执行 onClick，由 bindMenu 处理
      if (item.title !== '主题模式') {
        item.onClick?.();
      }
    })
  }

  // private async showClearDataDialog() {
  //   NativeDialogHelper.showClearAllDataDialog(() => {
  //     this.clearAllData();
  //   });
  // }

  // private async clearAllData() {
  //   try {
  //     // 清空所有对话及消息
  //     await this.databaseManager.clearAllConversations();
  //
  // // 递增刷新版本号，通知聊天页面重新加载
  // const currentVersion = AppStorage.get('conversationsReloadVersion') as number | undefined;
  // const nextVersion = (currentVersion ?? 0) + 1;
  // AppStorage.SetOrCreate('conversationsReloadVersion', nextVersion);
  //
  //     try {
  //       promptAction.showToast({ message: '数据已清空' });
  //     } catch (toastErr) {
  //       console.warn('Toast display failed (清空成功):', toastErr);
  //     }
  //
  //   } catch (error) {
  //     console.error('Failed to clear data:', error);
  //     try {
  //       promptAction.showToast({ message: '清空失败' });
  //     } catch (toastErr) {
  //       console.warn('Toast display failed (清空失败):', toastErr);
  //     }
  //   }
  // }

  private openUrl(url: string) {
    const useUrl = url;

    // 使用内置浏览器打开（使用显式类型参数，避免未声明对象字面量）
    try {
      const param: WebBrowserParam = { url: useUrl };
      this.pathStack.pushPathByName('WebBrowser', param);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Open internal browser failed: %{public}s', String(err));
      // 兜底：尝试系统浏览器
      this.openUrlInBrowser(useUrl);
    }
  }

  // 专用于不适配内置 WebView 的站点：弹窗提醒并用系统浏览器打开
  private openUrlExternalWithConfirm(url: string) {
    const useUrl = url;

    AlertDialog.show({
      title: '打开外部链接',
      message: `即将在系统浏览器中打开${useUrl}，是否继续？`,
      primaryButton: {
        value: '取消',
        action: () => {
          
        }
      },
      secondaryButton: {
        value: '打开',
        action: () => {
          this.openUrlInBrowser(useUrl);
        }
      }
    });
  }

  private openUrlInBrowser(url: string) {
    const context = getContext(this) as common.UIAbilityContext;

    BrowserHelper.openUrl(context, url)
      .then((success: boolean) => {
        if (!success) {
          try {
            Prompt.showToast({
              message: '无法打开浏览器',
              duration: 2000
            });
          } catch (toastErr) {
            hilog.warn(DOMAIN, TAG, 'Toast display failed (无法打开浏览器): %{public}s', String(toastErr));
          }
        }
      })
      .catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to open URL: %{public}s', String(error));
        try {
          Prompt.showToast({
            message: '打开链接失败',
            duration: 2000
          });
        } catch (toastErr) {
          hilog.warn(DOMAIN, TAG, 'Toast display failed (打开链接失败): %{public}s', String(toastErr));
        }
      });
  }

  private async copyToClipboard(text: string) {
    try {
      const success = await ClipboardManager.getInstance().copyText(text);
      try {
        Prompt.showToast({
          message: success ? 'QQ群号已复制到剪贴板' : '复制失败',
          duration: 2000
        });
      } catch (toastErr) {
        hilog.warn(DOMAIN, TAG, 'Toast display failed: %{public}s', String(toastErr));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to copy to clipboard: %{public}s', String(error));
      try {
        Prompt.showToast({
          message: '复制失败',
          duration: 2000
        });
      } catch (toastErr) {
        hilog.warn(DOMAIN, TAG, 'Toast display failed: %{public}s', String(toastErr));
      }
    }
  }
}

interface SettingItem {
  title: string;
  subtitle?: string;
  onClick?: () => void;
  isDestructive?: boolean;
}

export function startQQGroupAbility(context: common.UIAbilityContext, groupNum: number) {
  let openLinkOptions: OpenLinkOptions = {
    appLinkingOnly: false,
  };
  try {
    context.openLink('mqqapi://card/show_pslcard?src_type=internal&version=1&uin=' + groupNum +
      '&card_type=group&source=qrcode', openLinkOptions)
  } catch (paramError) {
  }
}
