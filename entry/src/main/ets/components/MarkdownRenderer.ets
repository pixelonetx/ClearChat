import { MarkdownParser, MarkdownBlock, MarkdownBlockType, TextSegment, TableColumn, TableAlignment } from '../components/MarkdownParser';
import { CodeBlock } from './CodeBlock';
import { LinkActionHelper } from './LinkActionSheet';
import { common } from '@kit.AbilityKit';

// 表格渲染信息接口
interface TableRenderInfo {
  columns: TableColumn[];
  widths: number[];
}

// 内容部分接口
interface ContentPart {
  type: 'thinking' | 'normal';
  content: string;
  id?: number;
}

@Component
export struct MarkdownRenderer {
  @Prop content: string;
  @Prop maxWidth: string = '100%'; // 新增宽度约束属性

  private parser: MarkdownParser = new MarkdownParser();
  private context = getContext(this) as common.UIAbilityContext;
  @State private expandedSections: Set<number> = new Set<number>(); // 显式声明泛型类型

  // 解析思考模型内容
  private parseThinkingContent(content: string): ContentPart[] {
    const parts: ContentPart[] = [];
    let currentIndex = 0;
    let thinkingId = 0;

    const thinkRegex = /<think>([\s\S]*?)<\/think>/g;
    let match: RegExpExecArray | null;

    while ((match = thinkRegex.exec(content)) !== null) {
      // 添加思考标签前的普通内容
      if (match.index > currentIndex) {
        const normalContent: string = content.substring(currentIndex, match.index);
        if (normalContent.trim()) {
          parts.push({ type: 'normal', content: normalContent });
        }
      }

      // 添加思考内容
      parts.push({
        type: 'thinking',
        content: match[1],
        id: thinkingId++
      });

      currentIndex = match.index + match[0].length;
    }

    // 添加剩余的普通内容
    if (currentIndex < content.length) {
      const remainingContent: string = content.substring(currentIndex);
      if (remainingContent.trim()) {
        parts.push({ type: 'normal', content: remainingContent });
      }
    }

    // 如果没有思考标签，返回整个内容作为普通内容
    if (parts.length === 0) {
      parts.push({ type: 'normal', content: content });
    }

    return parts;
  }

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
            .fontColor('#333333')
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

  @Builder
  renderCode(block: MarkdownBlock) {
    if (block.language && block.language !== 'text' && block.content.includes('\n')) {
      // 多行代码块
      Column() {
        CodeBlock({
          content: block.content,
          language: block.language || 'text'
        })
      }
      // 移除固定宽度，让代码块根据内容自适应
    } else {
      // 行内代码
      Text(block.content)
        .fontSize(14)
        .fontColor('#D63384')
        .fontFamily('monospace')
        .backgroundColor('#F8F8F8')
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .borderRadius(4)
        .border({ width: 1, color: '#E0E0E0' })
        .copyOption(CopyOptions.InApp)
        .maxLines(999)
        .textOverflow({ overflow: TextOverflow.None })
        .wordBreak(WordBreak.BREAK_ALL)
        .constraintSize({
          maxWidth: this.maxWidth // 使用传入的宽度约束
        })
    }
  }

