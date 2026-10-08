import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/drive/google_drive_account.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';

import 'fake_sign_in_platform.dart';

const driveTestAccount = 'ops@example.com';

/// A controller wired the way a Drive build is, minus the network: real
/// [GoogleDriveAccount] over a faked sign-in platform, mock storage.
BackupController driveController(FakeSignInPlatform platform) {
  GoogleSignInPlatform.instance = platform;
  return BackupController.forService(
    BackupService(
      target: MockBackupTarget(),
      targetIdentity: 'drive:$driveTestAccount',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => {'schemaVersion': 1},
      localIsPristine: () async => true,
    ),
    driveAccount: GoogleDriveAccount(
        expectedAccount: driveTestAccount, signIn: GoogleSignIn.instance),
  );
}
