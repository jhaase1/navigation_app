import 'package:flutter/foundation.dart';

enum BackupTargetKind { disabled, mock, drive }

/// Which backup target this build runs against.
///
/// - [BackupTargetKind.mock] whenever `BACKUP_MOCK` is set, on any platform,
///   so the screenshot rig never touches a real account.
/// - [BackupTargetKind.drive] only on macOS and iOS, the platforms
///   `google_sign_in` supports, and only when the shared account is
///   configured with `--dart-define=BACKUP_GOOGLE_ACCOUNT`. The address is a
///   build-time value rather than source because the repository is public.
/// - Otherwise [BackupTargetKind.disabled]: the pill reads "Not backed up".
BackupTargetKind selectBackupTarget({
  required bool useMock,
  required String googleAccount,
  required TargetPlatform platform,
  bool isWeb = false,
}) {
  if (useMock) return BackupTargetKind.mock;
  if (googleAccount.trim().isEmpty || isWeb) return BackupTargetKind.disabled;
  return switch (platform) {
    TargetPlatform.macOS || TargetPlatform.iOS => BackupTargetKind.drive,
    _ => BackupTargetKind.disabled,
  };
}
