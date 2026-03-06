import { Conversation } from '../../services/ConversationModels';

@Preview
@CustomDialog
export struct RenameConversationDialog {
  controller: CustomDialogController;
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
        .margin({bottom:10 })

      // 输入框
      TextInput({ text: this.newTitle, placeholder: '输入新的对话标题' })
        .width('100%')
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => {
          this.newTitle = value;
        })
        .onSubmit(() => {
          this.confirmRename();
        })

      Flex({ justifyContent: FlexAlign.SpaceAround }) {
        Button('取消')
          .backgroundColor($r('app.color.dialog_button_bac_color'))
          .fontColor(Color.Red)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
          })
        Button('确定')
          .backgroundColor($r('app.color.dialog_button_bac_color'))
          .fontColor($r('app.color.text_color'))
          .layoutWeight(1)
          .enabled(this.newTitle.trim().length > 0)
          .onClick(() => {
            this.confirmRename();
          })
      }
      .margin({ top: 10 })
    }
    .borderRadius(24)
    .backgroundColor($r('sys.color.background_primary'))
    .width(280)
    .padding(20)
  }

  private confirmRename() {
    const trimmedTitle = this.newTitle.trim();
    if (trimmedTitle.length > 0) {
      this.onConfirm?.(this.conversation.id, trimmedTitle);
      this.controller.close();
    }
  }
}
