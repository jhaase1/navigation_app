import 'package:flutter/material.dart';

/// Shows a device command outcome to the operator.
///
/// Replaces any message still on screen so a rapid run of cues always shows
/// the latest result rather than queueing stale ones behind it.
void showDeviceResponse(BuildContext context, String message) {
  if (message.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
}
