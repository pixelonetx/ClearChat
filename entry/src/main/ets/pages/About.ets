// 跳转页面入口函数
@Builder
export function AboutBuilder() {
  About();
}

@Entry
@Component
struct About {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;

  build() {
    NavDestination() {
      Text('关于页')
    }
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    })
    .title('关于')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })

  }
}