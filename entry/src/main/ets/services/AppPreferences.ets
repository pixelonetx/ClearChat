/**
 * AppPreferences - 应用偏好设置管理
 * 
 * 管理应用的各种偏好设置：主题模式、字体大小等
 * 简化版本：直接使用 AppStorage 和 preferences，使用静态方法
 */

import { preferences } from '@kit.ArkData';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';

const PREFERENCES_NAME = 'app_settings';
const KEY_THEME_MODE = 'theme_mode';
const KEY_FONT_SIZE = 'font_size';
const KEY_AUTO_EXPAND_THINKING = 'auto_expand_thinking';

/**
 * 主题模式枚举
 */
export enum ThemeMode {
  /** 跟随系统 */
  AUTO = 0,
  /** 浅色模式 */
  LIGHT = 1,
  /** 深色模式 */
  DARK = 2
}

/**
 * 字体大小枚举
 */
export enum FontSize {
  /** 小 */
  SMALL = 0,
  /** 标准 */
  MEDIUM = 1,
  /** 大 */
  LARGE = 2
}

/**
 * 应用偏好设置工具类
 */
export class AppPreferences {
  /**
   * 初始化主题设置
   */
  static init(context: common.Context): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const savedMode = prefs.getSync(KEY_THEME_MODE, ThemeMode.AUTO) as number;
      const autoExpandThinking = prefs.getSync(KEY_AUTO_EXPAND_THINKING, true) as boolean;
      
      // 保存到 AppStorage
      AppStorage.setOrCreate('themeMode', savedMode);
      AppStorage.setOrCreate('autoExpandThinking', autoExpandThinking);
      
      // 应用主题
      AppPreferences.applyTheme(context, savedMode);
    } catch (err) {
      console.error('Failed to init theme:', err);
    }
  }

  /**
   * 设置主题模式
   */
  static setTheme(context: common.Context, mode: ThemeMode): void {
    try {
      // 保存到 preferences
      const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      prefs.putSync(KEY_THEME_MODE, mode);
      prefs.flush();
      
      // 更新 AppStorage
      AppStorage.setOrCreate('themeMode', mode);
      
      // 应用主题
      AppPreferences.applyTheme(context, mode);
    } catch (err) {
      console.error('Failed to set theme:', err);
    }
  }

  /**
   * 应用主题
   */
  private static applyTheme(context: common.Context, mode: ThemeMode): void {
    try {
      const colorMode = AppPreferences.toColorMode(mode);
      context.getApplicationContext().setColorMode(colorMode);
    } catch (err) {
      console.error('Failed to apply theme:', err);
    }
  }

  /**
   * 转换为系统颜色模式
   */
  static toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
    switch (mode) {
      case ThemeMode.LIGHT:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      case ThemeMode.DARK:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
  }

  /**
   * 获取显示名称
   */
  static getDisplayName(mode: ThemeMode): string {
    switch (mode) {
      case ThemeMode.AUTO:
        return '跟随系统';
      case ThemeMode.LIGHT:
        return '浅色';
      case ThemeMode.DARK:
        return '深色';
      default:
        return '未知';
    }
  }

  /**
   * 设置是否自动展开思考过程
   */
  static setAutoExpandThinking(context: common.Context, enabled: boolean): void {
    try {
      const prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      prefs.putSync(KEY_AUTO_EXPAND_THINKING, enabled);
      prefs.flush();

      AppStorage.setOrCreate('autoExpandThinking', enabled);
    } catch (err) {
      console.error('Failed to set autoExpandThinking:', err);
    }
  }
}
