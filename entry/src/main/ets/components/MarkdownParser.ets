import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Markdown块类型枚举
 * 定义了支持的Markdown块类型
 */
export enum MarkdownBlockType {
  PARAGRAPH = 'paragraph',
  HEADING = 'heading',
  CODE_BLOCK = 'code_block',
  LIST = 'list',
  QUOTE = 'quote',
  TABLE = 'table',
  HORIZONTAL_RULE = 'horizontal_rule'
}

/**
 * 表格列对齐方式
 * 定义了表格中列的对齐方式
 */
export enum TableAlignment {
  LEFT = 'left',
  CENTER = 'center',
  RIGHT = 'right'
}

/**
 * 表格列信息
 * 定义了表格列的属性，包括对齐方式和宽度信息
 */
export interface TableColumn {
  alignment: TableAlignment;
  width: number; // 列的最大宽度（字符数）
  relativeWidth: number; // 相对宽度（0-1之间的比例）
}

/**
 * Markdown块接口
 * 定义了Markdown块的基本结构和属性
 */
export interface MarkdownBlock {
  type: MarkdownBlockType;
  content: string;
  rawText?: string; // 原始文本，用于表格解析
  level?: number; // 标题级别
  language?: string; // 代码语言
  items?: string[]; // 列表项
  ordered?: boolean; // 是否为有序列表
  startNumber?: number; // 有序列表起始编号
  tableData?: string[][]; // 表格数据
  tableColumns?: TableColumn[]; // 表格列信息（包含对齐和宽度）
}

/**
 * 文本格式化片段
 * 定义了文本的格式化属性，包括粗体、斜体、代码、删除线和链接等
 */
export interface TextSegment {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  strikethrough: boolean;
  isLink: boolean;
  url?: string; // 使用可选属性标记
}

/**
 * 代码块解析结果类型
 * 包含解析后的代码块和下一个解析位置的索引
 */
interface CodeBlockResult {
  block: MarkdownBlock;
  nextIndex: number;
}

/**
 * 列表解析结果类型
 * 包含解析后的列表块和下一个解析位置的索引
 */
interface ListResult {
  block: MarkdownBlock;
  nextIndex: number;
}

/**
 * 段落解析结果类型
 * 包含解析后的段落块和下一个解析位置的索引
 */
interface ParagraphResult {
  block: MarkdownBlock;
  nextIndex: number;
}

/**
 * 表格解析结果类型
 * 包含解析后的表格块和下一个解析位置的索引
 */
interface TableResult {
  block: MarkdownBlock;
  nextIndex: number;
}

/**
 * 引用解析结果类型
 * 包含解析后的引用块和下一个解析位置的索引
 */
interface QuoteResult {
  block: MarkdownBlock;
  nextIndex: number;
}

/**
 * Markdown解析器类
 * 提供将Markdown文本解析为结构化数据的功能
 */
const DOMAIN = 0x0000;
const TAG = 'MarkdownParser';

export class MarkdownParser {
  /**
   * 解析Markdown文本
   * @param markdown 要解析的Markdown文本
   * @returns 解析后的Markdown块数组
   */
  parse(markdown: string): MarkdownBlock[] {
    const lines = markdown.split('\n');
    const blocks: MarkdownBlock[] = [];
    let i = 0;

    while (i < lines.length) {
      const rawLine = lines[i];
      const line = rawLine.trim();

      // 跳过空行
      if (line === '') {
        i++;
        continue;
      }

      // 解析代码块
      if (this.isCodeBlockStart(line)) {
        const codeBlock = this.parseCodeBlock(lines, i);
        blocks.push(codeBlock.block);
        i = codeBlock.nextIndex;
        continue;
      }

      // 解析标题
      if (this.isHeadingLine(line)) {
        blocks.push(this.parseHeading(line));
        i++;
        continue;
      }

      // 解析引用
      if (this.isQuoteLine(line)) {
        const quote = this.parseQuoteBlock(lines, i);
        blocks.push(quote.block);
        i = quote.nextIndex;
        continue;
      }

      // 解析水平线
      if (this.isHorizontalRule(line)) {
        blocks.push({
          type: MarkdownBlockType.HORIZONTAL_RULE,
          content: '' // 添加空内容以满足接口要求
        });
        i++;
        continue;
      }

      // 解析列表
      if (this.isListLine(line)) {
        const listBlock = this.parseList(lines, i);
        blocks.push(listBlock.block);
        i = listBlock.nextIndex;
        continue;
      }

      // 解析表格
      if (this.isTableStart(lines, i)) {
        const tableBlock = this.parseTable(lines, i);
        blocks.push(tableBlock.block);
        i = tableBlock.nextIndex;
        continue;
      }

      // 默认为段落
      const paragraphResult = this.parseParagraphBlock(lines, i);
      blocks.push(paragraphResult.block);
      i = paragraphResult.nextIndex;
    }

    return blocks;
  }

