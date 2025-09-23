// 跳转页面入口函数
@Builder
export function NavDestinationPageBuilder() {
  NavDestinationPage();
}

@Component
struct NavDestinationPage {
  pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
    }
    .title('NavDestinationPage')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}