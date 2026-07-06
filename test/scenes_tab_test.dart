import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/scene.dart';
import 'package:navigation_app/widgets/scenes_tab.dart';

PanasonicCameraConfig _makeCamera(String name, String ip) =>
    PanasonicCameraConfig(name: name, ipAddress: ip);

Widget _buildTab({
  List<PanasonicCameraConfig> cameras = const [],
  List<Scene> scenes = const [],
  List<Person> people = const [],
  ValueChanged<String>? onResponse,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Scaffold(
      body: ScenesTab(
        cameras: cameras,
        scenes: scenes,
        people: people,
        onResponse: onResponse ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('ScenesTab — empty states', () {
    testWidgets('shows no-cameras message when cameras list is empty',
        (tester) async {
      await tester.pumpWidget(_buildTab());
      expect(find.text('No cameras configured'), findsOneWidget);
    });

    testWidgets('shows no-scenes message when scenes list is empty',
        (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);

      await tester.pumpWidget(_buildTab(cameras: [camera]));
      expect(find.text('No scenes configured'), findsOneWidget);
    });
  });

  group('ScenesTab — scene cards', () {
    testWidgets('renders a card for each scene', (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);
      final scenes = [
        Scene(id: 's1', name: 'Lectern'),
        Scene(id: 's2', name: 'Pulpit'),
      ];

      await tester.pumpWidget(_buildTab(cameras: [camera], scenes: scenes));

      expect(find.text('Lectern'), findsOneWidget);
      expect(find.text('Pulpit'), findsOneWidget);
    });

    testWidgets(
        'shows "no one configured" text when no person has a preset for that scene',
        (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);
      final scenes = [Scene(id: 's1', name: 'Lectern')];
      final people = [Person(id: 'p1', name: 'Alice')]; // no presets

      await tester.pumpWidget(
          _buildTab(cameras: [camera], scenes: scenes, people: people));

      expect(
          find.text('No one configured here for this camera'), findsOneWidget);
    });
  });

  group('ScenesTab — person buttons', () {
    testWidgets(
        'shows FilledButton for person who has a preset on the selected camera',
        (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);
      final scene = Scene(id: 's1', name: 'Lectern');
      final person = Person(
        id: 'p1',
        name: 'Alice',
        scenePresets: {
          's1': {'10.0.0.1': 2},
        },
      );

      await tester.pumpWidget(_buildTab(
          cameras: [camera], scenes: [scene], people: [person]));

      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
    });

    testWidgets(
        'does not show button for person without a preset on the active camera',
        (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);
      final scene = Scene(id: 's1', name: 'Lectern');
      final personWithPreset = Person(
        id: 'p1',
        name: 'Alice',
        scenePresets: {'s1': {'10.0.0.1': 2}},
      );
      final personWithoutPreset = Person(
        id: 'p2',
        name: 'Bob',
        scenePresets: {}, // no presets at all
      );

      await tester.pumpWidget(_buildTab(
        cameras: [camera],
        scenes: [scene],
        people: [personWithPreset, personWithoutPreset],
      ));

      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Bob'), findsNothing);
    });

    testWidgets(
        'only shows button for person whose preset matches the ACTIVE camera IP',
        (tester) async {
      final cam1 = _makeCamera('Cam 1', '10.0.0.1');
      final cam2 = _makeCamera('Cam 2', '10.0.0.2');
      addTearDown(cam1.ipController.dispose);
      addTearDown(cam2.ipController.dispose);
      final scene = Scene(id: 's1', name: 'Lectern');

      // Alice only has a preset on Cam 2
      final alice = Person(
        id: 'p1',
        name: 'Alice',
        scenePresets: {'s1': {'10.0.0.2': 5}},
      );
      // Bob only has a preset on Cam 1
      final bob = Person(
        id: 'p2',
        name: 'Bob',
        scenePresets: {'s1': {'10.0.0.1': 3}},
      );

      await tester.pumpWidget(_buildTab(
        cameras: [cam1, cam2],
        scenes: [scene],
        people: [alice, bob],
      ));

      // Default is Cam 1 selected → only Bob shows
      expect(find.widgetWithText(FilledButton, 'Bob'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Alice'), findsNothing);

      // Switch to Cam 2 via ToggleButtons
      await tester.tap(find.text('Cam 2'));
      await tester.pumpAndSettle();

      // Now only Alice shows
      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Bob'), findsNothing);
    });

    testWidgets(
        'multiple people with presets for same scene all get buttons',
        (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);
      final scene = Scene(id: 's1', name: 'Lectern');
      final people = [
        Person(
            id: 'p1',
            name: 'Alice',
            scenePresets: {'s1': {'10.0.0.1': 0}}),
        Person(
            id: 'p2',
            name: 'Bob',
            scenePresets: {'s1': {'10.0.0.1': 1}}),
        Person(
            id: 'p3',
            name: 'Carol',
            scenePresets: {'s1': {'10.0.0.1': 2}}),
      ];

      await tester.pumpWidget(
          _buildTab(cameras: [camera], scenes: [scene], people: people));

      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Bob'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Carol'), findsOneWidget);
    });

    testWidgets('pressing button when camera is disconnected calls onResponse',
        (tester) async {
      final camera = _makeCamera('Cam 1', '10.0.0.1');
      addTearDown(camera.ipController.dispose);
      // isConnected defaults to false, service is null
      final scene = Scene(id: 's1', name: 'Lectern');
      final person = Person(
        id: 'p1',
        name: 'Alice',
        scenePresets: {'s1': {'10.0.0.1': 2}},
      );

      String? lastResponse;
      await tester.pumpWidget(_buildTab(
        cameras: [camera],
        scenes: [scene],
        people: [person],
        onResponse: (r) => lastResponse = r,
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'Alice'));
      await tester.pumpAndSettle();

      expect(lastResponse, contains('not connected'));
    });
  });

  group('ScenesTab — camera toggle', () {
    testWidgets('camera toggle buttons render for each camera', (tester) async {
      final cam1 = _makeCamera('Cam 1', '10.0.0.1');
      final cam2 = _makeCamera('Cam 2', '10.0.0.2');
      final cam3 = _makeCamera('Cam 3', '10.0.0.3');
      addTearDown(cam1.ipController.dispose);
      addTearDown(cam2.ipController.dispose);
      addTearDown(cam3.ipController.dispose);

      await tester.pumpWidget(
          _buildTab(cameras: [cam1, cam2, cam3], scenes: []));

      expect(find.text('Cam 1'), findsOneWidget);
      expect(find.text('Cam 2'), findsOneWidget);
      expect(find.text('Cam 3'), findsOneWidget);
    });
  });
}
