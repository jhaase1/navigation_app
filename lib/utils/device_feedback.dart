import 'package:flutter/material.dart';

/// Shows a device command outcome to the operator.
///
/// Replaces any message still on screen so a rapid run of cues always shows
/// the latest result rather than queueing stale ones behind it.
///
/// A [failed] outcome is drawn as one — error colour, error icon — and stays
/// up twice as long. A dead camera reported in the same grey toast as a
/// successful cut is a failure nobody reads.
void showDeviceResponse(BuildContext context, String message,
    {bool failed = false}) {
  if (message.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: failed
          ? Row(children: [
              Icon(Icons.error, color: scheme.onError),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(message, style: TextStyle(color: scheme.onError))),
            ])
          : Text(message),
      backgroundColor: failed ? scheme.error : null,
      duration: Duration(seconds: failed ? 6 : 3),
      behavior: SnackBarBehavior.floating,
    ));
}
