
@CustomDialog
export struct DeleteModelDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: null,
    autoCancel: true
  });

  modelName: string = '';
  onConfirm?: () => void;
  onCancel?: () => void;

  build() {
    Column() {
      // 标题
      Text('删除模型')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 20 })

      // 消息内容
      Column() {
        Text(`确定要删除模型"${this.modelName}"吗？`)
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .lineHeight(22)
          .margin({ bottom: 10 })

        Text('此操作无法撤销，模型配置将永久删除。')
          .fontSize(13)
          .textAlign(TextAlign.Center)
          .lineHeight(18)
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

        Button('删除')
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