  /**
   * 解析代码块
   * @param lines 行数组
   * @param startIndex 起始索引
   * @returns 代码块解析结果
   */
  private parseCodeBlock(lines: string[], startIndex: number): CodeBlockResult {
    const startLine = lines[startIndex].trim();
    const fence = startLine.match(/^(`{3,}|~{3,})/)?.[0];
    if (!fence) {
      // This should not happen if called after isCodeBlockStart
      return this.parseParagraphBlock(lines, startIndex);
    }

    const language = startLine.substring(fence.length).trim();
    const codeLines: string[] = [];
    let i = startIndex + 1;

    while (i < lines.length) {
      const currentLine = lines[i];
      if (currentLine.trim().startsWith(fence)) {
        i++; // Consume the closing fence
        break;
      }
      codeLines.push(currentLine);
      i++;
    }

    const blockResult: CodeBlockResult = {
      block: {
        type: MarkdownBlockType.CODE_BLOCK,
        content: codeLines.join('\n'),
        language: language || 'text'
      },
      nextIndex: i
    };

    return blockResult;
  }

  /**
   * 解析标题
   * @param line 标题行文本
   * @returns 解析后的标题块
   */
  private parseHeading(line: string): MarkdownBlock {
    const match = line.match(/^(#{1,6})\s+(.+)$/);
    if (match) {
      const heading: MarkdownBlock = {
        type: MarkdownBlockType.HEADING,
        content: match[2],
        level: match[1].length
      };
      return heading;
    }

    const paragraph: MarkdownBlock = {
      type: MarkdownBlockType.PARAGRAPH,
      content: line
    };
    return paragraph;
  }

  /**
   * 解析引用块
   * @param lines 行数组
   * @param startIndex 起始索引
   * @returns 引用块解析结果
   */
  private parseQuoteBlock(lines: string[], startIndex: number): QuoteResult {
    const contents: string[] = [];
    let i = startIndex;

    while (i < lines.length) {
      const rawLine = lines[i];
      const trimmedLine = rawLine.trim();

      if (trimmedLine.startsWith('>')) {
        const lineContent = trimmedLine.substring(1).trimStart();
        contents.push(lineContent);
        i++;
        continue;
      }

      if (trimmedLine === '') {
        contents.push('');
        i++;
        continue;
      }

      break;
    }

    const quoteResult: QuoteResult = {
      block: {
        type: MarkdownBlockType.QUOTE,
        content: contents.join('\n')
      },
      nextIndex: i
    };

    return quoteResult;
  }

  /**
   * 解析列表
   * @param lines 行数组
   * @param startIndex 起始索引
   * @returns 列表解析结果
   */
  private parseList(lines: string[], startIndex: number): ListResult {
    const items: string[] = [];
    let i = startIndex;
    let currentItem = '';
    let isOrdered: boolean | null = null;
    let startNumber: number | undefined = undefined;

    const pushCurrentItem = (): void => {
      if (currentItem.trim().length > 0) {
        items.push(currentItem.trim());
      }
      currentItem = '';
    };

    while (i < lines.length) {
      const rawLine = lines[i];
      const trimmedLine = rawLine.trim();

      if (trimmedLine === '') {
        pushCurrentItem();
        i++;
        break;
      }

      const listMatch = rawLine.match(/^(\s{0,3})([-*+]|(\d+)\.)\s+(.*)$/);
      if (listMatch) {
        const currentIsOrdered = !!listMatch[3];
        if (isOrdered === null) {
          isOrdered = currentIsOrdered;
          if (currentIsOrdered && listMatch[3]) {
            startNumber = parseInt(listMatch[3]);
          }
        } else if (isOrdered !== currentIsOrdered) {
          // 类型切换，终止当前列表
          break;
        }

        pushCurrentItem();
        currentItem = listMatch[4];
        if (isOrdered && startNumber === undefined && listMatch[3]) {
          startNumber = parseInt(listMatch[3]);
        }
        i++;
        continue;
      }

      const indentation = rawLine.match(/^\s+/);
      if (indentation && indentation[0].length > 0 && currentItem.length > 0) {
        currentItem += '\n' + trimmedLine;
        i++;
        continue;
      }

      // 遇到其他块，结束列表
      break;
    }

    pushCurrentItem();

    const listResult: ListResult = {
      block: {
        type: MarkdownBlockType.LIST,
        content: '',
        items: items,
        ordered: isOrdered ?? false,
        startNumber: isOrdered ? (startNumber ?? 1) : undefined
      },
      nextIndex: i
    };

    return listResult;
  }

  /**
   * 解析表格
   * @param lines 行数组
   * @param startIndex 起始索引
   * @returns 表格解析结果
   */
  private parseTable(lines: string[], startIndex: number): TableResult {
    const tableData: string[][] = [];
    const alignments: TableAlignment[] = [];
    let i = startIndex;
    let hasAlignment = false;

    // 安全拆分：忽略转义管道（\|）与代码片段中的管道（`|`）
    const splitRow = (line: string): string[] => {
      const cells: string[] = [];
      let current = '';
      let inCode = false;
      for (let idx = 0; idx < line.length; idx++) {
        const ch = line[idx];
        const prev = idx > 0 ? line[idx - 1] : '';

        if (ch === '`') {
          // 处理行内代码切换
          inCode = !inCode;
          current += ch;
          continue;
        }

        if (ch === '\\' && !inCode && idx + 1 < line.length && line[idx + 1] === '|') {
          // 处理转义管道 \|
          current += '|';
          idx++;
          continue;
        }

        if (ch === '|') {
          if (!inCode && prev !== '\\') {
            // 作为分隔符
            cells.push(current.trim());
            current = '';
          } else {
            // 作为普通字符
            current += ch;
          }
          continue;
        }

        current += ch;
      }

      // 推入最后一个单元格
      cells.push(current.trim());

      // 去掉由于首尾管道导致的空单元格
      if (cells.length > 0 && cells[0] === '') {
        cells.shift();
      }
      if (cells.length > 0 && cells[cells.length - 1] === '') {
        cells.pop();
      }

      return cells;
    };

