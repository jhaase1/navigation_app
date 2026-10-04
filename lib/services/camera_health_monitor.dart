import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/panasonic_camera_config.dart';
import 'abstract/panasonic_service_abstract.dart';

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

  /// Each watched camera, with the service it was watched through. A camera
  /// whose service is swapped — Demo Mode, a reconnect, Settings replacing
  /// it — is a different thing to watch: a demo stand-in always answers.
  final Map<PanasonicCameraConfig, PanasonicServiceAbstract> _watched = {};
  final Map<PanasonicCameraConfig, int> _misses = {};

  /// Cameras with a probe still out. Each is skipped until it returns, so a
  /// camera that hangs never holds up checks on the others.
  final Set<PanasonicCameraConfig> _inFlight = {};
  Timer? _timer;

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
    final current = cameras();
    _watched.removeWhere(
        (c, service) => !current.contains(c) || !identical(c.service, service));
    _misses.removeWhere((c, _) => !_watched.containsKey(c));
    for (final c in current) {
      final service = c.service;
      if (c.isConnected.value && service != null) {
        _watched.putIfAbsent(c, () => service);
      }
    }
    await Future.wait([
      for (final MapEntry(key: camera, value: service) in [..._watched.entries])
        if (!_inFlight.contains(camera)) _check(camera, service),
    ]);
  }

  Future<void> _check(
      PanasonicCameraConfig camera, PanasonicServiceAbstract service) async {
    bool answered;
    _inFlight.add(camera);
    try {
      await service.probe();
      answered = true;
    } catch (_) {
      answered = false;
    } finally {
      _inFlight.remove(camera);
    }
    // Forgotten, removed or given another service while the probe was out:
    // the answer is about something that is no longer there.
    if (!identical(_watched[camera], service) ||
        !identical(camera.service, service)) {
      return;
    }

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
