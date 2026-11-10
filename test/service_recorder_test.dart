import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/mock/mock_panasonic_service.dart';
import 'package:navigation_app/services/service_recorder.dart';
import 'package:navigation_app/services/service_store.dart';
import 'package:navigation_app/widgets/positions_tab.dart';
import 'package:navigation_app/widgets/recording_controls.dart';
import 'package:navigation_app/widgets/service_tab.dart';

const _camIp = '10.0.1.10';

/// A camera whose recalls don't answer until [release] completes.
class _SlowCamera extends MockPanasonicService {
  final release = Completer<void>();
  @override
  Future<String> recallPreset(int preset) async {
    await release.future;
    return super.recallPreset(preset);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ServiceRecorder', () {
    test('keeps macros and role shots in the order they were fired', () {
      final r = ServiceRecorder()..start();
      r.recordStep(
          const ServiceStep(id: 'm1', type: StepType.macro, macroNumber: 3));
      r.recordMinistry(
          roleName: 'Lector',
          personId: 'jane',
          positionId: 'ambo',
          cameraIp: _camIp);
      r.recordStep(
          const ServiceStep(id: 'm2', type: StepType.macro, macroNumber: 4));

      final service = r.toService('Sunday Mass');
      expect(service.steps.map((s) => s.type),
          [StepType.macro, StepType.ministry, StepType.macro]);

      final shot = service.steps[1];
      expect(shot.positionId, 'ambo');
      expect(shot.cameraIp, _camIp);
      expect(service.participants.single.id, shot.participantId);
      expect(service.participants.single.name, 'Lector');
    });

    test('the same role typed twice is one role, not two', () {
      final r = ServiceRecorder()..start();
      r.recordMinistry(
          roleName: 'Lector',
          personId: 'jane',
          positionId: 'ambo',
          cameraIp: _camIp);
      r.recordMinistry(
          roleName: ' lector ',
          personId: 'bob',
          positionId: 'chair',
          cameraIp: _camIp);

      final service = r.toService('Mass');
      expect(service.participants, hasLength(1));
      expect(service.steps.map((s) => s.participantId).toSet(),
          {service.participants.single.id});
    });

    test('remembers the role a person was given earlier in the recording', () {
      final r = ServiceRecorder()..start();
      r.recordMinistry(
          roleName: 'Cantor',
          personId: 'jane',
          positionId: 'ambo',
          cameraIp: _camIp);
      expect(r.roleNameFor('jane'), 'Cantor');
      expect(r.roleNameFor('bob'), isNull);
    });

    test('starting again mid-recording keeps the steps taken so far', () {
      final r = ServiceRecorder()..start();
      r.recordStep(const ServiceStep(id: 'm', type: StepType.macro));
      r.start();
      expect(r.steps, hasLength(1));
    });

    test('nothing is recorded while not recording', () {
      final r = ServiceRecorder();
      r.recordMinistry(
          roleName: 'Lector',
          personId: 'jane',
          positionId: 'ambo',
          cameraIp: _camIp);
      r.recordStep(const ServiceStep(id: 'm', type: StepType.macro));
      expect(r.steps, isEmpty);
      expect(r.participants, isEmpty);
    });
  });

  testWidgets(
      'record Jane as Lector on the Positions tab; running it with Bob as '
      'Lector aims at Bob\'s shot, not Jane\'s', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cam = PanasonicCameraConfig(
        name: 'Cam', ipAddress: _camIp, service: MockPanasonicService());
    cam.isConnected.value = true;
    addTearDown(cam.dispose);

    final ambo = Position(id: 'ambo', name: 'Ambo');
    final jane = Person(id: 'jane', name: 'Jane', positionPresets: {
      'ambo': {_camIp: 2},
    });
    final bob = Person(id: 'bob', name: 'Bob', positionPresets: {
      'ambo': {_camIp: 7},
    });
    final recorder = ServiceRecorder();
    addTearDown(recorder.dispose);

    // ── Record ────────────────────────────────────────────────────────────
    final recordResponses = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          RecordingIndicator(recorder: recorder, onResponse: (_) {}),
        ]),
        body: PositionsTab(
          cameras: [cam],
          positions: [ambo],
          people: [jane, bob],
          heightRanges: const [],
          recorder: recorder,
          onResponse: recordResponses.add,
        ),
      ),
    ));

    recorder.start();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Jane'));
    await tester.pumpAndSettle();

    // The shot still fires during recording, so the operator sees it.
    expect(recordResponses.last, contains('Recalled preset 2'));

    // Then the app asks which role Jane is playing.
    await tester.enterText(find.byType(TextField), 'Lector');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add step'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Stop'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sunday Mass');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = await ServiceStore.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.participants.map((p) => p.name), ['Lector']);

    // ── Next week: Bob is Lector ──────────────────────────────────────────
    final runResponses = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServiceTab(
          cameras: [cam],
          people: [jane, bob],
          positions: [ambo],
          services: saved,
          heightRanges: const [],
          rolandService: null,
          rolandConnected: null,
          onResponse: runResponses.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunday Mass').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Lector  ·'));
    await tester.pumpAndSettle();

    expect(runResponses.last, contains('Recalled preset 7'));
  });

  testWidgets(
      'a second person tapped before the first shot answers is ignored while '
      'recording, so prompts never stack and steps stay in firing order',
      (tester) async {
    final slow = _SlowCamera();
    final cam =
        PanasonicCameraConfig(name: 'Cam', ipAddress: _camIp, service: slow);
    cam.isConnected.value = true;
    addTearDown(cam.dispose);

    final ambo = Position(id: 'ambo', name: 'Ambo');
    final jane = Person(id: 'jane', name: 'Jane', positionPresets: {
      'ambo': {_camIp: 2},
    });
    final bob = Person(id: 'bob', name: 'Bob', positionPresets: {
      'ambo': {_camIp: 7},
    });
    final recorder = ServiceRecorder()..start();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PositionsTab(
          cameras: [cam],
          positions: [ambo],
          people: [jane, bob],
          heightRanges: const [],
          recorder: recorder,
          onResponse: (_) {},
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Jane'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Bob'));
    await tester.pump();

    slow.release.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Jane at Ambo'), findsOneWidget);
  });

  testWidgets(
      'typing an existing role in a different case highlights that role',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => askForRole(ctx,
              personName: 'Bob',
              positionName: 'Ambo',
              existingRoles: const ['Lector']),
          child: const Text('Ask'),
        ),
      ),
    ));
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lector');
    await tester.pump();

    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.selected, isTrue);
  });
}