    while (i < lines.length) {
      const line = lines[i].trim();

      if (!line.includes('|')) {
        break;
      }

      // 兼容无首尾管道的对齐分隔行
      if (this.isTableSeparatorLine(line)) {
        if (!hasAlignment) {
          const alignmentCells = splitRow(line);
          alignmentCells.forEach((cell: string) => {
            const trimmedCell = cell.trim();
            const startsColon = trimmedCell.startsWith(':');
            const endsColon = trimmedCell.endsWith(':');
            if (startsColon && endsColon) {
              alignments.push(TableAlignment.CENTER);
            } else if (endsColon) {
              alignments.push(TableAlignment.RIGHT);
            } else {
              alignments.push(startsColon ? TableAlignment.LEFT : TableAlignment.LEFT);
            }
          });
          hasAlignment = true;
        }
        i++;
        continue;
      }

      // 跳过纯分隔字符行（避免被当作数据行）
      if (/^[\|\s:\-]+$/.test(line)) {
        i++;
        continue;
      }

      // 解析表格数据行（安全拆分）
      const cells = splitRow(line);
      if (cells.length > 0) {
        tableData.push(cells);
      }
      i++;
    }

    // 如果没有明确的对齐信息，默认左对齐
    if (!hasAlignment && tableData.length > 0) {
      const columnCount = Math.max(...tableData.map(row => row.length));
      for (let j = 0; j < columnCount; j++) {
        alignments.push(TableAlignment.LEFT);
      }
    }

    // 计算每列的最大宽度并标准化表格数据
    const columnCount = Math.max(
      alignments.length,
      tableData.length > 0 ? Math.max(...tableData.map(row => row.length)) : 0
    );
    const columnWidths: number[] = new Array(columnCount).fill(0);

