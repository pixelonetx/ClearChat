import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSettings, AIProvider, AIModel, ChatMessage } from '../services/DataModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NetworkManager } from '../services/NetworkManager';
import { NativeDialogHelper } from '../components/NativeDialogHelper';
import { ProviderSettingsDialog } from '../components/ProviderSettingsDialog';
import { ModelSettingsDialog } from '../components/ModelSettingsDialog';
import { DatabaseError } from '../components/Errors';

interface ErrorLike {
  message?: string;
}

type ErrorInput = Error | ErrorLike | string | number | boolean | null | undefined | object;

// 跳转页面入口函数
@Builder
export function ModelSettingsBuilder() {
  ModelSettings();
}

@Entry
@Component
struct ModelSettings {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight')
  bottomRectHeight: number = 0;
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;

  @State isLoading: boolean = false;
  @State isTesting: boolean = false;

  // 新版本多服务商状态
  @State providers: AIProvider[] = [];
  @State currentProviderIndex: number = 0;
  @State activeProviderId: string = '';
  @State activeModelId: string = '';


  private databaseManager = DatabaseManager.getInstance();
  private networkManager = NetworkManager.getInstance();

  // bindSheet 状态
  @State private isSettingsSheetVisible: boolean = false;
  @State private activeSheetType: string = '';
  @State private providerDraft: AIProvider | null = null;
  @State private providerEditIndex: number = -1;
  @State private modelDraft: AIModel | null = null;
  @State private modelProviderIndex: number = -1;
  @State private modelEditIndex: number = -1;
  private hasLoadedSettings: boolean = false;
  private isRefreshingSettings: boolean = false;
  async aboutToAppear() {
    await this.ensureSettingsLoaded();
  }

  async onPageShow() {
    await this.ensureSettingsLoaded(true);
  }

  private async ensureSettingsLoaded(force: boolean = false) {
    if (this.isRefreshingSettings) {
      return;
    }

    if (!force && this.hasLoadedSettings) {
      return;
    }

    this.isRefreshingSettings = true;
    try {
      this.hasLoadedSettings = await this.loadSettings();
    } finally {
      this.isRefreshingSettings = false;
    }
  }

  private async fetchSettings(): Promise<AppSettings | null> {
    try {
      return await this.databaseManager.getSettings();
    } catch (error) {
      const normalizedError = this.ensureError(error as ErrorInput);
      if (this.isDatabaseNotInitialized(normalizedError)) {
        try {
          const context = getContext(this) as common.UIAbilityContext;
          await this.databaseManager.initDatabase(context);
          return await this.databaseManager.getSettings();
        } catch (initError) {
          const normalizedInitError = this.ensureError(initError as ErrorInput);
          console.error('Failed to initialize database while loading settings:', normalizedInitError);
          throw normalizedInitError;
        }
      }
      throw normalizedError;
    }
  }

  private isDatabaseNotInitialized(error: Error): boolean {
    return error instanceof DatabaseError && error.message.includes('not initialized');
  }

  private ensureError(rawError: ErrorInput): Error {
    if (rawError instanceof Error) {
      return rawError;
    }

    if (typeof rawError === 'string') {
      return new Error(rawError);
    }

    if (typeof rawError === 'number' || typeof rawError === 'boolean') {
      return new Error(`${rawError}`);
    }

    if (rawError && typeof rawError === 'object') {
      const potentialMessage = (rawError as ErrorLike).message;
      if (typeof potentialMessage === 'string' && potentialMessage.length > 0) {
        return new Error(potentialMessage);
      }

      try {
        const serialized = JSON.stringify(rawError);
        if (serialized && serialized !== '{}') {
          return new Error(serialized);
        }
      } catch (serializationError) {
        console.warn('Failed to serialize error object:', serializationError);
      }
    }

    return new Error('Unknown error');
  }


  private cloneModel(model: AIModel): AIModel {
    return new AIModel(model.id, model.name, model.displayName, model.maxTokens, model.temperature);
  }

  private cloneProvider(provider: AIProvider): AIProvider {
    const clonedProvider = new AIProvider(provider.id, provider.name, provider.displayName, provider.apiUrl, provider.apiKey);
    clonedProvider.isActive = provider.isActive;
    clonedProvider.models = provider.models.map(model => this.cloneModel(model));
    return clonedProvider;
  }

