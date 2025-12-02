/**
 * TitleGenerationService - 对话标题生成服务
 * 
 * 功能说明：
 * - 基于对话内容自动生成简洁的标题
 * - 过滤无意义的问候语，专注于核心内容
 * - 提供智能的备用标题生成策略
 * - 支持多种AI模型进行标题生成
 * 
 * 使用场景：
 * - 新对话创建时自动生成标题
 * - 对话内容更新后重新生成标题
 * - 提升用户体验，便于对话管理
 */

import { ChatMessage } from '../services/DataModels';
import { NetworkManagerV2 } from '../services/NetworkManagerV2';
import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG = 'TitleGenerationService';

export class TitleGenerationService {
  private networkManager: NetworkManagerV2;

  constructor() {
    this.networkManager = NetworkManagerV2.getInstance();
  }

  /**
   * 生成对话标题
   * @param messages 对话消息列表
   * @param apiKey API密钥
   * @param baseUrl API基础URL
   * @param model 使用的AI模型
   * @returns Promise<string> 生成的标题
   */
  async generateTitle(messages: ChatMessage[], apiKey: string, baseUrl: string, model: string): Promise<string> {
    try {
      if (!messages || messages.length === 0) {
        return this.getFallbackTitle();
      }

      // 过滤掉简单的问候语，重点关注有意义的对话内容
      const meaningfulMessages = this.filterMeaningfulMessages(messages);

      // 如果没有足够的有意义内容，返回备用标题
      if (meaningfulMessages.length < 2) {
        return this.getFallbackTitle(messages);
      }

      // 获取前几条有意义的消息作为上下文
      const contextMessages: ChatMessage[] = meaningfulMessages.slice(0, 6);
      const conversationText: string = contextMessages
        .map((msg: ChatMessage): string => `${msg.role === 'user' ? '用户' : 'AI'}: ${msg.content}`)
        .join('\n');

      const titlePrompt: string = `
      请根据以下对话内容，生成一个简洁的标题（不超过15个字）：${conversationText}
      要求：
      1. 重点关注用户的核心问题和AI的回复内容
      2. 标题要准确概括对话主题，不超过15个字
      3. 不要包含引号或特殊符号
      4. 避免使用"你好"、"问候"等简单词汇
      5. 如果用户问题简短但AI回复详细，以问题的核心内容为主
      6. 直接返回标题，不要其他文字
      标题：`;

      const requestMessages: ChatMessage[] = [
        new ChatMessage(titlePrompt, 'user', {
          conversationId: 'temp'
        })
      ];

      const response: string = await this.networkManager.sendChatRequest(
        baseUrl,
        apiKey,
        model,
        requestMessages
      );

      const title: string = response.trim();

      // 验证标题长度和内容
      if (title && title.length <= 15 && !title.includes('"') && !title.includes("'") &&
        !this.isGenericTitle(title)) {
        return title;
      } else {
        return this.getFallbackTitle(contextMessages);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Title generation failed: %{public}s', String(error));
      return this.getFallbackTitle(messages);
    }
  }

  /**
   * 过滤有意义的消息，排除简单问候语
   * @param messages 原始消息列表
   * @returns ChatMessage[] 过滤后的有意义消息列表
   */
  private filterMeaningfulMessages(messages: ChatMessage[]): ChatMessage[] {
    const greetingPatterns = [
      /^(你好|hello|hi|您好|在吗|在不在)[\s]*[?？。！!]*$/i,
      /^(早上好|晚上好|下午好)[\s]*[?？。！!]*$/i,
      /^(谢谢|thank\s*you|thanks)[\s]*[?？。！!]*$/i
    ];

    // 首先检查是否有AI的长回复，如果有说明用户问题有价值
    const aiReplies = messages.filter(msg => msg.role === 'assistant');
    const hasLongAiReply = aiReplies.some(msg => msg.content.length > 50);

    return messages.filter((msg, index) => {
      // 保留所有AI回复
      if (msg.role === 'assistant') {
        return true;
      }

      // 检查用户消息
      const content = msg.content.trim();

      // 如果AI有长回复，说明即使用户问题简短也是有意义的
      if (hasLongAiReply) {
        // 只过滤掉极简单的问候语（<=5个字符）
        if (content.length <= 5) {
          return !greetingPatterns.some(pattern => pattern.test(content));
        }
        return true;
      }

      // 如果没有长AI回复，按原逻辑过滤
      if (content.length <= 10) {
        return !greetingPatterns.some(pattern => pattern.test(content));
      }

      return true;
    });
  }

  /**
   * 检查是否为通用无意义标题
   * @param title 待检查的标题
   * @returns boolean 是否为通用标题
   */
  private isGenericTitle(title: string): boolean {
    const genericTitles = [
      '你好', '问候', '聊天', '对话', '交流', 'hello', 'hi',
      '新对话', '开始', '咨询', '询问'
    ];

    return genericTitles.some(generic =>
    title.toLowerCase().includes(generic.toLowerCase())
    );
  }

  /**
   * 生成备用标题
   * @param messages 可选的消息列表
   * @returns string 备用标题
   */
  private getFallbackTitle(messages?: ChatMessage[]): string {
    if (messages && messages.length > 0) {
      const firstUserMessage: ChatMessage | undefined = messages.find((msg: ChatMessage): boolean => msg.role === 'user');
      if (firstUserMessage) {
        const content: string = firstUserMessage.content.substring(0, 15);
        return content.length < firstUserMessage.content.length ? content + '...' : content;
      }
    }

    const now: Date = new Date();
    const timeStr: string = `${now.getMonth() + 1}月${now.getDate()}日 ${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}`;
    return `新对话 ${timeStr}`;
  }
}

