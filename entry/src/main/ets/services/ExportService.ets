/**
 * ExportService - 聊天记录导出服务
 *
 * 功能说明：
 * - 将对话及其消息导出为 JSON 文件
 * - 支持导出当前对话或指定对话
 * - 使用系统文件选择器让用户选择保存位置
 * - 生成结构化的 JSON 数据，便于备份和迁移
 */

import { fileIo } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ChatMessage } from './DataModels';
import { Conversation } from './ConversationModels';
import { DatabaseManager } from './DatabaseManager';
import { createLogger, LogDomain } from '../common/Logger';

const logger = createLogger('ExportService', LogDomain.DATABASE);

/**
 * OpenAI 兼容的消息结构（仅 role + content）
 */
interface OpenAIMessage {
  role: string;
  content: string;
}

/**
 * 导出的对话结构（OpenAI 兼容简单格式）
 */
interface ExportedConversation {
  title: string;
  messages: OpenAIMessage[];
}

/**
 * 导出文件的顶层结构
 */
interface ExportData {
  conversations: ExportedConversation[];
}

/**
 * 聊天记录导出服务
 */
export class ExportService {
  private static instance: ExportService;
  private databaseManager: DatabaseManager;

  private constructor() {
    this.databaseManager = DatabaseManager.getInstance();
  }

  static getInstance(): ExportService {
    if (!ExportService.instance) {
      ExportService.instance = new ExportService();
    }
    return ExportService.instance;
  }

  /**
   * 导出单个对话为 JSON
   * @param conversation 要导出的对话
   * @param messages 对话的消息列表（可选，若不提供则从数据库加载）
   * @returns 是否导出成功
   */
  async exportConversation(conversation: Conversation, messages?: ChatMessage[]): Promise<boolean> {
    try {
      // 获取消息
      let chatMessages: ChatMessage[];
      if (messages && messages.length > 0) {
        chatMessages = messages;
      } else {
        chatMessages = await this.databaseManager.getChatMessages(conversation.id, 10000);
      }

      // 构建导出数据
      const exportData = this.buildExportData([conversation], [chatMessages]);

      // 序列化为 JSON
      const jsonString = JSON.stringify(exportData, null, 2);

      // 生成文件名
      const fileName = this.generateFileName(conversation.title);

      // 保存文件
      return await this.saveToFile(jsonString, fileName);
    } catch (error) {
      logger.error('Export conversation failed: %{public}s', String(error));
      throw new Error(`导出失败: ${String(error)}`);
    }
  }

  /**
   * 导出所有对话为 JSON
   * @returns 是否导出成功
   */
  async exportAllConversations(): Promise<boolean> {
    try {
      const conversations = await this.databaseManager.getAllConversations();
      if (conversations.length === 0) {
        throw new Error('没有可导出的对话');
      }

      const allMessages: ChatMessage[][] = [];
      for (const conv of conversations) {
        const msgs = await this.databaseManager.getChatMessages(conv.id, 10000);
        allMessages.push(msgs);
      }

      const exportData = this.buildExportData(conversations, allMessages);
      const jsonString = JSON.stringify(exportData, null, 2);
      const fileName = this.generateFileName('全部对话');

      return await this.saveToFile(jsonString, fileName);
    } catch (error) {
      logger.error('Export all conversations failed: %{public}s', String(error));
      throw new Error(`导出全部对话失败: ${String(error)}`);
    }
  }

  /**
   * 构建 OpenAI 兼容的导出数据结构
   */
  private buildExportData(conversations: Conversation[], allMessages: ChatMessage[][]): ExportData {
    const exportedConversations: ExportedConversation[] = [];

    for (let i = 0; i < conversations.length; i++) {
      const conv = conversations[i];
      const messages = i < allMessages.length ? allMessages[i] : [];

      const openAIMessages: OpenAIMessage[] = messages.map((msg): OpenAIMessage => {
        return {
          role: msg.role,
          content: msg.content
        };
      });

      exportedConversations.push({
        title: conv.title,
        messages: openAIMessages
      });
    }

    return {
      conversations: exportedConversations
    };
  }

  /**
   * 使用系统文件选择器保存文件
   */
  private async saveToFile(content: string, fileName: string): Promise<boolean> {
    try {
      // 使用 DocumentViewPicker 让用户选择保存位置
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [fileName];
      documentSaveOptions.fileSuffixChoices = ['.json'];

      const documentPicker = new picker.DocumentViewPicker();
      const saveResult = await documentPicker.save(documentSaveOptions);

      if (!saveResult || saveResult.length === 0) {
        logger.info('User cancelled export');
        return false;
      }

      const uri = saveResult[0];
      logger.info('Saving export to: %{public}s', uri);

      // 将字符串编码为 ArrayBuffer 并写入文件
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE);
      try {
        const textEncoder = new util.TextEncoder();
        const uint8Array = textEncoder.encodeInto(content);
        fileIo.writeSync(file.fd, uint8Array.buffer);
      } finally {
        fileIo.closeSync(file);
      }

      logger.info('Export saved successfully, file: %{public}s', fileName);
      return true;
    } catch (error) {
      logger.error('Save to file failed: %{public}s', String(error));
      throw new Error(`保存文件失败: ${String(error)}`);
    }
  }

  /**
   * 生成导出文件名
   */
  private generateFileName(title: string): string {
    const now = new Date();
    const dateStr = `${now.getFullYear()}${(now.getMonth() + 1).toString().padStart(2, '0')}${now.getDate().toString().padStart(2, '0')}`;
    const timeStr = `${now.getHours().toString().padStart(2, '0')}${now.getMinutes().toString().padStart(2, '0')}`;

    // 清理文件名中的非法字符
    const cleanTitle = title
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, '_')
      .substring(0, 30);

    return `ClearChat_${cleanTitle}_${dateStr}_${timeStr}.json`;
  }

}
