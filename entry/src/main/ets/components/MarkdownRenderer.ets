import { common } from '@kit.AbilityKit';
import { MarkdownParser, MarkdownBlock, MarkdownBlockType, TextSegment, TableColumn, TableAlignment } from '../components/MarkdownParser';
import { CodeBlock } from './CodeBlock';
import { LinkActionHelper } from './LinkActionSheet';
import { WebBrowserParam } from './WebViewBrowser';

/**
 * 表格渲染信息接口
 * 定义了表格渲染所需的列信息和宽度信息
 */
interface TableRenderInfo {
  columns: TableColumn[];
  widths: number[];
}

/**
 * 内容部分接口
 * 定义了内容部分的类型和内容
 */
interface ContentPart {
  type: 'thinking' | 'normal';
  content: string;
  id?: number;
}

/**
 * Markdown渲染器组件
 * 用于将Markdown文本渲染为可视化UI组件
 */
@Component
export struct MarkdownRenderer {
  @Prop content: string;
  @Prop maxWidth: string = '100%'; // 新增宽度约束属性
  // 是否默认展开“思考过程”卡片
  @Prop defaultThinkingExpanded: boolean = true;

  // 优先使用内置浏览器打开链接
  @Prop preferInternalBrowser: boolean = true;

  // 获取导航栈以便内部路由
  @Consume('NavPathStack') private pathStack?: NavPathStack;

  private parser: MarkdownParser = new MarkdownParser();
  private context = getContext(this) as common.UIAbilityContext;
  @State private expandedSections: Set<number> = new Set<number>(); // 显式声明泛型类型
  @State private seenThinkingIds: Set<number> = new Set<number>(); // 记录已出现过的思考块，避免反复自动展开
  
  // 缓存解析结果以提升性能
  @State private parsedContent: ContentPart[] = [];
  @State private lastContent: string = '';

  aboutToAppear() {
    this.updateParsedContent();
  }

  // 在每次渲染前根据最新 content 执行增量解析，避免在 build() 顶部产生非 UI 语句
  aboutToRender() {
    this.updateParsedContent();
  }

  private updateParsedContent() {
    if (this.content !== this.lastContent) {
      this.parsedContent = this.parseThinkingContent(this.content || '');
      this.lastContent = this.content;
      // 解析更新后尝试自动展开新出现的思考块
      this.maybeAutoExpandThinkingSections();
    }
  }

  // 首次出现的思考块默认展开（可配置），用户手动折叠后不再强制展开
  private maybeAutoExpandThinkingSections() {
    // 收集当前内容中的所有思考块 id
    const thinkingIds: number[] = [];
    for (let i = 0; i < this.parsedContent.length; i++) {
      const part = this.parsedContent[i];
      if (part.type === 'thinking' && part.id !== undefined) {
        thinkingIds.push(part.id);
      }
    }

    let changed = false;
    for (const id of thinkingIds) {
      if (!this.seenThinkingIds.has(id)) {
        this.seenThinkingIds.add(id);
        // 仅在配置允许时，自动展开首次出现的思考块
        if (this.defaultThinkingExpanded && !this.expandedSections.has(id)) {
          this.expandedSections.add(id);
          changed = true;
        }
      }
    }

    if (changed) {
      // 触发界面更新
      this.expandedSections = new Set(this.expandedSections);
    }
  }

