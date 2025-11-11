import { Prompt } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SearchConfigManager, SearchConfig } from '../services/search/SearchConfigManager';
import { SearchServiceFactory } from '../services/search/SearchServiceFactory';
import {
  SearchServiceOptions,
  TavilyOptions,
  ExaOptions,
  ZhipuOptions,
  SearXNGOptions,
  BraveOptions,
  MetasoOptions,
  GoogleCustomSearchOptions,
  SearchCommonOptions
} from '../services/search/SearchModels';

const DOMAIN = 0x0001;
const TAG = 'SearchServices';

@Builder
export function SearchServicesBuilder() {
  SearchServices();
}

@Entry
@Component
struct SearchServices {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;

  @State config: SearchConfig = {
    enabledServices: [],
    selectedServiceIndex: 0,
    commonOptions: { resultSize: 10, timeout: 10000 },
    enableWebSearch: false,
    connectionStatus: {}
  };
  @State selectedIndex: number = 0;
  @State enableWebSearch: boolean = false;
  @State resultSize: number = 10;
  @State timeout: number = 10000;
  @State testingServiceId: string = '';
  @State connectionStatus: Record<string, boolean | null> = {};
  @State showAddServiceDialog: boolean = false;
  @State selectedServiceType: string = 'tavily';
  @State newServiceApiKey: string = '';
  @State newServiceUrl: string = '';
  @State newServiceEngines: string = '';
  @State newServiceLanguage: string = '';
  @State newServiceUsername: string = '';
  @State newServicePassword: string = '';
  @State newServiceSearchEngineId: string = '';

  private uiContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private configManager: SearchConfigManager = SearchConfigManager.getInstance();

  aboutToAppear(): void {
    this.loadConfig();
  }

  private loadConfig(): void {
    try {
      const config = this.configManager.getConfig();
      this.config = config;
      this.selectedIndex = config.selectedServiceIndex;
      this.enableWebSearch = config.enableWebSearch;
      this.resultSize = config.commonOptions.resultSize ?? 10;
      this.timeout = config.commonOptions.timeout ?? 10000;
      this.connectionStatus = config.connectionStatus ?? {};
      hilog.info(DOMAIN, TAG, 'Config loaded: %{public}d services', config.enabledServices.length);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load config: %{public}s', String(error));
      this.showToast('加载配置失败');
    }
  }

  private showToast(message: string): void {
    try {
      Prompt.showToast({ message, duration: 2000 });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to show toast: %{public}s', String(error));
    }
  }

  private getServiceName(service: SearchServiceOptions): string {
    switch (service.type) {
      case 'tavily': return 'Tavily';
      case 'exa': return 'Exa';
      case 'zhipu': return '智谱';
      case 'searxng': return 'SearXNG';
      case 'brave': return 'Brave';
      case 'metaso': return '秘塔';
      case 'google_custom_search': return 'Google Custom Search';
      default: return service.id;
    }
  }

  private getServiceDescription(service: SearchServiceOptions): string {
    switch (service.type) {
      case 'tavily': return '为 LLM 优化的 AI 搜索 API';
      case 'exa': return '神经搜索引擎';
      case 'zhipu': return '中文 AI 搜索服务';
      case 'searxng': return '隐私搜索引擎';
      case 'brave': return '独立搜索引擎';
      case 'metaso': return '中文搜索引擎';
      case 'google_custom_search': return '谷歌自定义搜索';
      default: return '搜索服务';
    }
  }

