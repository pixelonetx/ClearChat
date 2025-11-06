# ClearChat 代码改进实施指南

## 快速开始

本文档提供了具体的代码改进建议实施步骤。建议按照优先级逐步实施。

---

## 📍 第一阶段：高优先级改进（第1-2周）

### 1️⃣ 拆分 Chat.ets 大文件

**文件位置**: `entry/src/main/ets/pages/Chat.ets` (2503 行)

**步骤 1**: 创建新的目录结构

```bash
mkdir -p entry/src/main/ets/pages/chat
touch entry/src/main/ets/pages/chat/ChatInputArea.ets
touch entry/src/main/ets/pages/chat/ChatMessageList.ets
touch entry/src/main/ets/pages/chat/ChatSidebar.ets
touch entry/src/main/ets/pages/chat/ChatHeader.ets
touch entry/src/main/ets/pages/chat/chatLogic.ts
```

**步骤 2**: 提取输入区域组件

**文件**: `entry/src/main/ets/pages/chat/ChatInputArea.ets`

```ets
import { promptAction } from '@kit.ArkUI';

@Component
export struct ChatInputArea {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State @Link inputText: string;
  @Prop isLoading: boolean;
  @Prop ctrlFlag: boolean;
  
  onSend?: (text: string) => void;
  onModelSelector?: () => void;
  onClearChat?: () => void;

  build() {
    Column() {
      Row({ space: 8 }) {
        // 输入框
        TextInput({
          placeholder: '输入消息...',
          text: this.inputText
        })
        .onChange((value) => {
          this.inputText = value;
        })
        .enabled(!this.isLoading)
        .layoutWeight(1)

        // 发送按钮
        Button('发送')
          .onClick(() => {
            if (this.inputText.trim() && this.onSend) {
              this.onSend(this.inputText.trim());
            }
          })
          .enabled(!this.isLoading && this.inputText.trim().length > 0)
      }
      .padding({ left: 12, right: 12, bottom: 12 })
    }
  }
}
```

**步骤 3**: 提取消息列表组件

**文件**: `entry/src/main/ets/pages/chat/ChatMessageList.ets`

```ets
import { ChatMessage } from '../../services/DataModels';
import { ArrayDataSource } from '../../utils/ArrayDataSource';
import { MessageItem } from '../../components/MessageItem';

@Component
export struct ChatMessageList {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop messages: ChatMessage[];
  @Prop messageDataSource: ArrayDataSource<ChatMessage>;
  
  scroller: Scroller = new Scroller();
  
  onDelete?: (message: ChatMessage) => void;
  onRegenerate?: (message: ChatMessage) => void;

  build() {
    Stack() {
      Scroll(this.scroller) {
        LazyForEach(this.messageDataSource, (message: ChatMessage) => {
          MessageItem({
            message: message,
            onDelete: this.onDelete,
            onRegenerate: this.onRegenerate
          })
        }, (message: ChatMessage) => message.id?.toString() || message.timestamp.toString())
      }
      .scrollBarColor($r('sys.color.ohos_id_color_scroll_bar'))
      .scrollBar(BarState.Auto)
    }
  }
}
```

**步骤 4**: 更新主页面

**文件**: `entry/src/main/ets/pages/Chat.ets`（现在会大大简化）

