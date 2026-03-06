import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { createLogger, LogDomain } from '../common/Logger';

const logger = createLogger('EntryBackupAbility', LogDomain.APP);

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    logger.info('onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    logger.info('onRestore ok %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