  // 构造可持久化的设置对象，所有改动仅在确认或显式保存后写入数据库
  private buildSettingsPayload(): AppSettings {
    const settings = new AppSettings();

    if (this.providers.length > 0 && this.activeProviderId) {
      const activeProvider = this.providers.find(p => p.id === this.activeProviderId);
      if (activeProvider) {
        settings.apiUrl = activeProvider.apiUrl;
        settings.apiKey = activeProvider.apiKey;
        const activeModel = activeProvider.models.find(m => m.id === this.activeModelId);
        settings.modelName = activeModel?.name || '';
      }
    }

    settings.providers = this.providers.map(provider => {
      const cloned = this.cloneProvider(provider);
      cloned.isActive = provider.id === this.activeProviderId;
      return cloned;
    });
    settings.activeProviderId = this.activeProviderId;
    settings.activeModelId = this.activeModelId;

    return settings;
  }

  private async persistSettingsSilently() {
    const settings = this.buildSettingsPayload();
    await this.databaseManager.saveSettings(settings);
    this.notifySettingsUpdated();
  }

  private notifySettingsUpdated() {
    try {
      const version = Date.now();
      const updated = AppStorage.Set('settingsVersion', version);
      console.info('ModelSettings: bump settingsVersion', version, 'updated existing key:', updated);
      if (!updated) {
        AppStorage.SetOrCreate('settingsVersion', version);
        console.info('ModelSettings: settingsVersion created with value', version);
      }
    } catch (error) {
      console.error('Failed to update settings version:', error);
    }
  }

  private showToast(message: string) {
    try {
      promptAction.showToast({ message });
    } catch (toastError) {
      console.error('Failed to show toast:', toastError);
    }
  }

  private closeSettingsSheet() {
    this.isSettingsSheetVisible = false;
    this.resetSheetState();
  }

  private resetSheetState() {
    if (!this.isSettingsSheetVisible) {
      this.activeSheetType = '';
      this.providerDraft = null;
      this.providerEditIndex = -1;
      this.modelDraft = null;
      this.modelProviderIndex = -1;
      this.modelEditIndex = -1;
    }
  }

  private async handleProviderConfirm(provider: AIProvider) {
    const clonedProvider = this.cloneProvider(provider);
    let toastMessage = '服务商已添加并保存';

    if (this.providerEditIndex >= 0 && this.providerEditIndex < this.providers.length) {
      const newProviders = [...this.providers];
      newProviders[this.providerEditIndex] = clonedProvider;
      this.providers = newProviders;
      toastMessage = '服务商已修改并保存';
    } else {
      this.providers = [...this.providers, clonedProvider];
    }

    try {
      await this.persistSettingsSilently();
      this.showToast(toastMessage);
    } catch (error) {
      console.error('Failed to save provider changes:', error);
      this.showToast('保存设置失败');
    } finally {
      this.closeSettingsSheet();
    }
  }

  private async handleModelConfirm(model: AIModel) {
    if (this.modelProviderIndex < 0 || this.modelProviderIndex >= this.providers.length) {
      this.showToast('未找到指定的服务商');
      this.closeSettingsSheet();
      return;
    }

    const provider = this.providers[this.modelProviderIndex];
    const updatedModel = this.cloneModel(model);
    const newProviders = [...this.providers];
    const models = [...provider.models];
    let toastMessage = '模型已添加并保存';

    if (this.modelEditIndex >= 0 && this.modelEditIndex < models.length) {
      models[this.modelEditIndex] = updatedModel;
      toastMessage = '模型已修改并保存';
    } else {
      models.push(updatedModel);
    }

    newProviders[this.modelProviderIndex] = this.cloneProvider(provider);
    newProviders[this.modelProviderIndex].models = models;
    this.providers = newProviders;

    try {
      await this.persistSettingsSilently();
      this.showToast(toastMessage);
    } catch (error) {
      console.error('Failed to save model changes:', error);
      this.showToast('保存设置失败');
    } finally {
      this.closeSettingsSheet();
    }
  }

