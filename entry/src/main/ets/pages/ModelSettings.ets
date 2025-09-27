import promptAction from '@ohos.promptAction';
import { AIProvider, AIModel, AppSettings, ChatMessage } from '../services/DataModels';
import { DatabaseManager } from '../services/DatabaseManager';
import { NetworkManager } from '../services/NetworkManager';

function deepCloneModel(model: AIModel): AIModel {
  return new AIModel(model.id, model.name, model.displayName, model.maxTokens, model.temperature);
}

function deepCloneProvider(provider: AIProvider): AIProvider {
  const cloned = new AIProvider(provider.id, provider.name, provider.displayName, provider.apiUrl, provider.apiKey);
  cloned.models = provider.models.map(item => deepCloneModel(item));
  cloned.isActive = provider.isActive;
  return cloned;
}

function showToastSafely(message: string): void {
  try {
    promptAction.showToast({ message });
  } catch (error) {
    console.warn('Toast display failed:', error);
  }
}

type DialogMode = 'create' | 'edit';

interface ProviderDraft {
  id: string;
  name: string;
  displayName: string;
  apiUrl: string;
  apiKey: string;
}

interface ModelDraft {
  id: string;
  displayName: string;
  maxTokens: string;
  temperature: string;
}

interface DeleteModelContext {
  providerIndex: number;
  modelIndex: number;
  modelName: string;
}

function createProviderDraft(initial?: AIProvider | null): ProviderDraft {
  if (!initial) {
    return {
      id: '',
      name: '',
      displayName: '',
      apiUrl: '',
      apiKey: ''
    };
  }

  return {
    id: initial.id,
    name: initial.name,
    displayName: initial.displayName,
    apiUrl: initial.apiUrl,
    apiKey: initial.apiKey
  };
}

function createModelDraft(initial?: AIModel | null): ModelDraft {
  if (!initial) {
    return {
      id: '',
      displayName: '',
      maxTokens: '4096',
      temperature: '0.7'
    };
  }

  return {
    id: initial.id,
    displayName: initial.displayName,
    maxTokens: initial.maxTokens.toString(),
    temperature: initial.temperature.toString()
  };
}

// 跳转页面入口函数
@Builder
export function ModelSettingsBuilder() {
  ModelSettings();
}
@Entry
@Component
struct ModelSettings {
  @State providers: AIProvider[] = [];
  @State currentProviderIndex: number = 0;
  @State activeProviderId: string = '';
  @State activeModelId: string = '';
  @State isLoading: boolean = false;
  @State testingProviderId: string = '';

  private databaseManager = DatabaseManager.getInstance();
  private networkManager = NetworkManager.getInstance();
  @State private showProviderDialog: boolean = false;
  @State private providerDialogMode: DialogMode = 'create';
  @State private providerDialogIndex: number = -1;
  @State private providerDraft: ProviderDraft = createProviderDraft();
  private providerDialogInitialModels: AIModel[] = [];
  private providerDialogWasActive: boolean = false;

  @State private showModelDialog: boolean = false;
  @State private modelDialogMode: DialogMode = 'create';
  @State private modelDialogProviderIndex: number = -1;
  @State private modelDialogIndex: number = -1;
  @State private modelDraft: ModelDraft = createModelDraft();
  private modelDialogWasActive: boolean = false;

  @State private deleteModelContext: DeleteModelContext | null = null;

  async aboutToAppear() {
    await this.loadSettings();
  }

  private async loadSettings(): Promise<void> {
    this.isLoading = true;
    try {
      const settings = await this.databaseManager.getSettings();
      if (settings && settings.providers.length > 0) {
        const clonedProviders = settings.providers.map(item => deepCloneProvider(item));
        this.providers = clonedProviders;
        const preferredProviderId = settings.activeProviderId && clonedProviders.some(provider => provider.id === settings.activeProviderId)
          ? settings.activeProviderId
          : clonedProviders[0].id;
        this.updateActiveState(preferredProviderId, settings.activeModelId);
      } else {
        await this.initializeDefaultProviders();
      }
    } catch (error) {
      console.error('Failed to load settings:', error);
      showToastSafely('加载设置失败，已恢复默认配置');
      await this.initializeDefaultProviders();
    } finally {
      this.isLoading = false;
    }
  }

