import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/abstract/roland_service_abstract.dart';
import 'package:navigation_app/services/mock/mock_roland_service.dart';
import 'package:navigation_app/services/service_recorder.dart';
import 'package:navigation_app/services/service_store.dart';
import 'package:navigation_app/services/visibility_store.dart';
import 'package:navigation_app/services/preset_name_store.dart';
import 'package:navigation_app/widgets/operator_panel.dart';
import 'package:navigation_app/widgets/recording_controls.dart';

Widget _build({
  OperatorProfile operator = OperatorProfile.defaultProfile,
  List<PanasonicCameraConfig> cameras = const [],
  RolandServiceAbstract? rolandService,
  ValueNotifier<bool>? rolandConnected,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Scaffold(
      body: OperatorPanel(
        operator: operator,
        rolandService: rolandService,
        rolandConnected: rolandConnected ?? ValueNotifier(false),
        cameras: cameras,
        onResponse: (_) {},
      ),
    ),
  );
}

/// Refuses the first write of the saved services list; later writes succeed.
class _RefuseFirstServicesWrite extends InMemorySharedPreferencesStore {
  _RefuseFirstServicesWrite() : super.empty();
  bool refused = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('services') && !refused) {
      refused = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

/// Holds every write of the saved services list until [release] completes.
class _GatedServicesWrite extends InMemorySharedPreferencesStore {
  _GatedServicesWrite() : super.empty();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('services')) await release.future;
    return super.setValue(valueType, key, value);
  }
}

