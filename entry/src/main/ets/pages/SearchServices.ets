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
  // 🔥 移除 enableWebSearch 状态，统一在 Chat.ets 控制
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
      // 🔥 不再加载 enableWebSearch，统一在 Chat.ets 控制
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
      case 'tavily':
        return 'Tavily';
      case 'exa':
        return 'Exa';
      case 'zhipu':
        return '智谱';
      case 'searxng':
        return 'SearXNG';
      case 'brave':
        return 'Brave';
      case 'metaso':
        return '秘塔';
      case 'google_custom_search':
        return 'Google Custom Search';
      default:
        return service.id;
    }
  }

  private getServiceDescription(service: SearchServiceOptions): string {
    switch (service.type) {
      case 'tavily':
        return '为 LLM 优化的 AI 搜索 API';
      case 'exa':
        return '神经搜索引擎';
      case 'zhipu':
        return '中文 AI 搜索服务';
      case 'searxng':
        return '隐私搜索引擎';
      case 'brave':
        return '独立搜索引擎';
      case 'metaso':
        return '中文搜索引擎';
      case 'google_custom_search':
        return '谷歌自定义搜索';
      default:
        return '搜索服务';
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
      // 🔥 不再保存 enableWebSearch，统一在 Chat.ets 控制
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
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text('添加搜索服务')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .layoutWeight(1);
      }
      .width('100%')
      .padding({
        top: 24,
        left: 24,
        right: 24,
        bottom: 16
      });

      Scroll() {
        Column({ space: 20 }) {
          // 服务类型选择
          Column({ space: 8 }) {
            Text('服务类型')
              .fontSize(13)
              .fontColor('#666666')
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
              .selected(0)
              .value(this.selectedServiceType)
              .onSelect((index: number, value?: string | string[]) => {
                const types = ['tavily', 'exa', 'zhipu', 'searxng', 'brave', 'metaso', 'google_custom_search'];
                if (index >= 0 && index < types.length) {
                  this.selectedServiceType = types[index];
                }
              })
              .width('100%')
              .borderRadius(12)
              .backgroundColor('#F8F9FA');
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%');

          // 根据服务类型显示不同字段
          if (this.selectedServiceType === 'searxng') {
            // SearXNG 特殊字段
            Column({ space: 8 }) {
              Text('实例 URL')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: 'https://your-searxng-instance.com', text: this.newServiceUrl })
                .onChange((value) => {
                  this.newServiceUrl = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');

            Column({ space: 8 }) {
              Text('搜索引擎（可选）')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: 'google,bing', text: this.newServiceEngines })
                .onChange((value) => {
                  this.newServiceEngines = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');

            Column({ space: 8 }) {
              Text('语言（可选）')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: 'zh-CN', text: this.newServiceLanguage })
                .onChange((value) => {
                  this.newServiceLanguage = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');

            Column({ space: 8 }) {
              Text('用户名（可选）')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: '用户名', text: this.newServiceUsername })
                .onChange((value) => {
                  this.newServiceUsername = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');

            Column({ space: 8 }) {
              Text('密码（可选）')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: '密码', text: this.newServicePassword })
                .type(InputType.Password)
                .onChange((value) => {
                  this.newServicePassword = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');
          } else if (this.selectedServiceType === 'google_custom_search') {
            // Google Custom Search 特殊字段
            Column({ space: 8 }) {
              Text('API Key')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: '输入 API Key', text: this.newServiceApiKey })
                .onChange((value) => {
                  this.newServiceApiKey = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');

            Column({ space: 8 }) {
              Text('搜索引擎 ID')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: '输入搜索引擎 ID', text: this.newServiceSearchEngineId })
                .onChange((value) => {
                  this.newServiceSearchEngineId = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');
          } else {
            // 其他服务的 API Key
            Column({ space: 8 }) {
              Text('API Key')
                .fontSize(13)
                .fontColor('#666666')
                .fontWeight(FontWeight.Medium);

              TextInput({ placeholder: '输入 API Key', text: this.newServiceApiKey })
                .onChange((value) => {
                  this.newServiceApiKey = value;
                })
                .width('100%')
                .borderRadius(12)
                .backgroundColor('#F8F9FA')
                .padding(12);
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%');
          }
        }
        .padding({ left: 24, right: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);

      // 按钮行
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .fontColor('#666666')
          .backgroundColor('#F0F0F0')
          .borderRadius(12)
          .onClick(() => {
            this.showAddServiceDialog = false;
            this.resetServiceForm();
          });

        Button('添加')
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .type(ButtonType.Normal)
          .backgroundColor('#007AFF')
          .borderRadius(12)
          .onClick(() => this.handleAddService());
      }
      .width('100%')
      .padding({
        top: 16,
        left: 24,
        right: 24,
        bottom: 24
      });
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius({ topLeft: 16, topRight: 16 });
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 20 }) {

            // 通用设置卡片
            Column({ space: 16 }) {
              Text('通用设置')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_color'));

              // 返回结果数设置
              Column({ space: 12 }) {
                Row() {
                  Text('返回结果数')
                    .fontSize(15)
                    .fontColor('#1A1A1A');
                  Blank();
                  Text(String(this.resultSize))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#007AFF');
                }
                .width('100%');

                Slider({
                  value: this.resultSize,
                  min: 5,
                  max: 50,
                  step: 5,
                  style: SliderStyle.OutSet
                })
                  .width('100%')
                  .blockColor('#007AFF')
                  .trackColor('#E5E5EA')
                  .selectedColor('#007AFF')
                  .onChange((value) => {
                    this.resultSize = Math.round(value);
                    this.handleUpdateSettings();
                  });
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .shadow({ radius: 8, color: '#0D000000', offsetY: 2 });

              // 超时时间设置
              Column({ space: 12 }) {
                Row() {
                  Text('超时时间')
                    .fontSize(15)
                    .fontColor('#1A1A1A');
                  Blank();
                  Text(`${this.timeout / 1000}s`)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#007AFF');
                }
                .width('100%');

                Slider({
                  value: this.timeout,
                  min: 5000,
                  max: 30000,
                  step: 1000,
                  style: SliderStyle.OutSet
                })
                  .width('100%')
                  .blockColor('#007AFF')
                  .trackColor('#E5E5EA')
                  .selectedColor('#007AFF')
                  .onChange((value) => {
                    this.timeout = Math.round(value);
                    this.handleUpdateSettings();
                  });
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .shadow({ radius: 8, color: '#0D000000', offsetY: 2 });
            }
            .width('100%');

            // 搜索服务列表卡片
            Column({ space: 16 }) {
              Row() {
                Text('搜索服务')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A')
                  .layoutWeight(1);

                Button({ type: ButtonType.Normal }) {
                  Row({ space: 6 }) {
                    Text('添加')
                      .fontSize(14)
                      .fontColor('#FFFFFF')
                      .fontWeight(FontWeight.Medium);
                  }
                }
                .height(36)
                .padding({ left: 16, right: 16 })
                .backgroundColor('#007AFF')
                .borderRadius(18)
                .onClick(() => this.showAddServiceDialog = true);
              }
              .width('100%');

              if (this.config.enabledServices.length === 0) {
                Column({ space: 12 }) {
                  Image($r('sys.symbol.magnifyingglass'))
                    .width(48)
                    .height(48)
                    .fillColor('#C7C7CC')
                    .opacity(0.5);

                  Text('暂无搜索服务')
                    .fontSize(15)
                    .fontColor('#8E8E93')
                    .fontWeight(FontWeight.Medium);

                  Text('点击上方"添加"按钮配置搜索服务')
                    .fontSize(13)
                    .fontColor('#C7C7CC');
                }
                .width('100%')
                .padding(40)
                .justifyContent(FlexAlign.Center);
              } else {
                Column({ space: 12 }) {
                  ForEach(this.config.enabledServices, (service: SearchServiceOptions, index: number) => {
                    Column({ space: 12 }) {
                      // 服务主信息行
                      Row({ space: 12 }) {
                        Radio({ value: service.id, group: 'searchService' })
                          .checked(this.selectedIndex === index)
                          .radioStyle({
                            checkedBackgroundColor: '#007AFF'
                          })
                          .onChange(() => this.handleSelectService(index));

                        Column({ space: 4 }) {
                          Text(this.getServiceName(service))
                            .fontSize(16)
                            .fontWeight(FontWeight.Medium)
                            .fontColor('#1A1A1A');
                          Text(this.getServiceDescription(service))
                            .fontSize(13)
                            .fontColor('#8E8E93');
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start);
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Top);

                      // 状态和操作行
                      Row({ space: 8 }) {
                        Row({ space: 6 }) {
                          Circle({ width: 6, height: 6 })
                            .fill(this.getStatusColor(service.id));

                          Text(this.getStatusText(service.id))
                            .fontSize(13)
                            .fontColor(this.getStatusColor(service.id))
                            .fontWeight(FontWeight.Medium);
                        }
                        .layoutWeight(1);

                        Button({ type: ButtonType.Normal }) {
                          Text('测试')
                            .fontSize(13)
                            .fontColor('#007AFF')
                            .fontWeight(FontWeight.Medium);
                        }
                        .height(32)
                        .padding({ left: 12, right: 12 })
                        .backgroundColor('#F0F5FF')
                        .borderRadius(8)
                        .opacity(this.testingServiceId === service.id ? 0.5 : 1)
                        .enabled(this.testingServiceId !== service.id)
                        .onClick(() => this.handleTestConnection(index));

                        Button({ type: ButtonType.Normal }) {
                          Text('删除')
                            .fontSize(13)
                            .fontColor('#FF3B30')
                            .fontWeight(FontWeight.Medium);
                        }
                        .height(32)
                        .padding({ left: 12, right: 12 })
                        .backgroundColor('#FFF0F0')
                        .borderRadius(8)
                        .onClick(() => this.handleRemoveService(index));
                      }
                      .width('100%');
                    }
                    .width('100%')
                    .padding(16)
                    .backgroundColor('#FFFFFF')
                    .borderRadius(12)
                    .shadow({ radius: 8, color: '#0D000000', offsetY: 2 });
                  }, (service: SearchServiceOptions) => service.id);
                }
                .width('100%');
              }
            }
            .width('100%');

            Blank().height(20);
          }
          .padding(16)
          .width('100%');
        }
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring);
      }
      .width('100%')
      .height('100%')
    }
    .bindSheet(this.showAddServiceDialog, this.BuildAddServiceDialog(), {
      height: SheetSize.FIT_CONTENT,
      showClose: false,
      dragBar: true,
      onDisappear: () => {
        this.showAddServiceDialog = false;
        this.resetServiceForm();
      }
    })
    .title('搜索服务')
    .backgroundColor($r('app.color.common_background'))
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}