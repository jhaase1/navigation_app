import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/widgets/positions_tab.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PositionsTab — empty states', () {
    testWidgets('shows "No cameras" when camera list is empty', (tester) async {
      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: const [],
        positions: const [],
        people: const [],
        heightRanges: const [],
        onResponse: (_) {},
      )));
      expect(find.text('No cameras configured'), findsOneWidget);
    });

    testWidgets('shows "No positions configured" when positions are empty',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: const [],
        people: const [],
        heightRanges: const [],
        onResponse: (_) {},
      )));
      expect(find.text('No positions configured'), findsOneWidget);
    });
  });

  group('PositionsTab — camera toggle', () {
    testWidgets('shows a toggle button per camera', (tester) async {
      final cam1 =
          PanasonicCameraConfig(name: 'Camera A', ipAddress: '10.0.1.10');
      final cam2 =
          PanasonicCameraConfig(name: 'Camera B', ipAddress: '10.0.1.11');
      addTearDown(cam1.dispose);
      addTearDown(cam2.dispose);

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam1, cam2],
        positions: const [],
        people: const [],
        heightRanges: const [],
        onResponse: (_) {},
      )));

      expect(find.text('Camera A'), findsOneWidget);
      expect(find.text('Camera B'), findsOneWidget);
    });
  });

  group('PositionsTab — position cards', () {
    testWidgets('renders a card for each position', (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      final positions = [
        Position(id: 'pos1', name: 'Lectern'),
        Position(id: 'pos2', name: 'Pulpit'),
      ];

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: positions,
        people: const [],
        heightRanges: const [],
        onResponse: (_) {},
      )));

      expect(find.text('Lectern'), findsOneWidget);
      expect(find.text('Pulpit'), findsOneWidget);
    });

    testWidgets('shows "No one configured" when no person has a preset for the position',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [Person(id: 'p1', name: 'Alice')],
        heightRanges: const [],
        onResponse: (_) {},
      )));

      expect(find.textContaining('No one configured'), findsOneWidget);
    });

    testWidgets('shows person button when they have a preset for the position',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      final person = Person(
        id: 'p1',
        name: 'Alice',
        positionPresets: {
          'pos1': {'10.0.1.10': 0},
        },
      );

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [person],
        heightRanges: const [],
        onResponse: (_) {},
      )));

      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
    });

    testWidgets('only shows people with a preset for the selected camera',
        (tester) async {
      final cam1 =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      final cam2 =
          PanasonicCameraConfig(name: 'Cam 2', ipAddress: '10.0.1.11');
      addTearDown(cam1.dispose);
      addTearDown(cam2.dispose);

      // Alice has a preset only for cam1
      final alice = Person(
        id: 'p1',
        name: 'Alice',
        positionPresets: {
          'pos1': {'10.0.1.10': 2},
        },
      );
      // Bob has a preset only for cam2
      final bob = Person(
        id: 'p2',
        name: 'Bob',
        positionPresets: {
          'pos1': {'10.0.1.11': 5},
        },
      );

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam1, cam2],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [alice, bob],
        heightRanges: const [],
        onResponse: (_) {},
      )));

      // Cam 1 is selected by default — only Alice should appear
      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Bob'), findsNothing);
    });
  });

  group('PositionsTab — height range defaults', () {
    testWidgets(
        'shows a person with no explicit override but a matching height range',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      final shortRange = HeightRange(
        id: 'hr1',
        maxHeightCm: 165,
        positionPresets: {
          'pos1': {'10.0.1.10': 4},
        },
      );
      final alice = Person(id: 'p1', name: 'Alice', heightCm: 160);

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [alice],
        heightRanges: [shortRange],
        onResponse: (_) {},
      )));

      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
    });

    testWidgets('hides a person whose height matches no range and has no override',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      final shortRange = HeightRange(
        id: 'hr1',
        maxHeightCm: 150,
        positionPresets: {
          'pos1': {'10.0.1.10': 4},
        },
      );
      final alice = Person(id: 'p1', name: 'Alice', heightCm: 180);

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [alice],
        heightRanges: [shortRange],
        onResponse: (_) {},
      )));

      expect(find.textContaining('No one configured'), findsOneWidget);
    });

    testWidgets('tapping a height-resolved person attempts to recall its preset',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      final shortRange = HeightRange(
        id: 'hr1',
        maxHeightCm: 165,
        positionPresets: {
          'pos1': {'10.0.1.10': 4},
        },
      );
      final alice = Person(id: 'p1', name: 'Alice', heightCm: 160);

      String? response;
      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [alice],
        heightRanges: [shortRange],
        onResponse: (r) => response = r,
      )));

      await tester.tap(find.widgetWithText(FilledButton, 'Alice'));
      await tester.pumpAndSettle();

      // Camera isn't connected, but the preset itself was found via the
      // height range — proves resolution happened rather than falling
      // back to the "no preset linked" branch.
      expect(response, 'Cam not connected');
    });

    testWidgets('personal override takes precedence over a matching height range',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      final shortRange = HeightRange(
        id: 'hr1',
        maxHeightCm: 165,
        positionPresets: {
          'pos1': {'10.0.1.10': 4},
        },
      );
      final alice = Person(
        id: 'p1',
        name: 'Alice',
        heightCm: 160,
        positionPresets: {
          'pos1': {'10.0.1.10': 9},
        },
      );

      await tester.pumpWidget(_wrap(PositionsTab(
        cameras: [cam],
        positions: [Position(id: 'pos1', name: 'Lectern')],
        people: [alice],
        heightRanges: [shortRange],
        onResponse: (_) {},
      )));

      expect(find.widgetWithText(FilledButton, 'Alice'), findsOneWidget);
    });
  });
}