```ets
// ... 导入新组件 ...
import { ChatInputArea } from './chat/ChatInputArea';
import { ChatMessageList } from './chat/ChatMessageList';
import { ChatSidebar } from './chat/ChatSidebar';
import { ChatHeader } from './chat/ChatHeader';

@Entry()
@Component
struct Chat {
  // ... 现有的状态和初始化 ...
  
  build() {
    NavDestination() {
      SideBarContainer(SideBarContainerType.AUTO) {
        // 侧边栏
        ChatSidebar({
          conversations: this.conversations,
          onSelectConversation: this.handleConversationSelect.bind(this)
        })

        // 主内容
        Column() {
          // 标题栏
          ChatHeader({
            currentConversation: this.currentConversation,
            onRename: this.renameConversation.bind(this),
            onClearChat: this.clearCurrentChat.bind(this)
          })

          // 消息列表
          ChatMessageList({
            messages: this.messages,
            messageDataSource: this.messageDataSource,
            onDelete: this.deleteMessage.bind(this),
            onRegenerate: this.regenerateMessage.bind(this)
          })
          .layoutWeight(1)

          // 输入区域
          ChatInputArea({
            inputText: this.inputText,
            isLoading: this.isLoading,
            ctrlFlag: this.ctrlFlag,
            onSend: this.sendMessage.bind(this),
            onModelSelector: () => { this.showModelSelectorSheet = true; },
            onClearChat: this.clearCurrentChat.bind(this)
          })
        }
      }
    }
  }
}
```

### 2️⃣ 修复内存泄漏 - 窗口事件监听

**文件**: `entry/src/main/ets/entryability/EntryAbility.ets`

```ets
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private windowClass: window.Window | null = null;
  
  // 保存事件处理函数引用，以便后续卸载
  private avoidAreaChangeHandler: (data: window.AvoidAreaChangeInfo) => void = (data) => {
    if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
      let topRectHeight = data.area.topRect.height;
      AppStorage.setOrCreate('topRectHeight', topRectHeight);
    } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      let bottomRectHeight = data.area.bottomRect.height;
      AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);
    }
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    // ✅ 清理资源
    if (this.windowClass) {
      this.windowClass.off('avoidAreaChange', this.avoidAreaChangeHandler);
      this.windowClass = null;
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      this.windowClass = windowStage.getMainWindowSync();
      
      if (this.windowClass) {
        // 设置窗口全屏
        let isLayoutFullScreen = true;
        this.windowClass.setWindowLayoutFullScreen(isLayoutFullScreen).then(() => {
          hilog.info(DOMAIN, 'testTag', 'Succeeded in setting the window layout to full-screen mode.');
        }).catch((err: BusinessError) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to set the window layout to full-screen mode. Code is %{public}d, message is %{public}s', err.code, err.message);
        });

        // 获取初始避让区域
        let type = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR;
        let avoidArea = this.windowClass.getWindowAvoidArea(type);
        let bottomRectHeight = avoidArea.bottomRect.height;
        AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);

        type = window.AvoidAreaType.TYPE_SYSTEM;
        avoidArea = this.windowClass.getWindowAvoidArea(type);
        let topRectHeight = avoidArea.topRect.height;
        AppStorage.setOrCreate('topRectHeight', topRectHeight);

        // ✅ 注册监听（现在可以正确卸载）
        this.windowClass.on('avoidAreaChange', this.avoidAreaChangeHandler);
      }

      let applicationContext = this.context.getApplicationContext();
      applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    });
  }

  onWindowStageDestroy(): void {
    // ✅ 清理窗口监听
    if (this.windowClass) {
      this.windowClass.off('avoidAreaChange', this.avoidAreaChangeHandler);
      this.windowClass = null;
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
```

### 3️⃣ 创建统一的输入验证层

**文件**: `entry/src/main/ets/utils/InputValidator.ets`

