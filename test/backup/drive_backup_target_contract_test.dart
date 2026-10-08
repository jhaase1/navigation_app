import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/drive/drive_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_target_contract.dart';
import 'support/fake_drive.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  runBackupTargetContract('DriveBackupTarget', () async {
    final drive = FakeDrive();
    final target = DriveBackupTarget(
      client: drive.client,
      account: 'ops@example.com',
      now: () => drive.clock,
    );
    return ContractHarness(target, drive.advanceClock);
  });
}
