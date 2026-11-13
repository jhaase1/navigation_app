import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/panasonic_service.dart';
import 'package:navigation_app/services/roland_service.dart';
import 'package:navigation_app/widgets/service_tab.dart';

/// A switcher on loopback that acknowledges everything and records what
/// it was told, so the test sees the bytes the real service sent.
class _Switcher {
  late ServerSocket _server;
  final _sockets = <Socket>[];
  final commands = <String>[];

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((s) {
      _sockets.add(s);
      var authed = false;
      s.listen((data) {
        for (final line in utf8.decode(data).split(RegExp(r'\r?\n'))) {
          if (line.trim().isEmpty) continue;
          if (!authed) {
            authed = true;
            s.write('Welcome\r\n');
            continue;
          }
          commands.add(line.trim());
          s.write('ACK;\r\n');
        }
      }, onError: (_) {});
    });
  }

  int get port => _server.port;

  Future<void> stop() async {
    for (final s in _sockets) {
      s.destroy();
    }
    await _server.close();
  }
}

const _camIp = '10.0.1.11';

PanasonicCameraConfig _camera({required String reply}) =>
    PanasonicCameraConfig(
        name: 'Cam 2', ipAddress: _camIp, rolandInput: 'SDI2')
      ..service = PanasonicService(
          ipAddress: _camIp,
          maxRetries: 1,
          client: MockClient((_) async => http.Response(reply, 200)))
      ..isConnected.value = true;

final _service = Service(id: 's1', name: 'Mass', steps: [
  const ServiceStep(
      id: 'shot', type: StepType.shot, cameraIp: _camIp, cameraPresetIndex: 3),
  const ServiceStep(id: 'mac', type: StepType.macro, macroNumber: 7),
]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Switcher switcher;
  late RolandService roland;

  Future<void> open(WidgetTester tester, PanasonicCameraConfig cam,
      {List<PanasonicCameraConfig>? cameras, Service? service}) async {
    await tester.runAsync(() async {
      switcher = _Switcher();
      await switcher.start();
      roland = RolandService(host: '127.0.0.1', port: switcher.port);
      await roland.connect();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        roland.dispose();
        await switcher.stop();
      });
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServiceTab(
          cameras: cameras ?? [cam],
          people: const [],
          positions: const [],
          services: [service ?? _service],
          heightRanges: const [],
          rolandService: roland,
          rolandConnected: ValueNotifier(true),
          onResponse: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mass').last);
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    // The switcher is a real socket and the tab runs on the fake clock, so
    // alternate the two until the command and its ACK have both landed.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
    }
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> tapCue(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining(label));
    await settle(tester);
  }

  testWidgets('firing a camera cue puts that camera on preview',
      (tester) async {
    await open(tester, _camera(reply: 's03'));

    await tapCue(tester, 'Preset 4');

    expect(switcher.commands, ['PST:SDI2;']);
  });

  testWidgets('a macro cue leaves preview alone', (tester) async {
    await open(tester, _camera(reply: 's03'));

    await tapCue(tester, 'Preset 4');
    await tapCue(tester, 'Macro 7');

    // The shot put SDI2 up; the macro after it sent only itself.
    expect(switcher.commands, ['PST:SDI2;', 'MCREX:MACRO7;']);
  });

  testWidgets('a preset the camera refused does not go on preview',
      (tester) async {
    await open(tester, _camera(reply: 'ER3:R03'));

    await tapCue(tester, 'Preset 4');
    await tapCue(tester, 'Macro 7');

    // The macro reaching the switcher proves the link was live.
    expect(switcher.commands, ['MCREX:MACRO7;']);
  });

  testWidgets(
      'a slow camera cue finishing after a later one does not take preview back',
      (tester) async {
    // Cam 2 answers only when the test says; Cam 3 answers at once.
    final slowReply = Completer<http.Response>();
    final slow = PanasonicCameraConfig(
        name: 'Cam 2', ipAddress: _camIp, rolandInput: 'SDI2')
      ..service = PanasonicService(
          ipAddress: _camIp,
          maxRetries: 1,
          client: MockClient((_) => slowReply.future))
      ..isConnected.value = true;
    const fastIp = '10.0.1.12';
    final fast = PanasonicCameraConfig(
        name: 'Cam 3', ipAddress: fastIp, rolandInput: 'SDI3')
      ..service = PanasonicService(
          ipAddress: fastIp,
          maxRetries: 1,
          client: MockClient((_) async => http.Response('s05', 200)))
      ..isConnected.value = true;
    final twoShots = Service(id: 's2', name: 'Mass', steps: [
      const ServiceStep(
          id: 'a', type: StepType.shot, cameraIp: _camIp, cameraPresetIndex: 3),
      const ServiceStep(
          id: 'b', type: StepType.shot, cameraIp: fastIp, cameraPresetIndex: 5),
    ]);
    await open(tester, slow, cameras: [slow, fast], service: twoShots);

    await tester.tap(find.textContaining('Preset 4'));
    await tester.pump();
    await tapCue(tester, 'Preset 6');
    slowReply.complete(http.Response('s03', 200));
    await settle(tester);

    expect(switcher.commands, ['PST:SDI3;']);
  });
}
