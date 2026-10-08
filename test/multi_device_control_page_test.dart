import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/mock/mock_panasonic_service.dart';
import 'package:navigation_app/services/mock/mock_roland_service.dart';
import 'package:navigation_app/services/abstract/panasonic_service_abstract.dart';
import 'package:navigation_app/services/abstract/roland_service_abstract.dart';
import 'package:navigation_app/services/device_config_store.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/services/service_store.dart';
import 'package:navigation_app/widgets/multi_device_control_page.dart';

import 'backup/support/drive_controller.dart';
import 'backup/support/fake_sign_in_platform.dart';

// Connects using Demo Mode so tests never attempt a real network connection.
// The app now defaults to production (live) mode, so tests must switch it
// on explicitly before hitting "Connect All".
Future<void> _connect(WidgetTester tester) async {
  await tester
      .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
  await tester.pumpAndSettle();

  await tester.tap(find.descendant(
      of: find.byType(AppBar), matching: find.byIcon(Icons.settings)));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Switch));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Connect All'));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// A switcher whose link can be dropped from the test, and which announces
/// its own deliberate disconnect the way [RolandService] does.
class _FakeRoland extends MockRolandService {
  final _link = StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectionChanges => _link.stream;

  void drop() => _link.add(false);

  /// The service reconnected on its own.
  void restore() => _link.add(true);

  /// Set once the page lets go of this session. A real service that is
  /// never let go keeps reconnecting on its own, forever.
  bool released = false;

  @override
  Future<void> disconnect() async {
    released = true;
    _link.add(false);
  }

  /// When set, every macro is refused, the way a NACK reaches the page.
  bool refuseMacros = false;

  @override
  Future<void> executeMacro(int macro) async {
    if (refuseMacros) throw Exception('NACK');
  }
}

/// A connector whose connects finish only when the test says so.
class _SlowConnector {
  final pending = <Completer<RolandServiceAbstract>>[];
  final sessions = <_FakeRoland>[];

  Future<RolandServiceAbstract> call(String host) {
    final c = Completer<RolandServiceAbstract>();
    pending.add(c);
    return c.future;
  }

  void finishAll() {
    for (final c in pending) {
      final r = _FakeRoland();
      sessions.add(r);
      c.complete(r);
    }
  }
}

/// Fixed pumps: a connect still in flight spins forever, so nothing settles.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(AppBar), matching: find.byIcon(Icons.settings)));
  await tester.pump(const Duration(seconds: 1));
}

/// A camera that can stop answering, the way one does when it loses power.
class _FakeCamera extends MockPanasonicService {
  bool up = true;
  int probes = 0;

  @override
  Future<void> probe() async {
    probes++;
    if (!up) throw Exception('no answer');
  }
}

