/**
 * MarkdownStyle - Markdown 渲染样式常量
 *
 * 功能说明：
 * - 集中管理 Markdown 渲染中的所有样式参数
 * - 包含颜色、字号、字体等样式配置
 * - 支持未来的用户自定义样式扩展
 *
 * 样式分类：
 * - 字体大小：heading、code、quote、text
 * - 颜色定义：link、code、text、secondary
 * - 字体配置：monospace、default
 * - 装饰效果：underline、linethrough 等
 *
 * 备注：
 * - TEXT_FONT_SIZE 用于渲染 Markdown 中的普通文本内容（段落、引用等）
 * - 这是助手消息的实际字号控制点
 *
 * 使用方式：
 * - 通过 MarkdownStyle.CATEGORY_NAME 访问
 * - 所有常量均为只读静态属性
 * - 确保类型安全和值不可变
 */
export class MarkdownStyle {
  // ============ 字体大小配置 ============
  /** 标题 H1 字体大小 */
  static readonly HEADING_SIZE_H1: number = 17;
  /** 标题 H2 字体大小 */
  static readonly HEADING_SIZE_H2: number = 16;
  /** 标题 H3 字体大小 */
  static readonly HEADING_SIZE_H3: number = 15;
  /** 标题 H4 字体大小 */
  static readonly HEADING_SIZE_H4: number = 15;
  /** 标题 H5 字体大小 */
  static readonly HEADING_SIZE_H5: number = 15;
  /** 标题 H6 字体大小 */
  static readonly HEADING_SIZE_H6: number = 15;

  /** 普通文本字体大小 */
  static readonly TEXT_FONT_SIZE: number = 15;
  /** 代码块文本字体大小 */
  static readonly CODE_FONT_SIZE: number = 14;
  /** 表格单元格文本字体大小 */
  static readonly TABLE_CELL_FONT_SIZE: number = 14;

  // ============ 颜色配置 ============
  /** 链接颜色 */
  static readonly LINK_COLOR: string = '#1A73E8';
  /** 代码块（行内代码）颜色 */
  static readonly CODE_COLOR: string = '#C678DD';
  /** 普通文本颜色 */
  static readonly TEXT_COLOR: string = '#1F1F1F';

  // ============ 字体配置 ============
  /** 等宽字体（用于代码块） */
  static readonly FONT_FAMILY_MONOSPACE: string = 'monospace';
  /** 默认字体 */
  static readonly FONT_FAMILY_DEFAULT: string = 'default';

  // ============ 装饰效果 ============
  /** 链接下划线颜色 */
  static readonly LINK_UNDERLINE_COLOR: string = '#1A73E8';

  // ============ 间距配置 ============
  /** 标题上下间距 - 上边距 */
  static readonly HEADING_MARGIN_TOP: number = 10;
  /** 标题上下间距 - 下边距 */
  static readonly HEADING_MARGIN_BOTTOM: number = 6;
  /** 标题行高 */
  static readonly HEADING_LINE_HEIGHT: number = 24;

  /** 普通文本行高 */
  static readonly TEXT_LINE_HEIGHT: number = 22;
  /** 段落间距 - 上边距 */
  static readonly PARAGRAPH_MARGIN_TOP: number = 0;
  /** 段落间距 - 下边距 */
  static readonly PARAGRAPH_MARGIN_BOTTOM: number = 8;

  /** 引用块上下间距 - 上边距 */
  static readonly QUOTE_MARGIN_TOP: number = 6;
  /** 引用块上下间距 - 下边距 */
  static readonly QUOTE_MARGIN_BOTTOM: number = 6;
  /** 引用块左侧边距 */
  static readonly QUOTE_PADDING_LEFT: number = 12;
  /** 引用块段落间距 */
  static readonly QUOTE_PARAGRAPH_SPACING: number = 2;

  /** 代码块上下间距 */
  static readonly CODE_BLOCK_MARGIN_TOP: number = 6;
  static readonly CODE_BLOCK_MARGIN_BOTTOM: number = 6;

  /** 列表上下间距 */
  static readonly LIST_MARGIN_TOP: number = 2;
  static readonly LIST_MARGIN_BOTTOM: number = 6;
  static readonly LIST_ITEM_MARGIN_BOTTOM: number = 2;

  /** 水平线上下间距 */
  static readonly HORIZONTAL_RULE_MARGIN_TOP: number = 12;
  static readonly HORIZONTAL_RULE_MARGIN_BOTTOM: number = 12;
  static readonly HORIZONTAL_RULE_HEIGHT: number = 1;

  /** 表格上下间距 */
  static readonly TABLE_MARGIN_TOP: number = 6;
  static readonly TABLE_MARGIN_BOTTOM: number = 6;
  static readonly TABLE_CELL_PADDING_LEFT: number = 10;
  static readonly TABLE_CELL_PADDING_RIGHT: number = 10;
  static readonly TABLE_CELL_PADDING_TOP: number = 6;
  static readonly TABLE_CELL_PADDING_BOTTOM: number = 6;

  // ============ 其他样式配置 ============
  /** 最大行数（用于 Text 组件的 maxLines） */
  static readonly MAX_LINES: number = 999;
  /** 词尾换行 */
  static readonly WORD_BREAK: WordBreak = WordBreak.BREAK_ALL;

  /**
   * 获取指定级别标题的字体大小
   * @param level 标题级别 (1-6)
   * @returns 对应的字体大小
   */
  static getHeadingSize(level: number): number {
    switch (level) {
      case 1: return MarkdownStyle.HEADING_SIZE_H1;
      case 2: return MarkdownStyle.HEADING_SIZE_H2;
      case 3: return MarkdownStyle.HEADING_SIZE_H3;
      case 4: return MarkdownStyle.HEADING_SIZE_H4;
      case 5: return MarkdownStyle.HEADING_SIZE_H5;
      case 6: return MarkdownStyle.HEADING_SIZE_H6;
      default: return MarkdownStyle.HEADING_SIZE_H4;
    }
  }
}
