/**
 * MessageStyle - 消息样式配置
 *
 * 功能说明：
 * - 集中管理消息组件（MessageItem）的样式参数
 * - 包含用户消息和消息辅助信息的字号配置
 * - 助手消息内容（Markdown）的字号由 MarkdownStyle 单独管理
 * - 支持未来的用户自定义字体大小扩展
 *
 * 样式分类：
 * - 消息主体字号：user message
 * - 辅助信息字号：model name、search status、citation（引用信息）
 * - 搜索结果字号：search result title/summary/url
 *
 * 架构说明：
 * ├─ MessageStyle：消息容器与辅助信息样式
 * └─ MarkdownStyle：Markdown 渲染内容样式（标题、段落、代码、表格等）
 *
 * 使用方式：
 * - 通过 MessageStyle.CATEGORY_NAME 访问
 * - 所有常量均为只读静态属性
 * - 确保类型安全和值不可变
 */
export class MessageStyle {
  // ============ 消息主体字号配置 ============
  /** 用户消息文本字体大小（纯文本消息） */
  static readonly USER_MESSAGE_FONT_SIZE: number = 15;

  // ============ 辅助信息字号配置 ============
  /** 模型名称字体大小 */
  static readonly MODEL_NAME_FONT_SIZE: number = 13;

  /** 搜索状态提示文字大小 */
  static readonly SEARCH_STATUS_FONT_SIZE: number = 14;

  /** 引用标题字体大小 */
  static readonly CITATION_TITLE_FONT_SIZE: number = 14;

  /** 引用URL字体大小 */
  static readonly CITATION_URL_FONT_SIZE: number = 12;

  /** 引用数量提示字体大小 */
  static readonly CITATION_COUNT_FONT_SIZE: number = 13;

  // ============ 搜索结果相关字号配置 ============
  /** 搜索结果标题字体大小 */
  static readonly SEARCH_RESULT_TITLE_FONT_SIZE: number = 14;

  /** 搜索结果摘要字体大小 */
  static readonly SEARCH_RESULT_SUMMARY_FONT_SIZE: number = 12;

  /** 搜索结果URL字体大小 */
  static readonly SEARCH_RESULT_URL_FONT_SIZE: number = 11;

  // ============ 颜色配置 ============
  /** 用户消息背景色 */
  static readonly USER_MESSAGE_BACKGROUND: string = '$r(\'sys.color.ohos_fa_list_card_bg\')';

  /** 助手消息背景色 */
  static readonly ASSISTANT_MESSAGE_BACKGROUND: string = '$r(\'sys.color.ohos_fa_list_card_bg\')';

  // ============ 间距配置 ============
  /** 消息行内部间距 */
  static readonly MESSAGE_PADDING: number = 12;

  /** 消息圆角半径 */
  static readonly MESSAGE_BORDER_RADIUS: number = 16;

  /** 操作按钮大小 */
  static readonly ACTION_BUTTON_SIZE: number = 28;

  /** 操作按钮圆角 */
  static readonly ACTION_BUTTON_RADIUS: number = 8;
}


