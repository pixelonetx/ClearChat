import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { window, KeyboardAvoidMode, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppPreferences } from '../services/AppPreferences';
import { SearchConfigManager } from '../services/search/SearchConfigManager';
import { createLogger, LogDomain } from '../common/Logger';

const logger = createLogger('EntryAbility', LogDomain.APP);

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.info('Ability onCreate');
    
    // 初始化应用偏好设置
    AppPreferences.init(this.context);
    
    // 初始化搜索配置管理器
    try {
      const searchConfigManager = SearchConfigManager.getInstance();
      searchConfigManager.init(this.context).then(() => {
        logger.info('Search config manager initialized');
      }).catch((error: Object) => {
        const err = error instanceof Error ? error : new Error(String(error));
        logger.warn('Failed to initialize search config: %{public}s', err.message);
      });
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.warn('Search config initialization error: %{public}s', err.message);
    }
    
    // 保存当前颜色模式到 AppStorage
    AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
  }

  onDestroy(): void {
    logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    logger.info('Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        return;
      }
      logger.info('Succeeded in loading the content.');

      let windowClass: window.Window = windowStage.getMainWindowSync(); // 获取应用主窗口
      // 设置窗口全屏
      let isLayoutFullScreen = true;
      windowClass.setWindowLayoutFullScreen(isLayoutFullScreen).then(() => {
        logger.info('Succeeded in setting the window layout to full-screen mode.');
      }).catch((err: BusinessError) => {
        logger.error('Failed to set the window layout to full-screen mode. Code is %{public}d, message is %{public}s', err.code, err.message);
      });
      // 获取布局避让遮挡的区域
      let type = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR; // 此处以导航条避让为例
      let avoidArea = windowClass.getWindowAvoidArea(type);
      let bottomRectHeight = avoidArea.bottomRect.height; // 获取到导航区域的高度
      AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);

      type = window.AvoidAreaType.TYPE_SYSTEM; // 以状态栏避让为例
      avoidArea = windowClass.getWindowAvoidArea(type);
      let topRectHeight = avoidArea.topRect.height; // 获取状态栏区域高度
      AppStorage.setOrCreate('topRectHeight', topRectHeight);

      // 获取键盘初始高度
      const keyboardType = window.AvoidAreaType.TYPE_KEYBOARD;
      const keyboardArea = windowClass.getWindowAvoidArea(keyboardType);
      AppStorage.setOrCreate('keyboardHeight', keyboardArea.bottomRect.height);

      // 注册监听函数，动态获取避让区域数据
      windowClass.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          let topRectHeight = data.area.topRect.height;
          AppStorage.setOrCreate('topRectHeight', topRectHeight);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          let bottomRectHeight = data.area.bottomRect.height;
          AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);
        } else if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          // 键盘高度变化
          const keyboardHeight = data.area.bottomRect.height;
          AppStorage.setOrCreate('keyboardHeight', keyboardHeight);
          logger.debug('Keyboard height changed: %{public}d', keyboardHeight);
        }
      });

      // 深色模式
      let applicationContext = this.context.getApplicationContext();
      // 不在这里设置颜色模式，因为已在onCreate中根据用户首选项设置

    });
  }

  /**
   * 监听配置变更（包括深浅色模式变更）
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    logger.info('Configuration updated');

    // 更新当前颜色模式到AppStorage
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
    logger.info('Color mode changed to: %{public}d', newConfig.colorMode);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    logger.info('Ability onBackground');
  }
}
