// 跳转页面入口函数
@Builder
export function ModelSettingsBuilder() {
  ModelSettings();
}

@Entry
@Component
struct ModelSettings {
  pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {}
    .hideToolBar(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })

  }
}