```ets
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'InputValidator';

/**
 * 验证结果接口
 */
export interface ValidationResult {
  valid: boolean;
  error?: string;
}

/**
 * 统一的输入验证工具类
 */
export class InputValidator {
  /**
   * 验证 API URL 格式
   */
  static validateApiUrl(url: string): ValidationResult {
    if (!url || url.trim().length === 0) {
      return { 
        valid: false, 
        error: 'API URL 不能为空' 
      };
    }

    const trimmedUrl = url.trim();
    
    // 基本格式检查
    if (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://')) {
      return {
        valid: false,
        error: 'API URL 必须以 http:// 或 https:// 开头'
      };
    }

    try {
      new URL(trimmedUrl);
      return { valid: true };
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Invalid URL format: %{public}s', trimmedUrl);
      return {
        valid: false,
        error: 'API URL 格式无效'
      };
    }
  }

  /**
   * 验证 API Key
   */
  static validateApiKey(key: string): ValidationResult {
    if (!key || key.trim().length === 0) {
      return {
        valid: false,
        error: 'API Key 不能为空'
      };
    }

    const trimmedKey = key.trim();
    
    if (trimmedKey.length < 10) {
      return {
        valid: false,
        error: 'API Key 长度过短，请检查是否正确'
      };
    }

    // 检查是否包含非法字符
    if (!/^[a-zA-Z0-9\-_.]+$/.test(trimmedKey)) {
      return {
        valid: false,
        error: 'API Key 包含非法字符'
      };
    }

    return { valid: true };
  }

  /**
   * 验证模型 ID
   */
  static validateModelId(modelId: string): ValidationResult {
    if (!modelId || modelId.trim().length === 0) {
      return {
        valid: false,
        error: '模型 ID 不能为空'
      };
    }

    const trimmedId = modelId.trim();
    
    if (trimmedId.length > 256) {
      return {
        valid: false,
        error: '模型 ID 过长'
      };
    }

    return { valid: true };
  }

  /**
   * 验证用户输入消息
   */
  static validateUserMessage(
    content: string,
    options: { maxLength?: number; minLength?: number } = {}
  ): ValidationResult {
    const maxLength = options.maxLength ?? 10000;
    const minLength = options.minLength ?? 1;

    if (!content || content.trim().length === 0) {
      return {
        valid: false,
        error: '消息不能为空'
      };
    }

    const trimmedContent = content.trim();

    if (trimmedContent.length < minLength) {
      return {
        valid: false,
        error: `消息长度不能少于 ${minLength} 字符`
      };
    }

    if (trimmedContent.length > maxLength) {
      return {
        valid: false,
        error: `消息长度不能超过 ${maxLength} 字符`
      };
    }

    return { valid: true };
  }

  /**
   * 验证对话标题
   */
  static validateConversationTitle(title: string): ValidationResult {
    if (!title || title.trim().length === 0) {
      return {
        valid: false,
        error: '标题不能为空'
      };
    }

    const trimmedTitle = title.trim();

    if (trimmedTitle.length < 2) {
      return {
        valid: false,
        error: '标题长度至少为 2 个字符'
      };
    }

    if (trimmedTitle.length > 100) {
      return {
        valid: false,
        error: '标题长度不能超过 100 个字符'
      };
    }

    return { valid: true };
  }

  /**
   * 验证提供商名称
   */
  static validateProviderName(name: string): ValidationResult {
    if (!name || name.trim().length === 0) {
      return {
        valid: false,
        error: '提供商名称不能为空'
      };
    }

    const trimmedName = name.trim();

    if (trimmedName.length < 2) {
      return {
        valid: false,
        error: '提供商名称长度至少为 2 个字符'
      };
    }

    if (trimmedName.length > 50) {
      return {
        valid: false,
        error: '提供商名称长度不能超过 50 个字符'
      };
    }

    return { valid: true };
  }

  /**
   * 批量验证模型配置
   */
  static validateModelConfig(config: {
    temperature?: number;
    maxTokens?: number;
  }): ValidationResult {
    if (config.temperature !== undefined) {
      if (config.temperature < 0 || config.temperature > 2) {
        return {
          valid: false,
          error: 'Temperature 必须在 0 到 2 之间'
        };
      }
    }

    if (config.maxTokens !== undefined) {
      if (config.maxTokens < 1 || config.maxTokens > 10000) {
        return {
          valid: false,
          error: 'Max tokens 必须在 1 到 10000 之间'
        };
      }
    }

    return { valid: true };
  }
}
```

---

## 📍 第二阶段：中优先级改进（第3-4周）

### 4️⃣ 创建全局错误处理框架

**文件**: `entry/src/main/ets/utils/ErrorBoundary.ets`

