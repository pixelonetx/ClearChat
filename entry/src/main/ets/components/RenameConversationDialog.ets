import { Conversation } from '../services/ConversationModels';

@CustomDialog
export struct RenameConversationDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: null,
    autoCancel: true
  });
  conversation: Conversation = new Conversation();
  @State newTitle: string = '';
  onConfirm?: (conversationId: string, newTitle: string) => void;

  aboutToAppear() {
    this.newTitle = this.conversation.title;
  }

  build() {
    Column() {
      // 标题
      Text('重命名对话')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 20 })

      // 输入框
      TextInput({ text: this.newTitle, placeholder: '输入新的对话标题' })
        .width('100%')
        .height(40)
        .fontSize(16)
        .borderRadius(8)
        .border({ width: 1, color: Color.Gray })
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 24 })
        .onChange((value: string) => {
          this.newTitle = value;
        })
        .onSubmit(() => {
          this.confirmRename();
        })

      // 按钮行
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .borderRadius(8)
          .onClick(() => {
            this.controller.close();
          })

        Button('确定')
          .layoutWeight(1)
          .height(40)
          .fontColor(Color.White)
          .borderRadius(8)
          .enabled(this.newTitle.trim().length > 0)
          .onClick(() => {
            this.confirmRename();
          })
      }
      .width('100%')
    }
    .width(280)
    .padding(20)
    .borderRadius(12)
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.15)',
      offsetX: 0,
      offsetY: 4
    })
  }

  private confirmRename() {
    const trimmedTitle = this.newTitle.trim();
    if (trimmedTitle.length > 0) {
      this.onConfirm?.(this.conversation.id, trimmedTitle);
      this.controller.close();
    }
  }
}
