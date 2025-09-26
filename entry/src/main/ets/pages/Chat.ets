
const uiContext: UIContext | undefined = AppStorage.get('uiContext');
let storage = uiContext?.getSharedLocalStorage();

// 跳转页面入口函数

@Builder
export function ChatBuilder() {
  Chat();
}


@Entry(storage)
@Component
struct Chat {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;


  build() {
    NavDestination() {
      SideBarContainer(SideBarContainerType.AUTO) {
        // 侧边栏内容
        Column() {
          Row() {
            Text(' ')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
              .textAlign(TextAlign.End)
              .margin({right:24})
            // Button() {
            //   Image($r('app.media.close_sidebar'))
            //     .size({width:24, height:24})
            // }
            // .type(ButtonType.Circle)
            // .size({width:48, height:48})
            // .onClick(()=>{})
          }
          .width('100%')
          .height(56)

          Row() {
            Button() {
              Text('新建对话')
                .fontSize(16)
                .fontColor($r('app.color.text_color'))
            }
            .buttonStyle(ButtonStyleMode.NORMAL)
            .width('90%')
            .height(48)
            .onClick(()=>{})
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({top:12, bottom:12})

          // 对话列表
          if(1) { //this.conversations.length === 0
            Column() {
              Text('还没有对话记录')
                .fontSize(14)
                .fontColor($r('app.color.text_color'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column()
                .width('100%')
                .padding({left:16, right:16})
                .alignItems(HorizontalAlign.Start)
                .justifyContent(FlexAlign.Start)
            }
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.TopStart)
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Off)
          }

          Column() {
            Divider()
            Button() {
              Row({space:8}) {
                Image($r('app.media.gearshape'))
                  .size({width:24, height:24})
                  .fillColor($r('app.color.text_color'))
                Text('设置')
                  .fontSize(14)
                  .fontColor($r('app.color.text_color'))
              }
            }
            .onClick(()=>{
              this.pathStack.pushPathByName("Settings", null);
            })
            .buttonStyle(ButtonStyleMode.NORMAL)
            .width('90%')
            .height(48)
          }
        }
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
        .width(300)
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({
          top: this.getUIContext().px2vp(this.topRectHeight),
          bottom: this.getUIContext().px2vp(this.bottomRectHeight)
        })

        // 主内容区
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
                    // Button() {
                    //   Image($r('app.media.close_sidebar'))
                    //     .size({ width: 24, height: 24 })
                    // }
                    // .type(ButtonType.Circle)
                    // .size({ width: 48, height: 48 }) // 点击热区
                    // .backgroundColor(Color.White)
                    // .onClick(() => {
                    // }) //展示侧栏

                    Text('AI')
                      .fontSize(18)
                      .fontColor($r('app.color.text_color'))
                      .fontWeight(FontWeight.Medium)
                      .layoutWeight(1)
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ left: 8, right: 8 })

                    Button() {
                      Image($r('app.media.chat_new_line'))
                        .size({ width: 24, height: 24 })
                        .fillColor($r('app.color.text_color'))
                    }
                    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                    .type(ButtonType.Circle)
                    .size({ width: 48, height: 48 })
                    .margin({ right: 8 })
                    .onClick(() => {
                    })

                    Button() {
                      Image($r('app.media.more_fill'))
                        .size({ width: 24, height: 24 })
                        .fillColor($r('app.color.text_color'))
                    }
                    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                    .type(ButtonType.Circle)
                    .size({ width: 48, height: 48 })
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
                        .fontColor($r('app.color.text_color'))
                      if (1) { //!this.hasSettings
                        Button('配置API设置')
                          .fontColor($r('app.color.text_color'))
                          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                          .type(ButtonType.Capsule)
                          .margin({ top: 10 })
                          .buttonStyle(ButtonStyleMode.NORMAL)
                          .onClick(() => {
                            this.pathStack.pushPathByName("ModelSettings", null);
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
                      .fontColor($r('app.color.text_color'))
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
                          .fillColor($r('app.color.text_color'))
                      }
                    }
                    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                    .type(ButtonType.Circle)
                    .size({ width: 40, height: 40 })
                    .margin({ left: 6 })

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
        .padding({
          top: this.getUIContext().px2vp(this.topRectHeight),
          bottom: this.getUIContext().px2vp(this.bottomRectHeight)
        })
      }
      .controlButton({
        left:24,
        top:this.getUIContext().px2vp(this.topRectHeight)+16,
        width:24,
        height:24,
        icons: {
          hidden: $r('sys.symbol.close_sidebar'),
          shown: $r('sys.symbol.open_sidebar'),
          // switching: $r('sys.symbol.close_sidebar')
        }
      })
      .showSideBar(false)
      // .minSideBarWidth(50)
      // .maxSideBarWidth(300)
      // .minContentWidth(0)
      .onChange((value: boolean) => {})
      // .divider({
      //   strokeWidth: '1vp',
      //   color: Color.Gray,
      //   startMargin: '4vp',
      //   endMargin: '4vp'
      // })
    }
    .hideToolBar(true)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })

    }
  }