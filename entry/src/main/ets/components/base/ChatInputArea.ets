/**
 * ChatInputArea.ets
 * 聊天输入区域组件
 * 
 * 职责：封装聊天输入框、发送按钮、联网搜索开关
 */

/**
 * 输入区域配置
 */
export interface ChatInputConfig {
  placeholder?: string;
  maxLength?: number;
  showWebSearchToggle?: boolean;
}

/**
 * 默认配置
 */
export const DEFAULT_INPUT_CONFIG: ChatInputConfig = {
  placeholder: '输入你的消息...',
  maxLength: 10000,
  showWebSearchToggle: true
};

/**
 * 聊天输入区域组件
 */
@Component
export struct ChatInputArea {
  @Link inputText: string;
  @Prop isLoading: boolean = false;
  @Prop isGenerating: boolean = false;
  @Link enableWebSearch: boolean;
  @Prop config: ChatInputConfig = DEFAULT_INPUT_CONFIG;
  
  // 回调
  onSend?: () => void;
  onStop?: () => void;
  onWebSearchChange?: (enabled: boolean) => void;
  
  // 内部状态
  @State private ctrlFlag: boolean = false;

  build() {
    Column() {
      // 输入框
      TextArea({ 
        placeholder: this.config.placeholder ?? DEFAULT_INPUT_CONFIG.placeholder, 
        text: this.inputText 
      })
        .fontSize(16)
        .backgroundColor($r('app.color.input_area_color'))
        .showCounter(true)
        .onChange((value: string) => {
          this.inputText = value;
        })
        .enterKeyType(EnterKeyType.Send)
        .onSubmit((enterKey: EnterKeyType) => {
          if (this.ctrlFlag) {
            this.inputText += '\n';
          } else {
            this.handleSend();
          }
        })
        .onKeyEvent((event: KeyEvent) => {
          this.ctrlFlag = event.getModifierKeyState?.(['Ctrl']) ?? false;
        })

      // 工具栏
      Row() {
        // 联网搜索开关
        if (this.config.showWebSearchToggle ?? true) {
          Toggle({ type: ToggleType.Button, isOn: this.enableWebSearch }) {
            Image($r('app.media.worldclock'))
              .size({ width: 24, height: 24 })
              .fillColor(this.enableWebSearch ? Color.Blue : Color.Gray)
          }
          .size({ width: 40, height: 40 })
          .backgroundColor(Color.Transparent)
          .onChange((on: boolean) => {
            this.enableWebSearch = on;
            this.onWebSearchChange?.(on);
          })
          .margin({ left: 12 })
        }

        Blank()

        // 发送/停止按钮
        Button() {
          if (this.isGenerating) {
            SymbolGlyph($r('sys.symbol.stop_circle'))
              .fontSize(24)
              .fontColor([Color.Red])
          } else if (this.isLoading) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(Color.Red)
          } else {
            SymbolGlyph($r('sys.symbol.arrow_up_circle'))
              .fontSize(24)
              .fontColor([$r('app.color.text_color')])
          }
        }
        .type(ButtonType.Circle)
        .backgroundColor($r('sys.color.button_background_color_transparent'))
        .size({ width: 40, height: 40 })
        .margin({ right: 12 })
        .enabled(this.isGenerating || (this.inputText.trim() !== '' && !this.isLoading))
        .onClick(() => {
          if (this.isGenerating) {
            this.onStop?.();
          } else {
            this.handleSend();
          }
        })
      }
      .margin({ bottom: 12 })
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
    }
    .backgroundColor($r('app.color.input_area_color'))
    .borderColor($r('app.color.text_secondary'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .width('100%')
    .padding({
      left: 2,
      right: 2,
      top: 6,
      bottom: 4
    })
  }

  private handleSend(): void {
    if (this.inputText.trim() !== '' && !this.isLoading) {
      this.onSend?.();
    }
  }
}
