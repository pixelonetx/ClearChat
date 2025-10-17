# ClearChat 开发指南

## 项目概述

ClearChat 是一个基于 HarmonyOS ArkTS 开发的 AI 对话应用，支持多种 AI 模型和服务提供商，提供流畅的对话体验和完善的数据管理功能。

## 技术架构

### 核心技术栈
- **开发语言**: ArkTS (TypeScript for HarmonyOS)
- **UI框架**: ArkUI
- **数据库**: 关系型数据库 (RDB)
- **网络请求**: HTTP Client
- **状态管理**: ArkTS 状态管理

### 项目结构
```
entry/src/main/ets/
├── components/           # UI组件
│   ├── Constants.ets    # 应用常量
│   ├── Errors.ets       # 错误定义
│   └── ...
├── pages/               # 页面组件
│   ├── Chat.ets         # 主聊天页面
│   ├── Settings.ets     # 设置页面
│   └── ...
├── services/            # 业务服务
│   ├── DatabaseManager.ets      # 数据库管理
│   ├── NetworkManager.ets       # 网络请求管理
│   ├── TitleGenerationService.ets # 标题生成服务
│   ├── DataModels.ets           # 数据模型
│   └── ConversationModels.ets   # 对话模型
└── utils/               # 工具类
    ├── MarkdownParser.ets       # Markdown解析
    ├── MarkdownRenderer.ets     # Markdown渲染
    └── ...
```

## 开发规范

### 代码规范

#### 1. 命名规范
- **组件命名**: 使用大驼峰命名法，以功能描述结尾
  ```typescript
  // 正确
  export struct MessageItem { }
  export struct SettingsDialog { }
  
  // 错误
  export struct messageitem { }
  export struct settings_dialog { }
  ```

- **变量命名**: 使用小驼峰命名法
  ```typescript
  // 正确
  let messageContent: string = '';
  let isUserMessage: boolean = false;
  
  // 错误
  let message_content: string = '';
  let IsUserMessage: boolean = false;
  ```

- **常量命名**: 使用全大写，下划线分隔
  ```typescript
  // 正确
  static readonly DB_NAME = 'ChatDatabase.db';
  static readonly DEFAULT_TIMEOUT = 30000;
  ```

#### 2. 状态管理规范
- **@State 变量**: 用于组件内部状态
  ```typescript
  @State private messageList: ChatMessage[] = [];
  @State private isLoading: boolean = false;
  ```

- **@Prop 变量**: 用于父子组件通信
  ```typescript
  @Prop message: ChatMessage;
  @Prop onMessageClick: (message: ChatMessage) => void;
  ```

- **@Link 变量**: 用于双向数据绑定
  ```typescript
  @Link selectedConversation: string;
  ```

#### 3. 组件结构规范
```typescript
@Component
export struct ComponentName {
  // 1. @Prop 属性
  @Prop propValue: string;
  
  // 2. @State 状态
  @State private stateValue: boolean = false;
  
  // 3. 生命周期方法
  aboutToAppear() {
    // 初始化逻辑
  }
  
  // 4. 私有方法
  private handleAction() {
    // 处理逻辑
  }
  
  // 5. @Builder 方法
  @Builder
  private buildCustomComponent() {
    // 自定义组件构建
  }
  
  // 6. build 方法
  build() {
    // UI构建
  }
}
```

### 性能优化规范

#### 1. 渲染优化
- 使用 `@Builder` 减少重复代码
- 缓存计算结果，避免重复计算
- 合理使用 `ForEach` 的 `keyGenerator`

```typescript
// 缓存计算结果
@State private cachedContent: string = '';
@State private lastMessageId: number = -1;

private updateCachedContent() {
  if (this.message.id !== this.lastMessageId) {
    this.cachedContent = this.processContent(this.message.content);
    this.lastMessageId = this.message.id;
  }
}
```

#### 2. 内存优化
- 及时清理定时器和监听器
- 避免内存泄漏
- 合理使用数组操作方法

```typescript
aboutToDisappear() {
  // 清理定时器
  if (this.timerId) {
    clearInterval(this.timerId);
  }
  
  // 清理监听器
  this.eventBus.off('message', this.messageHandler);
}
```