  private async handleAddService(): Promise<void> {
    try {
      // 自动生成服务 ID: 类型 + 时间戳
      const serviceId = `${this.selectedServiceType}_${Date.now()}`;
      let newService: SearchServiceOptions | null = null;

      switch (this.selectedServiceType) {
        case 'tavily':
          if (!this.newServiceApiKey.trim()) {
            this.showToast('请输入 API Key');
            return;
          }
          newService = new TavilyOptions(serviceId, this.newServiceApiKey);
          break;
        case 'exa':
          if (!this.newServiceApiKey.trim()) {
            this.showToast('请输入 API Key');
            return;
          }
          newService = new ExaOptions(serviceId, this.newServiceApiKey);
          break;
        case 'zhipu':
          if (!this.newServiceApiKey.trim()) {
            this.showToast('请输入 API Key');
            return;
          }
          newService = new ZhipuOptions(serviceId, this.newServiceApiKey);
          break;
        case 'searxng':
          if (!this.newServiceUrl.trim()) {
            this.showToast('请输入 SearXNG 实例 URL');
            return;
          }
          newService = new SearXNGOptions(
            serviceId,
            this.newServiceUrl,
            this.newServiceEngines,
            this.newServiceLanguage,
            this.newServiceUsername,
            this.newServicePassword
          );
          break;
        case 'brave':
          if (!this.newServiceApiKey.trim()) {
            this.showToast('请输入 API Key');
            return;
          }
          newService = new BraveOptions(serviceId, this.newServiceApiKey);
          break;
        case 'metaso':
          if (!this.newServiceApiKey.trim()) {
            this.showToast('请输入 API Key');
            return;
          }
          newService = new MetasoOptions(serviceId, this.newServiceApiKey);
          break;
        case 'google_custom_search':
          if (!this.newServiceApiKey.trim() || !this.newServiceSearchEngineId.trim()) {
            this.showToast('请输入 API Key 和搜索引擎 ID');
            return;
          }
          newService = new GoogleCustomSearchOptions(serviceId, this.newServiceApiKey, this.newServiceSearchEngineId);
          break;
      }

      if (newService) {
        await this.configManager.addService(newService);
        this.showToast('服务添加成功');
        this.resetServiceForm();
        this.showAddServiceDialog = false;
        this.loadConfig();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to add service: %{public}s', String(error));
      this.showToast(`添加服务失败: ${error}`);
    }
  }

  private resetServiceForm(): void {
    this.newServiceApiKey = '';
    this.newServiceUrl = '';
    this.newServiceEngines = '';
    this.newServiceLanguage = '';
    this.newServiceUsername = '';
    this.newServicePassword = '';
    this.newServiceSearchEngineId = '';
  }

  private async handleRemoveService(index: number): Promise<void> {
    try {
      if (this.config && index >= 0 && index < this.config.enabledServices.length) {
        const service = this.config.enabledServices[index];
        await this.configManager.removeService(service.id);
        this.showToast('服务已移除');
        this.loadConfig();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to remove service: %{public}s', String(error));
      this.showToast('移除服务失败');
    }
  }

  private async handleSelectService(index: number): Promise<void> {
    try {
      await this.configManager.setSelectedService(index);
      this.selectedIndex = index;
      this.showToast('已切换搜索服务');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to select service: %{public}s', String(error));
      this.showToast('切换服务失败');
    }
  }

  private async handleTestConnection(index: number): Promise<void> {
    let service: SearchServiceOptions | null = null;
    try {
      if (index < 0 || index >= this.config.enabledServices.length) return;

      service = this.config.enabledServices[index];
      this.testingServiceId = service.id;

      const searchService = SearchServiceFactory.getService(service);
      const result = await searchService.search(
        '测试',
        this.config.commonOptions,
        service
      );

      const statusMap: Record<string, boolean | null> = {};
      const keys: string[] = Object.keys(this.connectionStatus);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const val = this.connectionStatus[key];
        if (val !== null && val !== undefined) {
          statusMap[key] = val;
        }
      }
      statusMap[service.id] = true;
      this.connectionStatus = statusMap;
      this.showToast('连接成功');
    } catch (error) {
      if (service) {
        const statusMap: Record<string, boolean | null> = {};
        const keys2: string[] = Object.keys(this.connectionStatus);
        for (let i = 0; i < keys2.length; i++) {
          const key = keys2[i];
          const val = this.connectionStatus[key];
          if (val !== null && val !== undefined) {
            statusMap[key] = val;
          }
        }
        statusMap[service.id] = false;
        this.connectionStatus = statusMap;
      }
      hilog.error(DOMAIN, TAG, 'Connection test failed: %{public}s', String(error));
      this.showToast('连接失败');
    } finally {
      this.testingServiceId = '';
    }
  }

  private async handleUpdateSettings(): Promise<void> {
    try {
      await this.configManager.setCommonOptions({
        resultSize: this.resultSize,
        timeout: this.timeout
      });
      await this.configManager.setWebSearchEnabled(this.enableWebSearch);
      this.showToast('设置已保存');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update settings: %{public}s', String(error));
      this.showToast('保存设置失败');
    }
  }

  private getStatusColor(serviceId: string): string {
    const status = this.connectionStatus[serviceId];
    if (status === null || status === undefined) {
      return '#99999999';
    }
    return status ? '#00C800' : '#E63946';
  }

  private getStatusText(serviceId: string): string {
    if (this.testingServiceId === serviceId) {
      return '测试中...';
    }
    const status = this.connectionStatus[serviceId];
    if (status === null || status === undefined) {
      return '未测试';
    }
    return status ? '已连接' : '连接失败';
  }

  @Builder
  private BuildAddServiceDialog() {
    Column() {
      // 标题栏
      Row() {
        Text('添加搜索服务')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1);
        
        Image($r('sys.symbol.xmark'))
          .width(24)
          .height(24)
          .fillColor('#666666')
          .onClick(() => {
            this.showAddServiceDialog = false;
            this.resetServiceForm();
          });
      }
      .width('100%')
      .padding({ bottom: 16 });

      Scroll() {
        Column({ space: 12 }) {
          // 服务类型选择
          Text('服务类型')
            .fontSize(14)
            .fontWeight(FontWeight.Medium);
          
          Select([
            { value: 'Tavily' },
            { value: 'Exa' },
            { value: '智谱' },
            { value: 'SearXNG' },
            { value: 'Brave' },
            { value: '秘塔' },
            { value: 'Google Custom Search' }
          ])
            .value(this.selectedServiceType)
            .onSelect((index: number, value?: string | string[]) => {
              const types = ['tavily', 'exa', 'zhipu', 'searxng', 'brave', 'metaso', 'google_custom_search'];
              if (index >= 0 && index < types.length) {
                this.selectedServiceType = types[index];
              }
            })
            .width('100%');

          // 根据服务类型显示不同字段
          if (this.selectedServiceType === 'searxng') {
            // SearXNG 特殊字段
            Text('实例 URL')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: 'https://your-searxng-instance.com', text: this.newServiceUrl })
              .onChange((value) => { this.newServiceUrl = value; })
              .width('100%');

            Text('搜索引擎（可选）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: 'google,bing', text: this.newServiceEngines })
              .onChange((value) => { this.newServiceEngines = value; })
              .width('100%');

            Text('语言（可选）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: 'en', text: this.newServiceLanguage })
              .onChange((value) => { this.newServiceLanguage = value; })
              .width('100%');

            Text('用户名（可选）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: '用户名', text: this.newServiceUsername })
              .onChange((value) => { this.newServiceUsername = value; })
              .width('100%');

            Text('密码（可选）')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: '密码', text: this.newServicePassword })
              .type(InputType.Password)
              .onChange((value) => { this.newServicePassword = value; })
              .width('100%');
          } else if (this.selectedServiceType === 'google_custom_search') {
            // Google Custom Search 特殊字段
            Text('API Key')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: '输入 API Key', text: this.newServiceApiKey })
              .onChange((value) => { this.newServiceApiKey = value; })
              .width('100%');

            Text('搜索引擎 ID')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: '输入搜索引擎 ID', text: this.newServiceSearchEngineId })
              .onChange((value) => { this.newServiceSearchEngineId = value; })
              .width('100%');
          } else {
            // 其他服务的 API Key
            Text('API Key')
              .fontSize(14)
              .fontWeight(FontWeight.Medium);
            
            TextInput({ placeholder: '输入 API Key', text: this.newServiceApiKey })
              .onChange((value) => { this.newServiceApiKey = value; })
              .width('100%');
          }
        }
      }
      .layoutWeight(1)
      .padding({ bottom: 16 });

      // 按钮行
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => {
            this.showAddServiceDialog = false;
            this.resetServiceForm();
          });

        Button('添加')
          .layoutWeight(1)
          .type(ButtonType.Capsule)
          .backgroundColor('#FF6B35')
          .onClick(() => this.handleAddService());
      }
      .width('100%');
    }
    .padding(20)
    .width('100%')
    .backgroundColor(Color.White);
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            // 启用搜索开关
            Row() {
              Text('启用网络搜索')
                .fontSize(14);
              Blank();
              Toggle({ type: ToggleType.Switch, isOn: this.enableWebSearch })
                .onChange((isOn) => {
                  this.enableWebSearch = isOn;
                    this.handleUpdateSettings();
                  });
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#F5F5F5')
              .borderRadius(8);

              // 通用设置
              Column({ space: 8 }) {
                Text('通用设置')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold);

                Row() {
                  Text('返回结果数');
                  Blank();
                  Slider({
                    value: this.resultSize,
                    min: 5,
                    max: 50,
                    step: 5
                  })
                    .layoutWeight(1)
                    .margin({ right: 12 })
                    .onChange((value) => {
                      this.resultSize = Math.round(value);
                      this.handleUpdateSettings();
                    });
                  Text(String(this.resultSize))
                    .width(30);
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#F5F5F5')
                .borderRadius(8);

                Row() {
                  Text('超时时间（ms）');
                  Blank();
                  Slider({
                    value: this.timeout,
                    min: 5000,
                    max: 30000,
                    step: 1000
                  })
                    .layoutWeight(1)
                    .margin({ right: 12 })
                    .onChange((value) => {
                      this.timeout = Math.round(value);
                      this.handleUpdateSettings();
                    });
                  Text(String(this.timeout))
                    .width(50);
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#F5F5F5')
                .borderRadius(8);
              }
              .padding(12)
              .backgroundColor('#F5F5F5')
              .borderRadius(8);

              // 搜索服务列表
              Column({ space: 8 }) {
                Row() {
                  Text('搜索服务')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold);
                  Blank();
                  Button('添加', { type: ButtonType.Normal })
                    .fontSize(12)
                    .height(32)
                    .onClick(() => this.showAddServiceDialog = true);
                }
                .width('100%');

                if (this.config.enabledServices.length === 0) {
                  Text('未配置任何搜索服务')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .padding(20)
                    .width('100%')
                    .textAlign(TextAlign.Center);
                } else {
                  ForEach(this.config.enabledServices, (service: SearchServiceOptions, index: number) => {
                    Column() {
                      Row() {
                        Radio({ value: service.id, group: 'searchService' })
                          .checked(this.selectedIndex === index)
                          .onChange(() => this.handleSelectService(index));

                        Column({ space: 4 }) {
                          Text(this.getServiceName(service))
                            .fontSize(14)
                            .fontWeight(FontWeight.Medium);
                          Text(this.getServiceDescription(service))
                            .fontSize(12)
                            .fontColor($r('app.color.text_secondary'));
                        }
                        .layoutWeight(1)
                        .margin({ left: 8 });

                        Button('测试')
                          .fontSize(12)
                          .height(32)
                          .opacity(this.testingServiceId === service.id ? 0.5 : 1)
                          .enabled(this.testingServiceId !== service.id)
                          .onClick(() => this.handleTestConnection(index));
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Center);

                      Row() {
                        Blank();
                        Text(this.getStatusText(service.id))
                          .fontSize(12)
                          .fontColor(this.getStatusColor(service.id));
                        Button('删除', { type: ButtonType.Normal })
                          .fontSize(12)
                          .height(32)
                          .backgroundColor('#E63946')
                          .margin({ left: 8 })
                          .onClick(() => this.handleRemoveService(index));
                      }
                      .width('100%')
                      .margin({ top: 8 });
                    }
                    .padding(12)
                    .backgroundColor('#F5F5F5')
                    .borderRadius(8);
                  }, (service: SearchServiceOptions) => service.id);
                }
              }
              .padding(12)
              .backgroundColor('#F5F5F5')
              .borderRadius(8);

              Blank().height(32);
            }
            .padding(16);
          }
        }
      }
      .bindSheet(this.showAddServiceDialog, this.BuildAddServiceDialog(), {
        height: SheetSize.FIT_CONTENT,
        showClose: true,
        dragBar: true,
        onDisappear: () => {
          this.showAddServiceDialog = false;
          this.resetServiceForm();
        }
      })
      .title('搜索服务')
      .backgroundColor('#FFFFFF')
      .padding({
        top: this.getUIContext().px2vp(this.topRectHeight),
      })
      .onReady((context: NavDestinationContext) => {
        this.pathStack = context.pathStack;
      })
    }
  }