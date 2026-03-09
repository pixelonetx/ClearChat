/**
 * Preference 页面 - 偏好设置
 *
 * 管理用户偏好设置：
 * - 自动展开思考过程
 */
import { common } from '@kit.AbilityKit';
import { AppPreferences } from '../services/AppPreferences';

@Builder
export function PreferenceBuilder() {
  Preference();
}

@Component
struct Preference {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;

  // 偏好状态
  @StorageLink('autoExpandThinking') autoExpandThinking: boolean = true;

  private uiContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // 聊天设置分组
            this.SettingGroup('聊天', [
              {
                title: '自动展开思考过程',
                description: '开启后，AI 的思考过程将自动展开显示',
                type: 'toggle',
                isOn: this.autoExpandThinking,
                onChange: (value: boolean) => {
                  AppPreferences.setAutoExpandThinking(this.uiContext, value);
                }
              }
            ]);
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        .margin({ top: 12 })
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
    .title('偏好')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  @Builder
  SettingGroup(title: string, items: PreferenceItem[]) {
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
        ForEach(items, (item: PreferenceItem, index: number) => {
          this.PreferenceItemView(item, index, items.length);

          if (index < items.length - 1) {
            Divider()
              .height(1)
              .color(Color.Gray)
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
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 2, right: 2 })
  }

  @Builder
  PreferenceItemView(item: PreferenceItem, index: number, total: number) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Normal)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)

        if (item.description) {
          Text(item.description)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding({ right: 12 })

      if (item.type === 'toggle') {
        Toggle({ type: ToggleType.Switch, isOn: item.isOn ?? false })
          .onChange((isOn: boolean) => {
            item.onChange?.(isOn);
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
    .borderRadius({
      topLeft: (index === 0) ? 12 : 0,
      topRight: (index === 0) ? 12 : 0,
      bottomLeft: (index === (total - 1)) ? 12 : 0,
      bottomRight: (index === (total - 1)) ? 12 : 0
    })
  }
}

interface PreferenceItem {
  title: string;
  description?: string;
  type: 'toggle';
  isOn?: boolean;
  onChange?: (value: boolean) => void;
}
