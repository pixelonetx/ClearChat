import { AIModel, AIProvider } from './DataModels';

/**
 * API 格式类型
 */
export type ApiFormat = 'openai' | 'anthropic' | 'gemini';

/**
 * 预设服务商配置
 */
export class PresetProvider {
  type: string;          // 内部标识，如 'openai'
  displayName: string;   // 显示名，如 'OpenAI'
  name: string;          // 简短标识，如 'openai'
  apiUrl: string;        // API 基地址
  apiFormat: ApiFormat;  // API 格式
  modelsEndpoint: string; // 模型列表端点（相对路径）
  defaultModels: AIModel[];
  website: string;

  constructor(
    type: string,
    displayName: string,
    name: string,
    apiUrl: string,
    apiFormat: ApiFormat,
    modelsEndpoint: string,
    defaultModels: AIModel[],
    website: string
  ) {
    this.type = type;
    this.displayName = displayName;
    this.name = name;
    this.apiUrl = apiUrl;
    this.apiFormat = apiFormat;
    this.modelsEndpoint = modelsEndpoint;
    this.defaultModels = defaultModels;
    this.website = website;
  }

  /** 创建 AIProvider 实例（不含 API Key） */
  createProvider(): AIProvider {
    const provider = new AIProvider(this.type, this.name, this.displayName, this.apiUrl, '');
    provider.models = this.defaultModels.map(m =>
      new AIModel(m.id, m.name, m.displayName, m.maxTokens, m.temperature, m.supportsWebSearch));
    return provider;
  }
}

/** 所有预设服务商 */
export const PRESET_PROVIDERS: PresetProvider[] = [
  new PresetProvider(
    'openai', 'OpenAI', 'openai',
    'https://api.openai.com/v1',
    'openai',
    '/v1/models',
    [
      new AIModel('gpt-5.5', 'gpt-5.5', 'GPT-5.5', 131072, 0.7, false),
      new AIModel('gpt-5.4-mini', 'gpt-5.4-mini', 'GPT-5.4 Mini', 131072, 0.7, false),
    ],
    'https://platform.openai.com'
  ),
  new PresetProvider(
    'anthropic', 'Anthropic', 'anthropic',
    'https://api.anthropic.com/v1',
    'anthropic',
    '/v1/models',
    [
      new AIModel('claude-opus-4-7', 'claude-opus-4-7', 'Claude Opus 4.7', 128000, 0.7, false),
      new AIModel('claude-sonnet-4-6', 'claude-sonnet-4-6', 'Claude Sonnet 4.6', 64000, 0.7, false),
    ],
    'https://console.anthropic.com'
  ),
  new PresetProvider(
    'deepseek', 'DeepSeek', 'deepseek',
    'https://api.deepseek.com/v1',
    'openai',
    '/v1/models',
    [
      new AIModel('deepseek-v4-pro', 'deepseek-v4-pro', 'DeepSeek V4 Pro', 65536, 0.7, false),
      new AIModel('deepseek-v4-flash', 'deepseek-v4-flash', 'DeepSeek V4 Flash', 65536, 0.7, false),
    ],
    'https://platform.deepseek.com'
  ),
  new PresetProvider(
    'zhipu', '智谱 AI', 'zhipu',
    'https://open.bigmodel.cn/api/paas/v4',
    'openai',
    '/v1/models',
    [
      new AIModel('glm-5.1', 'glm-5.1', 'GLM-5.1', 131072, 0.7, false),
      new AIModel('glm-4.7-flash', 'glm-4.7-flash', 'GLM-4.7 Flash', 131072, 0.7, false),
    ],
    'https://open.bigmodel.cn'
  ),
  new PresetProvider(
    'qwen', '通义千问', 'qwen',
    'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'openai',
    '/v1/models',
    [
      new AIModel('qwen3-max', 'qwen3-max', 'Qwen3 Max', 258048, 0.7, false),
      new AIModel('qwen-plus', 'qwen-plus', 'Qwen Plus', 131072, 0.7, false),
    ],
    'https://dashscope.console.aliyun.com'
  ),
  new PresetProvider(
    'siliconflow', '硅基流动', 'siliconflow',
    'https://api.siliconflow.cn/v1',
    'openai',
    '/v1/models',
    [
      new AIModel('deepseek-ai/DeepSeek-V3.2', 'deepseek-ai/DeepSeek-V3.2', 'DeepSeek V3.2', 65536, 0.7, false),
      new AIModel('Qwen/Qwen3.5-122B-A10B', 'Qwen/Qwen3.5-122B-A10B', 'Qwen3.5 122B', 65536, 0.7, false),
    ],
    'https://www.siliconflow.cn'
  ),
  new PresetProvider(
    'gemini', 'Google Gemini', 'gemini',
    'https://generativelanguage.googleapis.com/v1beta',
    'gemini',
    '/v1beta/models',
    [
      new AIModel('gemini-2.5-pro', 'gemini-2.5-pro', 'Gemini 2.5 Pro', 131072, 0.7, false),
      new AIModel('gemini-2.5-flash', 'gemini-2.5-flash', 'Gemini 2.5 Flash', 131072, 0.7, false),
    ],
    'https://aistudio.google.com'
  ),
];

/**
 * 根据 type 查找预设
 */
export function getPresetByType(type: string): PresetProvider | undefined {
  return PRESET_PROVIDERS.find(p => p.type === type);
}

/**
 * 根据 API URL 自动推断 API 格式。
 * 用户自行输入 URL 时用于兜底，默认返回 'openai'。
 */
export function inferApiFormat(apiUrl: string): ApiFormat {
  const url = apiUrl.toLowerCase();
  if (url.includes('anthropic.com')) {
    return 'anthropic';
  }
  if (url.includes('googleapis.com') || url.includes('generativelanguage')) {
    return 'gemini';
  }
  return 'openai';
}
