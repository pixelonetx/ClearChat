# ClearChat

HarmonyOS NEXT 原生 AI 聊天客户端。兼容 OpenAI API 格式，支持接入各类大模型服务。

## 功能

- 流式对话，支持 Tool Calling（联网搜索）
- 自研 Markdown 渲染（代码高亮、表格、`<think>` 思考过程折叠）
- 多服务商 / 多模型切换
- 对话管理（新建、重命名、删除、自动标题生成）
- 联网搜索：Tavily、Exa、智谱、SearXNG、Brave、秘塔、Google Custom Search
- 本地 SQLite 加密存储
- 深色模式
- 手机 / 折叠屏 / 平板 / 2in1 响应式布局

## 环境要求

- DevEco Studio 5.0+
- HarmonyOS NEXT SDK（targetSdkVersion 6.0.0、compatibleSdkVersion 5.0.5）
- 设备：phone / tablet / 2in1

## 构建运行

1. DevEco Studio 打开项目
2. 配置签名（`build-profile.json5` → `signingConfigs`）
3. Build → Run

命令行构建：

```bash
hvigorw assembleHap --no-daemon
```

## 使用

首次打开进入设置页面，配置至少一个 API 服务商（填写 API URL 和 Key，添加模型），即可开始对话。

联网搜索为可选功能，需要在「搜索服务配置」中配置对应搜索引擎的 API Key。

## 项目结构

```
entry/src/main/ets/
├── pages/           # 页面（Chat、Settings、ModelSettings、SearchServices、Preference）
├── components/      # UI 组件（消息列表、Markdown 渲染、对话框、代码块等）
├── services/        # 业务服务（网络、数据库、流处理、搜索）
├── viewmodels/      # ViewModel 层
├── common/          # 工具类（Logger、常量、网络工具）
├── interfaces/      # 接口定义
└── utils/           # 通用工具
```

## 权限

| 权限 | 用途 |
|------|------|
| `ohos.permission.INTERNET` | API 通信 |

## License

MIT
