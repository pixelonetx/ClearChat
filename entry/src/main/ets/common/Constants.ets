/**
 * Constants.ets
 * 应用常量定义
 * 
 * 职责：集中管理所有常量，避免魔法数字和字符串
 */

/**
 * 应用配置常量
 */
export class AppConfig {
  // 版本信息
  static readonly APP_VERSION = '0.3.2';
  static readonly VERSION_CODE = 10302;
  
  // 数据库配置
  static readonly DB_NAME = 'ClearChat.db';
  static readonly DB_SECURITY_LEVEL = 2; // S2
  
  // 网络配置
  static readonly REQUEST_TIMEOUT = 60000; // 60秒
  static readonly STREAM_TIMEOUT = 120000; // 120秒
  static readonly MAX_RETRY_COUNT = 3;
  static readonly RETRY_DELAY = 1000; // 1秒
  
  // UI配置
  static readonly SIDEBAR_WIDTH = 300;
  static readonly ANIMATION_DURATION = 300;
  static readonly TOAST_DURATION = 2000;
  static readonly DEBOUNCE_DELAY = 300;
  
  // 消息配置
  static readonly MAX_MESSAGE_LENGTH = 10000;
  static readonly MAX_HISTORY_MESSAGES = 10;
  static readonly TITLE_GENERATION_MIN_MESSAGES = 4;
  
  // 搜索配置
  static readonly SEARCH_RESULT_LIMIT = 10;
  static readonly SEARCH_CACHE_SIZE = 100;
}

/**
 * 存储键常量
 */
export class StorageKeys {
  // AppStorage 键
  static readonly SETTINGS_VERSION = 'settingsVersion';
  static readonly CONVERSATIONS_VERSION = 'conversationsReloadVersion';
  static readonly THEME_MODE = 'themeMode';
  
  // Preferences 键
  static readonly LAST_CONVERSATION_ID = 'lastConversationId';
  static readonly WEB_SEARCH_ENABLED = 'webSearchEnabled';
  static readonly SELECTED_PROVIDER_ID = 'selectedProviderId';
  static readonly SELECTED_MODEL_ID = 'selectedModelId';
}

/**
 * 路由路径常量
 */
export class RoutePaths {
  static readonly INDEX = 'Index';
  static readonly CHAT = 'Chat';
  static readonly SETTINGS = 'Settings';
  static readonly MODEL_SETTINGS = 'ModelSettings';
  static readonly SEARCH_SERVICES = 'SearchServices';
  static readonly WEB_BROWSER = 'WebBrowser';
}

/**
 * 日志域常量
 */
export class LogDomains {
  static readonly APP = 0x0000;
  static readonly NETWORK = 0x0001;
  static readonly DATABASE = 0x0002;
  static readonly UI = 0x0003;
  static readonly STREAM = 0x0004;
  static readonly SEARCH = 0x000A;
}

/**
 * 消息角色
 */
export type MessageRole = 'user' | 'assistant' | 'tool';

/**
 * 搜索服务类型
 */
export type SearchServiceType = 
  | 'tavily' 
  | 'exa' 
  | 'zhipu' 
  | 'searxng' 
  | 'brave' 
  | 'metaso' 
  | 'google_custom_search';

/**
 * 主题模式
 */
export enum ThemeMode {
  SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

/**
 * 断点类型
 */
export enum BreakpointType {
  SM = 'sm',  // 0-600vp 手机
  MD = 'md',  // 600-840vp 折叠屏
  LG = 'lg'   // 840vp+ 平板
}

/**
 * 断点阈值
 */
export class Breakpoints {
  static readonly SM_MAX = 600;
  static readonly MD_MAX = 840;
  
  static getType(width: number): BreakpointType {
    if (width < Breakpoints.SM_MAX) {
      return BreakpointType.SM;
    } else if (width < Breakpoints.MD_MAX) {
      return BreakpointType.MD;
    }
    return BreakpointType.LG;
  }
}

/**
 * 动画曲线
 */
export class AnimationCurves {
  static readonly EASE_OUT = Curve.EaseOut;
  static readonly EASE_IN_OUT = Curve.EaseInOut;
  static readonly SPRING = Curve.FastOutSlowIn;
}

/**
 * 颜色资源引用
 */
export class ColorResources {
  static readonly BG_PRIMARY = $r('app.color.common_background');
  static readonly BG_SECONDARY = $r('app.color.bg_secondary');
  static readonly TEXT_PRIMARY = $r('app.color.text_color');
  static readonly TEXT_SECONDARY = $r('app.color.text_secondary');
  static readonly ACCENT = $r('app.color.accent');
  static readonly ERROR = $r('app.color.error_color');
  static readonly BORDER_PRIMARY = $r('app.color.border_primary');
}

/**
 * 图标资源引用
 */
export class IconResources {
  static readonly SEND = $r('app.media.send_plane_line');
  static readonly STOP = $r('app.media.rectangle_on_rectangle');
  static readonly ADD = $r('app.media.send_plane_line');
  static readonly DELETE = $r('app.media.trash');
  static readonly SETTINGS = $r('app.media.send_plane_line');
  static readonly SEARCH = $r('app.media.send_plane_line');
  static readonly COPY = $r('app.media.arrow_go_back_line');
  static readonly REGENERATE = $r('app.media.restart_line');
  static readonly CHEVRON_DOWN = $r('app.media.chevron_down');
  static readonly CHEVRON_RIGHT = $r('app.media.chevron_right');
}

/**
 * 数据库常量（向后兼容，推荐使用 AppConfig）
 * @deprecated 请使用 AppConfig 类中的常量
 */
export class Constants {
  static readonly DB_NAME = 'ChatDatabase.db';
  static readonly DB_VERSION = 2;
  static readonly CHAT_TABLE = 'chat_messages';
  static readonly SETTINGS_TABLE = 'app_settings';
  static readonly DEFAULT_TIMEOUT = 30000;
}
