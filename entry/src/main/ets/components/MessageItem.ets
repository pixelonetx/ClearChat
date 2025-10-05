import { ChatMessage } from '../services/DataModels';
import { Constants } from '../components/Constants';
import { MarkdownRenderer } from './MarkdownRenderer';

@Component
export struct MessageItem {
  @Prop message: ChatMessage;

  // 回调函数
  onCopy?: (message: ChatMessage) => void | Promise<void>;
  onEdit?: (message: ChatMessage) => void | Promise<void>;
  onDelete?: (message: ChatMessage) => void | Promise<void>;
  onRegenerate?: (message: ChatMessage) => void | Promise<void>;

  @State showUserMenu: boolean = false;
  @State showAssistantMenu: boolean = false;

  @Builder
  UserDropdownMenu() {
    Column() {
      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.trash'))
            .size({ width: 14, height: 14 })
          Text('删除')
            .fontSize(13)
        }
      }
      .borderRadius(6)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .width(80)
      .height(32)
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete(this.message);
        }
        this.showUserMenu = false;
      })
    }
    .borderRadius(8)
    .padding(4)
    .shadow({ radius: 8, color: '#00000020', offsetX: 0, offsetY: 2 })
  }

  @Builder
  AssistantDropdownMenu() {
    Column() {
      Button() {
        Row({ space: 6 }) {
          Image($r('app.media.trash'))
            .size({ width: 14, height: 14 })
          Text('删除')
            .fontSize(13)
        }
      }
      .borderRadius(6)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .width(80)
      .height(32)
      .onClick(() => {
        if (this.onDelete) {
          this.onDelete(this.message);
        }
        this.showAssistantMenu = false;
      })
    }
    .borderRadius(8)
    .padding(4)
    .shadow({ radius: 8, color: '#00000020', offsetX: 0, offsetY: 2 })
  }

  @Builder
  UserActionButtons() {
    Row({ space: 8 }) {
      // 复制按钮 - 圆形
      Button() {
        Image($r('app.media.rectangle_on_rectangle'))
          .size({ width: 18, height: 18 })
      }
      .type(ButtonType.Circle)
      .size({ width: 36, height: 36 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        if (this.onCopy) {
          this.onCopy(this.message);
        }
      })

      // 编辑按钮 - 圆形
      Button() {
        Image($r('app.media.square_and_pencil'))
          .size({ width: 18, height: 18 })
      }
      .type(ButtonType.Circle)
      .size({ width: 36, height: 36 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        if (this.onEdit) {
          this.onEdit(this.message);
        }
      })

      // 更多按钮 - 圆形
      Button() {
        Image($r('app.media.more_fill'))
          .size({ width: 18, height: 18 })
      }
      .type(ButtonType.Circle)
      .size({ width: 36, height: 36 })
      .backgroundColor(Color.Transparent)
      .bindPopup(this.showUserMenu, {
        builder: this.UserDropdownMenu,
        placement: Placement.BottomLeft,
        maskColor: Color.Transparent,
        popupColor: Color.Transparent,
        enableArrow: false,
        showInSubWindow: false,
        onStateChange: (e) => {
          if (!e.isVisible) {
            this.showUserMenu = false;
          }
        }
      })
      .onClick(() => {
        this.showUserMenu = !this.showUserMenu;
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .margin({ top: 8, right: 4 })
  }

  @Builder
  AssistantActionButtons() {
    Row({ space: 8 }) {
      // 复制按钮 - 圆形
      Button() {
        Image($r('app.media.rectangle_on_rectangle'))
          .size({ width: 18, height: 18 })
      }
      .type(ButtonType.Circle)
      .size({ width: 36, height: 36 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        if (this.onCopy) {
          this.onCopy(this.message);
        }
      })

      // 重新生成按钮 - 圆形
      Button() {
        Image($r('app.media.arrow_clockwise'))
          .size({ width: 18, height: 18 })
      }
      .type(ButtonType.Circle)
      .size({ width: 36, height: 36 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        if (this.onRegenerate) {
          this.onRegenerate(this.message);
        }
      })

      // 更多按钮 - 圆形
      Button() {
        Image($r('app.media.more_fill'))
          .size({ width: 18, height: 18 })
      }
      .type(ButtonType.Circle)
      .size({ width: 36, height: 36 })
      .backgroundColor(Color.Transparent)
      .bindPopup(this.showAssistantMenu, {
        builder: this.AssistantDropdownMenu,
        placement: Placement.BottomRight,
        maskColor: Color.Transparent,
        popupColor: Color.Transparent,
        enableArrow: false,
        showInSubWindow: false,
        onStateChange: (e) => {
          if (!e.isVisible) {
            this.showAssistantMenu = false;
          }
        }
      })
      .onClick(() => {
        this.showAssistantMenu = !this.showAssistantMenu;
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .margin({ top: 8, left: 4 })
  }

  @Builder
  UserMessage() {
    Column() {
      Row() {
        Blank()

        Row() {
          Column() {
            Text(this.message.content)
              .fontSize(14)
              .fontColor(Color.White)
              .maxLines(999)
              .textOverflow({ overflow: TextOverflow.None })
              .wordBreak(WordBreak.BREAK_ALL)
          }
          .padding(16)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          .constraintSize({
            minWidth: 40,  // 减小最小宽度，适合短消息
            minHeight: 36  // 保持最小高度，防止变成小圆形
          })
        }
        .constraintSize({ maxWidth: '85%' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 添加操作按钮
      this.UserActionButtons()
    }
    .width('100%')
    .margin({ bottom: Constants.MESSAGE_MARGIN })
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  AssistantMessage() {
    Column() {
      // 只显示模型名称（如果有）
      if (this.message.modelName) {
        Row() {
          Text(this.message.modelName)
            .fontSize(11)
            .opacity(0.8)
            .margin({ left: 8, bottom: 4 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }

      Row() {
        Row() {
          Column() {
            MarkdownRenderer({
              content: this.message.content,
              maxWidth: 'auto' // 自动继承父容器宽度限制
            })
          }
          .padding(16)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
          .constraintSize({
            minWidth: 40,  // 减小最小宽度，适合短消息
            minHeight: 36  // 保持最小高度，防止变成小圆形
          })
        }
        .constraintSize({ maxWidth: '85%' }) // 动态宽度，最大85%
        .layoutWeight(0) // 不占用剩余空间，根据内容调整大小

        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.Start) // 靠左对齐，不居中

      // 添加操作按钮
      this.AssistantActionButtons()
    }
    .width('100%')
    .margin({ bottom: Constants.MESSAGE_MARGIN })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LoadingMessage() {
    Row() {
      Column() {
        Row({ space: 8 }) {
          ForEach([1, 2, 3], (item: number) => {
            Circle({ width: 8, height: 8 })
              .animation({
                duration: 600,
                curve: Curve.EaseInOut,
                iterations: -1,
                playMode: PlayMode.Alternate,
                delay: item * 200
              })
          })
        }
        .padding(16)
      }
      .borderRadius(16)
      .constraintSize({
        minWidth: 40,  // 减小最小宽度，适合短消息
        minHeight: 36  // 保持最小高度，防止变成小圆形
      })

      Blank()
    }
    .width('100%')
    .margin({ bottom: Constants.MESSAGE_MARGIN })
  }

  build() {
    Column() {
      if (this.message.role === 'user') {
        this.UserMessage()
      } else if (this.message.content === '...') {
        // 显示加载动画
        this.LoadingMessage()
      } else {
        this.AssistantMessage()
      }
    }
    .width('100%')
  }
}