    // 标准化所有行的列数
    tableData.forEach(row => {
      while (row.length < columnCount) {
        row.push('');
      }
      // 计算每列的最大宽度
      row.forEach((cell, colIndex) => {
        const cellWidth = this.getTextWidth(cell);
        columnWidths[colIndex] = Math.max(columnWidths[colIndex], cellWidth);
      });
    });

    // 确保对齐数组的长度正确
    while (alignments.length < columnCount) {
      alignments.push(TableAlignment.LEFT);
    }

    // 创建表格列信息
    const totalWidth = columnWidths.reduce((sum, width) => sum + Math.max(width, 3), 0);
    const tableColumns: TableColumn[] = alignments.map((alignment, index): TableColumn => {
      const columnWidth = Math.max(columnWidths[index] || 0, 3); // 最小宽度为3
      return {
        alignment: alignment,
        width: columnWidth,
        relativeWidth: totalWidth > 0 ? columnWidth / totalWidth : 1 / Math.max(alignments.length, 1)
      };
    });

    // 保存原始表格文本
    const rawText = lines.slice(startIndex, i).join('\n');

    const tableResult: TableResult = {
      block: {
        type: MarkdownBlockType.TABLE,
        content: '',
        rawText: rawText,
        tableData: tableData,
        tableColumns: tableColumns
      },
      nextIndex: i
    };