  private async initializeDefaultProviders(): Promise<void> {
    const openaiProvider = new AIProvider('default_openai', 'openai', 'OpenAI', 'https://api.openai.com/v1', '');
    openaiProvider.models = [
      new AIModel('gpt-3.5-turbo', 'gpt-3.5-turbo', 'GPT-3.5 Turbo', 4096, 0.7),
      new AIModel('gpt-4', 'gpt-4', 'GPT-4', 8192, 0.7)
    ];
    openaiProvider.isActive = true;

    this.providers = [openaiProvider];
    this.updateActiveState(openaiProvider.id, openaiProvider.models[0]?.id ?? '');
    await this.autoSaveSettings();
  }

  private async autoSaveSettings(): Promise<void> {
    try {
      const settings = new AppSettings();
      settings.providers = this.providers.map(provider => deepCloneProvider(provider));
      settings.activeProviderId = this.activeProviderId;
      settings.activeModelId = this.activeModelId;

      const activeProvider = this.providers.find(provider => provider.id === this.activeProviderId);
      if (activeProvider) {
        settings.apiUrl = activeProvider.apiUrl;
        settings.apiKey = activeProvider.apiKey;
        const activeModel = activeProvider.models.find(model => model.id === this.activeModelId);
        if (activeModel) {
          settings.modelName = activeModel.name;
        }
      }

      await this.databaseManager.saveSettings(settings);
      console.info('Settings auto-saved successfully');
    } catch (error) {
      console.error('Failed to auto-save settings:', error);
    }
  }

  private cloneProvidersList(): AIProvider[] {
    return this.providers.map(provider => deepCloneProvider(provider));
  }

  private updateProviderDraft(update: Partial<ProviderDraft>): void {
    const current = this.providerDraft;
    const next: ProviderDraft = {
      id: update.id !== undefined ? update.id : current.id,
      name: update.name !== undefined ? update.name : current.name,
      displayName: update.displayName !== undefined ? update.displayName : current.displayName,
      apiUrl: update.apiUrl !== undefined ? update.apiUrl : current.apiUrl,
      apiKey: update.apiKey !== undefined ? update.apiKey : current.apiKey
    };
    this.providerDraft = next;
  }

  private updateModelDraft(update: Partial<ModelDraft>): void {
    const current = this.modelDraft;
    const next: ModelDraft = {
      id: update.id !== undefined ? update.id : current.id,
      displayName: update.displayName !== undefined ? update.displayName : current.displayName,
      maxTokens: update.maxTokens !== undefined ? update.maxTokens : current.maxTokens,
      temperature: update.temperature !== undefined ? update.temperature : current.temperature
    };
    this.modelDraft = next;
  }
  private isProviderUnderTest(providerId: string): boolean {
    return this.testingProviderId === providerId;
  }

  private isModelActive(providerId: string, modelId: string): boolean {
    return this.activeProviderId === providerId && this.activeModelId === modelId;
  }

  private updateActiveState(providerId: string, modelId?: string): void {
    if (this.providers.length === 0) {
      this.activeProviderId = '';
      this.activeModelId = '';
      this.currentProviderIndex = 0;
      return;
    }

    let resolvedProviderId = providerId;
    const providersCopy = this.providers.map(provider => deepCloneProvider(provider));
    let activeProvider = providersCopy.find(provider => provider.id === resolvedProviderId);

    if (!activeProvider && providersCopy.length > 0) {
      activeProvider = providersCopy[0];
      resolvedProviderId = activeProvider.id;
    }

    let resolvedModelId = modelId;
    if (activeProvider) {
      if (!resolvedModelId || !activeProvider.models.some(model => model.id === resolvedModelId)) {
        resolvedModelId = activeProvider.models[0]?.id ?? '';
      }
    } else {
      resolvedModelId = '';
    }

    providersCopy.forEach(provider => {
      provider.isActive = provider.id === resolvedProviderId;
    });

    this.providers = providersCopy;
    this.activeProviderId = resolvedProviderId;
    this.activeModelId = resolvedModelId ?? '';
    this.currentProviderIndex = Math.max(0, providersCopy.findIndex(provider => provider.id === resolvedProviderId));
  }

