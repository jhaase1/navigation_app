import 'package:flutter/material.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/drive/google_drive_account.dart';
import 'google_drive_tile.dart';

/// A strip across the top of the app asking for a Google sign-in when this
/// machine has none, so nobody has to find the Settings tile first.
///
/// A banner, not a dialog: it never covers the controls, and "Not now" puts
/// it away for the rest of this run. It stays hidden while the saved session
/// is still being checked, so a machine that is already signed in never
/// flashes it at launch.
class GoogleSignInBanner extends StatefulWidget {
  final BackupController controller;

  const GoogleSignInBanner({super.key, required this.controller});

  @override
  State<GoogleSignInBanner> createState() => _GoogleSignInBannerState();
}

class _GoogleSignInBannerState extends State<GoogleSignInBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.controller.driveAccount;
    if (account == null || _dismissed) return const SizedBox.shrink();
    return ValueListenableBuilder<DriveAccountStatus>(
      valueListenable: account.status,
      builder: (context, status, _) {
        final message = switch (status.state) {
          DriveAccountState.signedOut =>
            'Backups are off until this machine signs in to Google.',
          DriveAccountState.wrongAccount =>
            'Backups are off: ${status.email} is not the backup account. '
                'Sign in as ${account.expectedAccount}.',
          DriveAccountState.checking || DriveAccountState.signedIn => null,
        };
        if (message == null) return const SizedBox.shrink();
        return MaterialBanner(
          leading: const Icon(Icons.cloud_off),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => setState(() => _dismissed = true),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () =>
                  signInToGoogleDrive(context, widget.controller, account),
              child: const Text('Sign in'),
            ),
          ],
        );
      },
    );
  }
}
