import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { ChatMessage } from '../main/ets/services/DataModels';
import { Conversation } from '../main/ets/services/ConversationModels';
import { groupConversationsByDate as groupConversationModels } from '../main/ets/services/ConversationGroupHelper';
import { inferApiFormat } from '../main/ets/services/PresetProviders';
import { SearchCache } from '../main/ets/services/search/SearchCache';
import {
  GoogleCustomSearchOptions,
  SearchResult,
  SearchServiceOptions,
  SearXNGOptions,
  TavilyOptions
} from '../main/ets/services/search/SearchModels';
import {
  cloneChatMessage,
  containsSuspiciousContent,
  formatDateGroup,
  getFriendlyErrorMessage,
  groupConversationsByDate,
  HasUpdatedAt,
  shouldGenerateTitle
} from '../main/ets/viewmodels/ChatUtils';

function createMessage(content: string, role: 'user' | 'assistant' | 'tool'): ChatMessage {
  return new ChatMessage(content, role, {
    conversationId: 'test-conversation',
    timestamp: 1000
  });
}

function createConversation(title: string, updatedAt: number): Conversation {
  const conversation = new Conversation(title);
  conversation.id = title;
  conversation.updatedAt = updatedAt;
  return conversation;
}

function createSearchResult(title: string): SearchResult {
  return {
    items: [{
      title: title,
      url: `https://example.com/${title}`,
      text: `${title} summary`
    }],
    executionTime: 10
  };
}

