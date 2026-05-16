import { AIProvider, AIModel } from '../../services/DataModels';

export interface ModelSelectorSheetParam {
  providers: AIProvider[];
  currentProviderId: string;
  currentModelId: string;
  onModelSelected: (providerId: string, modelId: string) => void;
  onClose: () => void;
}

@Builder
function ModelSelectorGroupHeader(title: string) {
  Text(title)
    .fontSize(14)
    .fontWeight(FontWeight.Medium)
    .padding({ left: 16, top: 8, bottom: 4 })
}

@Builder
export function ModelSelectorSheet(param: ModelSelectorSheetParam) {
  Column() {
    if (param.providers.length > 0) {
      List() {
        ForEach(param.providers, (provider: AIProvider) => {
          ListItemGroup({
            header: ModelSelectorGroupHeader(provider.displayName)
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

                  if (provider.id === param.currentProviderId && model.id === param.currentModelId) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(20)
                      .fontColor([Color.Green])
                  }
                }
                .width('100%')
                .height(56)
                .padding({ left: 20, right: 28 })
                .borderRadius(12)
                .margin({ left: 12, right: 12, bottom: 4 })
                .onClick(() => {
                  param.onModelSelected(provider.id, model.id);
                  param.onClose();
                })
              }
            }, (model: AIModel) => model.id || model.name)
          }
        }, (provider: AIProvider) => provider.id || provider.name)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .padding({ bottom: 24 })
    } else {
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
}
