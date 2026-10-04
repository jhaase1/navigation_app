import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';

import 'backup_target_contract.dart';

void main() {
  runBackupTargetContract('MockBackupTarget', () async {
    final mock = MockBackupTarget();
    return ContractHarness(mock, mock.advanceClock);
  });
}
