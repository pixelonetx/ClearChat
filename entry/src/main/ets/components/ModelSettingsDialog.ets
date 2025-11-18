import { Prompt } from '@kit.ArkUI';
import { AIModel } from '../services/DataModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct ModelSettingsDialog {
  model: AIModel = new AIModel('', '', '');
  isEditMode: boolean = false;
  onConfirm: (model: AIModel) => void = () => {};
  @State private editableModel: AIModel = new AIModel('', '', '');

  aboutToAppear() {
    this.editableModel = this.cloneModel(this.model);
  }

  build() {
    Column() {
      // 标题
      Text(this.isEditMode ? '编辑模型' : '添加模型')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 })

      // 模型显示名称
      Column() {
        Text('模型名称')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        TextInput({ placeholder: '例如：GPT-3.5 Turbo', text: this.editableModel.displayName })
          .height(48)
          .onChange((value: string) => {
            this.editableModel.displayName = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 模型ID
      Column() {
        Text('模型ID')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        TextInput({ placeholder: '例如：gpt-3.5-turbo', text: this.editableModel.name })
          .height(48)
          .onChange((value: string) => {
            this.editableModel.name = value;
            if (!this.isEditMode && !this.editableModel.id) {
              this.editableModel.id = value;
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 最大Token数
      Column() {
        Text('最大Token数')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        TextInput({ placeholder: '4096', text: this.editableModel.maxTokens.toString() })
          .height(48)
          .type(InputType.Number)
          .onChange((value: string) => {
            const tokens = parseInt(value) || 4096;
            this.editableModel.maxTokens = tokens;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 温度参数
      Column() {
        Text(`温度参数 (${this.editableModel.temperature})`)
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        Slider({
          value: this.editableModel.temperature * 100,
          min: 0,
          max: 200,
          step: 10,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .trackColor('#E0E0E0')
          .selectedColor('#4CAF50')
          .blockColor('#4CAF50')
          .onChange((value: number) => {
            this.editableModel.temperature = value / 100;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 24 })

      // 支持联网搜索
      Column() {
        Row() {
          Column() {
            Text('支持内置联网搜索')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start)

            Text('如启用，该模型在聊天时支持联网搜索功能')
              .fontSize(12)
              .fontColor('#888888')
              .alignSelf(ItemAlign.Start)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.editableModel.supportsWebSearch })
            .onChange((isOn: boolean) => {
              this.editableModel.supportsWebSearch = isOn;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .backgroundColor($r('sys.color.ohos_fa_list_card_bg'))
      .borderRadius(8)
      .margin({ bottom: 24 })

      // 按钮区域
      Row() {
        Button('确定')
          .layoutWeight(1)
          .height(48)
          .backgroundColor('#4CAF50')
          .fontColor(Color.White)
          .borderRadius(24)
          .margin({ left: 12 })
          .onClick(() => {
            this.confirmModel();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
    .borderRadius(12)
  }

  private confirmModel() {
    if (!this.editableModel.displayName.trim()) {
      this.showToast('请输入模型名称');
      return;
    }

    if (!this.editableModel.name.trim()) {
      this.showToast('请输入模型ID');
      return;
    }

    if (!this.editableModel.id) {
      this.editableModel.id = this.editableModel.name;
    }

    this.onConfirm(this.cloneModel(this.editableModel));
  }

  private cloneModel(model: AIModel): AIModel {
    return new AIModel(model.id, model.name, model.displayName, model.maxTokens, model.temperature, model.supportsWebSearch);
  }

  private showToast(message: string) {
    try {
      Prompt.showToast({ message });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to show toast: %{public}s', String(error));
    }
  }
}

const DOMAIN = 0x0000;
const TAG = 'ModelSettingsDialog';