/// Connects in Live Mode through an injected connector, so the page wires up
/// the link watcher exactly as it would for real hardware.
Future<_FakeRoland> _connectLive(WidgetTester tester) async {
  final roland = _FakeRoland();
  await tester.pumpWidget(MaterialApp(
    home: MultiDeviceControlPage(
      rolandConnector: (_) async => roland,
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Connect All'));
  await tester.pumpAndSettle();
  return roland;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MultiDeviceControlPage — tabs', () {
    testWidgets('shows Service, Panel, and Positions tabs once connected',
        (tester) async {
      await _connect(tester);

      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Panel'), findsOneWidget);
      expect(find.text('Positions'), findsOneWidget);
    });

    testWidgets('does not show a Switching tab', (tester) async {
      await _connect(tester);

      expect(find.text('Switching'), findsNothing);
    });
  });

  group('MultiDeviceControlPage — AppBar identity', () {
    testWidgets('shows the active operator name once connected',
        (tester) async {
      await _connect(tester);

      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('shows a Demo mode badge once connected in Demo Mode',
        (tester) async {
      await _connect(tester);

      expect(find.text('Demo'), findsOneWidget);
    });
  });

  group('MultiDeviceControlPage — offline prep', () {
    testWidgets('keeps the tabs usable while no device is connected',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Panel'), findsOneWidget);
      expect(find.text('Positions'), findsOneWidget);
      expect(find.text('No devices connected'), findsOneWidget);
      expect(find.text('Connect All'), findsOneWidget);
    });

    testWidgets('offers the operator switcher while offline', (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch operator'), findsOneWidget);
    });

    testWidgets('drops the offline banner once connected', (tester) async {
      await _connect(tester);

      expect(find.text('No devices connected'), findsNothing);
    });
  });

  group('MultiDeviceControlPage — production mode default', () {
    testWidgets('defaults to Live Mode (not Demo Mode) before connecting',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.text('Live Mode'), findsOneWidget);
      expect(find.text('Demo Mode'), findsNothing);
    });

    testWidgets('does not show a "Roland V-160HD Control" title',
        (tester) async {
      await _connect(tester);

      expect(find.text('Roland V-160HD Control'), findsNothing);
    });
  });

  group('MultiDeviceControlPage — People shortcut', () {
    testWidgets('AppBar has a People shortcut icon when connected',
        (tester) async {
      await _connect(tester);

      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('tapping the People shortcut opens the People manager',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.byIcon(Icons.person_add));
      await tester.pumpAndSettle();

      expect(find.text('Add Person'), findsOneWidget);
    });

    testWidgets('AppBar has a People shortcut icon before connecting',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets(
        'Settings dialog also has a Manage People tile, for setup discovery',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // The AppBar icon remains the fast path for the frequent case (a new
      // person filling a role); this tile exists so Settings' Positions /
      // Services / Height Ranges group doesn't leave People undiscoverable
      // during initial setup.
      expect(find.text('Manage People'), findsOneWidget);
    });
  });

  group('MultiDeviceControlPage — operator switching', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await OperatorStore.saveAll([
        OperatorProfile.defaultProfile,
        const OperatorProfile(id: 'op2', name: 'Engineer'),
      ]);
    });

    testWidgets(
        'tapping the operator name in the AppBar opens a switch-operator dialog',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();

      expect(find.text('Switch Operator'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
    });

    testWidgets('selecting a different operator updates the AppBar name',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engineer'));
      await tester.pumpAndSettle();

      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('Default'), findsNothing);
    });

    testWidgets('Settings dialog no longer has an Active operator tile',
        (tester) async {
      await _connect(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.textContaining('Active:'), findsNothing);
      expect(find.text('Tap to switch operator'), findsNothing);
    });
  });

  group('MultiDeviceControlPage — Roland link', () {
    testWidgets('the AppBar reads Live while the switcher is up',
        (tester) async {
      await _connectLive(tester);

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('the AppBar reads Offline before anything connects',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: MultiDeviceControlPage()));
      await tester.pumpAndSettle();

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
    });

    testWidgets('a dropped link flips to Offline and brings the banner back',
        (tester) async {
      final roland = await _connectLive(tester);

      roland.drop();
      await tester.pumpAndSettle();

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('No devices connected'), findsOneWidget);
      expect(find.textContaining('Roland connection lost'), findsOneWidget);
    });

    testWidgets('a deliberate disconnect does not claim the link was lost',
        (tester) async {
      await _connectLive(tester);

      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.settings)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Connections'));
      await tester.tap(find.text('Connections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Roland connection lost'), findsNothing);
    });

    testWidgets('a link that comes back on its own reads Live again',
        (tester) async {
      final roland = await _connectLive(tester);
      roland.drop();
      await tester.pumpAndSettle();

      roland.restore();
      await tester.pumpAndSettle();

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('No devices connected'), findsNothing);
      expect(find.text('Roland reconnected'), findsOneWidget);
    });

    testWidgets('a dead switcher is not Live just because a camera is up',
        (tester) async {
      final roland = _FakeRoland();
      final cameras = <String, _FakeCamera>{};
      await tester.pumpWidget(MaterialApp(
        home: MultiDeviceControlPage(
          rolandConnector: (_) async => roland,
          cameraConnector: (ip) async => cameras[ip] = _FakeCamera(),
          cameraHealthInterval: const Duration(seconds: 1),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pumpAndSettle();
      expect(find.text('Live'), findsOneWidget);

      roland.drop();
      await tester.pumpAndSettle();

      // Macros will fail; the badge must not tell the operator otherwise.
      expect(find.text('Live'), findsNothing);
      expect(find.text('Offline'), findsOneWidget);
      // The cameras still work, so prep stays open and no "nothing
      // connected" banner claims otherwise.
      expect(find.text('No devices connected'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a switcher that reconnects on its own clears the pill',
        (tester) async {
      final roland = await _connectLive(tester);
      roland.drop();
      await tester.pumpAndSettle();
      expect(find.text('Switcher offline'), findsOneWidget);

      roland.restore();
      await tester.pumpAndSettle();
      // Left up, the pill would say the switcher is down while the badge
      // says Live and every macro works.
      expect(find.text('Switcher offline'), findsNothing);
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('switching to Demo lets go of a switcher that is reconnecting',
        (tester) async {
      final roland = await _connectLive(tester);
      roland.drop();
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.settings)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(roland.released, isTrue);
      // Had it been kept, its reconnect would put the real switcher back in
      // charge while the operator thinks they are in Demo.
      roland.restore();
      await tester.pumpAndSettle();
      expect(find.text('Live'), findsNothing);
    });

    testWidgets('Connect while reconnecting replaces the old session',
        (tester) async {
      final sessions = <_FakeRoland>[];
      await tester.pumpWidget(MaterialApp(
        home: MultiDeviceControlPage(rolandConnector: (_) async {
          final r = _FakeRoland();
          sessions.add(r);
          return r;
        }),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pumpAndSettle();
      sessions.first.drop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect All'));
      await tester.pumpAndSettle();

      expect(sessions, hasLength(2));
      expect(sessions.first.released, isTrue,
          reason: 'two telnet sessions would fight over one switcher');
      expect(sessions.last.released, isFalse);
    });

    testWidgets('a connect that finishes after the page is gone is let go',
        (tester) async {
      final roland = _FakeRoland();
      var released = false;
      roland.connectionChanges.listen((up) => released = !up);
      final pending = Completer<RolandServiceAbstract>();
      await tester.pumpWidget(MaterialApp(
        home: MultiDeviceControlPage(rolandConnector: (_) => pending.future),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      pending.complete(roland);
      await tester.pumpAndSettle();

      expect(released, isTrue,
          reason: 'nobody is left to own the switcher session');
    });

    testWidgets('switching to Demo while the switcher is still connecting '
        'does not install it', (tester) async {
      final connector = _SlowConnector();
      await tester.pumpWidget(MaterialApp(
          home: MultiDeviceControlPage(rolandConnector: connector.call)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pump();

      await _openSettings(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      connector.finishAll();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Installed, it would take rehearsal cuts to air under a Demo badge.
      expect(connector.sessions.single.released, isTrue);
      expect(find.text('Live'), findsNothing);
    });

    testWidgets('a second Connect while the first is dialling leaves one session',
        (tester) async {
      final connector = _SlowConnector();
      await tester.pumpWidget(MaterialApp(
          home: MultiDeviceControlPage(rolandConnector: connector.call)));
      await tester.pumpAndSettle();

      await _openSettings(tester);
      await tester.ensureVisible(find.text('Connections'));
      await tester.tap(find.text('Connections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect').first);
      await tester.pump();
      await tester.tap(find.text('Save & Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pump();

      connector.finishAll();
      await tester.pumpAndSettle();

      expect(connector.sessions, hasLength(2));
      expect(connector.sessions.where((r) => !r.released), hasLength(1),
          reason: 'an orphaned session holds a telnet slot nobody can free');
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('switching Live to Demo updates the badge and banner at once',
        (tester) async {
      // Every device is let go of on the switch; a badge still reading Live
      // would be the lie the Offline badge exists to prevent.
      await _connectLive(tester);
      expect(find.text('Live'), findsOneWidget);

      await _openSettings(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Live'), findsNothing);
      expect(find.text('No devices connected'), findsOneWidget);
    });
  });

  testWidgets('a cue the switcher refuses reaches the operator as a failure',
      (tester) async {
    // Each tab falls back to plain text when the page passes no failure
    // handler, so a missed hookup here quietly turns failures grey again.
    await ServiceStore.saveAll([
      Service(id: 's1', name: 'Mass', steps: [
        const ServiceStep(id: 'st1', type: StepType.macro, macroNumber: 3),
      ]),
    ]);
    final roland = await _connectLive(tester);
    roland.refuseMacros = true;

    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mass').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Macro 3'));
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.byIcon(Icons.error)),
        findsOneWidget);
  });

  testWidgets('a camera that stops answering is reported, and so is its return',
      (tester) async {
    final cameras = <String, _FakeCamera>{};
    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(
        rolandConnector: (_) async => _FakeRoland(),
        cameraConnector: (ip) async => cameras[ip] = _FakeCamera(),
        cameraHealthInterval: const Duration(seconds: 1),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();

    cameras['10.0.1.10']!.up = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Camera 1 not responding'), findsOneWidget);

    cameras['10.0.1.10']!.up = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Camera 1 is back'), findsOneWidget);

    // Disposing the page stops the health checks.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a lost switcher and a lost camera show on the status pill',
      (tester) async {
    final roland = _FakeRoland();
    final cameras = <String, _FakeCamera>{};
    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(
        rolandConnector: (_) async => roland,
        cameraConnector: (ip) async => cameras[ip] = _FakeCamera(),
        cameraHealthInterval: const Duration(seconds: 1),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();

    roland.drop();
    await tester.pumpAndSettle();
    expect(find.text('Switcher offline'), findsOneWidget);

    cameras['10.0.1.11']!.up = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Camera 2 (10.0.1.11) offline'), findsOneWidget,
        reason: 'the newest problem is the one the pill names');

    cameras['10.0.1.11']!.up = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Switcher offline'), findsOneWidget,
        reason: 'the camera came back; the switcher is still down');

    await tester.pumpWidget(const SizedBox());
  });

  group('camera faults on the pill clear when the page reconnects it', () {
    Future<Map<String, _FakeCamera>> downCamera1(WidgetTester tester) async {
      final cameras = <String, _FakeCamera>{};
      await tester.pumpWidget(MaterialApp(
        home: MultiDeviceControlPage(
          rolandConnector: (_) async => _FakeRoland(),
          cameraConnector: (ip) async => cameras[ip] = _FakeCamera(),
          cameraHealthInterval: const Duration(seconds: 1),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pumpAndSettle();
      cameras['10.0.1.10']!.up = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Camera 1 (10.0.1.10) offline'), findsOneWidget);
      return cameras;
    }

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.settings)));
      await tester.pumpAndSettle();
    }

    testWidgets('pressing Connect on a dead camera', (tester) async {
      await downCamera1(tester);

      await openSettings(tester);
      await tester.ensureVisible(find.text('Connections'));
      await tester.tap(find.text('Connections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Camera 1 (10.0.1.10) offline'), findsNothing,
          reason: 'the camera answers again; red for the rest of the '
              'service would hide the next real problem');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('switching to Demo', (tester) async {
      await downCamera1(tester);

      await openSettings(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Camera 1 (10.0.1.10) offline'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a Connect that fails leaves "Switcher offline" on the pill',
      (tester) async {
    var calls = 0;
    final roland = _FakeRoland();
    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(rolandConnector: (_) async {
        if (++calls > 1) throw Exception('No route to host');
        return roland;
      }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();
    roland.drop();
    await tester.pumpAndSettle();
    expect(find.text('Switcher offline'), findsOneWidget);

    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Switcher offline'), findsOneWidget,
        reason: 'it is still unreachable; green here would be a lie');
  });

  group('Demo Mode lets go of every real camera', () {
    Future<void> toggleDemo(WidgetTester tester) async {
      await _openSettings(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a camera that was down when switching to Demo', (tester) async {
      // Down in Live, so the toggle skipped it and it kept its real service
      // under watch. When it came back, Demo cues moved the real camera.
      final cameras = <String, _FakeCamera>{};
      await tester.pumpWidget(MaterialApp(
        home: MultiDeviceControlPage(
          rolandConnector: (_) async => _FakeRoland(),
          cameraConnector: (ip) async => cameras[ip] = _FakeCamera(),
          cameraHealthInterval: const Duration(seconds: 1),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pumpAndSettle();
      final cam1 = cameras['10.0.1.10']!..up = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      await toggleDemo(tester);
      final probesAtToggle = cam1.probes;
      cam1.up = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Camera 1 is back'), findsNothing);
      expect(cam1.probes, probesAtToggle,
          reason: 'nothing in Demo should be talking to the real camera');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a camera still connecting when switching to Demo',
        (tester) async {
      final pending = <Completer<PanasonicServiceAbstract>>[];
      await tester.pumpWidget(MaterialApp(
        home: MultiDeviceControlPage(
          rolandConnector: (_) async => _FakeRoland(),
          cameraConnector: (ip) {
            final c = Completer<PanasonicServiceAbstract>();
            pending.add(c);
            return c.future;
          },
          cameraHealthInterval: const Duration(seconds: 1),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect All'));
      await tester.pump();

      await toggleDemo(tester);
      final real = [for (final _ in pending) _FakeCamera()];
      for (var i = 0; i < pending.length; i++) {
        pending[i].complete(real[i]);
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(real.map((c) => c.probes), everyElement(0),
          reason: 'a connect let go of mid-dial must not be installed');
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('two cameras with the same name keep their own faults',
      (tester) async {
    await DeviceConfigStore.save('10.0.1.100', const [
      CameraEntry(name: 'PTZ', ip: '10.0.1.10'),
      CameraEntry(name: 'PTZ', ip: '10.0.1.11'),
    ]);
    final cameras = <String, _FakeCamera>{};
    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(
        rolandConnector: (_) async => _FakeRoland(),
        cameraConnector: (ip) async => cameras[ip] = _FakeCamera(),
        cameraHealthInterval: const Duration(seconds: 1),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();

    cameras['10.0.1.10']!.up = false;
    cameras['10.0.1.11']!.up = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    cameras['10.0.1.11']!.up = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('PTZ (10.0.1.10) offline'), findsOneWidget,
        reason: 'the other PTZ coming back must not clear this one');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a camera Connect that fails leaves its fault on the pill',
      (tester) async {
    final cameras = <String, _FakeCamera>{};
    var refuse = false;
    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(
        rolandConnector: (_) async => _FakeRoland(),
        cameraConnector: (ip) async {
          if (refuse) throw Exception('No route to host');
          return cameras[ip] = _FakeCamera();
        },
        cameraHealthInterval: const Duration(seconds: 1),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();
    cameras['10.0.1.10']!.up = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    refuse = true;
    await _openSettings(tester);
    await tester.ensureVisible(find.text('Connections'));
    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect').last);
    await tester.pumpAndSettle();
    // Cancel, not Save & Close: saving replaces the camera list outright.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Camera 1 (10.0.1.10) offline'), findsOneWidget,
        reason: 'still unreachable; green here would be a lie');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a camera whose Connect failed is not driven from the Panel',
      (tester) async {
    // Connect lets go of the camera first. Had the Panel driven whatever
    // service that left behind, a dead camera would "recall" presets and
    // report success while the real one never moved.
    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(
        rolandConnector: (_) async => _FakeRoland(),
        cameraConnector: (_) async => throw Exception('No route to host'),
        cameraHealthInterval: const Duration(seconds: 1),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect All'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera 1'));
    await tester.pumpAndSettle();
    final presets = find.widgetWithText(FilledButton, '1');
    if (presets.evaluate().isNotEmpty) {
      await tester.tap(presets.first);
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('Recalled preset'), findsNothing);
    expect(presets, findsNothing,
        reason: 'no presets to offer for a camera that is not connected');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Drive build that launches signed out asks for a sign-in',
      (tester) async {
    final controller = driveController(FakeSignInPlatform());

    await tester.pumpWidget(
        MaterialApp(home: MultiDeviceControlPage(backupController: controller)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Backups are off'), findsOneWidget);
    // Disposing the page stops the scheduler's timers.
    await tester.pumpWidget(const SizedBox());
  });
}
