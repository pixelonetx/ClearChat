/**
 * Constants - 应用常量定义
 * 
 * 功能说明：
 * - 集中管理应用中使用的所有常量
 * - 包含数据库配置、API设置、UI参数等
 * - 便于维护和统一管理配置项
 * 
 * 常量分类：
 * - 数据库相关：表名、版本号、连接配置
 * - API相关：超时时间、请求参数
 * - UI相关：尺寸、颜色、动画时长
 * 
 * 使用方式：
 * - 通过 Constants.CONSTANT_NAME 访问
 * - 所有常量均为只读静态属性
 * - 确保类型安全和值不可变
 */
export class Constants {
  // 数据库常量 - Database Configuration
  /** 数据库文件名 */
  static readonly DB_NAME = 'ChatDatabase.db';
  /** 数据库版本号，用于数据迁移 */
  static readonly DB_VERSION = 2;
  /** 聊天消息表名 */
  static readonly CHAT_TABLE = 'chat_messages';
  /** 应用设置表名 */
  static readonly SETTINGS_TABLE = 'app_settings';

  // API相关常量 - Network Configuration
  /** 默认网络请求超时时间（毫秒） */
  static readonly DEFAULT_TIMEOUT = 30000; // 30秒超时
}