    return tableResult;
  }

  /**
   * 判断是否为代码块开始行
   * @param line 要检查的行
   * @returns 如果是代码块开始行返回true，否则返回false
   */
  private isCodeBlockStart(line: string): boolean {
    return line.trim().startsWith('```') || line.trim().startsWith('~~~');
  }

  /**
   * 判断是否为标题行
   * @param line 要检查的行
   * @returns 如果是标题行返回true，否则返回false
   */
  private isHeadingLine(line: string): boolean {
    return /^#{1,6}\s+/.test(line);
  }

  /**
   * 判断是否为引用行
   * @param line 要检查的行
   * @returns 如果是引用行返回true，否则返回false
   */
  private isQuoteLine(line: string): boolean {
    return line.startsWith('>');
  }

  /**
   * 判断是否为水平线
   * @param line 要检查的行
   * @returns 如果是水平线返回true，否则返回false
   */
  private isHorizontalRule(line: string): boolean {
    const trimmed = line.trim();
    return trimmed === '---' || trimmed === '***' || trimmed === '___';
  }

  /**
   * 判断是否为列表行
   * @param line 要检查的行
   * @returns 如果是列表行返回true，否则返回false
   */
  private isListLine(line: string): boolean {
    return /^(\s{0,3})([-*+]|(\d+)\.)\s+/.test(line);
  }

  /**
   * 判断是否为表格分隔行
   * @param line 要检查的行
   * @returns 如果是表格分隔行返回true，否则返回false
   */
  private isTableSeparatorLine(line: string): boolean {
    return /^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$/.test(line.trim());
  }

  /**
   * 判断是否为表格开始
   * @param lines 行数组
   * @param index 当前索引
   * @returns 如果是表格开始返回true，否则返回false
   */
  private isTableStart(lines: string[], index: number): boolean {
    const currentLine = lines[index];
    if (!currentLine || currentLine.trim() === '') {
      return false;
    }

    if (!currentLine.includes('|')) {
      return false;
    }

    const nextLine = lines[index + 1] ?? '';
    return this.isTableSeparatorLine(nextLine);
  }

  /**
   * 判断是否为新块开始
   * @param trimmedLine 要检查的行（已去除前后空格）
   * @returns 如果是新块开始返回true，否则返回false
   */
  private startsNewBlock(trimmedLine: string): boolean {
    return this.isCodeBlockStart(trimmedLine)
      || this.isHeadingLine(trimmedLine)
      || this.isQuoteLine(trimmedLine)
      || this.isHorizontalRule(trimmedLine)
      || this.isListLine(trimmedLine);
  }

  /**
   * 计算文本宽度（考虑中文字符）
   * @param text 要计算宽度的文本
   * @returns 文本的显示宽度
   */
  private getTextWidth(text: string): number {
    let width = 0;
    for (let i = 0; i < text.length; i++) {
      const char = text.charAt(i);
      // 中文字符、全角字符等占用2个字符宽度
      if (this.isFullWidth(char)) {
        width += 2;
      } else {
        width += 1;
      }
    }
    return width;
  }

  /**
   * 判断是否为全角字符
   * @param char 要检查的字符
   * @returns 如果是全角字符返回true，否则返回false
   */
  private isFullWidth(char: string): boolean {
    const code = char.charCodeAt(0);
    // 中文字符范围
    if (code >= 0x4e00 && code <= 0x9fff) {
      return true;
    }
    // 全角ASCII字符
    if (code >= 0xff01 && code <= 0xff5e) {
      return true;
    }
    // 其他常见全角字符
    if (code >= 0x3000 && code <= 0x303f) {
      return true;
    }
    return false;
  }

  /**
   * 格式化表格为对齐的字符串
   * @param tableData 表格数据
   * @param tableColumns 表格列信息
   * @returns 格式化后的表格字符串
   */
  formatTable(tableData: string[][], tableColumns: TableColumn[]): string {
    if (!tableData.length || !tableColumns.length) {
      return '';
    }

    const lines: string[] = [];

    tableData.forEach((row, rowIndex) => {
      const cells = row.map((cell, colIndex) => {
        const column = tableColumns[colIndex];
        const cellWidth = this.getTextWidth(cell);
        const padding = Math.max(0, column.width - cellWidth);

        let paddedCell = cell;
        switch (column.alignment) {
          case TableAlignment.LEFT:
            paddedCell = cell + ' '.repeat(padding);
            break;
          case TableAlignment.RIGHT:
            paddedCell = ' '.repeat(padding) + cell;
            break;
          case TableAlignment.CENTER:
            const leftPadding = Math.floor(padding / 2);
            const rightPadding = padding - leftPadding;
            paddedCell = ' '.repeat(leftPadding) + cell + ' '.repeat(rightPadding);
            break;
        }
        return paddedCell;
      });

      lines.push('| ' + cells.join(' | ') + ' |');

      // 在表头后添加分隔线
      if (rowIndex === 0) {
        const separators = tableColumns.map(column => {
          let separator = '-'.repeat(Math.max(3, column.width));
          switch (column.alignment) {
            case TableAlignment.LEFT:
              separator = ':' + separator.substring(1);
              break;
            case TableAlignment.RIGHT:
              separator = separator.substring(0, separator.length - 1) + ':';
              break;
            case TableAlignment.CENTER:
              separator = ':' + separator.substring(1, separator.length - 1) + ':';
              break;
          }
          return separator;
        });
        lines.push('| ' + separators.join(' | ') + ' |');
      }
    });

    return lines.join('\n');
  }

  /**
   * 获取表格列的标准化宽度（用于UI渲染）
   * @param tableColumns 表格列信息
   * @param totalWidth 表格总宽度
   * @param minColumnWidth 最小列宽度，默认为60
   * @returns 每列的实际宽度数组
   */
  getTableColumnWidths(
    tableColumns: TableColumn[],
    totalWidth: number,
    minColumnWidth: number = 60
  ): number[] {
    if (!tableColumns || tableColumns.length === 0) {
      return [];
    }

    // 计算基础宽度
    const baseWidths = tableColumns.map(column =>
    Math.max(minColumnWidth, column.relativeWidth * totalWidth)
    );

    // 确保总宽度不超出限制
    const currentTotal = baseWidths.reduce((sum, width) => sum + width, 0);
    if (currentTotal > totalWidth) {
      const ratio = totalWidth / currentTotal;
      return baseWidths.map(width => Math.max(minColumnWidth, width * ratio));
    }

    return baseWidths;
  }

  /**
   * 获取单元格的对齐样式
   * @param alignment 表格对齐方式
   * @returns 对应的Flex对齐样式字符串
   */
  getCellAlignment(alignment: TableAlignment): string {
    switch (alignment) {
      case TableAlignment.LEFT:
        return 'flex-start';
      case TableAlignment.CENTER:
        return 'center';
      case TableAlignment.RIGHT:
        return 'flex-end';
      default:
        return 'flex-start';
    }
  }

  /**
   * 解析段落，支持多行合并
   * @param lines 行数组
   * @param startIndex 起始索引
   * @returns 段落解析结果
   */
  private parseParagraphBlock(lines: string[], startIndex: number): ParagraphResult {
    const collectedLines: string[] = [];
    let i = startIndex;

    while (i < lines.length) {
      const rawLine = lines[i];
      const trimmedLine = rawLine.trim();

      if (trimmedLine === '') {
        i++;
        break;
      }

      if (this.startsNewBlock(trimmedLine)) {
        break;
      }

      collectedLines.push(trimmedLine);
      i++;
    }

    const paragraph: ParagraphResult = {
      block: {
        type: MarkdownBlockType.PARAGRAPH,
        content: collectedLines.join(' ')
      },
      nextIndex: i
    };

    return paragraph;
  }

  /**
   * 解析文本格式化
   * @param text 要解析的文本
   * @returns 文本格式化片段数组
   */
  parseTextFormatting(text: string): TextSegment[] {
    const segments: TextSegment[] = [];

    // 先处理链接 [文本](URL)
    const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g;
    let lastIndex = 0;
    let match: RegExpExecArray | null;

    // 重置正则表达式
    linkRegex.lastIndex = 0;

    while ((match = linkRegex.exec(text)) !== null) {
      // 处理链接前的文本
      if (match.index > lastIndex) {
        const beforeText = text.substring(lastIndex, match.index);
        segments.push(...this.parseFormattingWithoutLinks(beforeText));
      }

      // 处理链接文本
      const linkText = match[1];
      const url = match[2];

      // 为链接文本添加链接属性
      const linkSegments = this.parseFormattingWithoutLinks(linkText);
      linkSegments.forEach(segment => {
        segment.isLink = true;
        if (url) { // 确保url不为空
          segment.url = url;
        }
      });

      // 如果链接文本解析后没有任何段落，添加一个空的链接段落
      if (linkSegments.length === 0) {
        segments.push({
          text: linkText,
          bold: false,
          italic: false,
          code: false,
          strikethrough: false,
          isLink: true,
          url: url
        });
      } else {
        segments.push(...linkSegments);
      }

      lastIndex = match.index + match[0].length;
    }

    // 处理剩余文本
    if (lastIndex < text.length) {
      const remainingText = text.substring(lastIndex);
      segments.push(...this.parseFormattingWithoutLinks(remainingText));
    }

    hilog.info(DOMAIN, TAG, 'Parsed text "%{public}s" into %{public}d segments', String(text), segments.length);
    return segments;
  }

  // 解析格式化文本，不包括链接
  /**
   * 解析格式化文本，不包括链接
   * @param text 要解析的文本
   * @returns 文本格式化片段数组
   */
  private parseFormattingWithoutLinks(text: string): TextSegment[] {
    const segments: TextSegment[] = [];
    const chars = text.split('');
    let currentText = '';
    let bold = false;
    let italic = false;
    let code = false;
    let strikethrough = false;
    let i = 0;

    const pushSegment = (): void => {
      if (currentText) {
        const segment: TextSegment = {
          text: currentText,
          bold: bold,
          italic: italic,
          code: code,
          strikethrough: strikethrough,
          isLink: false
          // url属性为可选，不需要在这里初始化
        };
        segments.push(segment);
        hilog.info(DOMAIN, TAG, 'Text segment: "%{public}s", bold=%{public}s italic=%{public}s', currentText,
          String(bold), String(italic));
        currentText = '';
      }
    };

    while (i < chars.length) {
      const char = chars[i];
      const nextChar = i + 1 < chars.length ? chars[i + 1] : '';

      if (char === '*' && nextChar === '*') {
        pushSegment();
        bold = !bold;
        hilog.info(DOMAIN, TAG, 'Toggled bold to: %{public}s at position %{public}d', String(bold), i);
        i += 2;
        continue;
      }

      if (char === '*') {
        pushSegment();
        italic = !italic;
        hilog.info(DOMAIN, TAG, 'Toggled italic to: %{public}s at position %{public}d', String(italic), i);
        i++;
        continue;
      }

      if (char === '`') {
        pushSegment();
        code = !code;
        hilog.info(DOMAIN, TAG, 'Toggled code to: %{public}s at position %{public}d', String(code), i);
        i++;
        continue;
      }

      if (char === '~' && nextChar === '~') {
        pushSegment();
        strikethrough = !strikethrough;
        hilog.info(DOMAIN, TAG, 'Toggled strikethrough to: %{public}s at position %{public}d', String(strikethrough),
          i);
        i += 2;
        continue;
      }

      currentText += char;
      i++;
    }

    pushSegment();
    return segments;
  }
}