  /**
   * 解析思考模型内容
   * @param content 要解析的内容
   * @returns 解析后的内容部分数组
   */
  private parseThinkingContent(content: string): ContentPart[] {
    const parts: ContentPart[] = [];
    let cursor = 0;
    let thinkingId = 0;

    const OPEN = '<reasoning_content>';
    const CLOSE = '</reasoning_content>';

    // 流式友好解析：允许只有起始标签尚未闭合时也作为思考块渲染
    // 避免在闭合标签到来前把思考内容当做普通文本展示
    while (cursor < content.length) {
      const openIdx = content.indexOf(OPEN, cursor);
      if (openIdx === -1) {
        // 没有更多起始标签，余下为普通内容
        const tail = content.substring(cursor);
        if (tail.trim()) {
          parts.push({ type: 'normal', content: tail });
        }
        break;
      }

      // 起始标签前的普通内容
      if (openIdx > cursor) {
        const normalContent: string = content.substring(cursor, openIdx);
        if (normalContent.trim()) {
          parts.push({ type: 'normal', content: normalContent });
        }
      }

      const start = openIdx + OPEN.length;
      const closeIdx = content.indexOf(CLOSE, start);
      if (closeIdx === -1) {
        // 尚未闭合：将后续所有内容都作为思考块（流式场景）
        const thinkingContent = content.substring(start);
        parts.push({ type: 'thinking', content: thinkingContent, id: thinkingId++ });
        // 结束循环，等待下一次内容更新再继续解析
        break;
      } else {
        // 正常的完整思考块
        const thinkingContent = content.substring(start, closeIdx);
        parts.push({ type: 'thinking', content: thinkingContent, id: thinkingId++ });
        cursor = closeIdx + CLOSE.length;
      }
    }

    // 如果没有任何解析结果，返回整个内容作为普通内容
    if (parts.length === 0) {
      parts.push({ type: 'normal', content: content });
    }

    return parts;
  }

  /**
   * 渲染Markdown块
   * @param block 要渲染的Markdown块
   */
  @Builder
  renderBlock(block: MarkdownBlock) {
    if (block.type === MarkdownBlockType.HEADING) {
      this.renderHeading(block);
    } else if (block.type === MarkdownBlockType.CODE_BLOCK) {
      this.renderCode(block);
    } else if (block.type === MarkdownBlockType.QUOTE) {
      this.renderQuote(block);
    } else if (block.type === MarkdownBlockType.LIST) {
      this.renderList(block);
    } else if (block.type === MarkdownBlockType.TABLE) {
      this.renderTable(block);
    } else if (block.type === MarkdownBlockType.HORIZONTAL_RULE) {
      this.renderHorizontalRule();
    } else {
      this.renderText(block);
    }
  }

