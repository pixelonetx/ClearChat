import { promptAction } from '@kit.ArkUI';
import { AIProvider, AIModel } from '../services/DataModels';
import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG = 'ProviderSettingsDialog';

@Component
export struct ProviderSettingsDialog {
  provider: AIProvider = new AIProvider('', '', '');
  isEditMode: boolean = false;
  onConfirm: (provider: AIProvider) => void = () => {};
  @State private editableProvider: AIProvider = new AIProvider('', '', '');

  // 预定义的模型列表
  // model.id, model.name, model.displayName, model.maxTokens, model.temperature, supportsWebSearch
  private getPredefinedModels(providerType: string): AIModel[] {
    if (providerType === 'deepseek') {
      return [
        new AIModel('deepseek-chat', 'deepseek-chat', 'DeepSeek V3.1', 4000, 0.7, false),
        new AIModel('deepseek-reasoner', 'deepseek-reasoner', 'DeepSeek R1', 32000, 0.7, false)
      ];
    } else if (providerType === 'aliyun') {
      return [
        new AIModel('qwen3-max', 'qwen3-max', 'Qwen3-Max', 258048, 0.7, true),
        new AIModel('qwen-plus', 'qwen-plus', 'Qwen-Plus', 997952, 0.7, true),
        new AIModel('qwen-flash', 'qwen-flash', 'Qwen-Flash', 997952, 0.7, true),
      ];
    } else {
      return [];
    }
  }

  aboutToAppear() {
    this.editableProvider = this.cloneProvider(this.provider);
    if (this.editableProvider.id && this.editableProvider.models.length === 0) {
      // 如果是预定义服务商，加载默认模型
      const defaultModels = this.getPredefinedModels(this.editableProvider.name);
      this.editableProvider.models = [...defaultModels];
    }
  }

  build() {
    Column() {
      // 标题
      Text(this.isEditMode ? '编辑提供方' : '添加提供方')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 })

      // 服务商名称
      Column() {
        Text('模型提供方名称')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        TextInput({ placeholder: '如 DeepSeek 等', text: this.editableProvider.displayName })
          .height(48)
          .onChange((value: string) => {
            this.editableProvider.displayName = value;
            if (!this.isEditMode) {
              this.editableProvider.name = value.toLowerCase().replace(/\s+/g, '_');
              this.editableProvider.id = Date.now().toString();
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // API地址
      Column() {
        Text('API地址')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        TextInput({ placeholder: 'https://api.deepseek.com', text: this.editableProvider.apiUrl })
          .height(48)
          .onChange((value: string) => {
            this.editableProvider.apiUrl = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // API密钥
      Column() {
        Text('API密钥')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        TextInput({ placeholder: '请输入API密钥', text: this.editableProvider.apiKey })
          .height(48)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.editableProvider.apiKey = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: 16 })

      // 预设模板按钮
      if (!this.isEditMode) {
        Text('快速配置')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })

        Row() {
          Button('Qwen')
            .fontSize(12)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .margin({ left: 8 })
            .onClick(() => {
              this.loadPresetProvider('aliyun');
            })

          Button('DeepSeek')
            .fontSize(12)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .margin({ left: 8 })
            .onClick(() => {
              this.loadPresetProvider('deepseek');
            })
        }
        .width('100%')
        .margin({ bottom: 24 })
      }

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
            this.confirmProvider();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(24)
    .borderRadius(12)
  }

  private loadPresetProvider(providerType: string) {
    switch (providerType) {
      case 'aliyun':
        this.editableProvider.displayName = '阿里云';
        this.editableProvider.name = 'aliyun';
        this.editableProvider.apiUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
        this.editableProvider.models = this.getPredefinedModels('aliyun');
        break;
      case 'deepseek':
        this.editableProvider.displayName = 'DeepSeek';
        this.editableProvider.name = 'deepseek';
        this.editableProvider.apiUrl = 'https://api.deepseek.com/v1';
        this.editableProvider.models = this.getPredefinedModels('deepseek');
        break;
    }
    this.editableProvider.id = Date.now().toString();
  }

  private confirmProvider() {
    // 验证提供方名称
    const displayName = this.editableProvider.displayName.trim();
    if (!displayName) {
      this.showToast('请输入提供方名称');
      return;
    }
    if (displayName.length > 50) {
      this.showToast('提供方名称不能超过50个字符');
      return;
    }

    // 验证API地址
    const apiUrl = this.editableProvider.apiUrl.trim();
    if (!apiUrl) {
      this.showToast('请输入API地址');
      return;
    }
    if (!this.isValidUrl(apiUrl)) {
      this.showToast('请输入有效的API地址');
      return;
    }

    // 验证API密钥
    const apiKey = this.editableProvider.apiKey.trim();
    if (!apiKey) {
      this.showToast('请输入API密钥');
      return;
    }
    if (apiKey.length < 10 || apiKey.length > 200) {
      this.showToast('API密钥长度应在10-200个字符之间');
      return;
    }

    // 更新编辑的提供方数据
    this.editableProvider.displayName = displayName;
    this.editableProvider.apiUrl = apiUrl;
    this.editableProvider.apiKey = apiKey;

    this.onConfirm(this.cloneProvider(this.editableProvider));
  }

  private isValidUrl(url: string): boolean {
    // 简单的URL格式验证，适用于ArkTS环境
    const urlPattern = /^https?:\/\/([\w\-]+(\.[\w\-]+)*)(:\d+)?(\/.*)?$/i;
    return urlPattern.test(url.trim());
  }

  private cloneProvider(source: AIProvider): AIProvider {
    const clonedProvider = new AIProvider(source.id, source.name, source.displayName, source.apiUrl, source.apiKey);
    clonedProvider.isActive = source.isActive;
    clonedProvider.models = source.models.map(model => this.cloneModel(model));
    return clonedProvider;
  }

  private cloneModel(model: AIModel): AIModel {
    return new AIModel(model.id, model.name, model.displayName, model.maxTokens, model.temperature, model.supportsWebSearch);
  }

  private showToast(message: string) {
    try {
      promptAction.showToast({ message });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to show toast: %{public}s', String(error));
    }
  }
}
