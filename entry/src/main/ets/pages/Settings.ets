// 主设置页面

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

  private routes: Route[] = [
    {
      title: '通用设置',
      child: [
        { text: '主题模式', to: '' },
        { text: '字体大小', to: 'RudderStyleTab' }
      ]
    },
    {
      title: '模型设置',
      child: [
        { text: '模型提供方', to: 'ModelSettings' },
        { text: '联网搜索', to: 'UnderlineTab' }
      ]
    }
  ];

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            ForEach(this.routes, (item: Route) => {
              // 外层卡片
              Column() {
                // 标题
                Text(item.title)
                  .width('100%')
                  .fontSize("14fp")
                  .fontColor($r('sys.color.font_secondary'))
                  .padding({ left: 16, top: 18, right: 0, bottom: 8 })

                // 设置项列表
                ForEach(item.child, (itemChild: ChildRoute, index: number) => {
                  // 列表项
                  Row() {
                    Text(itemChild.text)
                      .fontColor($r('sys.color.font_primary'))
                      .fontWeight(FontWeight.Medium)
                      .fontSize("15fp")
                      .width('auto')
                      .height(48)
                      .textAlign(TextAlign.Start)

                    // 右侧箭头
                    if (itemChild.text !== '') {
                      SymbolGlyph($r('sys.symbol.chevron_forward'))
                        .fontSize("16fp")
                        .fontColor([$r('sys.color.icon_tertiary')])
                    }
                  }
                  .width('100%')
                  .height(48)
                  .justifyContent(FlexAlign.SpaceBetween)
                  .padding({ left: 16, right: 16 })
                  .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
                  .borderRadius(12)
                  .borderWidth({ bottom: index === item.child.length - 1 ? 0 : 0.5 })
                  .borderColor($r('sys.color.comp_divider'))
                  .onClick(() => {
                    if (itemChild.text === '' && itemChild.to === '') {
                      return;
                    }
                    this.pathStack.pushPathByName(itemChild.to, null);
                  })
                }, (item: ChildRoute, index: number) => JSON.stringify(item) + index)
              }
            }, (item: Route, index: number) => JSON.stringify(item) + index)
          }
          .width('100%')
        }
        .padding({
          left: 20,
          right: 20
        })
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .padding({
        right: 8,
        left: 8
      })
      .alignItems(HorizontalAlign.Center)

    }
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    })
    .title('设置')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}

interface ChildRoute {
  text: string;
  to: string;
}

interface Route {
  title: string;
  child: Array<ChildRoute>;
}
