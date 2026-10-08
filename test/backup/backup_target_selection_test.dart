import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_target_selection.dart';

void main() {
  const account = 'ops@example.com';

  BackupTargetKind select({
    bool mock = false,
    String googleAccount = account,
    TargetPlatform platform = TargetPlatform.macOS,
    bool isWeb = false,
  }) =>
      selectBackupTarget(
        useMock: mock,
        googleAccount: googleAccount,
        platform: platform,
        isWeb: isWeb,
      );

  test('Drive runs on the Mac and the iPad when an account is configured', () {
    expect(select(platform: TargetPlatform.macOS), BackupTargetKind.drive);
    expect(select(platform: TargetPlatform.iOS), BackupTargetKind.drive);
  });

  test('no configured account means no backup, never a guess', () {
    expect(select(googleAccount: ''), BackupTargetKind.disabled);
    expect(select(googleAccount: '   '), BackupTargetKind.disabled);
  });

  test('platforms without Google sign-in stay disabled', () {
    for (final p in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.fuchsia,
    ]) {
      expect(select(platform: p), BackupTargetKind.disabled, reason: '$p');
    }
    expect(select(isWeb: true), BackupTargetKind.disabled);
  });

  test('the mock wins everywhere, so the screenshot rig never touches Drive',
      () {
    expect(select(mock: true), BackupTargetKind.mock);
    expect(select(mock: true, platform: TargetPlatform.windows),
        BackupTargetKind.mock);
    expect(select(mock: true, googleAccount: ''), BackupTargetKind.mock);
  });
}