#### 3. 数据库优化
- 使用索引提高查询性能
- 批量操作减少数据库访问
- 合理使用事务

```typescript
// 批量插入消息
async batchInsertMessages(messages: ChatMessage[]): Promise<void> {
  const transaction = await this.rdbStore.beginTransaction();
  try {
    for (const message of messages) {
      await this.insertMessage(message);
    }
    await transaction.commit();
  } catch (error) {
    await transaction.rollback();
    throw error;
  }
}
```

### 错误处理规范

#### 1. 统一错误处理
```typescript
try {
  const result = await this.networkManager.sendRequest(data);
  return result;
} catch (error) {
  console.error('Request failed:', error);
  
  // 用户友好的错误提示
  const friendlyMessage = this.getFriendlyErrorMessage(error);
  this.showToast(friendlyMessage);
  
  throw error;
}
```

#### 2. 错误分类处理
```typescript
private getFriendlyErrorMessage(error: any): string {
  if (error.code === 'NETWORK_ERROR') {
    return '网络连接失败，请检查网络设置';
  } else if (error.code === 'TIMEOUT') {
    return '请求超时，请稍后重试';
  } else if (error.code === 'AUTH_ERROR') {
    return 'API密钥无效，请检查设置';
  } else {
    return '操作失败，请稍后重试';
  }
}
```

### 文档规范

#### 1. JSDoc 注释
```typescript
/**
 * 发送聊天消息
 * @param content 消息内容
 * @param conversationId 对话ID
 * @returns Promise<ChatMessage> 发送的消息对象
 * @throws NetworkError 网络请求失败时抛出
 */
async sendMessage(content: string, conversationId: string): Promise<ChatMessage> {
  // 实现逻辑
}
```

#### 2. 组件文档
```typescript
/**
 * MessageItem - 消息项组件
 * 
 * 功能说明：
 * - 显示单条聊天消息
 * - 支持用户消息和AI回复的不同样式
 * - 提供消息操作菜单（复制、删除等）
 * 
 * 使用示例：
 * ```
 * MessageItem({
 *   message: this.currentMessage,
 *   onCopy: (content) => this.copyToClipboard(content),
 *   onDelete: (id) => this.deleteMessage(id)
 * })
 * ```
 */
@Component
export struct MessageItem {
  // 组件实现
}
```

## 调试和测试

### 1. 日志规范
```typescript
// 使用统一的日志格式
console.info('[DatabaseManager] Database initialized successfully');
console.warn('[NetworkManager] Request timeout, retrying...');
console.error('[Chat] Failed to send message:', error);
```

### 2. 性能监控
```typescript
// 监控关键操作的性能
const startTime = Date.now();
await this.performHeavyOperation();
const duration = Date.now() - startTime;
console.info(`[Performance] Heavy operation completed in ${duration}ms`);
```

## 部署和发布

### 1. 构建配置
- 确保所有依赖项正确配置
- 检查权限配置是否完整
- 验证签名和证书设置

### 2. 版本管理
- 遵循语义化版本规范
- 维护详细的更新日志
- 确保数据库迁移脚本正确

### 3. 发布检查清单
- [ ] 代码审查完成
- [ ] 单元测试通过
- [ ] 性能测试通过
- [ ] 安全检查完成
- [ ] 文档更新完成
- [ ] 版本号更新
- [ ] 构建配置检查

## 贡献指南

1. **Fork 项目**并创建功能分支
2. **遵循代码规范**进行开发
3. **添加必要的测试**和文档
4. **提交 Pull Request**并描述变更内容
5. **等待代码审查**和反馈

## 常见问题

### Q: 如何添加新的AI模型支持？
A: 在 `DataModels.ets` 中添加模型配置，在 `NetworkManager.ets` 中实现对应的API调用逻辑。

### Q: 如何优化大量消息的渲染性能？
A: 使用虚拟滚动、消息分页加载、缓存渲染结果等技术。

### Q: 如何处理数据库升级？
A: 在 `DatabaseManager.ets` 中实现版本检查和迁移逻辑，确保数据完整性。

---

更多详细信息请参考项目 README.md 和相关源码注释。