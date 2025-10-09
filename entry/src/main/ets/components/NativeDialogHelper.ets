
/**
 * 原生弹窗助手类
 * 提供各种原生弹窗的便捷方法
 */
export class NativeDialogHelper {

  /**
   * 显示删除确认对话框
   * @param title 删除的对象名称
   * @param message 额外的警告消息（可选）
   * @param onConfirm 确认回调
   * @param onCancel 取消回调（可选）
   */
  static showDeleteConfirmDialog(
    title: string,
    message?: string,
    onConfirm?: () => void,
    onCancel?: () => void
  ): void {
    const dialogMessage = message
      ? `确定要删除"${title}"吗？\n\n${message}`
      : `确定要删除"${title}"吗？\n\n此操作无法撤销。`;

    AlertDialog.show({
      title: '删除确认',
      message: dialogMessage,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        fontColor: '#666666',
        action: () => {
          onCancel?.();
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF4757',
        action: () => {
          onConfirm?.();
        }
      },
      cancel: () => {
        onCancel?.();
      }
    });
  }

  /**
   * 显示警告对话框
   * @param title 标题
   * @param message 消息内容
   * @param onConfirm 确认回调
   * @param onCancel 取消回调（可选）
   */
  static showWarningDialog(
    title: string,
    message: string,
    onConfirm?: () => void,
    onCancel?: () => void
  ): void {
    AlertDialog.show({
      title: title,
      message: message,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        fontColor: '#666666',
        action: () => {
          onCancel?.();
        }
      },
      secondaryButton: {
        value: '确认',
        fontColor: '#FFA726',
        action: () => {
          onConfirm?.();
        }
      },
      cancel: () => {
        onCancel?.();
      }
    });
  }

  /**
   * 显示信息对话框（只有确认按钮）
   * @param title 标题
   * @param message 消息内容
   * @param onConfirm 确认回调（可选）
   */
  static showInfoDialog(
    title: string,
    message: string,
    onConfirm?: () => void
  ): void {
    AlertDialog.show({
      title: title,
      message: message,
      autoCancel: true,
      confirm: {
        value: '确认',
        fontColor: '#007AFF',
        action: () => {
          onConfirm?.();
        }
      }
    });
  }

  // /**
  //  * 显示清除所有数据确认对话框
  //  * @param onConfirm 确认回调
  //  * @param onCancel 取消回调（可选）
  //  */
  // static showClearAllDataDialog(
  //   onConfirm?: () => void,
  //   onCancel?: () => void
  // ): void {
  //   AlertDialog.show({
  //     title: '清除所有数据',
  //     message: '此操作将删除所有对话记录、模型配置和设置信息。\n\n此操作无法撤销，请谨慎操作！',
  //     autoCancel: true,
  //     primaryButton: {
  //       value: '取消',
  //       fontColor: '#666666',
  //       action: () => {
  //         onCancel?.();
  //       }
  //     },
  //     secondaryButton: {
  //       value: '清除',
  //       fontColor: '#FF4757',
  //       action: () => {
  //         onConfirm?.();
  //       }
  //     },
  //     cancel: () => {
  //       onCancel?.();
  //     }
  //   });
  // }
}
