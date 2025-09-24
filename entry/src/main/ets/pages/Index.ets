@Entry
@Component
struct Index {
  pathStack : NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pathStack){
    }.onAppear(() => {
      this.pathStack.pushPathByName("Chat", null, false);
    })
    .hideNavBar(true)
  }
}