import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/panasonic_camera_config.dart';

/// Notices when a connected camera stops answering, and when it comes back.
///
/// "Connected" used to mean "answered once, at Connect". A camera that lost
/// power or its cable afterwards kept that status for the rest of the
/// service, and every cue aimed at it failed into a toast nobody connected
/// to the green light.
class CameraHealthMonitor {
  final List<PanasonicCameraConfig> Function() cameras;
  final void Function(PanasonicCameraConfig camera, bool up) onChange;
  final Duration interval;

  /// Consecutive unanswered checks before a camera counts as gone. One HTTP
  /// request lost to a busy camera is not an outage.
  final int missesBeforeDown;

  final Set<PanasonicCameraConfig> _watched = {};
  final Map<PanasonicCameraConfig, int> _misses = {};
  Timer? _timer;
  bool _checking = false;

  CameraHealthMonitor({
    required this.cameras,
    required this.onChange,
    this.interval = const Duration(seconds: 5),
    this.missesBeforeDown = 2,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stops watching [camera] — for when the operator disconnects it on
  /// purpose, so the monitor does not reconnect it behind their back.
  void forget(PanasonicCameraConfig camera) {
    _watched.remove(camera);
    _misses.remove(camera);
  }

  @visibleForTesting
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      final current = cameras();
      _watched.removeWhere((c) => !current.contains(c));
      _misses.removeWhere((c, _) => !current.contains(c));
      for (final c in current) {
        if (c.isConnected.value && c.service != null) _watched.add(c);
      }
      await Future.wait([for (final c in [..._watched]) _check(c)]);
    } finally {
      _checking = false;
    }
  }

  Future<void> _check(PanasonicCameraConfig camera) async {
    final service = camera.service;
    if (service == null) return;
    bool answered;
    try {
      await service.probe();
      answered = true;
    } catch (_) {
      answered = false;
    }
    // Forgotten or removed while the probe was out.
    if (!_watched.contains(camera)) return;

    if (answered) {
      _misses[camera] = 0;
      if (!camera.isConnected.value) {
        camera.isConnected.value = true;
        onChange(camera, true);
      }
      return;
    }
    final misses = (_misses[camera] ?? 0) + 1;
    _misses[camera] = misses;
    if (misses >= missesBeforeDown && camera.isConnected.value) {
      camera.isConnected.value = false;
      onChange(camera, false);
    }
  }
}
