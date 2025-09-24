// 跳转页面入口函数
@Builder
export function NavDestinationPageBuilder() {
  NavDestinationPage();
}

@Component
struct NavDestinationPage {
  pathStack: NavPathStack = new NavPathStack();

  build() {
    Navigation() {
    }
    .title('NavDestinationPage')
    .onAppear(() => {
      this.pathStack.pushPathByName("Index", null, false);
    })
    .hideNavBar(true)
    // .onReady((context: NavDestinationContext) => {
    //   this.pathStack = context.pathStack;
    // })
  }
}