```ets
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ErrorBoundary';

/**
 * 错误处理器类型
 */
export type ErrorHandler = (error: Error, context?: string) => void;

/**
 * 错误边界 - 全局错误处理
 */
export class ErrorBoundary {
  private static errorHandlers: Set<ErrorHandler> = new Set();
  private static uncaughtErrorCount: number = 0;
  private static maxUncaughtErrors: number = 10; // 超过10个未捕获错误后自动记录

  /**
   * 注册全局错误处理器
   */
  static registerErrorHandler(handler: ErrorHandler) {
    this.errorHandlers.add(handler);
  }

  /**
   * 移除全局错误处理器
   */
  static unregisterErrorHandler(handler: ErrorHandler) {
    this.errorHandlers.delete(handler);
  }

  /**
   * 捕获并处理错误
   */
  static catch(error: Error | unknown, context?: string) {
    const err = error instanceof Error ? error : new Error(String(error));
    this.uncaughtErrorCount++;

    const errorMessage = `Error caught: ${err.name} | Context: ${context || 'unknown'} | Message: ${err.message}`;
    
    hilog.error(DOMAIN, TAG, errorMessage);

    // 调用所有注册的错误处理器
    this.errorHandlers.forEach(handler => {
      try {
        handler(err, context);
      } catch (handlerError) {
        hilog.error(DOMAIN, TAG, 'Error handler execution failed: %{public}s', String(handlerError));
      }
    });

    // 如果未捕获错误过多，发出警告
    if (this.uncaughtErrorCount >= this.maxUncaughtErrors) {
      hilog.warn(DOMAIN, TAG, 'Too many uncaught errors detected: %{public}d', this.uncaughtErrorCount);
    }
  }

  /**
   * 包装异步操作
   */
  static async wrap<T>(
    operation: () => Promise<T>,
    context?: string,
    fallback?: T
  ): Promise<T | null> {
    try {
      return await operation();
    } catch (error) {
      this.catch(error, context);
      return fallback ?? null;
    }
  }

  /**
   * 包装同步操作
   */
  static syncWrap<T>(
    operation: () => T,
    context?: string,
    fallback?: T
  ): T | null {
    try {
      return operation();
    } catch (error) {
      this.catch(error, context);
      return fallback ?? null;
    }
  }

  /**
   * 重置错误计数
   */
  static resetErrorCount() {
    this.uncaughtErrorCount = 0;
  }

  /**
   * 获取当前错误计数
   */
  static getErrorCount(): number {
    return this.uncaughtErrorCount;
  }
}
```

**在主应用中使用**:

```ets
// pages/Index.ets 或 EntryAbility.ets
AboutToAppear() {
  // 注册全局错误处理器
  ErrorBoundary.registerErrorHandler((error, context) => {
    hilog.error(0x0000, 'App', 'Uncaught error in %{public}s: %{public}s', context || 'unknown', error.message);
    
    // 可以在这里集成错误上报服务
    this.reportErrorToServer(error, context);
  });
}

private async reportErrorToServer(error: Error, context?: string) {
  // 实现错误上报逻辑
}
```

### 5️⃣ 创建日志聚合系统

**文件**: `entry/src/main/ets/utils/Logger.ets`

