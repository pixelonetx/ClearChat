/**
 * 事务管理器 - 提供数据库事务支持
 *
 * 功能说明：
 * - 确保复杂数据库操作的原子性
 * - 在操作失败时自动回滚
 * - 提供统一的事务处理接口
 *
 * 使用示例：
 * const result = await transactionManager.executeInTransaction(async () => {
 *   await db.delete(...);
 *   await db.insert(...);
 * });
 */

import { relationalStore } from '@kit.ArkData';
import { DatabaseError } from '../common/ErrorHandler';
import { createLogger, LogDomain } from '../common/Logger';

const logger = createLogger('TransactionManager', LogDomain.DATABASE);

/**
 * 事务管理器 - 负责管理数据库事务
 */
export class TransactionManager {
  private rdbStore: relationalStore.RdbStore;

  constructor(rdbStore: relationalStore.RdbStore) {
    this.rdbStore = rdbStore;
  }

  /**
   * 在事务中执行操作
   * @param operation 需要执行的数据库操作函数
   * @returns 操作结果
   * @throws DatabaseError 如果操作失败或事务提交失败
   *
   * 特性：
   * - 自动开始事务
   * - 操作成功时自动提交
   * - 操作失败时自动回滚
   * - 异常时抛出 DatabaseError
   */
  async executeInTransaction<T>(operation: () => Promise<T>): Promise<T> {
    let transactionStarted = false;

    try {
      logger.info('Starting transaction');

      // 开始事务
      await this.rdbStore.beginTransaction();
      transactionStarted = true;

      // 执行用户提供的操作
      const result = await operation();

      // 提交事务
      await this.rdbStore.commit();
      logger.info('Transaction committed successfully');

      return result;
    } catch (error) {
      // 如果事务已开始，执行回滚
      if (transactionStarted) {
        try {
          await this.rdbStore.rollBack();
          logger.info('Transaction rolled back successfully');
        } catch (rollbackError) {
          logger.error('Failed to rollback transaction: %{public}s', String(rollbackError));
        }
      }

      // 包装错误并抛出
      const errorMessage = `Transaction execution failed: ${error}`;
      logger.error('Transaction execution failed: %{public}s', String(error));
      throw new DatabaseError(errorMessage);
    }
  }

  /**
   * 在事务中执行多个操作（顺序执行）
   * @param operations 操作数组
   * @returns 所有操作的结果数组
   * @throws DatabaseError 如果任何操作或事务失败
   *
   * 用途：当需要在一个事务中执行多个操作时
   */
  async executeMultipleInTransaction<T>(
    operations: Array<() => Promise<T>>
  ): Promise<T[]> {
    try {
      return await this.executeInTransaction(async () => {
        const results: T[] = [];

        for (const operation of operations) {
          const result = await operation();
          results.push(result);
        }

        return results;
      });
    } catch (error) {
      // 重新抛出异常，由调用者处理
      if (error instanceof DatabaseError) {
        const dbError: DatabaseError = error as DatabaseError;
        throw dbError;
      }
      throw new DatabaseError(`Operation failed: ${error}`);
    }
  }
}
