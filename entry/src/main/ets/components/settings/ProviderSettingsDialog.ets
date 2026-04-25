import { Prompt } from '@kit.ArkUI';
import { AIProvider, AIModel } from '../../services/DataModels';
import { createLogger, LogDomain } from '../../common/Logger';
import { PresetProvider, PRESET_PROVIDERS, ApiFormat, inferApiFormat } from '../../services/PresetProviders';
import { NetworkManagerV2 } from '../../services/NetworkManagerV2';

const logger = createLogger('ProviderSettingsDialog', LogDomain.SETTINGS);

@Component
export struct ProviderSettingsDialog {
  provider: AIProvider = new AIProvider('', '', '');
  isEditMode: boolean = false;
  onConfirm: (provider: AIProvider) => void = () => {};
  @State private editableProvider: AIProvider = new AIProvider('', '', '');
  @State private isFetchingModels: boolean = false;
  @State private selectedPresetType: string = '';
  private networkManager = NetworkManagerV2.getInstance();

  aboutToAppear() {
    this.editableProvider = this.cloneProvider(this.provider);
    // 如果编辑模式下没有模型，尝试匹配预设
    if (this.isEditMode && this.editableProvider.models.length === 0) {
      const matched = PRESET_PROVIDERS.find(p => p.type === this.editableProvider.name || p.type === this.editableProvider.id);
      if (matched) {
        this.editableProvider.models = matched.defaultModels.map(m =>
          new AIModel(m.id, m.name, m.displayName, m.maxTokens, m.temperature, m.supportsWebSearch));
      }
    }
  }

  /** 当前编辑中的服务商对应的 ApiFormat */
  private getCurrentApiFormat(): ApiFormat {
    const url = this.editableProvider.apiUrl;
    if (url) return inferApiFormat(url);
    // fallback: 检查是否匹配某个预设
    if (this.selectedPresetType) {
      const preset = PRESET_PROVIDERS.find(p => p.type === this.selectedPresetType);
      if (preset) return preset.apiFormat;
    }
    return 'openai';
  }

