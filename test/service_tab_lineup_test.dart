import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/lineup_store.dart';
import 'package:navigation_app/services/mock/mock_panasonic_service.dart';
import 'package:navigation_app/widgets/service_tab.dart';

class _RecordingCamera extends MockPanasonicService {
  final recalls = <int>[];

  @override
  Future<String> recallPreset(int preset) async {
    recalls.add(preset);
    return 'ok';
  }
}

final _mass = Service(
  id: 's1',
  name: 'Mass',
  participants: [Participant(id: 'pt1', name: 'Reader 1')],
  steps: [
    const ServiceStep(
      id: 'st1',
      type: StepType.ministry,
      participantId: 'pt1',
      positionId: 'pos1',
    ),
  ],
);

final _alice = Person(id: 'p1', name: 'Alice');
final _bob = Person(id: 'p2', name: 'Bob');

Widget _tab({
  List<Service>? services,
  List<Person>? people,
  List<PanasonicCameraConfig> cameras = const [],
  ValueChanged<String>? onFailure,
  Key? key,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ServiceTab(
          key: key,
          cameras: cameras,
          people: people ?? [_alice, _bob],
          positions: [Position(id: 'pos1', name: 'Lectern')],
          services: services ?? [_mass],
          heightRanges: const [],
          rolandService: null,
          rolandConnected: null,
          onResponse: (_) {},
          onFailure: onFailure,
        ),
      ),
    );

Future<void> _assignAlice(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButton<String?>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mass').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('— unassigned —').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alice').last);
  await tester.pumpAndSettle();
}

/// Throws the tab away and builds a fresh one, as switching tabs, switching
/// operators or the OS killing the app would.
Future<void> _remount(WidgetTester tester, Widget tab) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(tab);
  await tester.pumpAndSettle();
}

Finder get _castAlice => find.descendant(
    of: find.ancestor(
        of: find.text("Today's cast"), matching: find.byType(Column)),
    matching: find.text('Alice'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the lineup and selected service survive a remount',
      (tester) async {
    await tester.pumpWidget(_tab());
    await _assignAlice(tester);

    await _remount(tester, _tab(key: UniqueKey()));

    expect(find.text("Today's cast"), findsOneWidget);
    expect(_castAlice, findsOneWidget);
  });

  testWidgets('a lineup restores once services finish loading',
      (tester) async {
    await tester.pumpWidget(_tab());
    await _assignAlice(tester);

    // The page loads services asynchronously, so a fresh tab can mount
    // with none and receive them a frame later.
    await _remount(tester, _tab(services: const []));
    await tester.pumpWidget(_tab());
    await tester.pumpAndSettle();

    expect(_castAlice, findsOneWidget);
  });

  testWidgets('a lineup naming someone since deleted shows unassigned',
      (tester) async {
    await tester.pumpWidget(_tab());
    await _assignAlice(tester);

    await _remount(tester, _tab(people: [_bob], key: UniqueKey()));

    expect(tester.takeException(), isNull);
    expect(find.text("Today's cast"), findsOneWidget);
    expect(find.text('— unassigned —'), findsOneWidget);
  });

  testWidgets('each service remembers its own lineup', (tester) async {
    final vespers = Service(
      id: 's2',
      name: 'Vespers',
      participants: [Participant(id: 'pt1', name: 'Reader 1')],
      steps: _mass.steps,
    );
    await tester.pumpWidget(_tab(services: [_mass, vespers]));
    await _assignAlice(tester);

    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vespers').last);
    await tester.pumpAndSettle();
    expect(_castAlice, findsNothing);

    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mass').last);
    await tester.pumpAndSettle();
    expect(_castAlice, findsOneWidget);
  });

  testWidgets('a lineup that expires while the tab is open is dropped',
      (tester) async {
    var clock = DateTime(2026, 10, 4, 9, 0);
    LineupStore.now = () => clock;
    addTearDown(() => LineupStore.now = DateTime.now);
    await tester.pumpWidget(_tab());
    await _assignAlice(tester);

    // The iPad sat locked on this tab for half an hour, then woke up.
    clock = clock.add(const Duration(minutes: 30));
    await LineupStore.renew();
    await tester.pumpAndSettle();

    expect(_castAlice, findsNothing,
        reason: 'the copy on screen would outlive the one that expired');
  });

  testWidgets('changing one reader on a lapsed lineup does not save the rest',
      (tester) async {
    // The Mac woke from sleep before the renew timer ran. Re-saving the
    // whole lineup on screen would give yesterday's readers a fresh 20
    // minutes, and the next reader cue would aim at the wrong person.
    var clock = DateTime(2026, 10, 4, 9, 0);
    LineupStore.now = () => clock;
    addTearDown(() => LineupStore.now = DateTime.now);
    final twoReaders = Service(
      id: 's1',
      name: 'Mass',
      participants: [
        Participant(id: 'pt1', name: 'Reader 1'),
        Participant(id: 'pt2', name: 'Reader 2'),
      ],
      steps: [
        for (final pt in ['pt1', 'pt2'])
          ServiceStep(
              id: 'st-$pt',
              type: StepType.ministry,
              participantId: pt,
              positionId: 'pos1'),
      ],
    );
    await tester.pumpWidget(_tab(services: [twoReaders]));
    await _assignAlice(tester);

    clock = clock.add(const Duration(minutes: 30));
    await tester.tap(find.text('— unassigned —').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();

    expect(await LineupStore.load('s1'), {'pt2': 'p2'});
    expect(_castAlice, findsNothing);
  });

  testWidgets('a lapsed lineup still on screen does not fire its reader cue',
      (tester) async {
    // The Mac slept overnight on this tab. The renew timer pauses while it
    // sleeps but the lease runs on the wall clock, so on waking Saturday's
    // lineup is still on screen until the timer next runs. A reader cue
    // tapped then must not aim the camera at Saturday's reader.
    var clock = DateTime(2026, 10, 3, 17, 0);
    LineupStore.now = () => clock;
    addTearDown(() => LineupStore.now = DateTime.now);
    final service = _RecordingCamera();
    final camera = PanasonicCameraConfig(
        name: 'Cam', ipAddress: '10.0.1.10', service: service)
      ..isConnected.value = true;
    addTearDown(camera.dispose);
    final failed = <String>[];
    final mass = Service(
      id: 's1',
      name: 'Mass',
      participants: [Participant(id: 'pt1', name: 'Reader 1')],
      steps: [
        const ServiceStep(
          id: 'st1',
          type: StepType.ministry,
          participantId: 'pt1',
          positionId: 'pos1',
          cameraIp: '10.0.1.10',
        ),
      ],
    );
    final alice = Person(id: 'p1', name: 'Alice', positionPresets: {
      'pos1': {'10.0.1.10': 7},
    });
    await tester.pumpWidget(_tab(
        services: [mass],
        people: [alice],
        cameras: [camera],
        onFailure: failed.add));
    await _assignAlice(tester);

    await tester.tap(find.textContaining('Reader 1  ·'));
    await tester.pumpAndSettle();
    expect(service.recalls, [7], reason: 'the cue fires on a live lineup');

    clock = clock.add(const Duration(hours: 15));
    await tester.tap(find.textContaining('Reader 1  ·'));
    await tester.pumpAndSettle();

    expect(service.recalls, [7], reason: "Saturday's reader was recalled");
    expect(failed, ['No one assigned to "Reader 1" for this service']);
    expect(_castAlice, findsNothing);
  });
}