  async loadSettings(): Promise<boolean> {
    try {
      const settings = await this.fetchSettings();
      if (!settings) {
        console.info('No settings found in database');
        this.providers = [];
        this.activeProviderId = '';
        this.activeModelId = '';
        this.currentProviderIndex = 0;
        return true;
      }

      const storedProviders = settings.providers ?? [];

      if (storedProviders.length === 0) {
        this.providers = [];
        this.activeProviderId = '';
        this.activeModelId = '';
        this.currentProviderIndex = 0;
        console.info('Settings found but no providers configured.');
        return true;
      }

      const activeIndex = storedProviders.findIndex(provider => provider.id === settings.activeProviderId);
      const resolvedIndex = activeIndex >= 0 ? activeIndex : 0;
      const resolvedProvider = storedProviders[resolvedIndex];
      const resolvedModelId = (settings.activeModelId && resolvedProvider.models.some(model => model.id === settings.activeModelId))
        ? settings.activeModelId
        : (resolvedProvider.models[0]?.id || '');

      this.providers = storedProviders.map(provider => this.cloneProvider(provider));
      this.currentProviderIndex = resolvedIndex;
      this.activeProviderId = resolvedProvider.id;
      this.activeModelId = resolvedModelId;

      console.info('Loaded providers from database:', storedProviders.length);
      return true;
    } catch (error) {
      console.error('Failed to load settings:', error);
      this.showToast('加载设置失败');
      return false;
    }
  }

  // 保存所有设置（手动保存，显示提示）
  async saveAllSettings() {
    try {
      this.isLoading = true;
      await this.persistSettingsSilently();
      this.showToast('设置已保存');
    } catch (error) {
      console.error('Failed to save settings:', error);
      this.showToast('保存设置失败');
    } finally {
      this.isLoading = false;
    }
  }

  // 添加服务商
  addProvider() {
    this.providerDraft = new AIProvider('', '', '');
    this.providerEditIndex = -1;
    this.activeSheetType = 'provider';
    this.isSettingsSheetVisible = true;
  }

  // 编辑服务商
  editProvider(index: number) {
    if (index >= 0 && index < this.providers.length) {
      const provider = this.providers[index];
      this.providerDraft = this.cloneProvider(provider);
      this.providerEditIndex = index;
      this.activeSheetType = 'provider';
      this.isSettingsSheetVisible = true;
    }
  }

  // 删除服务商
  async deleteProvider(index: number) {
    if (index >= 0 && index < this.providers.length && this.providers.length > 1) {
      const newProviders = [...this.providers];
      const deletedProvider = newProviders.splice(index, 1)[0];
      this.providers = newProviders;

      // 如果删除的是当前活跃的服务商，切换到第一个
      let savedByActiveSwitch = false;
      if (deletedProvider.id === this.activeProviderId && this.providers.length > 0) {
        const switched = await this.setActiveProvider(this.providers[0].id, this.providers[0].models[0]?.id || '');
        savedByActiveSwitch = switched;
      }

      // 调整当前页签索引
      if (this.currentProviderIndex >= this.providers.length) {
        this.currentProviderIndex = this.providers.length - 1;
      }

      if (savedByActiveSwitch) {
        this.showToast('服务商已删除并保存');
      } else {
        try {
          await this.persistSettingsSilently();
          this.showToast('服务商已删除并保存');
        } catch (error) {
          console.error('Failed to save after deleting provider:', error);
          this.showToast('保存设置失败');
        }
      }
    }
  }

  // 设置活跃的服务商和模型
  async setActiveProvider(providerId: string, modelId: string): Promise<boolean> {
    const providerIndex = this.providers.findIndex(provider => provider.id === providerId);
    if (providerIndex === -1) {
      this.showToast('未找到指定的服务商');
      return false;
    }

    const provider = this.providers[providerIndex];
    if (!provider.models || provider.models.length === 0) {
      this.showToast('该服务商没有可用模型，请先添加模型');
      return false;
    }

    const matchedModel = provider.models.find(model => model.id === modelId);
    const resolvedModelId = matchedModel ? matchedModel.id : provider.models[0].id;

    this.currentProviderIndex = providerIndex;
    this.activeProviderId = providerId;
    this.activeModelId = resolvedModelId;
    try {
      await this.persistSettingsSilently();
      return true;
    } catch (error) {
      console.error('Failed to save active provider/model:', error);
      this.showToast('保存设置失败');
      return false;
    }
  }

