

@CustomDialog
export struct OpenLinkDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: null,
    autoCancel: true
  });

  url: string = '';
  onConfirm?: () => void;
  onCancel?: () => void;

  build() {
    Column() {
      // 标题
      Text('打开外部链接')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 20 })

      // 消息内容
      Column() {
        Text('即将在系统浏览器中打开以下链接：')
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .lineHeight(22)
          .margin({ bottom: 12 })

        Text(this.url)
          .fontSize(13)
          .textAlign(TextAlign.Center)
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .margin({ bottom: 24 })

      // 按钮组
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .borderRadius(8)
          .onClick(() => {
            this.controller.close();
            this.onCancel?.();
          })

        Button('打开')
          .layoutWeight(1)
          .height(40)
          .fontColor(Color.White)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .borderRadius(8)
          .onClick(() => {
            this.controller.close();
            this.onConfirm?.();
          })
      }
      .width('100%')
    }
    .width(280) // 固定宽度，不占满屏幕
    .padding(20) // 减少内边距
    .borderRadius(16)
    .shadow({
      radius: 16,
      color: 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: 4
    })
  }
}