  @Builder
  renderQuote(block: MarkdownBlock) {
    Row() {
      Divider()
        .vertical(true)
        .width(4)
        .color('#007AFF')

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
                  .fontColor('#666666')
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

  @Builder
  renderList(block: MarkdownBlock) {
    Column() {
      if ((block.items ?? []).length > 0) {
        ForEach(block.items ?? [], (item: string, index: number) => {
          Row() {
            Text(block.ordered ? `${(block.startNumber ?? 1) + index}.` : '•')
              .fontSize(14)
              .fontColor('#666666')
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

  private getQuoteParagraphs(content: string): string[] {
    const paragraphSource: string[] = content.split(/\n{2,}/);
    if (paragraphSource.length === 1 && paragraphSource[0] === '') {
      return [''];
    }
    return paragraphSource;
  }

  @Builder
  renderText(block: MarkdownBlock) {
    Text() {
      ForEach(this.parser.parseTextFormatting(block.content), (segment: TextSegment, index: number) => {
        if (segment.code) {
          // 行内代码需要特殊处理，暂时显示为普通文本
          Span(segment.text)
            .fontSize(14)
            .fontColor('#D63384')
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
            .fontColor('#333333')
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

  @Builder
  renderHorizontalRule() {
    Divider()
      .height(2)
      .color(Color.Black)
      .margin({ top: 16, bottom: 16 })
  }

  @Builder
  renderTable(block: MarkdownBlock) {
    if (block.tableData && block.tableData.length > 0) {
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
                        .fontColor('#333333')
                        .fontWeight(segment.bold ? FontWeight.Bold : (rowIndex === 0 ? FontWeight.Bold : FontWeight.Normal))
                        .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
                        .decoration(segment.strikethrough ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
                    }
                  })
                }
                .padding({ left: 6, right: 6, top: 8, bottom: 8 })
                .textAlign(TextAlign.Start)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .wordBreak(WordBreak.BREAK_ALL)
              }
              .layoutWeight(1)
              .height(40)
              .backgroundColor(rowIndex === 0 ? '#F5F5F5' : '#FFFFFF')
              .border({
                width: 1,
                color: '#E0E0E0'
              })
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Center)
            })
          }
          .height(40)
        })
      }
      .margin({ top: 8, bottom: 8 })
      .border({
        width: 1,
        color: '#E0E0E0',
        radius: 4
      })
      .constraintSize({ maxWidth: '100%' })
      .clip(true)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 获取表格渲染信息
  private getTableRenderInfo(block: MarkdownBlock): TableRenderInfo {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    const columnWidths = this.parser.getTableColumnWidths(tableColumns, 300, 60); // 总宽度300，最小列宽60

    return {
      columns: tableColumns,
      widths: columnWidths
    };
  }

  // 获取单元格文本对齐方式
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

  // 获取单元格水平对齐方式
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

  // 获取表格单元格文本对齐方式
  private getTableCellTextAlign(block: MarkdownBlock, columnIndex: number): TextAlign {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    return this.getCellTextAlign(columnIndex, tableColumns);
  }

  // 获取表格单元格水平对齐方式
  private getTableCellAlignment(block: MarkdownBlock, columnIndex: number): HorizontalAlign {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    return this.getCellAlignment(columnIndex, tableColumns);
  }

  // 获取表格单元格宽度
  private getTableCellWidth(block: MarkdownBlock, columnIndex: number): number {
    const tableColumns: TableColumn[] = block.tableColumns || [];
    const columnWidths = this.parser.getTableColumnWidths(tableColumns, 300, 60);
    return columnWidths[columnIndex] || 60;
  }

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

  // 显示链接操作弹窗
  private showLinkActionSheet(url: string | undefined) {
    if (!url) return;

    // 使用原生 ActionSheet 替代自定义弹窗
    LinkActionHelper.showLinkActionSheet(url, this.context);
  }

  // 渲染思考部分
  @Builder
  renderThinkingSection(content: string, id: number) {
    Column() {
      // 思考部分的标题/切换按钮
      Row() {
        Text(this.expandedSections.has(id) ? '🤔 思考过程 ▼' : '🤔 思考过程 ▶')
          .fontSize(13)
          .fontColor('#666666')
          .fontWeight(FontWeight.Medium)

        Blank()

        Text(`${this.expandedSections.has(id) ? '收起' : '展开'}`)
          .fontSize(12)
          .fontColor('#007AFF')
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor('#F8F9FA')
      .borderRadius(6)
      .onClick(() => {
        if (this.expandedSections.has(id)) {
          this.expandedSections.delete(id);
        } else {
          this.expandedSections.add(id);
        }
      })

      // 思考内容（可折叠）
      if (this.expandedSections.has(id)) {
        Row() {
          // 左侧竖线
          Line()
            .width(3)
            .height('100%')
            .backgroundColor('#007AFF')
            .opacity(0.6)
            .margin({ right: 12 })

          // 思考内容
          Column() {
            ForEach(this.parser.parse(content || ''), (block: MarkdownBlock, index: number) => {
              this.renderBlock(block)
            })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top)
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor('#F8F9FA')
        .borderRadius({ bottomLeft: 6, bottomRight: 6 })
        .border({
          width: { left: 0, right: 1, top: 0, bottom: 1 },
          color: '#E0E0E0',
          style: BorderStyle.Solid
        })
      }
    }
    .width('100%')
    .margin({ top: 8, bottom: 8 })
  }

  build() {
    Column() {
      // 解析内容，区分思考部分和普通部分
      ForEach(this.parseThinkingContent(this.content || ''), (part: ContentPart, index: number) => {
        if (part.type === 'thinking' && part.id !== undefined) {
          // 渲染思考部分
          this.renderThinkingSection(part.content, part.id)
        } else {
          // 渲染普通内容
          ForEach(this.parser.parse(part.content || ''), (block: MarkdownBlock, blockIndex: number) => {
            this.renderBlock(block)
          })
        }
      })
    }
    .constraintSize({ maxWidth: this.maxWidth === 'auto' ? '100%' : this.maxWidth })
    .alignItems(HorizontalAlign.Start)
  }
}