  private openProviderDialog(initialProvider: AIProvider | null, mode: DialogMode, providerIndex: number): void {
    const sourceProvider = initialProvider ? deepCloneProvider(initialProvider) : null;
    this.providerDialogMode = mode;
    this.providerDialogIndex = providerIndex;
    this.providerDraft = createProviderDraft(sourceProvider);
    this.providerDialogInitialModels = sourceProvider ? sourceProvider.models.map(item => deepCloneModel(item)) : [];
    this.providerDialogWasActive = sourceProvider ? sourceProvider.isActive : false;
    this.showProviderDialog = true;
  }

  private closeProviderDialog(): void {
    this.showProviderDialog = false;
    this.providerDialogIndex = -1;
    this.providerDialogInitialModels = [];
    this.providerDialogWasActive = false;
  }

  private async confirmProviderDialog(): Promise<void> {
    const draft = this.providerDraft;
    const trimmedId = draft.id.trim();
    if (!trimmedId) {
      showToastSafely('请输入服务商ID');
      return;
    }

    const trimmedApiUrl = draft.apiUrl.trim();
    if (!trimmedApiUrl) {
      showToastSafely('请输入API地址');
      return;
    }

    const internalName = draft.name.trim() || trimmedId;
    const displayName = draft.displayName.trim() || internalName;

    if (this.providerDialogMode === 'create') {
      if (this.providerIdExists(trimmedId)) {
        showToastSafely('服务商ID已存在，请使用其他ID');
        return;
      }
    } else if (this.providerDialogMode === 'edit') {
      if (this.providerDialogIndex < 0 || this.providerDialogIndex >= this.providers.length) {
        return;
      }
      if (this.providerIdExists(trimmedId, this.providerDialogIndex)) {
        showToastSafely('服务商ID已存在，请使用其他ID');
        return;
      }
    }

    const provider = new AIProvider(trimmedId, internalName, displayName, trimmedApiUrl, draft.apiKey.trim());
    provider.models = this.providerDialogInitialModels.map(item => deepCloneModel(item));
    provider.isActive = this.providerDialogMode === 'edit' ? this.providerDialogWasActive : false;

    if (this.providerDialogMode === 'create') {
      const providersCopy = this.cloneProvidersList();
      providersCopy.push(provider);
      this.providers = providersCopy;

      if (providersCopy.length === 1) {
        this.updateActiveState(provider.id, provider.models[0]?.id ?? '');
      }

      await this.autoSaveSettings();
      showToastSafely('服务商已添加并保存');
    } else {
      const providersCopy = this.cloneProvidersList();
      const index = this.providerDialogIndex;
      const wasActive = providersCopy[index].id === this.activeProviderId;
      provider.isActive = wasActive;
      providersCopy[index] = provider;
      this.providers = providersCopy;

      if (wasActive) {
        this.updateActiveState(provider.id, this.activeModelId);
      } else {
        await this.autoSaveSettings();
      }

      showToastSafely('服务商已修改并保存');
    }

    this.closeProviderDialog();
  }

  private openModelDialog(providerIndex: number, initialModel: AIModel | null, mode: DialogMode, modelIndex: number): void {
    const sourceModel = initialModel ? deepCloneModel(initialModel) : null;
    this.modelDialogMode = mode;
    this.modelDialogProviderIndex = providerIndex;
    this.modelDialogIndex = modelIndex;
    this.modelDraft = createModelDraft(sourceModel);
    if (sourceModel && providerIndex >= 0 && providerIndex < this.providers.length) {
      const provider = this.providers[providerIndex];
      this.modelDialogWasActive = provider.id === this.activeProviderId && sourceModel.id === this.activeModelId;
    } else {
      this.modelDialogWasActive = false;
    }
    this.showModelDialog = true;
  }

  private closeModelDialog(): void {
    this.showModelDialog = false;
    this.modelDialogProviderIndex = -1;
    this.modelDialogIndex = -1;
    this.modelDialogWasActive = false;
  }

