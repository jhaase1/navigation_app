import 'package:flutter/material.dart';

/// Shows a device command outcome to the operator.
///
/// Replaces any message still on screen so a rapid run of cues always shows
/// the latest result rather than queueing stale ones behind it.
///
/// A [failed] outcome is drawn as one — error colour, error icon — and stays
/// up twice as long. A dead camera reported in the same grey toast as a
/// successful cut is a failure nobody reads.
///
/// A failure still on screen is only replaced by something at least as
/// urgent, because the next cue going through half a second later would
/// otherwise wipe the one that did not:
/// - a newer failed command replaces any failure;
/// - a [link] message (a device's connection dropping or coming back, which
///   the pill and the badge already show) never hides a failed command, and
///   a link coming back only replaces that same link's "lost" message;
/// - an ordinary success waits its turn — it is not shown at all.
void showDeviceResponse(BuildContext context, String message,
    {bool failed = false, String? link}) {
  if (message.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final onScreen = _failureOnScreen[messenger];
  if (onScreen != null) {
    final replaces = failed
        ? link == null || onScreen.link != null
        : link != null && link == onScreen.link;
    if (!replaces) return;
  }
  final scheme = Theme.of(context).colorScheme;
  messenger.hideCurrentSnackBar();
  final shown = messenger.showSnackBar(SnackBar(
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
  if (!failed) {
    _failureOnScreen[messenger] = null;
    return;
  }
  _failureOnScreen[messenger] = (controller: shown, link: link);
  shown.closed.then((_) {
    // A newer message may have taken the slot; only this one may free it.
    if (identical(_failureOnScreen[messenger]?.controller, shown)) {
      _failureOnScreen[messenger] = null;
    }
  });
}

/// The failure toast each messenger is showing, if any, and the link it is
/// about (null for a failed command).
final _failureOnScreen = Expando<
    ({
      ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
      String? link
    })>('failureOnScreen');
