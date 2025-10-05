import { AIProvider, AIModel } from '../services/DataModels';

@Component
export struct ModelSelectorSheet {
  @Prop providers: AIProvider[] = [];
  @Prop currentProviderId: string = '';
  @Prop currentModelId: string = '';
  onModelSelected: (providerId: string, modelId: string) => void = () => {};
  onClose: () => void = () => {};

  @Builder
  buildGroupHeader(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .padding({ left: 16, top: 8, bottom: 4 })
  }

  build() {
    Column() {
      // 标题
      Text('选择AI模型')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ left: 20, right: 20, top: 16, bottom: 20 })

      // 提供商和模型列表
      if (this.providers.length > 0) {
        List() {
          ForEach(this.providers, (provider: AIProvider) => {
            ListItemGroup({
              header: this.buildGroupHeader(provider.displayName)
            }) {
              ForEach(provider.models, (model: AIModel) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(model.displayName)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)

                      if (model.name && model.name !== model.displayName) {
                        Text(model.name)
                          .fontSize(12)
                          .margin({ top: 4 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (provider.id === this.currentProviderId &&
                      model.id === this.currentModelId) {
                      Stack() {
                        Circle({ width: 20, height: 20 })

                        Text('✓')
                          .fontSize(12)
                          .fontColor(Color.White)
                          .fontWeight(FontWeight.Bold)
                      }
                    }
                  }
                  .width('100%')
                  .height(64)
                  .padding({ left: 20, right: 20 })
                  .borderRadius(12)
                  .margin({ left: 12, right: 12, bottom: 4 })
                  .onClick(() => {
                    this.onModelSelected(provider.id, model.id);
                    this.onClose();
                  })
                }
              })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .padding({ bottom: 24 })
      } else {
        // 空状态
        Column() {
          Text('暂无可用模型')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 8 })

          Text('请先在设置中配置AI服务提供商')
            .fontSize(14)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(40)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 0 }) // 确保内容延伸到底部
  }
}