  // 添加模型
  addModel(providerIndex: number) {
    if (providerIndex >= 0 && providerIndex < this.providers.length) {
      this.modelDraft = new AIModel('', '', '');
      this.modelProviderIndex = providerIndex;
      this.modelEditIndex = -1;
      this.activeSheetType = 'model';
      this.isSettingsSheetVisible = true;
    }
  }

  // 编辑模型
  editModel(providerIndex: number, modelIndex: number) {
    if (providerIndex >= 0 && providerIndex < this.providers.length &&
      modelIndex >= 0 && modelIndex < this.providers[providerIndex].models.length) {
      const model = this.providers[providerIndex].models[modelIndex];
      this.modelDraft = this.cloneModel(model);
      this.modelProviderIndex = providerIndex;
      this.modelEditIndex = modelIndex;
      this.activeSheetType = 'model';
      this.isSettingsSheetVisible = true;
    }
  }

  // 删除模型
  async deleteModel(providerIndex: number, modelIndex: number) {
    if (providerIndex >= 0 && providerIndex < this.providers.length &&
      modelIndex >= 0 && modelIndex < this.providers[providerIndex].models.length &&
      this.providers[providerIndex].models.length > 1) {

      const model = this.providers[providerIndex].models[modelIndex];

      // 如果删除的是当前活跃的模型，切换到同一服务商的第一个模型
      if (this.providers[providerIndex].id === this.activeProviderId && model.id === this.activeModelId) {
        const remainingModels = this.providers[providerIndex].models.filter((_, i) => i !== modelIndex);
        if (remainingModels.length > 0) {
          this.activeModelId = remainingModels[0].id;
        }
      }

      // 删除模型
      const newProviders = [...this.providers];
      newProviders[providerIndex].models.splice(modelIndex, 1);
      this.providers = newProviders;

      try {
        await this.persistSettingsSilently();
        this.showToast('模型已删除并保存');
      } catch (error) {
        console.error('Failed to save after deleting model:', error);
        this.showToast('保存设置失败');
      }
    }
  }

  // 测试服务商连接
  async testProviderConnection(provider: AIProvider) {
    if (!provider.apiUrl || !provider.apiKey || provider.models.length === 0) {
      this.showToast('请先完善服务商配置');
      return;
    }

    this.isTesting = true;

    try {
      // 优先使用当前激活服务商对应的激活模型；否则回退到该服务商的第一个模型
      let testModel: AIModel | undefined = undefined;
      if (provider.id === this.activeProviderId && this.activeModelId) {
        testModel = provider.models.find(m => m.id === this.activeModelId);
      }
      if (!testModel) {
        testModel = provider.models[0];
      }

      if (!testModel || !testModel.name || testModel.name.trim().length === 0) {
        this.showToast('模型ID无效，请检查模型设置');
        return;
      }

      if (!provider.apiUrl.startsWith('http')) {
        this.showToast('API地址格式不正确，应以 http/https 开头');
        return;
      }

      const testMessage = new ChatMessage('Hello', 'user', {
        conversationId: 'test'
      });
      await this.networkManager.sendChatRequest(
        provider.apiUrl,
        provider.apiKey,
        testModel.name,
        [testMessage]
      );

      this.showToast('连接测试成功！');
    } catch (error) {
      const normalizedError = this.ensureError(error as ErrorInput);
      console.error('Connection test failed:', normalizedError);
      const msg = (normalizedError.message || '').toLowerCase();
      if (msg.includes('401') || msg.includes('unauthorized') || msg.includes('forbidden') || msg.includes('invalid api')) {
        this.showToast('API密钥无效，请检查设置');
      } else if (msg.includes('404') || msg.includes('not found')) {
        this.showToast('API地址无效，请检查是否为“基地址或兼容地址”');
      } else if (msg.includes('timeout') || msg.includes('超时')) {
        this.showToast('请求超时，请稍后重试');
      } else if (msg.includes('network') || msg.includes('网络') || msg.includes('connection')) {
        this.showToast('网络连接失败，请检查网络设置');
      } else if (msg.includes('model') && (msg.includes('not found') || msg.includes('unknown') || msg.includes('does not exist'))) {
        this.showToast('模型不可用或模型ID错误');
      } else {
        this.showToast('连接测试失败');
      }
    } finally {
      this.isTesting = false;
    }
  }

