# ClearChat API 文档

## 概述

本文档描述了 ClearChat 应用的内部 API 接口和服务架构。应用采用模块化设计，各服务之间通过明确定义的接口进行通信。

## 核心服务

### 1. DatabaseManager - 数据库管理服务

#### 初始化
```typescript
async initDatabase(context: Context): Promise<void>
```
- **功能**: 初始化数据库连接和表结构
- **参数**: `context` - 应用上下文
- **异常**: `DatabaseError` - 数据库初始化失败

#### 消息操作
```typescript
// 插入消息
async insertMessage(message: ChatMessage): Promise<number>

// 获取对话消息
async getMessages(conversationId: string, limit?: number, offset?: number): Promise<ChatMessage[]>

// 更新消息元数据
async updateMessageMetadata(messageId: number, metadata: ChatMessageMetadataUpdate): Promise<void>

// 删除消息
async deleteMessage(messageId: number): Promise<void>
```

#### 对话操作
```typescript
// 创建对话
async createConversation(conversation: Conversation): Promise<string>

// 获取对话列表
async getConversations(limit?: number, offset?: number): Promise<Conversation[]>

// 更新对话
async updateConversation(conversationId: string, updates: Partial<Conversation>): Promise<void>

// 删除对话
async deleteConversation(conversationId: string): Promise<void>
```

#### 设置操作
```typescript
// 保存设置
async saveSettings(settings: AppSettings): Promise<void>

// 获取设置
async getSettings(): Promise<AppSettings | null>
```

### 2. NetworkManager - 网络请求管理服务

#### 聊天请求
```typescript
async sendChatRequest(
  baseUrl: string,
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  onProgress?: (content: string) => void
): Promise<string>
```
- **功能**: 发送聊天请求到AI服务
- **参数**:
  - `baseUrl`: API基础URL
  - `apiKey`: API密钥
  - `model`: 使用的模型名称
  - `messages`: 消息历史
  - `onProgress`: 流式响应回调（可选）
- **返回**: AI回复内容
- **异常**: `NetworkError`, `AuthError`, `TimeoutError`

#### 连接测试
```typescript
async testConnection(baseUrl: string, apiKey: string, model: string): Promise<boolean>
```
- **功能**: 测试API连接是否正常
- **返回**: 连接状态（true/false）

### 3. TitleGenerationService - 标题生成服务

#### 生成标题
```typescript
async generateTitle(
  messages: ChatMessage[],
  apiKey: string,
  baseUrl: string,
  model: string
): Promise<string>
```
- **功能**: 基于对话内容生成简洁标题
- **参数**:
  - `messages`: 对话消息列表
  - `apiKey`: API密钥
  - `baseUrl`: API基础URL
  - `model`: 使用的AI模型
- **返回**: 生成的标题（不超过15字符）
- **异常**: 生成失败时返回备用标题

## 数据模型

### ChatMessage - 聊天消息
```typescript
class ChatMessage {
  id?: number;                    // 数据库主键
  content: string;                // 消息内容
  role: 'user' | 'assistant';     // 消息角色
  timestamp: number;              // 时间戳
  conversationId: string;         // 对话ID
  modelName?: string;             // AI模型名称
  providerName?: string;          // 服务提供商
  providerMessageId?: string;     // 服务商消息ID
  providerCreatedAt?: number;     // 服务商创建时间
  systemFingerprint?: string;     // 系统指纹
}
```

### Conversation - 对话会话
```typescript
class Conversation {
  id: string;                     // 对话唯一ID
  title: string;                  // 对话标题
  createdAt: number;              // 创建时间
  updatedAt: number;              // 更新时间
  messageCount: number;           // 消息数量
  lastMessage?: string;           // 最后一条消息
  isArchived: boolean;            // 是否归档
  tags?: string[];                // 标签
}
```

### AppSettings - 应用设置
```typescript
interface AppSettings {
  // AI服务配置
  selectedProvider: string;       // 选中的服务提供商
  selectedModel: string;          // 选中的模型
  
  // 界面设置
  theme: 'light' | 'dark' | 'auto'; // 主题模式
  fontSize: 'small' | 'medium' | 'large'; // 字体大小
  
  // 功能设置
  autoSave: boolean;              // 自动保存
  streamResponse: boolean;        // 流式响应
  showTimestamp: boolean;         // 显示时间戳
  
  // 高级设置
  maxTokens: number;              // 最大令牌数
  temperature: number;            // 温度参数
  timeout: number;                // 请求超时时间
}
```

