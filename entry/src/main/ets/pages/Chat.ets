// 跳转页面入口函数
@Builder
export function ChatBuilder() {
  Chat();
}

@Entry
@Component
struct Chat {
  pathStack: NavPathStack = new NavPathStack();
  @State isInitialized: boolean = false;

  build() {
    NavDestination() {
      Column() {
        Stack() {
          Column() {
            if (0) { //!this.isInitialized
              Column() {
                LoadingProgress()
                  .color(Color.Blue)
                  .size({ width: 48, height: 48 })
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .height('100%')

            } else {
              // 主界面
              Column() {
                // 标题栏
                Row() {
                  Button() {
                    Image($r('app.media.close_sidebar'))
                      .size({ width: 24, height: 24 })
                  }
                  .type(ButtonType.Circle)
                  .size({ width: 48, height: 48 }) // 点击热区
                  .backgroundColor(Color.White)
                  .onClick(() => {
                  }) //展示侧栏

                  Text('AI')
                    .fontSize(18)
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 8, right: 8 })

                  Button() {
                    Image($r('app.media.chat_new_line'))
                      .size({ width: 24, height: 24 })
                  }
                  .type(ButtonType.Circle)
                  .size({ width: 48, height: 48 })
                  .margin({ right: 8 })
                  .backgroundColor(Color.White)
                  .onClick(() => {
                  })

                  Button() {
                    Image($r('app.media.more_fill'))
                      .size({ width: 24, height: 24 })
                  }
                  .type(ButtonType.Circle)
                  .size({ width: 48, height: 48 })
                  .backgroundColor(Color.White)
                  .onClick(() => {
                  })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })

                // 消息列表
                if (1) {
                  // 空状态
                  Column() {
                    Text('有什么可以帮忙的？')
                      .fontSize(18)
                    if (1) { //!this.hasSettings
                      Button('配置API设置')
                        .type(ButtonType.Capsule)
                        .margin({ top: 10 })
                        .buttonStyle(ButtonStyleMode.NORMAL)
                        .onClick(() => {
                          console.log('跳转触发');
                          this.pathStack.pushPathByName("Settings", null);
                        })
                    }
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                } else {
                  // 消息列表
                  Scroll() {
                    Column() {
                      //ForEach()
                    }
                    .padding({
                      left: 12,
                      right: 12,
                      top: 16,
                      bottom: 16
                    })
                    .width('100%')
                    .alignItems(HorizontalAlign.Center)
                    .justifyContent(FlexAlign.Center)
                  }
                  .layoutWeight(1)
                  .scrollable(ScrollDirection.Vertical)
                  .scrollBar(BarState.Off)
                  .width('100%')
                  .height('100%')
                  .align(Alignment.TopStart)
                  .onClick(() => {
                  }) //点击消息列表区域时隐藏键盘
                }

                // 输入区域
                Row() {
                  TextArea({ placeholder: '输入你的消息' }) //, text: this.inputText
                    .layoutWeight(1)
                    .borderRadius(20)
                    .border({ width: 1, color: Color.Gray })
                    .padding({ left: 16, right: 16 })
                    .onChange(() => {
                    })
                  Button() {
                    if (0) { //this.isLoading
                      LoadingProgress()
                        .size({ width: 24, height: 24 })
                        .color(Color.Red)
                    } else {
                      Image($r('app.media.send_plane_line'))
                        .size({ width: 24, height: 24 })
                    }
                  }
                  .type(ButtonType.Circle)
                  .size({ width: 40, height: 40 })
                  .margin({ left: 6 })
                  .backgroundColor(Color.White)

                  // .enabled()
                  // .onClick()
                }
                .width('100%')
                .padding({ left: 12, right: 12 })
                .alignItems(VerticalAlign.Bottom) //发送按钮置底
              }
              .width('100%')
              .height('100%')

            }
          }
        }
      }
      .width('100%')
      .height('100%')
      .flexGrow(1) // 动态填充
    }
    .hideToolBar(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}