import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/drive/google_drive_account.dart';

/// Settings → Data: who backups go to, and the one place sign-in happens.
///
/// The backup engine never prompts. When the pill says Drive needs a
/// sign-in, this tile is where the operator goes to give it one.
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
              : _signIn(context),
        );
      },
    );
  }

  Future<void> _signIn(BuildContext context) async {
    try {
      await account.signIn();
    } on GoogleSignInException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Google sign-in failed: ${e.description ?? e.code.name}')));
      return;
    }
    if (account.status.value.state == DriveAccountState.signedIn) {
      // Don't make the operator wait out the 10-minute sweep to see green.
      await controller.retryNow();
    }
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