### AIProvider - AI服务提供商
```typescript
interface AIProvider {
  id: string;                     // 提供商ID
  name: string;                   // 提供商名称
  displayName: string;            // 显示名称
  apiUrl: string;                 // API地址
  apiKey: string;                 // API密钥
  models: AIModel[];              // 支持的模型列表
  isActive: boolean;              // 是否启用
  description?: string;           // 描述信息
  website?: string;               // 官网地址
}
```

### AIModel - AI模型配置
```typescript
interface AIModel {
  id: string;                     // 模型ID
  name: string;                   // 模型名称
  displayName: string;            // 显示名称
  maxTokens: number;              // 最大令牌数
  temperature: number;            // 默认温度
  description?: string;           // 模型描述
  pricing?: {                     // 价格信息
    input: number;                // 输入价格
    output: number;               // 输出价格
    unit: string;                 // 计价单位
  };
}
```

## 错误处理

### 错误类型
```typescript
// 数据库错误
class DatabaseError extends Error {
  constructor(message: string, cause?: Error);
}

// 网络错误
class NetworkError extends Error {
  constructor(message: string, statusCode?: number);
}

// 认证错误
class AuthError extends Error {
  constructor(message: string);
}

// 超时错误
class TimeoutError extends Error {
  constructor(message: string, timeout: number);
}
```

### 错误码定义
| 错误码 | 描述 | 处理建议 |
|--------|------|----------|
| `DB_INIT_FAILED` | 数据库初始化失败 | 检查存储权限和空间 |
| `DB_QUERY_FAILED` | 数据库查询失败 | 检查SQL语法和数据完整性 |
| `NETWORK_TIMEOUT` | 网络请求超时 | 增加超时时间或重试 |
| `INVALID_API_KEY` | API密钥无效 | 检查密钥配置 |
| `MODEL_NOT_FOUND` | 模型不存在 | 选择其他可用模型 |
| `QUOTA_EXCEEDED` | 配额超限 | 等待配额重置或升级账户 |

## 事件系统

### 消息事件
```typescript
// 消息发送事件
interface MessageSentEvent {
  type: 'message_sent';
  data: {
    message: ChatMessage;
    conversationId: string;
  };
}

// 消息接收事件
interface MessageReceivedEvent {
  type: 'message_received';
  data: {
    message: ChatMessage;
    conversationId: string;
  };
}

// 消息更新事件
interface MessageUpdatedEvent {
  type: 'message_updated';
  data: {
    messageId: number;
    updates: Partial<ChatMessage>;
  };
}
```

### 对话事件
```typescript
// 对话创建事件
interface ConversationCreatedEvent {
  type: 'conversation_created';
  data: {
    conversation: Conversation;
  };
}

// 对话更新事件
interface ConversationUpdatedEvent {
  type: 'conversation_updated';
  data: {
    conversationId: string;
    updates: Partial<Conversation>;
  };
}
```

## 性能优化

### 数据库优化
- 使用索引提高查询性能
- 批量操作减少数据库访问
- 合理使用事务保证数据一致性

### 网络优化
- 实现请求重试机制
- 支持请求取消
- 使用连接池管理HTTP连接

### 内存优化
- 及时释放不需要的资源
- 使用对象池减少GC压力
- 合理设置缓存大小

## 安全考虑

### 数据安全
- 数据库加密存储敏感信息
- API密钥本地加密保存
- 定期清理临时数据

### 网络安全
- 使用HTTPS协议
- 验证服务器证书
- 防止中间人攻击

### 隐私保护
- 不记录敏感用户信息
- 支持数据导出和删除
- 遵循隐私保护法规

## 版本兼容性

### 数据库迁移
```typescript
// 版本升级处理
async migrateDatabase(oldVersion: number, newVersion: number): Promise<void> {
  if (oldVersion < 2) {
    // 添加新字段
    await this.addColumn('messages', 'provider_name', 'TEXT');
  }
  
  if (oldVersion < 3) {
    // 创建新表
    await this.createTable('providers', providerTableSchema);
  }
}
```

### API兼容性
- 保持向后兼容的接口设计
- 使用版本号管理API变更
- 提供迁移指南和工具

---

本文档会随着应用功能的更新而持续维护。如有疑问或建议，请参考项目源码或联系开发团队。