export default function localUnitTest() {
  describe('chat pure utilities', () => {
    it('cloneChatMessage preserves metadata without reusing the source object', 0, () => {
      const source = new ChatMessage('hello', 'assistant', {
        conversationId: 'conv-1',
        modelName: 'gpt-test',
        providerName: 'OpenAI',
        timestamp: 123456,
        providerMessageId: 'msg-remote',
        providerCreatedAt: 123,
        systemFingerprint: 'fp-test',
        toolCallId: 'tool-call-1',
        toolCalls: [{
          id: 'call-1',
          type: 'function',
          function: {
            name: 'web_search',
            arguments: '{"query":"HarmonyOS"}'
          }
        }]
      });
      source.id = 42;

      const cloned = cloneChatMessage(source);

      expect(cloned === source).assertFalse();
      expect(cloned.id).assertEqual(42);
      expect(cloned.content).assertEqual('hello');
      expect(cloned.role).assertEqual('assistant');
      expect(cloned.conversationId).assertEqual('conv-1');
      expect(cloned.modelName).assertEqual('gpt-test');
      expect(cloned.toolCallId).assertEqual('tool-call-1');
      expect(cloned.toolCalls?.length).assertEqual(1);
    });

    it('maps common provider failures to localized user-facing errors', 0, () => {
      expect(getFriendlyErrorMessage(null)).assertEqual('发送消息失败');
      expect(getFriendlyErrorMessage(new Error('request timeout after 60s'))).assertEqual('请求超时，请稍后重试');
      expect(getFriendlyErrorMessage(new Error('401 invalid api key'))).assertEqual('API密钥无效，请检查设置');
      expect(getFriendlyErrorMessage(new Error('model does not exist'))).assertEqual('模型不可用，请检查模型ID');
      expect(getFriendlyErrorMessage(new Error('custom upstream panic'))).assertEqual('发送失败：custom upstream panic');
    });

    it('detects executable markup while allowing ordinary markdown text', 0, () => {
      expect(containsSuspiciousContent('<script>alert(1)</script>')).assertTrue();
      expect(containsSuspiciousContent('javascript:alert(1)')).assertTrue();
      expect(containsSuspiciousContent('<img src=x onclick=alert(1)>')).assertTrue();
      expect(containsSuspiciousContent('普通 **Markdown** 文本 https://example.com')).assertFalse();
    });

    it('decides title generation only after enough useful conversation context exists', 0, () => {
      const usefulMessages: ChatMessage[] = [
        createMessage('帮我分析 HarmonyOS ArkTS 项目的架构问题', 'user'),
        createMessage('可以，我会从页面、服务和数据层看起。', 'assistant'),
        createMessage('重点看发布前风险', 'user'),
        createMessage('核心风险包括流式状态、数据库事务和 UI 重渲染。', 'assistant')
      ];
      const shortGreeting: ChatMessage[] = [
        createMessage('你好', 'user'),
        createMessage('你好', 'assistant'),
        createMessage('在吗', 'user'),
        createMessage('在的', 'assistant')
      ];

      expect(shouldGenerateTitle(usefulMessages, '新对话')).assertTrue();
      expect(shouldGenerateTitle(usefulMessages, '已命名对话')).assertFalse();
      expect(shouldGenerateTitle(usefulMessages.slice(0, 3), '新对话')).assertFalse();
      expect(shouldGenerateTitle(shortGreeting, '新对话')).assertFalse();
    });

    it('formats and groups timestamps into stable date buckets', 0, () => {
      const now = Date.now();
      const oneDayMs = 24 * 60 * 60 * 1000;
      const items: HasUpdatedAt[] = [
        { updatedAt: now },
        { updatedAt: now - 3 * oneDayMs },
        { updatedAt: now - 40 * oneDayMs }
      ];

      expect(formatDateGroup(now)).assertEqual('今天');
      expect(formatDateGroup(now - 3 * oneDayMs)).assertEqual('最近7天');
      expect(formatDateGroup(now - 40 * oneDayMs)).assertEqual('更早');

      const groups = groupConversationsByDate(items);
      expect(groups['今天'].length).assertEqual(1);
      expect(groups['最近7天'].length).assertEqual(1);
      expect(groups['更早'].length).assertEqual(1);
    });
  });

  describe('conversation grouping helper', () => {
    it('sorts conversations newest first and groups by release-facing buckets', 0, () => {
      const now = new Date();
      const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
      const oneDayMs = 24 * 60 * 60 * 1000;
      const conversations: Conversation[] = [
        createConversation('month', todayStart - 15 * oneDayMs),
        createConversation('newer-today', todayStart + 20),
        createConversation('older-today', todayStart + 10),
        createConversation('yesterday', todayStart - 1),
        createConversation('older', todayStart - 45 * oneDayMs)
      ];

      const groups = groupConversationModels(conversations);

      expect(groups['today'].length).assertEqual(2);
      expect(groups['today'][0].title).assertEqual('newer-today');
      expect(groups['today'][1].title).assertEqual('older-today');
      expect(groups['yesterday'][0].title).assertEqual('yesterday');
      expect(groups['this_month'][0].title).assertEqual('month');
      expect(groups['older'][0].title).assertEqual('older');
    });
  });

  describe('provider and search configuration helpers', () => {
    it('infers API format from known provider base URLs', 0, () => {
      expect(inferApiFormat('https://api.anthropic.com/v1/messages')).assertEqual('anthropic');
      expect(inferApiFormat('https://generativelanguage.googleapis.com/v1beta/models')).assertEqual('gemini');
      expect(inferApiFormat('https://api.openai.com/v1/chat/completions')).assertEqual('openai');
      expect(inferApiFormat('https://openrouter.ai/api/v1/chat/completions')).assertEqual('openai');
    });

    it('round-trips search service options through json factories', 0, () => {
      const tavily = SearchServiceOptions.fromJson(new TavilyOptions('search-1', 'tk-test').toJson()) as TavilyOptions;
      expect(tavily.type).assertEqual('tavily');
      expect(tavily.id).assertEqual('search-1');
      expect(tavily.apiKey).assertEqual('tk-test');

      const searxngJson: Record<string, Object | string | number | boolean | null> = {};
      searxngJson['type'] = 'searxng';
      searxngJson['id'] = 'sx';
      searxngJson['url'] = 'https://search.example.com';
      const searxng = SearchServiceOptions.fromJson(searxngJson) as SearXNGOptions;
      expect(searxng.engines).assertEqual('');
      expect(searxng.language).assertEqual('');
      expect(searxng.url).assertEqual('https://search.example.com');

      const google = SearchServiceOptions.fromJson(
        new GoogleCustomSearchOptions('gcs', 'api-key', 'engine-id').toJson()
      ) as GoogleCustomSearchOptions;
      expect(google.type).assertEqual('google_custom_search');
      expect(google.searchEngineId).assertEqual('engine-id');
    });
  });

  describe('search cache', () => {
    const cache = SearchCache.getInstance();

    beforeEach(() => {
      cache.clear();
      cache.setConfig({
        maxEntries: 50,
        ttlMs: 5 * 60 * 1000,
        enabled: true
      });
    });

    it('uses normalized cache keys and respects disabled state', 0, () => {
      const result = createSearchResult('HarmonyOS');

      cache.set(' HarmonyOS ', 'tavily', 5, result);
      expect(cache.get('harmonyos', 'tavily', 5)?.items[0].title).assertEqual('HarmonyOS');
      expect(cache.get('harmonyos', 'tavily', 3)).assertNull();

      cache.setConfig({ enabled: false });
      expect(cache.get('harmonyos', 'tavily', 5)).assertNull();
    });

    it('evicts old entries and clears entries by service type', 0, () => {
      cache.setConfig({ maxEntries: 2 });
      cache.set('first', 'tavily', 5, createSearchResult('first'));
      cache.set('second', 'exa', 5, createSearchResult('second'));
      cache.set('third', 'tavily', 5, createSearchResult('third'));

      expect(cache.get('first', 'tavily', 5)).assertNull();
      expect(cache.get('second', 'exa', 5)?.items[0].title).assertEqual('second');
      expect(cache.getStats().size).assertEqual(2);

      cache.clearByServiceType('tavily');
      expect(cache.get('third', 'tavily', 5)).assertNull();
      expect(cache.get('second', 'exa', 5)?.items[0].title).assertEqual('second');
    });

    it('expires stale search results during lookup and cleanup', 0, () => {
      cache.setConfig({ ttlMs: -1 });
      cache.set('stale', 'tavily', 5, createSearchResult('stale'));

      expect(cache.get('stale', 'tavily', 5)).assertNull();
      expect(cache.cleanupExpired()).assertEqual(0);
    });
  });
}