  private async fetchModelsFromApi(): Promise<void> {
    const url = this.editableProvider.apiUrl.trim();
    const key = this.editableProvider.apiKey.trim();
    if (!url || !key) {
      this.showToast('请先填写 API 地址和密钥');
      return;
    }
    this.isFetchingModels = true;
    try {
      const format = this.getCurrentApiFormat();
      const models = await this.networkManager.fetchModels(url, key, format);
      if (models.length === 0) {
        this.showToast('未获取到可用模型，请手动添加');
        return;
      }
      this.editableProvider.models = models;
      this.showToast(`成功获取 ${models.length} 个模型`);
    } catch (error) {
      logger.error('Failed to fetch models: %{public}s', String(error));
      this.showToast(`获取模型失败: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      this.isFetchingModels = false;
    }
  }

  build() {
    Column() {
      Text(this.isEditMode ? '编辑提供方' : '添加提供方')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })
        .width('100%')

      // 服务商名称
      Column() {
        Text('模型提供方名称')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 6 })
        TextInput({ placeholder: '如 OpenAI', text: this.editableProvider.displayName })
          .height(44)
          .borderRadius(10)
          .fontSize(15)
          .onChange((value: string) => {
            this.editableProvider.displayName = value;
            if (!this.isEditMode) {
              this.editableProvider.name = value.toLowerCase().replace(/\s+/g, '_');
              this.editableProvider.id = Date.now().toString();
            }
          })
      }
      .width('100%')
      .margin({ bottom: 14 })

      // API 地址
      Column() {
        Text('API 地址')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 6 })
        TextInput({ placeholder: 'https://api.openai.com/v1', text: this.editableProvider.apiUrl })
          .height(44)
          .borderRadius(10)
          .fontSize(15)
          .onChange((value: string) => {
            this.editableProvider.apiUrl = value;
          })
      }
      .width('100%')
      .margin({ bottom: 14 })

      // API 密钥
      Column() {
        Text('API 密钥')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 6 })
        TextInput({ placeholder: '请输入 API 密钥', text: this.editableProvider.apiKey })
          .height(44)
          .borderRadius(10)
          .fontSize(15)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.editableProvider.apiKey = value;
          })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 预设服务商快速选择
      if (!this.isEditMode) {
        Text('快速配置')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        Scroll() {
          Row({ space: 10 }) {
            ForEach(PRESET_PROVIDERS, (preset: PresetProvider) => {
              this.PresetChip(preset)
            })
          }
          .padding({ left: 2, right: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ bottom: 16 })
      }

      // 获取模型按钮
      if (this.editableProvider.apiUrl.trim() && this.editableProvider.apiKey.trim()) {
        Row() {
          Button() {
            Row({ space: 6 }) {
              if (this.isFetchingModels) {
                LoadingProgress().width(16).height(16)
              }
              Text(this.isFetchingModels ? '获取中...' : '从 API 获取模型')
                .fontSize(14)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
            }
          }
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .enabled(!this.isFetchingModels)
          .onClick(() => { this.fetchModelsFromApi(); })

          if (this.editableProvider.models.length > 0) {
            Text(`${this.editableProvider.models.length} 个模型`)
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ left: 12 })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 16 })
      }

      // 确认按钮
      Row() {
        Button('确定')
          .layoutWeight(1)
          .height(48)
          .backgroundColor('#4CAF50')
          .fontColor(Color.White)
          .borderRadius(24)
          .onClick(() => { this.confirmProvider(); })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
    .borderRadius(12)
  }

  @Builder
  PresetChip(preset: PresetProvider) {
    Column() {
      Text(preset.displayName)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(20)
    .border({
      width: this.selectedPresetType === preset.type ? 2 : 1,
      color: this.selectedPresetType === preset.type
        ? '#4CAF50'
        : $r('sys.color.ohos_id_color_text_secondary')
    })
    .backgroundColor(this.selectedPresetType === preset.type
      ? 'rgba(76, 175, 80, 0.08)'
      : $r('sys.color.ohos_id_color_button_normal'))
    .onClick(() => {
      this.applyPreset(preset);
    })
  }

  private applyPreset(preset: PresetProvider): void {
    this.selectedPresetType = preset.type;
    this.editableProvider.displayName = preset.displayName;
    this.editableProvider.name = preset.name;
    this.editableProvider.apiUrl = preset.apiUrl;
    this.editableProvider.id = Date.now().toString() + '_' + preset.type;
    this.editableProvider.models = preset.defaultModels.map(m =>
      new AIModel(m.id, m.name, m.displayName, m.maxTokens, m.temperature, m.supportsWebSearch));
  }

  private confirmProvider(): void {
    const displayName = this.editableProvider.displayName.trim();
    if (!displayName) {
      this.showToast('请输入提供方名称');
      return;
    }
    if (displayName.length > 50) {
      this.showToast('提供方名称不能超过50个字符');
      return;
    }

    const apiUrl = this.editableProvider.apiUrl.trim();
    if (!apiUrl) {
      this.showToast('请输入 API 地址');
      return;
    }
    if (!this.isValidUrl(apiUrl)) {
      this.showToast('请输入有效的 API 地址');
      return;
    }

    const apiKey = this.editableProvider.apiKey.trim();
    if (!apiKey) {
      this.showToast('请输入 API 密钥');
      return;
    }
    if (apiKey.length < 10 || apiKey.length > 200) {
      this.showToast('API 密钥长度应在 10-200 个字符之间');
      return;
    }

    this.editableProvider.displayName = displayName;
    this.editableProvider.apiUrl = apiUrl;
    this.editableProvider.apiKey = apiKey;

    if (!this.editableProvider.id || this.editableProvider.id.trim().length === 0) {
      this.editableProvider.id = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
    }
    if (!this.editableProvider.name || this.editableProvider.name.trim().length === 0) {
      this.editableProvider.name = displayName;
    }

    this.onConfirm(this.cloneProvider(this.editableProvider));
  }

  private isValidUrl(url: string): boolean {
    const urlPattern = /^https?:\/\/([\w\-]+(\.[\w\-]+)*)(:\d+)?(\/.*)?$/i;
    return urlPattern.test(url.trim());
  }

  private cloneProvider(source: AIProvider): AIProvider {
    const cloned = new AIProvider(source.id, source.name, source.displayName, source.apiUrl, source.apiKey);
    cloned.isActive = source.isActive;
    cloned.models = source.models.map(m => this.cloneModel(m));
    return cloned;
  }

  private cloneModel(model: AIModel): AIModel {
    return new AIModel(model.id, model.name, model.displayName, model.maxTokens, model.temperature, model.supportsWebSearch);
  }

  private showToast(message: string): void {
    try {
      Prompt.showToast({ message, duration: 2000 });
    } catch (error) {
      logger.error('Failed to show toast: %{public}s', String(error));
    }
  }
}
