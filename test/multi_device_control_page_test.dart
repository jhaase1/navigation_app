import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/services/mock/mock_panasonic_service.dart';
import 'package:navigation_app/services/mock/mock_roland_service.dart';
import 'package:navigation_app/services/abstract/panasonic_service_abstract.dart';
import 'package:navigation_app/services/abstract/roland_service_abstract.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/widgets/multi_device_control_page.dart';

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

  /// Set once the page lets go of this session.
  bool released = false;

  @override
  Future<void> disconnect() async {
    released = true;
    _link.add(false);
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
      expect(find.text('Roland connection lost'), findsOneWidget);
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

      expect(find.text('Roland connection lost'), findsNothing);
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
}