  private async confirmModelDialog(): Promise<void> {
    if (this.modelDialogProviderIndex < 0 || this.modelDialogProviderIndex >= this.providers.length) {
      return;
    }

    const draft = this.modelDraft;
    const id = draft.id.trim();
    if (!id) {
      showToastSafely('请输入模型ID');
      return;
    }

    const displayName = draft.displayName.trim() || id;
    const maxTokens = Number.parseInt(draft.maxTokens, 10);
    if (!Number.isFinite(maxTokens) || maxTokens <= 0) {
      showToastSafely('请填写合法的最大Token数量');
      return;
    }

    let temperature = Number.parseFloat(draft.temperature);
    if (!Number.isFinite(temperature)) {
      temperature = 0.7;
    }
    temperature = Math.min(Math.max(temperature, 0), 2);

    const provider = this.providers[this.modelDialogProviderIndex];

    if (this.modelDialogMode === 'create') {
      if (provider.models.some(existing => existing.id === id)) {
        showToastSafely('模型ID已存在，请使用其他ID');
        return;
      }
    } else if (this.modelDialogMode === 'edit') {
      if (this.modelDialogIndex < 0 || this.modelDialogIndex >= provider.models.length) {
        return;
      }
      if (provider.models.some((existing, idx) => idx !== this.modelDialogIndex && existing.id === id)) {
        showToastSafely('模型ID已存在，请使用其他ID');
        return;
      }
    }

    const model = new AIModel(id, id, displayName, maxTokens, temperature);

    const providersCopy = this.cloneProvidersList();
    const targetProvider = providersCopy[this.modelDialogProviderIndex];

    if (this.modelDialogMode === 'create') {
      targetProvider.models.push(model);
      this.providers = providersCopy;
      await this.autoSaveSettings();
      showToastSafely('模型已添加并保存');
    } else {
      const wasActive = this.modelDialogWasActive;
      targetProvider.models[this.modelDialogIndex] = model;
      this.providers = providersCopy;

      if (wasActive) {
        await this.handleSetActiveModel(targetProvider.id, model.id, `已切换到 ${model.displayName}`);
      } else {
        await this.autoSaveSettings();
      }

      showToastSafely('模型已修改并保存');
    }

    this.closeModelDialog();
  }

  private openDeleteModelDialog(providerIndex: number, modelIndex: number, modelName: string): void {
    this.deleteModelContext = { providerIndex, modelIndex, modelName };
  }

  private closeDeleteModelDialog(): void {
    this.deleteModelContext = null;
  }

  private async confirmDeleteModel(): Promise<void> {
    if (!this.deleteModelContext) {
      return;
    }

  const providerIndex = this.deleteModelContext.providerIndex;
  const modelIndex = this.deleteModelContext.modelIndex;
  await this.performDeleteModel(providerIndex, modelIndex);
    this.closeDeleteModelDialog();
  }

  private providerIdExists(id: string, ignoreIndex: number = -1): boolean {
    return this.providers.some((provider, index) => provider.id === id && index !== ignoreIndex);
  }

  addProvider() {
    this.openProviderDialog(null, 'create', -1);
  }

  editProvider(index: number) {
    if (index < 0 || index >= this.providers.length) {
      return;
    }

    const originalProvider = this.providers[index];
    this.openProviderDialog(originalProvider, 'edit', index);
  }

  async deleteProvider(index: number) {
    if (this.providers.length <= 1) {
      showToastSafely('至少保留一个服务商');
      return;
    }
    if (index < 0 || index >= this.providers.length) {
      return;
    }

    const providersCopy = this.cloneProvidersList();
    const removedProvider = providersCopy.splice(index, 1)[0];
    this.providers = providersCopy;

    if (providersCopy.length > 0) {
      if (removedProvider.id === this.activeProviderId) {
        const fallbackProvider = providersCopy[0];
        this.updateActiveState(fallbackProvider.id, fallbackProvider.models[0]?.id ?? '');
      } else {
        this.updateActiveState(this.activeProviderId, this.activeModelId);
      }
    } else {
      this.updateActiveState('', '');
    }

    await this.autoSaveSettings();
    showToastSafely('服务商已删除并保存');
  }

  setActiveProvider(providerId: string, modelId: string) {
    this.handleSetActiveModel(providerId, modelId, undefined);
  }

  private async handleSetActiveModel(providerId: string, modelId: string, toastMessage?: string) {
    this.updateActiveState(providerId, modelId);
    await this.autoSaveSettings();
    if (toastMessage) {
      showToastSafely(toastMessage);
    }
  }

  addModel(providerIndex: number) {
    if (providerIndex < 0 || providerIndex >= this.providers.length) {
      return;
    }

    this.openModelDialog(providerIndex, null, 'create', -1);
  }

