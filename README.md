# ClearChat

一个基于 HarmonyOS NEXT 的 AI 对话应用，支持多模型接入和流式对话。

## 技术栈

### 核心框架
- **HarmonyOS NEXT** - 基于鸿蒙原生应用框架
- **ArkTS** - 鸿蒙应用开发语言
- **ArkUI** - 声明式 UI 开发框架

### 开发工具
- **DevEco Studio** - 鸿蒙应用集成开发环境
- **Hvigor** - 构建工具链

### 主要能力集
- `@kit.NetworkKit` - 网络请求能力
- `@kit.ArkData` - 关系型数据库存储
- `@kit.AbilityKit` - 应用能力框架
- `@kit.ArkUI` - UI 组件和交互能力
- `@kit.IMEKit` - 输入法能力

## 架构设计

### 分层架构

```
├── Pages (页面层)
│   ├── Chat.ets              - 主聊天页面
│   ├── Settings.ets          - 设置页面
│   ├── ModelSettings.ets     - 模型配置页面
│   └── Index.ets             - 应用入口
│
├── Components (组件层)
│   ├── AboutSheet.ets        - 关于半模态弹窗组件
│   ├── MarkdownRenderer.ets  - Markdown 渲染引擎
│   ├── MarkdownParser.ets    - Markdown 解析器
│   ├── MessageItem.ets       - 消息项组件
│   ├── CodeBlock.ets         - 代码块组件
│   ├── ClipboardManager.ets  - 剪贴板管理
│   └── ...
│
├── Services (服务层)
│   ├── NetworkManagerV2.ets  - 网络请求管理（事件驱动）
│   ├── DatabaseManager.ets   - 数据库管理
│   ├── TitleGenerationService.ets - 标题生成服务
│   ├── BrowserHelper.ets     - 浏览器辅助
│   └── DataModels.ets        - 数据模型定义
│
└── Utils (工具层)
    └── ArrayDataSource.ets   - 数据源工具
```

### 核心设计模式

#### 1. 单例模式
关键服务采用单例模式确保全局唯一性：
```typescript
export class DatabaseManager {
  private static instance: DatabaseManager;
  
  static getInstance(): DatabaseManager {
    if (!DatabaseManager.instance) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }
}
```

#### 2. 状态管理
使用 ArkUI 状态管理机制：
- `@State` - 组件内部状态
- `@StorageLink` - 应用级共享状态
- `@StorageProp` - 单向状态同步
- `@Provide/@Consume` - 跨组件状态传递

#### 3. 数据驱动
基于响应式数据源实现列表更新：
```typescript
private messageDataSource: ArrayDataSource<ChatMessage> = 
  new ArrayDataSource<ChatMessage>(this.messages);
```

## 核心功能实现

### 1. 流式对话

支持 SSE (Server-Sent Events) 流式响应处理：

```typescript
// 关键特性：
- 实时流式内容渲染
- 支持中断控制 (AbortController)
- 错误处理和重连机制
- 增量内容解析和展示
```

**技术细节**：
- 使用 HTTP 长连接接收流式数据
- 逐字符/逐词解析 SSE 事件流
- 实时更新 UI 显示生成内容
- 支持用户主动中断生成

### 2. 数据持久化

基于关系型数据库的本地存储方案：

```typescript
// 数据表结构
- conversations  // 对话记录
- messages       // 消息记录
- settings       // 应用设置
- providers      // AI 提供商配置
- models         // 模型配置
```

**技术特性**：
- 数据库加密 (SecurityLevel.S2)
- 事务支持确保数据一致性
- 版本管理和自动迁移
- 索引优化查询性能

### 3. Markdown 渲染

自实现的 Markdown 解析和渲染引擎：

**支持特性**：
- 标题 (H1-H6)
- 列表 (有序/无序/任务列表)
- 代码块 (语法高亮)
- 表格渲染
- 链接和图片
- 引用块
- 粗体/斜体/删除线
- 特殊处理：思考过程折叠展示

**技术亮点**：
- 分块解析算法
- 增量渲染优化
- 自定义组件化渲染
- 性能缓存机制

### 4. 多模型支持

灵活的 AI 模型接入架构：

```typescript
// 支持的提供商类型
- OpenAI API 兼容接口
- 阿里云通义千问
- 其他兼容 Chat Completion API 的服务
```

**配置化设计**：
- 动态模型列表
- 自定义 API 端点
- 模型参数配置 (temperature, max_tokens)
- 联网搜索开关 (部分模型)

### 5. 响应式布局

适配多设备屏幕尺寸：

```typescript
// 断点系统
- sm: 小屏设备 (手机)
- md: 中屏设备 (折叠屏)
- lg: 大屏设备 (平板、2in1)
```

**布局特性**：
- 自适应侧边栏
- 手势交互 (滑动打开/关闭)
- 动画过渡效果
- 键盘避让模式

## 应用特性

### 性能优化

1. **列表虚拟化**
   - 使用 LazyForEach 实现长列表性能优化
   - 数据源管理减少不必要的渲染

2. **缓存机制**
   - Markdown 解析结果缓存
   - 分组数据缓存
   - 图片资源缓存

3. **增量更新**
   - 流式内容增量追加
   - 差异化状态更新
   - 防抖处理减少频繁操作

### 用户体验

1. **流畅交互**
   - 300ms 动画时长
   - 手势响应优化
   - 加载状态反馈

2. **错误处理**
   - 网络异常提示
   - 数据库错误恢复
   - API 调用失败重试

3. **数据安全**
   - 本地数据加密存储
   - API Key 安全管理
   - 敏感信息清理

## 权限说明

应用所需权限：

- `ohos.permission.INTERNET` - 网络通信（必需）

## 数据流

```
User Input
    ↓
[Chat Page]
    ↓
[NetworkManagerV2] ←→ [AI API]
    ↓
[DatabaseManager] ←→ [Local DB]
    ↓
[Message List]
    ↓
[MarkdownRenderer]
    ↓
Display
```

## 开发说明

### 构建要求

- DevEco Studio 5.0+
- HarmonyOS NEXT SDK
- Node.js (用于构建工具)

### 项目结构

```
entry/src/main/
├── ets/
│   ├── pages/          # 页面
│   ├── components/     # 组件
│   ├── services/       # 服务
│   ├── utils/          # 工具
│   └── interfaces/     # 接口定义
├── resources/          # 资源文件
└── module.json5        # 模块配置
```

### 构建命令

```bash
# 清理构建
hvigorw clean

# 构建 HAP
hvigorw assembleHap

# 构建 APP
hvigorw assembleApp
```

## 代码规范

- 使用 TypeScript 严格模式
- 遵循 ArkTS 编码规范
- 组件命名采用 PascalCase
- 服务和工具类采用 camelCase
- 完善的错误处理和日志记录

## 技术亮点

1. **原生鸿蒙应用** - 基于 HarmonyOS NEXT 纯血鸿蒙系统
2. **流式处理** - 支持 SSE 流式响应的实时渲染
3. **自研引擎** - 独立实现 Markdown 解析渲染引擎
4. **性能优化** - 多层次缓存和虚拟化列表
5. **模块化设计** - 清晰的分层架构和服务解耦
6. **数据安全** - 加密存储和安全的密钥管理

## 许可

本项目尚未开源。

---

**版本**: 0.2.5  
**最低兼容**: HarmonyOS NEXT 5.0.5 (17)
