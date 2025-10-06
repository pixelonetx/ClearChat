import { promptAction } from '@kit.ArkUI';
import { AppSettings } from '../services/DataModels';
import { Conversation } from '../services/ConversationModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NativeDialogHelper } from '../components/NativeDialogHelper';
import { BrowserHelper } from '../services/BrowserHelper';
import common from '@ohos.app.ability.common';

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

  private databaseManager: DatabaseManager = DatabaseManager.getInstance();
  @State appSettings: AppSettings | null = null;

  build() {
    NavDestination() {
      Column() {
        // 设置列表
        Scroll() {
          Column() {
            // 模型设置
            this.SettingGroup('模型设置', [
              {
                title: '模型配置',
                subtitle: '配置 AI 模型和提供商',
                onClick: () => {
                  this.pathStack.pushPathByName("ModelSettings", null, false);
                }
              }
            ]);

            // 数据设置
            this.SettingGroup('数据设置', [
              {
                title: '清空聊天记录',
                subtitle: '删除所有对话数据',
                onClick: () => {
                  this.showClearDataDialog();
                },
                isDestructive: true
              }
            ]);

            // 帮助与支持
            this.SettingGroup('帮助与支持', [
              {
                title: '帮助文档',
                subtitle: '使用指南和常见问题',
                onClick: () => {
                  this.pathStack.pushPathByName("About", null, false);
                }
              }
            ]);

            // 关于
            this.SettingGroup('关于', [
              {
                title: '关于',
                subtitle: '应用信息和版本',
                onClick: () => {
                  this.pathStack.pushPathByName("About", null, false);
                }
              },
              {
                title: '意见反馈',
                subtitle: '帮助我们改进产品',
                onClick: () => {
                  this.openFeedbackUrl();
                }
              }
            ]);
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .padding({ left: 16, right: 16, top: 0, bottom: 32 });
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart);
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center);
    }
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    })
    .title('设置')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    });
  }

  @Builder
  SettingGroup(title: string, items: SettingItem[]) {
    Column() {
      // 分组标题
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 8, top: 16 });

      // 设置项列表
      Column() {
        ForEach(items, (item: SettingItem, index: number) => {
          this.SettingItem(item, index === items.length - 1);

          // 分割线（除了最后一项）
          if (index < items.length - 1) {
            Divider()
              .height(0.5)
              .margin({ left: 16 });
          }
        });
      }
      .borderRadius(8)
      .margin({ bottom: 8 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  SettingItem(item: SettingItem, isLast: boolean) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Normal)
          .width('100%')
          .textAlign(TextAlign.Start);

        if (item.subtitle) {
          Text(item.subtitle)
            .fontSize(13)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 2 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center);

      Text('›')
        .fontSize(20)
        .fontWeight(FontWeight.Normal);
    }
    .width('100%')
    .height(item.subtitle ? 56 : 44)
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      item.onClick?.();
    })
    .gesture(
      TapGesture().onAction(() => {
        // 轻微的触摸反馈（可后续添加 haptic 反馈）
      })
    );
  }

  private async showClearDataDialog() {
    NativeDialogHelper.showClearAllDataDialog(() => {
      this.clearAllData();
    });
  }

  private async clearAllData() {
    try {
      // 获取所有对话
      const conversations: Conversation[] = await this.databaseManager.getAllConversations();

      // 删除每个对话
      for (const conversation of conversations) {
        await this.databaseManager.deleteConversation(conversation.id);
      }

      // 清空默认对话的聊天记录
      await this.databaseManager.clearChatHistory();

      try {
        promptAction.showToast({ message: '数据已清空' });
      } catch (toastErr) {
        console.warn('Toast display failed (清空成功):', toastErr);
      }

    } catch (error) {
      console.error('Failed to clear data:', error);
      try {
        promptAction.showToast({ message: '清空失败' });
      } catch (toastErr) {
        console.warn('Toast display failed (清空失败):', toastErr);
      }
    }
  }

  private openFeedbackUrl() {
    const feedbackUrl = 'https://www.wjx.top/vm/P9ruqRM.aspx';

    AlertDialog.show({
      title: '打开外部链接',
      message: `即将在系统浏览器中打开意见反馈页面，是否继续？\n\n${feedbackUrl}`,
      primaryButton: {
        value: '取消',
        action: () => {
          console.log('用户取消打开链接');
        }
      },
      secondaryButton: {
        value: '打开',
        action: () => {
          this.openUrlInBrowser(feedbackUrl);
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
            promptAction.showToast({
              message: '无法打开浏览器',
              duration: 2000
            });
          } catch (toastErr) {
            console.warn('Toast display failed (无法打开浏览器):', toastErr);
          }
        }
      })
      .catch((error: Error) => {
        console.error('Failed to open URL:', error);
        try {
          promptAction.showToast({
            message: '打开链接失败',
            duration: 2000
          });
        } catch (toastErr) {
          console.warn('Toast display failed (打开链接失败):', toastErr);
        }
      });
  }
}

interface SettingItem {
  title: string;
  subtitle?: string;
  onClick?: () => void;
  isDestructive?: boolean;
}