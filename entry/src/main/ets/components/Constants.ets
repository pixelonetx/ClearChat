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
}