  editModel(providerIndex: number, modelIndex: number) {
    if (providerIndex < 0 || providerIndex >= this.providers.length) {
      return;
    }
    const provider = this.providers[providerIndex];
    if (modelIndex < 0 || modelIndex >= provider.models.length) {
      return;
    }

    const originalModel = provider.models[modelIndex];
    this.openModelDialog(providerIndex, originalModel, 'edit', modelIndex);
  }

  private async performDeleteModel(providerIndex: number, modelIndex: number): Promise<void> {
    if (providerIndex < 0 || providerIndex >= this.providers.length) {
      return;
    }

    const provider = this.providers[providerIndex];
    if (provider.models.length <= 1) {
      showToastSafely('至少保留一个模型');
      throw new Error('last_model');
    }
    if (modelIndex < 0 || modelIndex >= provider.models.length) {
      return;
    }

    const providersCopy = this.cloneProvidersList();
    const targetProvider = providersCopy[providerIndex];
    const removedModel = targetProvider.models.splice(modelIndex, 1)[0];
    this.providers = providersCopy;

    if (targetProvider.id === this.activeProviderId && removedModel.id === this.activeModelId) {
      const fallbackModelId = targetProvider.models[0]?.id ?? '';
      await this.handleSetActiveModel(targetProvider.id, fallbackModelId);
    } else {
      await this.autoSaveSettings();
    }

    showToastSafely('模型已删除并保存');
  }

  async testProviderConnection(provider: AIProvider) {
    if (!provider.apiUrl || !provider.apiKey || provider.models.length === 0) {
      showToastSafely('请先完善服务商配置');
      return;
    }

    this.testingProviderId = provider.id;
    try {
      const testModel = provider.models[0];
      const testMessage = new ChatMessage('Hello', 'user', 'test');
      await this.networkManager.sendChatRequest(provider.apiUrl, provider.apiKey, testModel.name, [testMessage]);
      showToastSafely('连接测试成功');
    } catch (error) {
      console.error('Connection test failed:', error);
      showToastSafely(this.mapNetworkError(error as Error));
    } finally {
      this.testingProviderId = '';
    }
  }

  private mapNetworkError(error: Error): string {
    const message = error?.message ?? '';
    if (message.includes('401') || message.includes('403')) {
      return 'API密钥无效，请检查设置';
    }
    if (message.includes('404')) {
      return 'API地址无效，请检查设置';
    }
    if (message.includes('timeout')) {
      return '请求超时，请稍后再试';
    }
    if (message.includes('网络')) {
      return '网络连接失败，请检查网络设置';
    }
    return '连接测试失败';
  }

  @Builder
  private SettingsContent() {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text('模型与服务商配置')
            .fontSize(22)
            .fontWeight(FontWeight.Medium);
          Text('管理大模型服务商、API和模型参数')
            .fontSize(14)
            .fontColor(Color.Gray);
        };

        Blank();