/// The services list is written, then the backup generation bump that
/// follows is refused once, so saveAll throws after the data is on disk.
class _RefuseFirstGenerationBump extends InMemorySharedPreferencesStore {
  _RefuseFirstGenerationBump() : super.empty();
  bool refused = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('backup_mutation_generation') && !refused) {
      refused = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

/// Holds the services write until [release], then refuses it.
class _GatedThenRefusedServicesWrite extends InMemorySharedPreferencesStore {
  _GatedThenRefusedServicesWrite() : super.empty();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('services')) {
      await release.future;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OperatorPanel — device tabs', () {
    testWidgets('shows Roland tab by default', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Roland'), findsOneWidget);
    });

    testWidgets('shows camera tab when a camera is provided', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();
      expect(find.text('Wide'), findsOneWidget);
    });

    testWidgets('Roland tab is selected initially', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();
      final tb = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(tb.isSelected[0], isTrue);
      expect(tb.isSelected[1], isFalse);
    });
  });

  group('OperatorPanel — Default operator', () {
    testWidgets('shows all 100 Roland macros', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('shows Macro 1 button', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Macro 1'), findsWidgets);
    });

    testWidgets('shows no empty-state message', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.textContaining('No items'), findsNothing);
    });
  });

  group('OperatorPanel — custom operator', () {
    testWidgets('shows empty state when operator has no items configured',
        (tester) async {
      const op = OperatorProfile(id: 'op1', name: 'Sound');
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.textContaining('No items configured'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows only configured items', (tester) async {
      const op = OperatorProfile(
        id: 'op1',
        name: 'Camera Op',
        items: {'roland_': [3, 7, 42]},
      );
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(3));
    });

    testWidgets('shows custom preset name alongside its macro number',
        (tester) async {
      await PresetNameStore.save('roland_', 3, 'Entrance');
      const op = OperatorProfile(
        id: 'op1',
        name: 'Camera Op',
        items: {'roland_': [3]},
      );
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.text('Entrance (3)'), findsOneWidget);
    });

    testWidgets('empty state mentions the operator name', (tester) async {
      const op = OperatorProfile(id: 'op1', name: 'Choir Director');
      await tester.pumpWidget(_build(operator: op));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choir Director'), findsOneWidget);
    });
  });

  group('OperatorPanel — camera tab', () {
    testWidgets('tapping camera tab switches selection', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Side', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Side'));
      await tester.pumpAndSettle();

      final tb = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(tb.isSelected[1], isTrue);
    });

    testWidgets(
        'disconnected camera with no items shows empty panel for custom op',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Close', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);
      const op = OperatorProfile(id: 'op1', name: 'Op');
      await tester.pumpWidget(_build(operator: op, cameras: [cam]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('OperatorPanel — operator rebuild', () {
    testWidgets('rebuilds when operator prop changes', (tester) async {
      const op1 = OperatorProfile(
        id: 'op1',
        name: 'A',
        items: {'roland_': [1]},
      );
      const op2 = OperatorProfile(
        id: 'op2',
        name: 'B',
        items: {'roland_': [1, 2, 3]},
      );

      // Start with op1 (1 button)
      await tester.pumpWidget(_build(operator: op1));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(1));

      // Switch to op2 (3 buttons)
      await tester.pumpWidget(_build(operator: op2));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(3));
    });
  });

  group('OperatorPanel — VisibilityStore', () {
    testWidgets('hides an item marked hidden, for every operator',
        (tester) async {
      await VisibilityStore.save('roland_', 1, ItemVisibility.hidden);
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Macro 1'), findsNothing);
    });

    testWidgets('leaves items with no saved visibility shown',
        (tester) async {
      await VisibilityStore.save('roland_', 1, ItemVisibility.hidden);
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Macro 2'), findsOneWidget);
    });

    testWidgets(
        'hiding wins even when a custom operator explicitly allows the item',
        (tester) async {
      await VisibilityStore.save('roland_', 1, ItemVisibility.hidden);
      const custom = OperatorProfile(
        id: 'custom',
        name: 'Custom',
        items: {
          'roland_': [1, 2]
        },
      );
      await tester.pumpWidget(_build(operator: custom));
      await tester.pumpAndSettle();
      expect(find.text('Macro 1'), findsNothing);
      expect(find.text('Macro 2'), findsOneWidget);
    });

    testWidgets(
        'an already-mounted panel hides an item as soon as it is saved '
        'elsewhere, without switching devices or rebuilding',
        (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Macro 1'), findsOneWidget);

      await VisibilityStore.save('roland_', 1, ItemVisibility.hidden);
      await tester.pumpAndSettle();

      expect(find.text('Macro 1'), findsNothing);
    });

    testWidgets(
        'reloads visibility for the new Roland IP after it changes while '
        'the panel stays mounted', (tester) async {
      final ipController = TextEditingController(text: '10.0.1.20');
      addTearDown(ipController.dispose);
      await VisibilityStore.save('roland_10.0.1.20', 1, ItemVisibility.hidden);

      Widget build() => MaterialApp(
            theme: ThemeData(useMaterial3: false),
            home: Scaffold(
              body: OperatorPanel(
                operator: OperatorProfile.defaultProfile,
                rolandService: null,
                rolandConnected: ValueNotifier(false),
                rolandIpController: ipController,
                cameras: const [],
                onResponse: (_) {},
              ),
            ),
          );

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.text('Macro 1'), findsNothing);

      // The Roland IP changes in place (mirrors Settings -> Connections
      // mutating the same TextEditingController) while the panel is not
      // rebuilt from scratch.
      ipController.text = '10.0.1.30';
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      // The new IP has no saved visibility, so macro 1 should show again.
      expect(find.text('Macro 1'), findsOneWidget);
    });
  });

  group('OperatorPanel — recording (started from Settings, stopped in the top bar)', () {
    late ServiceRecorder recorder;
    setUp(() => recorder = ServiceRecorder());
    tearDown(() => recorder.dispose());

    Widget build({VoidCallback? onServicesChanged}) => MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: Scaffold(
            appBar: AppBar(actions: [
              RecordingIndicator(
                recorder: recorder,
                onResponse: (_) {},
                onServicesChanged: onServicesChanged,
              ),
            ]),
            body: OperatorPanel(
              operator: OperatorProfile.defaultProfile,
              rolandService: MockRolandService(),
              rolandConnected: ValueNotifier(true),
              cameras: const [],
              onResponse: (_) {},
              recorder: recorder,
            ),
          ),
        );

    testWidgets(
        'the panel has no Record button; the top bar shows nothing until a '
        'recording starts', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.text('Record'), findsNothing);
      expect(find.textContaining('Recording'), findsNothing);

      recorder.start();
      await tester.pumpAndSettle();
      expect(find.text('Recording · 0 steps · Stop'), findsOneWidget);
    });

    testWidgets('firing an action while not recording records nothing',
        (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      expect(recorder.steps, isEmpty);
    });

    testWidgets('stopping with no recorded steps does not show a save dialog',
        (tester) async {
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(recorder.isRecording, isFalse);
    });

    testWidgets(
        'macros fired while recording are saved in order on Stop then Save',
        (tester) async {
      var changedCount = 0;
      await tester.pumpWidget(build(onServicesChanged: () => changedCount++));
      recorder.start();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 2').first);
      await tester.pumpAndSettle();
      expect(find.text('Recording · 2 steps · Stop'), findsOneWidget);

      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Recorded Run');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = await ServiceStore.loadAll();
      expect(saved, hasLength(1));
      expect(saved.first.name, 'Recorded Run');
      expect(saved.first.steps.map((s) => s.type),
          [StepType.macro, StepType.macro]);
      expect(saved.first.steps.map((s) => s.macroNumber), [1, 2]);
      expect(changedCount, 1);
      expect(find.textContaining('Recording'), findsNothing);
    });

    testWidgets(
        'a save that fails tells the operator and keeps the recording, so '
        'Stop then Save again succeeds', (tester) async {
      SharedPreferencesStorePlatform.instance = _RefuseFirstServicesWrite();
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sunday Mass');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't save"), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();

      // Nothing lost, nothing added: capture stopped at Stop, the steps are
      // held, and the top bar offers the retry.
      expect(find.text('Unsaved recording · 1 step · Save'), findsOneWidget);
      await tester.tap(find.text('Macro 2').first);
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(1));

      await tester.tap(find.byType(RecordingIndicator));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sunday Mass');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = await ServiceStore.loadAll();
      expect(saved.map((s) => s.name), ['Sunday Mass']);
      expect(saved.single.steps, hasLength(1));
    });

    testWidgets('Stop cannot start a second save while one is in progress',
        (tester) async {
      final store = _GatedServicesWrite();
      addTearDown(() {
        if (!store.release.isCompleted) store.release.complete();
      });
      SharedPreferencesStorePlatform.instance = store;
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Once');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // The write is still pending; a second Stop must not reopen the dialog.
      await tester.tap(find.byType(RecordingIndicator), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // A button pressed after Stop is not captured, so it can't be wiped
      // by the post-save clear without anyone knowing.
      await tester.tap(find.text('Macro 2').first);
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(1));

      store.release.complete();
      await tester.pumpAndSettle();
      expect((await ServiceStore.loadAll()).map((s) => s.name), ['Once']);
    });

    testWidgets(
        'tapping outside the name dialog keeps the recording; only Discard '
        'throws it away', (tester) async {
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(5, 590));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(recorder.steps, hasLength(1));
      expect(recorder.isRecording, isTrue);
    });

    testWidgets(
        'a retry after a save that half-landed keeps one copy of the service',
        (tester) async {
      SharedPreferencesStorePlatform.instance = _RefuseFirstGenerationBump();
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byType(RecordingIndicator));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Sunday Mass');
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        if (attempt == 0) {
          expect(find.textContaining("Couldn't save"), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, 'OK'));
          await tester.pumpAndSettle();
        }
      }

      final saved = await ServiceStore.loadAll();
      expect(saved.map((s) => s.name), ['Sunday Mass']);
    });

    testWidgets(
        'Discard after a save that half-landed removes that copy too',
        (tester) async {
      SharedPreferencesStorePlatform.instance = _RefuseFirstGenerationBump();
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RecordingIndicator));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sunday Mass');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RecordingIndicator));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(await ServiceStore.loadAll(), isEmpty);
      expect(find.byType(RecordingIndicator), findsOneWidget);
      expect(find.textContaining('Recording'), findsNothing);
    });

    testWidgets(
        'a failed save still tells the operator when the Stop button is gone '
        'by the time it fails', (tester) async {
      final store = _GatedThenRefusedServicesWrite();
      addTearDown(() {
        if (!store.release.isCompleted) store.release.complete();
      });
      SharedPreferencesStorePlatform.instance = store;
      final showIndicator = ValueNotifier(true);
      addTearDown(showIndicator.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Scaffold(
          appBar: AppBar(actions: [
            ValueListenableBuilder<bool>(
              valueListenable: showIndicator,
              builder: (_, show, __) => show
                  ? RecordingIndicator(recorder: recorder, onResponse: (_) {})
                  : const SizedBox.shrink(),
            ),
          ]),
          body: OperatorPanel(
            operator: OperatorProfile.defaultProfile,
            rolandService: MockRolandService(),
            rolandConnected: ValueNotifier(true),
            cameras: const [],
            onResponse: (_) {},
            recorder: recorder,
          ),
        ),
      ));
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sunday Mass');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Devices drop mid-save: the page swaps app bars under the save.
      showIndicator.value = false;
      await tester.pumpAndSettle();
      store.release.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't save"), findsOneWidget);
    });

    testWidgets('Discard clears the pending recording without saving',
        (tester) async {
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(await ServiceStore.loadAll(), isEmpty);
      expect(recorder.isRecording, isFalse);
      expect(recorder.steps, isEmpty);
    });

    testWidgets(
        'the recorder going away while the save dialog is open does not throw',
        (tester) async {
      await tester.pumpWidget(build());
      recorder.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Stop'));
      await tester.pumpAndSettle();

      // The page that owns the recorder is torn down mid-dialog.
      final orphan = recorder;
      recorder = ServiceRecorder();
      orphan.dispose();

      await tester.enterText(find.byType(TextField), 'Late Save');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
