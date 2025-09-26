// 跳转页面入口函数
@Builder
export function ModelSettingsBuilder() {
  ModelSettings();
}

@Entry
@Component
struct ModelSettings {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;

  build() {
    NavDestination() {
      Tabs() {
        TabContent() {}
        .tabBar('OpenAI')
      }
    }
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    })
    .title('模型设置')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })

  }
}