        Button('新建服务商')
          .type(ButtonType.Capsule)
          .height(40)
          .padding({ left: 20, right: 20 })
          .onClick(() => this.addProvider());
      }
      .width('100%');

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .size({ width: 48, height: 48 });
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center);
      } else if (this.providers.length === 0) {
        Column({ space: 16 }) {
          Text('还没有配置AI服务商')
            .fontSize(16)
            .fontColor(Color.Gray);

          Button('添加服务商')
            .type(ButtonType.Capsule)
            .height(44)
            .padding({ left: 24, right: 24 })
            .onClick(() => this.addProvider());
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        Tabs({ barPosition: BarPosition.Start, index: this.currentProviderIndex }) {
          ForEach(this.providers, (provider: AIProvider, index: number) => {
            TabContent() {
              this.ProviderContent(provider, index);
            }
            .tabBar(provider.displayName);
          });
        }
        .layoutWeight(1)
        .barMode(BarMode.Scrollable)
        .onChange((index: number) => {
          this.currentProviderIndex = index;
        });
      }
    }
    .padding(16)
    .width('100%')
    .height('100%');
  }


  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.SettingsContent();
      if (this.showProviderDialog) {
        this.ProviderDialogOverlay();
      }
      if (this.showModelDialog) {
        this.ModelDialogOverlay();
      }
      if (this.deleteModelContext) {
        this.DeleteModelDialogOverlay(this.deleteModelContext);
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ProviderContent(provider: AIProvider, providerIndex: number) {
    Scroll() {
      Column({ space: 20 }) {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('服务商信息')
              .fontSize(18)
              .fontWeight(FontWeight.Bold);

            if (provider.id === this.activeProviderId) {
              Text('使用中')
                .fontSize(12)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor('#1E007AFF')
                .borderRadius(12)
                .fontColor(Color.Blue);
            }
          }

          Text(`API 地址：${provider.apiUrl || '未设置'}`)
            .fontSize(14)
            .fontColor(Color.Gray);

          Text(`API Key：${provider.apiKey ? '已设置' : '未设置'}`)
            .fontSize(14)
            .fontColor(Color.Gray);
        }
        .width('100%')
        .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12);

        Column({ space: 16 }) {
          Row() {
            Text('模型列表')
              .fontSize(18)
              .fontWeight(FontWeight.Bold);

            Blank();

            Button('添加模型')
              .fontSize(14)
              .height(32)
              .type(ButtonType.Capsule)
              .onClick(() => this.addModel(providerIndex));
          }
          .width('100%');

          if (provider.models.length === 0) {
            Text('还没有配置模型')
              .fontSize(14)
              .fontColor(Color.Gray)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(24);
          } else {
            ForEach(provider.models, (model: AIModel, modelIndex: number) => {
              this.ModelItem(model, provider, providerIndex, modelIndex);
            });
          }
        }
        .width('100%')
        .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12);

        Row({ space: 12 }) {
          Button(this.isProviderUnderTest(provider.id) ? '测试中...' : '测试连接')
            .layoutWeight(1)
            .height(44)
            .type(ButtonType.Capsule)
            .enabled(!this.isProviderUnderTest(provider.id))
            .onClick(() => this.testProviderConnection(provider));

          Button('编辑服务商')
            .layoutWeight(1)
            .height(44)
            .type(ButtonType.Capsule)
            .onClick(() => this.editProvider(providerIndex));

          if (this.providers.length > 1) {
            Button('删除')
              .layoutWeight(1)
              .height(44)
              .type(ButtonType.Capsule)
              .fontColor(Color.Red)
              .border({ width: 1, color: Color.Red })
              .backgroundColor(Color.Transparent)
              .onClick(async () => await this.deleteProvider(providerIndex));
          }
        }
        .width('100%');
      }
      .width('100%')
      .padding({ bottom: 24 });
    }
    .width('100%')
    .align(Alignment.TopStart);
  }

  @Builder
  private ModelItem(model: AIModel, provider: AIProvider, providerIndex: number, modelIndex: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column() {
          Row({ space: 8 }) {
            Text(model.displayName)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });

            if (this.isModelActive(provider.id, model.id)) {
              Text('使用中')
                .fontSize(12)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor('#1E007AFF')
                .borderRadius(12)
                .fontColor(Color.Blue);
            }
          }

          Text(`ID: ${model.name}`)
            .fontSize(12)
            .fontColor(Color.Gray)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Text(`Tokens: ${model.maxTokens} · Temperature: ${model.temperature}`)
            .fontSize(12)
            .fontColor(Color.Gray);
        }
        .layoutWeight(1);

        Row({ space: 8 }) {
          if (!this.isModelActive(provider.id, model.id)) {
            Button('使用')
              .fontSize(12)
              .height(32)
              .onClick(async () => await this.handleSetActiveModel(provider.id, model.id, `已切换到 ${model.displayName}`));
          }

          Button('编辑')
            .fontSize(12)
            .height(32)
            .onClick(() => this.editModel(providerIndex, modelIndex));

          if (provider.models.length > 1) {
            Button('删除')
              .fontSize(12)
              .height(32)
              .fontColor(Color.Red)
              .border({ width: 1, color: Color.Red })
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.openDeleteModelDialog(providerIndex, modelIndex, model.displayName);
              });
          }
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#0C000000')
    .borderRadius(12)
    .onClick(async () => {
      if (!this.isModelActive(provider.id, model.id)) {
        await this.handleSetActiveModel(provider.id, model.id, `已切换到 ${model.displayName}`);
      }
    });
  }

  @Builder
  private ProviderDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.45)')
        .onClick(() => this.closeProviderDialog());

      Column({ space: 0 }) {
        this.ProviderDialogCard();
      }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ProviderDialogCard() {
    Column({ space: 20 }) {
      Text(this.providerDialogMode === 'edit' ? '编辑服务商' : '新建服务商')
        .fontSize(20)
        .fontWeight(FontWeight.Medium);

      Column({ space: 12 }) {
        Text('服务商ID')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '请输入服务商ID', text: this.providerDraft.id })
          .onChange(value => this.updateProviderDraft({ id: value }));
      }

      Column({ space: 12 }) {
        Text('内部名称（可选）')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '用于标识服务商的内部名称', text: this.providerDraft.name })
          .onChange(value => this.updateProviderDraft({ name: value }));
      }

      Column({ space: 12 }) {
        Text('显示名称')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '在界面上显示的名称', text: this.providerDraft.displayName })
          .onChange(value => this.updateProviderDraft({ displayName: value }));
      }

      Column({ space: 12 }) {
        Text('API 地址')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: 'https://', text: this.providerDraft.apiUrl })
          .onChange(value => this.updateProviderDraft({ apiUrl: value }));
      }

      Column({ space: 12 }) {
        Text('API Key')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '请输入API Key', text: this.providerDraft.apiKey })
          .onChange(value => this.updateProviderDraft({ apiKey: value }));
      }

      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: Color.Gray })
          .fontColor(Color.Gray)
          .onClick(() => this.closeProviderDialog());

        Button(this.providerDialogMode === 'edit' ? '保存' : '创建')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .onClick(async () => await this.confirmProviderDialog());
      }
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .width('90%');
  }

  @Builder
  private ModelDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.45)')
        .onClick(() => this.closeModelDialog());

      Column({ space: 0 }) {
        this.ModelDialogCard();
      }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ModelDialogCard() {
    Column({ space: 20 }) {
      Text(this.modelDialogMode === 'edit' ? '编辑模型' : '添加模型')
        .fontSize(20)
        .fontWeight(FontWeight.Medium);

      Column({ space: 12 }) {
        Text('模型ID')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '例如 gpt-4', text: this.modelDraft.id })
          .onChange(value => this.updateModelDraft({ id: value }));
      }

      Column({ space: 12 }) {
        Text('显示名称')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '例如 GPT-4', text: this.modelDraft.displayName })
          .onChange(value => this.updateModelDraft({ displayName: value }));
      }

      Column({ space: 12 }) {
        Text('最大Token数量')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '4096', text: this.modelDraft.maxTokens })
          .onChange(value => this.updateModelDraft({ maxTokens: value }));
      }

      Column({ space: 12 }) {
        Text('Temperature (0-2)')
          .fontSize(14)
          .fontColor(Color.Gray);
        TextInput({ placeholder: '0.7', text: this.modelDraft.temperature })
          .onChange(value => this.updateModelDraft({ temperature: value }));
      }

      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: Color.Gray })
          .fontColor(Color.Gray)
          .onClick(() => this.closeModelDialog());

        Button(this.modelDialogMode === 'edit' ? '保存' : '添加')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .onClick(async () => await this.confirmModelDialog());
      }
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .width('90%');
  }

  @Builder
  private DeleteModelDialogOverlay(context: DeleteModelContext) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.45)')
        .onClick(() => this.closeDeleteModelDialog());

      Column({ space: 0 }) {
        this.DeleteModelDialogCard(context.modelName);
      }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private DeleteModelDialogCard(modelName: string) {
    Column({ space: 20 }) {
      Text('删除模型')
        .fontSize(20)
        .fontWeight(FontWeight.Medium);

      Text(`确定要删除模型 “${modelName}” 吗？此操作无法撤销。`)
        .fontSize(14)
        .fontColor(Color.Gray);

      Row({ space: 16 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: Color.Gray })
          .fontColor(Color.Gray)
          .onClick(() => this.closeDeleteModelDialog());

        Button('删除')
          .layoutWeight(1)
          .height(44)
          .type(ButtonType.Capsule)
          .backgroundColor(Color.Red)
          .fontColor(Color.White)
          .onClick(async () => await this.confirmDeleteModel());
      }
    }
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .width('90%');
  }
}

