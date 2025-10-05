/**
 * 应用常量定义
 */
export class Constants {
  // 数据库常量
  static readonly DB_NAME = 'ChatDatabase.db';
  static readonly DB_VERSION = 2;
  static readonly CHAT_TABLE = 'chat_messages';
  static readonly SETTINGS_TABLE = 'app_settings';

  // API相关常量
  static readonly DEFAULT_TIMEOUT = 30000; // 30秒超时
  // UI常量
  static readonly AVATAR_SIZE = 40;
  static readonly MESSAGE_MARGIN = 12;
  static readonly INPUT_MIN_HEIGHT = 40;
  static readonly INPUT_MAX_HEIGHT = 120;

  // 默认配置
  static readonly DEFAULT_API_URL = 'https://api.openai.com/v1/chat/completions';
  static readonly DEFAULT_MODEL_NAME = 'gpt-3.5-turbo';
}
