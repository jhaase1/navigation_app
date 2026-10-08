import 'dart:async';

import 'package:flutter/widgets.dart';

import 'lineup_store.dart';

/// Keeps the day's lineup alive while the app is on screen, and lets it
/// lapse [LineupStore.leaseLength] after the screen goes off.
///
/// Renews every [renewEvery] while the app is resumed or inactive, and once
/// immediately on coming back — which is also when a lineup that lapsed
/// while the screen was off is found and cleared. Inactive counts as on
/// screen: macOS reports a visible window behind another app that way, and
/// an operator running slides elsewhere must not lose the lineup. Hidden and
/// paused (screen locked, app in the background) stop the renewals.
class LineupLease with WidgetsBindingObserver {
  LineupLease({this.renewEvery = const Duration(minutes: 5)});

  final Duration renewEvery;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _apply(WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _apply(state);

  void _apply(AppLifecycleState state) {
    final onScreen = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (!onScreen) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    unawaited(LineupStore.renew());
    _timer = Timer.periodic(renewEvery, (_) => unawaited(LineupStore.renew()));
  }
}
