import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/services/camera_health_monitor.dart';
import 'package:navigation_app/services/mock/mock_panasonic_service.dart';
import 'package:navigation_app/services/panasonic_service.dart';

/// A camera on the network that can be unplugged: answers QID while up,
/// and refuses the connection while down.
class _Camera {
  bool up = true;
  int queries = 0;

  late final client = MockClient((request) async {
    queries++;
    if (!up) throw http.ClientException('Connection refused', request.url);
    return http.Response('OID:AW-UE150', 200);
  });
}

void main() {
  late _Camera cam;
  late PanasonicCameraConfig config;
  late List<(String, bool)> changes;
  late CameraHealthMonitor monitor;

  setUp(() {
    cam = _Camera();
    config = PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10')
      ..service = PanasonicService(
          ipAddress: '10.0.1.10', client: cam.client, maxRetries: 1)
      ..isConnected.value = true;
    changes = [];
    monitor = CameraHealthMonitor(
      cameras: () => [config],
      onChange: (c, up) => changes.add((c.name, up)),
    );
  });

  test('one missed answer is a blip, two mean the camera is gone', () async {
    cam.up = false;

    await monitor.checkNow();
    expect(config.isConnected.value, isTrue);
    expect(changes, isEmpty);

    await monitor.checkNow();
    expect(config.isConnected.value, isFalse);
    expect(changes, [('Cam 1', false)]);
  });

  test('a camera that comes back is marked connected again', () async {
    cam.up = false;
    await monitor.checkNow();
    await monitor.checkNow();

    cam.up = true;
    await monitor.checkNow();

    expect(config.isConnected.value, isTrue);
    expect(changes, [('Cam 1', false), ('Cam 1', true)]);
  });

  test('a healthy camera is checked but nothing changes', () async {
    await monitor.checkNow();
    await monitor.checkNow();

    expect(cam.queries, 2, reason: 'positive control: the probe really runs');
    expect(changes, isEmpty);
  });

  test('a camera disconnected on purpose is left alone', () async {
    cam.up = false;
    await monitor.checkNow();
    await monitor.checkNow();
    monitor.forget(config);
    cam.up = true;
    final before = cam.queries;

    await monitor.checkNow();

    expect(cam.queries, before);
    expect(config.isConnected.value, isFalse);
  });

  test('a camera that was never connected is not probed', () async {
    config.isConnected.value = false;

    await monitor.checkNow();

    expect(cam.queries, 0);
  });

  test('a camera removed from the configuration is dropped', () async {
    final others = <PanasonicCameraConfig>[];
    final m = CameraHealthMonitor(
        cameras: () => others, onChange: (c, up) => changes.add((c.name, up)));
    // Seen once while configured...
    others.add(config);
    await m.checkNow();
    // ...then replaced by Settings -> Connections.
    others.clear();
    cam.up = false;

    await m.checkNow();
    await m.checkNow();

    expect(changes, isEmpty);
  });

  test('a camera switched to Demo is not brought back by its demo stand-in',
      () async {
    cam.up = false;
    await monitor.checkNow();
    await monitor.checkNow();

    // Settings -> Demo Mode swaps in a stand-in that always answers.
    config.service = MockPanasonicService();
    await monitor.checkNow();

    // "Connected" here would read Live while every cue went nowhere.
    expect(config.isConnected.value, isFalse);
    expect(changes, [('Cam 1', false)]);
  });

  test('an answer that arrives after the camera was replaced is ignored',
      () async {
    final gate = Completer<void>();
    config.service = PanasonicService(
        ipAddress: '10.0.1.10',
        maxRetries: 1,
        client: MockClient((_) async {
          await gate.future;
          return http.Response('OID:AW-UE150', 200);
        }));
    final check = monitor.checkNow();
    await pumpEventQueue();

    // Settings -> Connections replaces the camera list.
    config.isConnected.value = false;
    config.service = null;
    config.dispose();
    gate.complete();
    await check;

    expect(changes, isEmpty);
  });

  test('a camera that never answers does not hold up checks on the others',
      () async {
    final hung = PanasonicCameraConfig(name: 'Cam 2', ipAddress: '10.0.1.11')
      ..service = PanasonicService(
          ipAddress: '10.0.1.11',
          maxRetries: 1,
          client: MockClient((_) => Completer<http.Response>().future))
      ..isConnected.value = true;
    final m = CameraHealthMonitor(
        cameras: () => [hung, config],
        onChange: (c, up) => changes.add((c.name, up)));
    cam.up = false;

    unawaited(m.checkNow());
    await pumpEventQueue();
    unawaited(m.checkNow());
    await pumpEventQueue();

    expect(changes, [('Cam 1', false)]);
  });
}
