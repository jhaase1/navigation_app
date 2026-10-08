import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/drive/google_drive_account.dart';

/// Shows Google's sign-in sheet, then — once the right account is in —
/// backs up straight away rather than waiting out the 10-minute sweep.
///
/// Every sign-in entry point (this tile, the pill's popover, the launch
/// banner) goes through here. None of them opens on its own: the backup
/// engine never prompts, so a sheet never lands on the operator mid-cue.
Future<void> signInToGoogleDrive(
  BuildContext context,
  BackupController controller,
  GoogleDriveAccount account,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await account.signIn();
  } catch (e) {
    // Every failure, not only the SDK's own: the native side reports some
    // as a bare PlatformException, and an unshown one is a dead button.
    final reason = switch (e) {
      GoogleSignInException(:final description, :final code) =>
        description ?? code.name,
      PlatformException(:final message, :final code) => message ?? code,
      _ => '$e',
    };
    messenger?.showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $reason')));
    return;
  }
  if (account.status.value.state == DriveAccountState.signedIn) {
    await controller.retryNow();
  }
}

/// Settings → Data: who backups go to, and where to sign in or out.
class GoogleDriveTile extends StatelessWidget {
  final BackupController controller;
  final GoogleDriveAccount account;

  const GoogleDriveTile(
      {super.key, required this.controller, required this.account});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DriveAccountStatus>(
      valueListenable: account.status,
      builder: (context, status, _) {
        final subtitle = switch (status.state) {
          DriveAccountState.checking => 'Checking Google sign-in…',
          DriveAccountState.signedIn =>
            'Backing up to ${status.email}. Tap to sign out.',
          DriveAccountState.signedOut =>
            'Not signed in, so nothing is being backed up. Tap to sign in.',
          DriveAccountState.wrongAccount =>
            '${status.email} is not the backup account. '
                'Tap to sign in as ${account.expectedAccount}.',
        };
        return ListTile(
          leading: Icon(
            status.state == DriveAccountState.signedIn
                ? Icons.cloud_done
                : Icons.cloud_off,
          ),
          title: const Text('Google Drive'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () => status.state == DriveAccountState.signedIn
              ? _confirmSignOut(context)
              : signInToGoogleDrive(context, controller, account),
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of Google Drive?'),
        content: const Text(
            'Backups stop on this machine until someone signs in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) await account.signOut();
  }
}
