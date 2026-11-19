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
      {List<PanasonicCameraConfig>? cameras,
      Service? service,
      bool switcherUp = true,
      List<String>? failures}) async {
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
          rolandConnected: ValueNotifier(switcherUp),
          onResponse: (_) {},
          onFailure: (m) => failures?.add(m),
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

  /// Cam 2 (SDI2) answers only when the test completes [slowReply];
  /// Cam 3 (SDI3) answers at once. Steps: A on Cam 2, B on Cam 3, a macro.
  Future<Completer<http.Response>> openSlowAndFast(WidgetTester tester) async {
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
    final steps = Service(id: 's2', name: 'Mass', steps: [
      const ServiceStep(
          id: 'a', type: StepType.shot, cameraIp: _camIp, cameraPresetIndex: 3),
      const ServiceStep(
          id: 'b', type: StepType.shot, cameraIp: fastIp, cameraPresetIndex: 5),
      const ServiceStep(id: 'm', type: StepType.macro, macroNumber: 7),
    ]);
    await open(tester, slow, cameras: [slow, fast], service: steps);
    return slowReply;
  }

  // Taps a cue whose camera will not answer yet; settling would wait on it.
  Future<void> tapSlowCue(WidgetTester tester) async {
    await tester.tap(find.textContaining('Preset 4'));
    await tester.pump();
  }

  testWidgets(
      'a slow camera cue finishing after a later one does not take preview back',
      (tester) async {
    final slowReply = await openSlowAndFast(tester);

    await tapSlowCue(tester);
    await tapCue(tester, 'Preset 6');
    slowReply.complete(http.Response('s03', 200));
    await settle(tester);

    expect(switcher.commands, ['PST:SDI3;']);
  });

  testWidgets(
      're-picking a slow camera cue still in flight puts it on preview when it lands',
      (tester) async {
    final slowReply = await openSlowAndFast(tester);

    await tapSlowCue(tester);
    await tapCue(tester, 'Preset 6');
    // The operator goes back to the slow cue before its camera answers.
    await tapSlowCue(tester);
    slowReply.complete(http.Response('s03', 200));
    await settle(tester);

    expect(switcher.commands, ['PST:SDI3;', 'PST:SDI2;']);
  });

  testWidgets(
      'a slow cue landing after the service was reordered under it does not '
      'go on preview', (tester) async {
    final slowReply = await openSlowAndFast(tester);
    final tab = tester.widget<ServiceTab>(find.byType(ServiceTab));

    await tapSlowCue(tester);
    // Someone edits the service while A is out: B now sits where A was, so
    // the highlighted row is a cue that never fired.
    final reordered = Service(id: 's2', name: 'Mass', steps: [
      const ServiceStep(
          id: 'b',
          type: StepType.shot,
          cameraIp: '10.0.1.12',
          cameraPresetIndex: 5),
      const ServiceStep(
          id: 'a', type: StepType.shot, cameraIp: _camIp, cameraPresetIndex: 3),
      const ServiceStep(id: 'm', type: StepType.macro, macroNumber: 7),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServiceTab(
          cameras: tab.cameras,
          people: const [],
          positions: const [],
          services: [reordered],
          heightRanges: const [],
          rolandService: tab.rolandService,
          rolandConnected: tab.rolandConnected,
          onResponse: (_) {},
        ),
      ),
    ));
    slowReply.complete(http.Response('s03', 200));
    await settle(tester);

    expect(switcher.commands, isEmpty);
  });

  testWidgets(
      'a slow camera cue landing after a macro does not overwrite preview',
      (tester) async {
    final slowReply = await openSlowAndFast(tester);

    await tapSlowCue(tester);
    // The operator fires the take macro before the camera has answered.
    await tapCue(tester, 'Macro 7');
    slowReply.complete(http.Response('s03', 200));
    await settle(tester);

    expect(switcher.commands, ['MCREX:MACRO7;']);
  });

  testWidgets(
      'a camera cue that cannot reach preview because the switcher is down says so',
      (tester) async {
    final failures = <String>[];
    await open(tester, _camera(reply: 's03'),
        switcherUp: false, failures: failures);

    await tapCue(tester, 'Preset 4');

    // The cue itself went through; only the preview could not follow.
    expect(failures, ['SDI2 not put on preview: switcher not connected']);
    expect(switcher.commands, isEmpty);
  });
}