```ets
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 日志级别枚举
 */
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

/**
 * 统一日志管理器
 */
export class Logger {
  private static minLevel: LogLevel = LogLevel.INFO;
  private static domain: number = 0x0000;
  private static isDevelopment: boolean = true; // 可根据构建配置改变

  /**
   * 设置最小日志级别
   */
  static setMinLevel(level: LogLevel) {
    this.minLevel = level;
  }

  /**
   * 设置开发模式
   */
  static setDevelopmentMode(isDev: boolean) {
    this.isDevelopment = isDev;
  }

  /**
   * 调试级别日志
   */
  static debug(tag: string, message: string, ...args: any[]) {
    if (this.minLevel <= LogLevel.DEBUG) {
      hilog.debug(this.domain, tag, message, ...this.formatArgs(args));
    }
  }

  /**
   * 信息级别日志
   */
  static info(tag: string, message: string, ...args: any[]) {
    if (this.minLevel <= LogLevel.INFO) {
      hilog.info(this.domain, tag, message, ...this.formatArgs(args));
    }
  }

  /**
   * 警告级别日志
   */
  static warn(tag: string, message: string, ...args: any[]) {
    if (this.minLevel <= LogLevel.WARN) {
      hilog.warn(this.domain, tag, message, ...this.formatArgs(args));
    }
  }

  /**
   * 错误级别日志
   */
  static error(tag: string, message: string, ...args: any[]) {
    if (this.minLevel <= LogLevel.ERROR) {
      hilog.error(this.domain, tag, message, ...this.formatArgs(args));
    }
  }

  /**
   * 格式化参数
   */
  private static formatArgs(args: any[]): string[] {
    return args.map(arg => {
      if (typeof arg === 'string') {
        return arg;
      }
      if (typeof arg === 'object') {
        return JSON.stringify(arg);
      }
      return String(arg);
    });
  }

  /**
   * 记录性能指标
   */
  static performance(tag: string, operationName: string, duration: number) {
    const message = `Performance: ${operationName} completed in ${duration}ms`;
    if (duration > 1000) {
      this.warn(tag, message);
    } else {
      this.debug(tag, message);
    }
  }

  /**
   * 记录 API 调用
   */
  static apiCall(tag: string, method: string, url: string, statusCode?: number) {
    const message = statusCode 
      ? `API: ${method} ${url} -> ${statusCode}`
      : `API: ${method} ${url}`;
    this.info(tag, message);
  }

  /**
   * 记录数据库操作
   */
  static database(tag: string, operation: string, tableName: string, rowCount?: number) {
    const message = rowCount !== undefined
      ? `Database: ${operation} on ${tableName}, affected rows: ${rowCount}`
      : `Database: ${operation} on ${tableName}`;
    this.debug(tag, message);
  }
}
```

### 6️⃣ 创建配置管理中心

**文件**: `entry/src/main/ets/config/AppConfig.ets`

