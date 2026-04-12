/**
 * ConversationGroupHelper.ets
 * 对话分组工具
 *
 * 职责：将对话列表按日期分组（今天、昨天、本周、本月、更早）
 */

import { Conversation } from './ConversationModels';

/**
 * 按日期分组对话列表
 * @param conversations 对话列表
 * @returns 分组后的记录，key 为日期标签
 */
export function groupConversationsByDate(conversations: Conversation[]): Record<string, Conversation[]> {
  const groups: Record<string, Conversation[]> = {};

  const sortedConversations = [...conversations].sort((a, b) =>
    new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
  );

  sortedConversations.forEach(conversation => {
    const date = new Date(conversation.updatedAt);
    const dateKey = getDateKey(date);

    if (!groups[dateKey]) {
      groups[dateKey] = [];
    }
    groups[dateKey].push(conversation);
  });

  return groups;
}

/**
 * 生成日期分组的 key
 * @param date 日期
 * @returns 分组标签
 */
function getDateKey(date: Date): string {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const conversationDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());

  const timeDiff = today.getTime() - conversationDate.getTime();
  const daysDiff = Math.floor(timeDiff / (1000 * 60 * 60 * 24));

  if (daysDiff === 0) {
    return 'today';
  } else if (daysDiff === 1) {
    return 'yesterday';
  } else if (daysDiff >= 2 && daysDiff <= 7) {
    return 'this_week';
  } else if (daysDiff >= 8 && daysDiff <= 30) {
    return 'this_month';
  } else {
    const conversationYear = date.getFullYear();
    const conversationMonth = date.getMonth() + 1;
    return `${conversationYear}-${conversationMonth.toString().padStart(2, '0')}`;
  }
}
