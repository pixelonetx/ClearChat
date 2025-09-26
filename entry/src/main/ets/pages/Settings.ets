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

  @Builder itemHead(text: string) {
    Text(text)
      .width('100%')
      .fontSize(12)
      .margin({left: 8, bottom:8})
  }

  build() {
    NavDestination() {
      List({space:16}) {
        ListItemGroup({header:this.itemHead('通用设置')}) {
          ListItem({ style: ListItemStyle.CARD }) {
            Row({space:8}) {
              Image($r('app.media.clock'))
                .size({width:24, height:24})
                .fillColor($r('app.color.text_color'))
              Text('主题模式').fontColor($r('app.color.text_color'))
            }.width('100%')
          }
          ListItem({ style: ListItemStyle.CARD }) {
            Row({space:8}) {
              Image($r('app.media.info_circle'))
                .size({width:24, height:24})
                .fillColor($r('app.color.text_color'))
              Text('字体大小').fontColor($r('app.color.text_color'))
            }.width('100%')
          }
        }
        .margin({left:16, right:16, top:16})
        .divider({strokeWidth:1, startMargin:10, endMargin:10,color:Color.Gray})

        ListItemGroup({header:this.itemHead('模型服务方')}) {
          ListItem({ style: ListItemStyle.CARD }) {
            Row({space:8}) {
              Image($r('app.media.square_grid_2x2'))
                .size({width:24, height:24})
                .fillColor($r('app.color.text_color'))
              Text('模型设置').fontColor($r('app.color.text_color'))
            }.width('100%')
          }
          .onClick(()=>{
            this.pathStack.pushPathByName("ModelSettings", null);
          })
          ListItem({ style: ListItemStyle.CARD }) {
            Row({space:8}) {
              Image($r('app.media.wifi'))
                .size({width:24, height:24})
                .fillColor($r('app.color.text_color'))
              Text('联网搜索').fontColor($r('app.color.text_color'))
            }.width('100%')
          }
        }
        .margin({left:16, right:16})
        .divider({strokeWidth:1, startMargin:10, endMargin:10,color:Color.Gray})

        ListItemGroup({header:this.itemHead('关于')}) {
          ListItem({ style: ListItemStyle.CARD }) {
            Row({space:8}) {
              Image($r('app.media.square_and_pencil'))
                .size({width:24, height:24})
                .fillColor($r('app.color.text_color'))
              Text('意见反馈').fontColor($r('app.color.text_color'))
            }.width('100%')
          }
          ListItem({ style: ListItemStyle.CARD }) {
            Row({space:8}) {
              Image($r('app.media.info_circle'))
                .size({width:24, height:24})
                .fillColor($r('app.color.text_color'))
              Text('关于').fontColor($r('app.color.text_color'))
            }.width('100%')
          }
          .onClick(()=>{
            this.pathStack.pushPathByName("About", null);
          })
        }
        .margin({left:16, right:16})
        .divider({strokeWidth:1, startMargin:10, endMargin:10,color:Color.Gray})
      }


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