```ets
/**
 * 应用配置中心
 * 集中管理所有应用配置和常量
 */
export class AppConfig {
  /**
   * 网络相关配置
   */
  static readonly NETWORK = {
    /** 普通请求超时时间（毫秒） */
    DEFAULT_TIMEOUT: 30000,
    /** 流式请求超时时间（毫秒） */
    STREAM_TIMEOUT: 60000,
    /** 重试次数 */
    RETRY_ATTEMPTS: 3,
    /** 重试延迟（毫秒） */
    RETRY_DELAY: 1000,
    /** 连接超时（毫秒） */
    CONNECT_TIMEOUT: 10000
  };

  /**
   * 模型相关配置
   */
  static readonly MODEL = {
    /** 默认最大令牌数 */
    DEFAULT_MAX_TOKENS: 2000,
    /** 默认温度参数（0-2之间） */
    DEFAULT_TEMPERATURE: 0.7,
    /** 最小温度 */
    MIN_TEMPERATURE: 0,
    /** 最大温度 */
    MAX_TEMPERATURE: 2,
    /** 最小最大令牌数 */
    MIN_MAX_TOKENS: 1,
    /** 最大最大令牌数 */
    MAX_MAX_TOKENS: 10000
  };

  /**
   * UI 相关配置
   */
  static readonly UI = {
    /** 侧边栏宽度 */
    SIDEBAR_WIDTH: 300,
    /** 动画持续时间（毫秒） */
    ANIMATION_DURATION: 300,
    /** 防抖延迟（毫秒） */
    DEBOUNCE_DELAY: 300,
    /** 消息最大长度 */
    MESSAGE_MAX_LENGTH: 10000,
    /** 消息最小长度 */
    MESSAGE_MIN_LENGTH: 1,
    /** 对话标题最大长度 */
    TITLE_MAX_LENGTH: 100,
    /** 对话标题最小长度 */
    TITLE_MIN_LENGTH: 2,
    /** 加载动画相关 */
    LOADING_DELAY: 500
  };

  /**
   * 数据库相关配置
   */
  static readonly DATABASE = {
    /** 数据库文件名 */
    DB_NAME: 'ChatDatabase.db',
    /** 数据库版本 */
    DB_VERSION: 2,
    /** 消息表名 */
    MESSAGES_TABLE: 'chat_messages',
    /** 设置表名 */
    SETTINGS_TABLE: 'app_settings',
    /** 对话表名 */
    CONVERSATIONS_TABLE: 'conversations',
    /** 提供商表名 */
    PROVIDERS_TABLE: 'providers',
    /** 模型表名 */
    MODELS_TABLE: 'models',
    /** 自动备份间隔（毫秒） */
    BACKUP_INTERVAL: 24 * 60 * 60 * 1000,
    /** 最大对话历史记录数 */
    MAX_CONVERSATION_HISTORY: 100,
    /** 最大消息历史记录数 */
    MAX_MESSAGE_HISTORY: 10000
  };

  /**
   * 缓存相关配置
   */
  static readonly CACHE = {
    /** 缓存过期时间（毫秒） */
    EXPIRY_TIME: 60 * 60 * 1000, // 1小时
    /** 最大缓存条目数 */
    MAX_CACHE_SIZE: 100
  };

  /**
   * 日志相关配置
   */
  static readonly LOGGING = {
    /** 是否启用详细日志 */
    VERBOSE: false,
    /** 最大日志文件大小（字节） */
    MAX_LOG_FILE_SIZE: 5 * 1024 * 1024, // 5MB
    /** 日志保留天数 */
    LOG_RETENTION_DAYS: 7
  };

  /**
   * 功能开关相关配置
   */
  static readonly FEATURES = {
    /** 是否启用网络搜索功能 */
    ENABLE_WEB_SEARCH: true,
    /** 是否启用思考内容显示 */
    ENABLE_REASONING_DISPLAY: true,
    /** 是否启用代码语法高亮 */
    ENABLE_CODE_HIGHLIGHT: true,
    /** 是否启用消息搜索 */
    ENABLE_MESSAGE_SEARCH: true
  };

  /**
   * 安全相关配置
   */
  static readonly SECURITY = {
    /** 是否启用数据库加密 */
    ENABLE_DB_ENCRYPTION: true,
    /** 加密安全级别 */
    ENCRYPTION_LEVEL: 'S2',
    /** 是否验证 SSL 证书 */
    VERIFY_SSL: true,
    /** API 密钥掩码长度（显示多少字符） */
    API_KEY_MASK_LENGTH: 10
  };

  /**
   * 获取配置项
   */
  static get<K extends keyof typeof AppConfig>(category: K): typeof AppConfig[K] {
    return AppConfig[category];
  }

  /**
   * 验证配置有效性
   */
  static validate(): boolean {
    // 验证关键配置
    if (this.NETWORK.DEFAULT_TIMEOUT <= 0) return false;
    if (this.MODEL.DEFAULT_TEMPERATURE < this.MODEL.MIN_TEMPERATURE || 
        this.MODEL.DEFAULT_TEMPERATURE > this.MODEL.MAX_TEMPERATURE) return false;
    if (this.UI.MESSAGE_MAX_LENGTH < this.UI.MESSAGE_MIN_LENGTH) return false;
    
    return true;
  }
}
```

---

## 📍 第三阶段：单元测试（第5-8周）

### 7️⃣ 创建基础测试框架

**文件**: `entry/src/test/utils/InputValidator.test.ets`