  /**
   * 渲染标题
   * @param block 要渲染的标题块
   */
  @Builder
  renderHeading(block: MarkdownBlock) {
    Text() {
      ForEach(this.parser.parseTextFormatting(block.content), (segment: TextSegment, index: number) => {
        if (segment.isLink) {
          // 渲染链接
          Span(segment.text)
            .fontSize(this.getHeadingSize(block.level || 1))
            .fontColor('#007AFF')
            .fontWeight(FontWeight.Bold) // 标题默认加粗
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration({
              type: TextDecorationType.Underline,
              color: '#007AFF'
            })
            .onClick(() => {
              // 显示链接操作弹窗
              this.showLinkActionSheet(segment.url);
            })
        } else {
          Span(segment.text)
            .fontSize(this.getHeadingSize(block.level || 1))
            .fontWeight(FontWeight.Bold) // 标题默认加粗
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration(segment.strikethrough ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
        }
      })
    }
    .margin({ top: 16, bottom: 8 })
    .maxLines(999)
    .textOverflow({ overflow: TextOverflow.None })
    .wordBreak(WordBreak.BREAK_ALL)
  }

  /**
   * 渲染代码块
   * @param block 要渲染的代码块
   */
  @Builder
  renderCode(block: MarkdownBlock) {
    // 只要是CODE_BLOCK类型，就应该被视为一个独立的块，而不是行内代码
    // 行内代码是在renderText等方法中通过TextSegment的code属性处理的
    Column() {
      CodeBlock({
        content: block.content,
        language: block.language || 'text'
      })
    }
    .margin({ top: 8, bottom: 8 }) // 为代码块添加垂直间距
  }

  /**
   * 渲染引用块
   * @param block 要渲染的引用块
   */
  @Builder
  renderQuote(block: MarkdownBlock) {
    Row() {
      // Divider()
      //   .vertical(true)
      //   .width(4)
      //   .color('#007AFF')

      Column({ space: 4 }) {
        ForEach(this.getQuoteParagraphs(block.content), (paragraph: string, paraIndex: number) => {
          Text() {
            ForEach(this.parser.parseTextFormatting(paragraph), (segment: TextSegment, index: number) => {
              if (segment.code) {
                Span(segment.text)
                  .fontSize(14)
                  .fontColor('#D63384')
                  .fontFamily('monospace')
                  .fontStyle(FontStyle.Italic)
              } else if (segment.isLink) {
                Span(segment.text)
                  .fontSize(14)
                  .fontColor('#007AFF')
                  .fontStyle(FontStyle.Italic)
                  .fontWeight(segment.bold ? FontWeight.Bold : FontWeight.Normal)
                  .decoration({
                    type: TextDecorationType.Underline,
                    color: '#007AFF'
                  })
                  .onClick(() => {
                    this.showLinkActionSheet(segment.url);
                  })
              } else {
                Span(segment.text)
                  .fontSize(14)
                  .fontStyle(FontStyle.Italic)
                  .fontWeight(segment.bold ? FontWeight.Bold : FontWeight.Normal)
                  .decoration(segment.strikethrough ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
              }
            })
          }
          .maxLines(999)
          .textOverflow({ overflow: TextOverflow.None })
          .wordBreak(WordBreak.BREAK_ALL)
        })
      }
      .padding({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .margin({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Top)
  }

  /**
   * 渲染列表
   * @param block 要渲染的列表块
   */
  @Builder
  renderList(block: MarkdownBlock) {
    Column() {
      if ((block.items ?? []).length > 0) {
        ForEach(block.items ?? [], (item: string, index: number) => {
          Row() {
            Text(block.ordered ? `${(block.startNumber ?? 1) + index}.` : '•')
              .fontSize(14)
              .width(block.ordered ? 28 : 16)
              .textAlign(TextAlign.End)
              .margin({ right: 8 })

            Column() {
              ForEach(this.parser.parse(item.trim()), (nestedBlock: MarkdownBlock, nestedIndex: number) => {
                this.renderBlock(nestedBlock)
              })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
          .margin({ bottom: 4 })
        })
      }
    }
    .margin({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 获取引用段落
   * @param content 引用内容
   * @returns 段落数组
   */
  private getQuoteParagraphs(content: string): string[] {
    const paragraphSource: string[] = content.split(/\n{2,}/);
    if (paragraphSource.length === 1 && paragraphSource[0] === '') {
      return [''];
    }
    return paragraphSource;
  }

  /**
   * 渲染文本
   * @param block 要渲染的文本块
   */
  @Builder
  renderText(block: MarkdownBlock) {
    Text() {
      ForEach(this.parser.parseTextFormatting(block.content), (segment: TextSegment, index: number) => {
        if (segment.code) {
          // 行内代码需要特殊处理，暂时显示为普通文本
          Span(segment.text)
            .fontSize(14)
            .fontColor('#007AFF') // '#D63384'
            .fontFamily('monospace')
        } else if (segment.isLink) {
          // 渲染链接
          Span(segment.text)
            .fontSize(14)
            .fontColor('#007AFF')
            .fontWeight(segment.bold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration({
              type: TextDecorationType.Underline,
              color: '#007AFF'
            })
            .onClick(() => {
              // 显示链接操作弹窗
              this.showLinkActionSheet(segment.url);
            })
        } else {
          Span(segment.text)
            .fontSize(14)
            .fontWeight(segment.bold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration(segment.strikethrough ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
        }
      })
    }
    .maxLines(999)
    .textOverflow({ overflow: TextOverflow.None })
    .wordBreak(WordBreak.BREAK_ALL)
    .copyOption(CopyOptions.InApp)
    .constraintSize({ maxWidth: '100%' })
  }

  /**
   * 渲染水平线
   */
  @Builder
  renderHorizontalRule() {
    Divider()
      .height(2)
      .color($r('app.color.text_secondary'))
      .margin({ top: 16, bottom: 16 })
  }

  /**
   * 渲染表格
   * @param block 要渲染的表格块
   */
  @Builder
  renderTable(block: MarkdownBlock) {
    if (block.tableData && block.tableData.length > 0) {
      Scroll() {
        Column() {
          ForEach(block.tableData, (row: string[], rowIndex: number) => {
            Row() {
              ForEach(row, (cell: string, cellIndex: number) => {
                Column() {
                  Text() {
                    ForEach(this.parser.parseTextFormatting(cell.trim()), (segment: TextSegment, segIndex: number) => {
                      if (segment.code) {
                        Span(segment.text)
                          .fontSize(12)
                          .fontColor('#D63384')
                          .fontFamily('monospace')
                      } else if (segment.isLink) {
                        Span(segment.text)
                          .fontSize(12)
                          .fontColor('#007AFF')
                          .fontWeight(segment.bold ? FontWeight.Bold : FontWeight.Normal)
                          .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
                          .decoration({
                            type: TextDecorationType.Underline,
                            color: '#007AFF'
                          })
                          .onClick(() => {
                            this.showLinkActionSheet(segment.url);
                          })
                      } else {
                        Span(segment.text)
                          .fontSize(12)

                          .fontWeight(segment.bold ? FontWeight.Bold : (rowIndex === 0 ? FontWeight.Bold : FontWeight.Normal))
                          .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
                          .decoration(segment.strikethrough ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
                      }
                    })

                    // 空内容占位，保证空白单元格有最小高度
                    if (cell.trim().length === 0) {
                      Span('\u00A0')
                        .fontSize(12)
                    }
                  }
                  .padding({ left: 6, right: 6, top: 8, bottom: 8 })
                  .textAlign(this.getTableCellTextAlign(block, cellIndex))
                  .wordBreak(WordBreak.BREAK_WORD)
                }
                .constraintSize({ minWidth: this.getTableCellWidth(block, cellIndex), maxWidth: this.getTableCellWidth(block, cellIndex) })
                .alignSelf(ItemAlign.Stretch)

                .border({
                  width: 1,
                  color: $r('app.color.text_secondary')
                })
                .alignItems(this.getTableCellAlignment(block, cellIndex))
                .justifyContent(FlexAlign.Start)
              })
            }
          })
        }
        .margin({ top: 8, bottom: 8 })
        .border({
          width: 1,
          color: $r('app.color.text_secondary'), // '#E0E0E0'
          radius: 4
        })
        .clip(true)
        .alignItems(HorizontalAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(4)
      .edgeEffect(EdgeEffect.None)
    }
  }

  /**
   * 获取表格渲染信息
   * @param block 表格块
   * @returns 表格渲染信息
   */
  private getTableRenderInfo(block: MarkdownBlock): TableRenderInfo {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    const columnWidths = this.parser.getTableColumnWidths(tableColumns, 300, 60); // 总宽度300，最小列宽60

    return {
      columns: tableColumns,
      widths: columnWidths
    };
  }

  /**
   * 获取单元格文本对齐方式
   * @param columnIndex 列索引
   * @param tableColumns 表格列信息
   * @returns 文本对齐方式
   */
  private getCellTextAlign(columnIndex: number, tableColumns: TableColumn[]): TextAlign {
    if (!tableColumns || columnIndex >= tableColumns.length) {
      return TextAlign.Start;
    }

    const alignment = tableColumns[columnIndex]?.alignment;
    switch (alignment) {
      case TableAlignment.CENTER:
        return TextAlign.Center;
      case TableAlignment.RIGHT:
        return TextAlign.End;
      default:
        return TextAlign.Start;
    }
  }

  /**
   * 获取单元格水平对齐方式
   * @param columnIndex 列索引
   * @param tableColumns 表格列信息
   * @returns 水平对齐方式
   */
  private getCellAlignment(columnIndex: number, tableColumns: TableColumn[]): HorizontalAlign {
    if (!tableColumns || columnIndex >= tableColumns.length) {
      return HorizontalAlign.Start;
    }

    const alignment = tableColumns[columnIndex]?.alignment;
    switch (alignment) {
      case TableAlignment.CENTER:
        return HorizontalAlign.Center;
      case TableAlignment.RIGHT:
        return HorizontalAlign.End;
      default:
        return HorizontalAlign.Start;
    }
  }

  /**
   * 获取表格单元格文本对齐方式
   * @param block 表格块
   * @param columnIndex 列索引
   * @returns 文本对齐方式
   */
  private getTableCellTextAlign(block: MarkdownBlock, columnIndex: number): TextAlign {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    return this.getCellTextAlign(columnIndex, tableColumns);
  }

  /**
   * 获取表格单元格水平对齐方式
   * @param block 表格块
   * @param columnIndex 列索引
   * @returns 水平对齐方式
   */
  private getTableCellAlignment(block: MarkdownBlock, columnIndex: number): HorizontalAlign {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    return this.getCellAlignment(columnIndex, tableColumns);
  }

  /**
   * 获取表格单元格宽度
   * @param block 表格块
   * @param columnIndex 列索引
   * @returns 单元格宽度
   */
  private getTableCellWidth(block: MarkdownBlock, columnIndex: number): number {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    const totalWidth: number = Math.max(tableColumns.length, 1) * 160;
    const minColumnWidth: number = 120;
    const columnWidths: number[] = this.parser.getTableColumnWidths(tableColumns, totalWidth, minColumnWidth);
    return columnWidths[columnIndex] || minColumnWidth;
  }

  /**
   * 获取标题字体大小
   * @param level 标题级别
   * @returns 字体大小
   */
  private getHeadingSize(level: number): number {
    switch (level) {
      case 1: return 24;
      case 2: return 20;
      case 3: return 18;
      case 4: return 16;
      case 5: return 14;
      case 6: return 12;
      default: return 16;
    }
  }

  // 处理链接点击：优先内置浏览器，其次弹出操作菜单
  private showLinkActionSheet(url: string | undefined) {
    if (!url) return;

    // 优先内置浏览器：通过 NavPathStack 跳转到内置 WebView 页面
    if (this.preferInternalBrowser && this.pathStack) {
      try {
        const param: WebBrowserParam = { url: url, title: url };
        this.pathStack.pushPathByName('WebBrowser', param);
        return;
      } catch (e) {
        // 回退到操作菜单
      }
    }

    // 回退：展示菜单，支持系统浏览器与复制
    LinkActionHelper.showLinkActionSheet(url, this.context);
  }

  /**
   * 渲染思考部分，UI和逻辑重构
   * @param content 思考内容
   * @param id 唯一标识符
   */
  @Builder
  renderThinkingSection(content: string, id: number) {
    Column() {
      // 标题和折叠切换器
      Row() {
        Text('思考过程 🤔')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))

        Blank()

        Image(this.expandedSections.has(id) ? $r('app.media.chevron_down') : $r('app.media.chevron_right'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.icon_secondary'))
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.bg_secondary'))
      .borderRadius(6)
      .onClick(() => {
        if (this.expandedSections.has(id)) {
          this.expandedSections.delete(id);
        } else {
          this.expandedSections.add(id);
        }
        // 强制刷新状态
        this.expandedSections = new Set(this.expandedSections);
      })

      // 可折叠的内容区域
      if (this.expandedSections.has(id)) {
        Column() {
          ForEach(this.parser.parse(content || ''), (block: MarkdownBlock) => {
            this.renderBlock(block)
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 12, left: 12, right: 12 })
        .alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.bg_secondary'))
        .border({
          width: { top: 1 },
          color: $r('app.color.border_primary'),
          style: BorderStyle.Solid
        })
        .margin({ top: -6 }) // 向上移动以覆盖标题的下圆角
        .borderWidth({ top: 1 })
        .borderColor($r('app.color.border_primary'))
        .borderRadius({ bottomLeft: 6, bottomRight: 6 })
      }
    }
    .borderWidth(0.5)
    .borderRadius(10)
    .width('100%')
    .margin({ top: 8, bottom: 8 })
  }

  build() {
    Column() {
      // 使用缓存的解析结果
      ForEach(this.parsedContent, (part: ContentPart, index: number) => {
        if (part.type === 'thinking' && part.id !== undefined) {
          // 渲染思考部分
          this.renderThinkingSection(part.content, part.id)
        } else {
          // 渲染普通内容
          ForEach(this.parser.parse(part.content || ''), (block: MarkdownBlock, blockIndex: number) => {
            this.renderBlock(block)
          }, (block: MarkdownBlock, blockIndex: number) => `block_${index}_${blockIndex}_${block.type}`)
        }
      }, (part: ContentPart, index: number) => `part_${index}_${part.type}_${part.id || 'normal'}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.maxWidth === 'auto' ? '100%' : this.maxWidth })
  }
}