  @Builder
  SettingsSheetBuilder() {
    if (this.activeSheetType === 'provider' && this.providerDraft) {
      ProviderSettingsDialog({
        provider: this.providerDraft,
        isEditMode: this.providerEditIndex >= 0,
        onConfirm: (provider: AIProvider) => {
          this.handleProviderConfirm(provider);
        }
      })
    } else if (this.activeSheetType === 'model' && this.modelDraft) {
      ModelSettingsDialog({
        model: this.modelDraft,
        isEditMode: this.modelEditIndex >= 0,
        onConfirm: (model: AIModel) => {
          this.handleModelConfirm(model);
        }
      })
    } else {
      Column().width('100%').height(1);
    }
  }

  build() {
    NavDestination() {
      Column() {
        if (this.providers.length === 0) {
          // 空状态
          Column() {
            Text('还没有配置AI服务商')
              .fontSize(16)
              .margin({ top: 16 })

            Button('添加服务商')
              .fontSize(16)
              .fontColor($r('app.color.text_color'))
              .backgroundColor($r('sys.color.button_background_color_transparent'))
              .border({
                width: 1
              })
              .borderRadius(24)
              .padding({ left: 24, right: 24 })
              .height(48)
              .margin({ top: 24 })
              .onClick(() => {
                this.addProvider();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 使用原生Tabs组件
          Tabs({ barPosition: BarPosition.Start, index: this.currentProviderIndex }) {
            ForEach(this.providers, (provider: AIProvider, index: number) => {
              TabContent() {
                this.ProviderContent(provider, index)
              }
              .tabBar(provider.displayName)
            })
          }
          .layoutWeight(1)
          .barMode(BarMode.Scrollable) // 可滚动的页签
          .onChange((index: number) => {
            this.currentProviderIndex = index;
          })
        }
      }
      .bindSheet(this.isSettingsSheetVisible, this.SettingsSheetBuilder(), {
        height: SheetSize.FIT_CONTENT,
        detents: [SheetSize.FIT_CONTENT],
        blurStyle: BlurStyle.Thick,
        showClose: true,
        enableOutsideInteractive: false,
        dragBar: true,
        onDisappear: () => {
          this.isSettingsSheetVisible = false;
          this.resetSheetState();
        }
      })
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.common_background'))
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    })
    .title('模型提供方')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }

  @Builder
  ProviderContent(provider: AIProvider, providerIndex: number) {
    Scroll() {
      Column({ space: 24 }) {
        // 模型列表
        Column({ space: 16 }) {
          Row() {
            Text('模型列表')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)

            Blank()

            Button('添加模型')
              .fontSize(14)
              .fontColor($r('app.color.text_color'))
              .backgroundColor($r('sys.color.button_background_color_transparent'))
              .border({
                width: 1
              })
              .borderRadius(16)
              .padding({ left: 16, right: 16 })
              .height(32)
              .onClick(() => {
                this.addModel(providerIndex);
              })
          }
          .width('100%')

          if (provider.models.length === 0) {
            Text('还没有配置模型')
              .fontSize(14)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(24)
          } else {
            ForEach(provider.models, (model: AIModel, modelIndex: number) => {
              this.ModelItem(model, provider.id, providerIndex, modelIndex)
            })
          }
        }
        .width('100%')
        .padding(16)
        .borderRadius(12)

        // 测试连接按钮
        if (provider.apiUrl && provider.apiKey && provider.models.length > 0) {
          Button(this.isTesting ? '测试中...' : '测试连接')
            .fontColor($r('app.color.text_color'))
            .width('100%')
            .height(48)
            .fontSize(16)
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .border({
              width: 1
            })
            .borderRadius(24)
            .enabled(!this.isTesting)
            .onClick(() => {
              this.testProviderConnection(provider);
            })
        }

        // 操作按钮
        Row({ space: 12 }) {
          Button('编辑服务商')
            .fontColor($r('app.color.text_color'))
            .layoutWeight(1)
            .height(48)
            .fontSize(16)
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .border({
              width: 1
            })
            .borderRadius(24)
            .onClick(() => {
              this.editProvider(providerIndex);
            })

          if (this.providers.length > 1) {
            Button('删除服务商')
              .fontColor($r('app.color.text_color'))
              .layoutWeight(1)
              .height(48)
              .fontSize(16)
              .backgroundColor($r('sys.color.button_background_color_transparent'))
              .border({
                width: 1
              })
              .borderRadius(24)
              .onClick(() => {
                const targetName = provider.displayName || provider.name || provider.id || '该服务商';
                NativeDialogHelper.showDeleteConfirmDialog(
                  targetName,
                  '此操作无法撤销，服务商及其模型配置将永久删除。',
                  () => {
                    this.deleteProvider(providerIndex).catch((error: Error) => {
                      console.error('Failed to delete provider after confirmation:', error);
                    });
                  }
                );
              })
          }
        }
        .width('100%')
        .margin({ bottom: 12 })

        Button('新建服务商')
          .fontColor($r('app.color.text_color'))
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor($r('sys.color.button_background_color_transparent'))
          .border({
            width: 1
          })
          .borderRadius(24)
          .onClick(() => {
            this.addProvider();
          })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start) // 从上对齐
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart) // 确保内容从顶部开始
  }

  @Builder
  ModelItem(model: AIModel, providerId: string, providerIndex: number, modelIndex: number) {
    Row() {
      Column() {
        Row() {
          Text(model.displayName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1) // 让文本占据剩余空间但不超出

          if (providerId === this.activeProviderId && model.id === this.activeModelId) {
            Text('使用中')
              .fontColor($r('app.color.text_color'))
              .fontSize(12)
              .border({
                width: 1,
              })
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
              .margin({ left: 8 })
              .flexShrink(0) // 防止压缩
          }
        }
        .width('100%')

        Text(`ID: ${model.name} | 最大Token: ${model.maxTokens} | 温度: ${model.temperature}`)
          .fontSize(12)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        if (providerId !== this.activeProviderId || model.id !== this.activeModelId) {
          Button('使用')
            .fontSize(12)
            .fontColor($r('app.color.text_color'))
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .border({
              width: 1
            })
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .height(28)
            .flexShrink(0) // 防止按钮被压缩
            .onClick(async () => {
              const switched = await this.setActiveProvider(providerId, model.id);
              if (switched) {
                this.showToast(`已切换到 ${model.displayName}`);
              }
            })
        }

        Button('编辑')
          .fontSize(12)
          .fontColor($r('app.color.text_color'))
          .backgroundColor($r('sys.color.button_background_color_transparent'))
          .border({
            width: 1
          })
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .height(28)
          .flexShrink(0) // 防止按钮被压缩
          .onClick(() => {
            this.editModel(providerIndex, modelIndex);
          })

        // 只有当服务商有多个模型时才显示删除按钮
        if (this.providers[providerIndex]?.models.length > 1) {
          Button('删除')
            .fontColor($r('app.color.text_color'))
            .fontSize(12)
            .backgroundColor($r('sys.color.button_background_color_transparent'))
            .border({
              width: 1
            })
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .height(28)
            .flexShrink(0) // 防止按钮被压缩
            .onClick(async () => {
              // 显示删除确认对话框
              NativeDialogHelper.showDeleteConfirmDialog(
                `删除模型"${model.displayName}"`,
                '此操作无法撤销，模型配置将永久删除。',
                async () => {
                  await this.deleteModel(providerIndex, modelIndex);
                }
              );
            })
        }
      }
      .flexShrink(0) // 防止整个按钮区域被压缩
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(8)
    .margin({ bottom: 8 })
    .onClick(() => {
      if (providerId !== this.activeProviderId || model.id !== this.activeModelId) {
        this.setActiveProvider(providerId, model.id).then((switched: boolean) => {
          if (switched) {
            this.showToast(`已切换到 ${model.displayName}`);
          }
        });
      }
    })
  }
}