```ets
import { describe, it, expect } from '@ohos/hypium';
import { InputValidator } from '../../main/ets/utils/InputValidator';

export default function InputValidatorTests() {
  describe('InputValidator', () => {
    describe('validateApiUrl', () => {
      it('should accept valid HTTPS URLs', () => {
        const result = InputValidator.validateApiUrl('https://api.example.com/v1');
        expect(result.valid).toBeTruthy();
      });

      it('should accept valid HTTP URLs', () => {
        const result = InputValidator.validateApiUrl('http://localhost:8000');
        expect(result.valid).toBeTruthy();
      });

      it('should reject empty URLs', () => {
        const result = InputValidator.validateApiUrl('');
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('不能为空');
      });

      it('should reject URLs without protocol', () => {
        const result = InputValidator.validateApiUrl('example.com');
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('http://');
      });

      it('should reject malformed URLs', () => {
        const result = InputValidator.validateApiUrl('https://');
        expect(result.valid).toBeFalsy();
      });
    });

    describe('validateApiKey', () => {
      it('should accept valid API keys', () => {
        const result = InputValidator.validateApiKey('sk-1234567890abcdef');
        expect(result.valid).toBeTruthy();
      });

      it('should reject empty API keys', () => {
        const result = InputValidator.validateApiKey('');
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('不能为空');
      });

      it('should reject short API keys', () => {
        const result = InputValidator.validateApiKey('short');
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('过短');
      });

      it('should reject API keys with invalid characters', () => {
        const result = InputValidator.validateApiKey('sk-invalid@#$%key');
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('非法字符');
      });
    });

    describe('validateUserMessage', () => {
      it('should accept valid messages', () => {
        const result = InputValidator.validateUserMessage('Hello, world!');
        expect(result.valid).toBeTruthy();
      });

      it('should reject empty messages', () => {
        const result = InputValidator.validateUserMessage('');
        expect(result.valid).toBeFalsy();
      });

      it('should respect maxLength option', () => {
        const result = InputValidator.validateUserMessage(
          'a'.repeat(101),
          { maxLength: 100 }
        );
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('100');
      });

      it('should respect minLength option', () => {
        const result = InputValidator.validateUserMessage(
          'a',
          { minLength: 2 }
        );
        expect(result.valid).toBeFalsy();
        expect(result.error).toContain('2');
      });
    });

    describe('validateConversationTitle', () => {
      it('should accept valid titles', () => {
        const result = InputValidator.validateConversationTitle('My Conversation');
        expect(result.valid).toBeTruthy();
      });

      it('should reject empty titles', () => {
        const result = InputValidator.validateConversationTitle('');
        expect(result.valid).toBeFalsy();
      });

      it('should reject titles that are too short', () => {
        const result = InputValidator.validateConversationTitle('a');
        expect(result.valid).toBeFalsy();
      });

      it('should reject titles that are too long', () => {
        const result = InputValidator.validateConversationTitle('a'.repeat(101));
        expect(result.valid).toBeFalsy();
      });
    });
  });
}
```

---

## 🚀 实施检查清单

- [ ] **第1周**: 拆分 Chat.ets 文件
- [ ] **第1周**: 修复内存泄漏
- [ ] **第2周**: 创建输入验证层
- [ ] **第3周**: 实现错误边界
- [ ] **第3周**: 日志聚合系统
- [ ] **第4周**: 配置管理中心
- [ ] **第5-8周**: 添加单元测试

---

## 📞 常见问题

### Q1: 改动会影响现有功能吗？
**A**: 建议逐步改动，每次改动后运行完整测试。使用 Git 分支管理，确保每个改动都有测试覆盖。

### Q2: 需要多久才能完成所有改进？
**A**: 预计 4-8 周，取决于团队规模和改动复杂度。建议并行处理某些改进。

### Q3: 如何处理向后兼容性？
**A**: 在 DatabaseManager 的数据库迁移中已有处理机制。新增功能应通过特性开关（在 AppConfig 中）来控制。

---

## 📚 相关资源

- [HarmonyOS 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-intro/brief)
- [ArkTS 编程指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-introduction)
- [性能优化最佳实践](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/performance-optimization)

