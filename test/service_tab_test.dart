import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/widgets/service_tab.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

ServiceTab _tab({
  List<PanasonicCameraConfig> cameras = const [],
  List<Person> people = const [],
  List<Position> positions = const [],
  List<Service> services = const [],
  ValueChanged<String>? onResponse,
}) =>
    ServiceTab(
      cameras: cameras,
      people: people,
      positions: positions,
      services: services,
      rolandService: null,
      rolandConnected: null,
      onResponse: onResponse ?? (_) {},
    );

void main() {
  group('ServiceTab — empty state', () {
    testWidgets('shows "No services configured" when service list is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(_tab()));
      expect(find.text('No services configured'), findsOneWidget);
      expect(find.textContaining('Manage Services'), findsOneWidget);
    });
  });

  group('ServiceTab — service selection', () {
    testWidgets('shows a service dropdown when services exist', (tester) async {
      final service = Service(id: 's1', name: 'Standard Mass');
      await tester.pumpWidget(_wrap(_tab(services: [service])));
      expect(find.text('Service'), findsOneWidget);
    });

    testWidgets('selecting a service shows its steps', (tester) async {
      final service = Service(
        id: 's1',
        name: 'Standard Mass',
        steps: [
          const ServiceStep(id: 'st1', type: StepType.macro, macroNumber: 3),
        ],
      );
      await tester.pumpWidget(_wrap(_tab(services: [service])));

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard Mass').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Macro 3'), findsOneWidget);
    });

    testWidgets('shows "This service has no steps" for a service with no steps',
        (tester) async {
      final service = Service(id: 's1', name: 'Empty Service');
      await tester.pumpWidget(_wrap(_tab(services: [service])));

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty Service').last);
      await tester.pumpAndSettle();

      expect(find.text('This service has no steps'), findsOneWidget);
    });
  });

  group('ServiceTab — participant assignment panel', () {
    testWidgets(
        'shows "Today\'s cast" panel when ministry steps reference participants',
        (tester) async {
      final service = Service(
        id: 's1',
        name: 'Mass',
        participants: [
          Participant(id: 'pt1', name: 'Reader 1'),
        ],
        steps: [
          const ServiceStep(
            id: 'st1',
            type: StepType.ministry,
            participantId: 'pt1',
            positionId: 'pos1',
          ),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(
        services: [service],
        positions: [Position(id: 'pos1', name: 'Lectern')],
      )));

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.text("Today's cast"), findsOneWidget);
      expect(find.text('Reader 1'), findsWidgets);
    });

    testWidgets('does not show "Today\'s cast" for macro-only service',
        (tester) async {
      final service = Service(
        id: 's1',
        name: 'Macro Only',
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.macro, macroNumber: 1),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [service])));

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macro Only').last);
      await tester.pumpAndSettle();

      expect(find.text("Today's cast"), findsNothing);
    });
  });

  group('ServiceTab — Prev/Next navigation', () {
    testWidgets('shows "Tap a step or Next to begin" initially',
        (tester) async {
      final service = Service(
        id: 's1',
        name: 'Mass',
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.macro, macroNumber: 1),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [service])));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.text('Tap a step or Next to begin'), findsOneWidget);
    });

    testWidgets('Next advances and shows counter', (tester) async {
      final service = Service(
        id: 's1',
        name: 'Mass',
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.macro, macroNumber: 1),
          const ServiceStep(
              id: 'st2', type: StepType.macro, macroNumber: 2),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [service])));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('Prev button is disabled before any step is selected',
        (tester) async {
      final service = Service(
        id: 's1',
        name: 'Mass',
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.macro, macroNumber: 1),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [service])));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      final prevButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Prev'));
      expect(prevButton.onPressed, isNull);
    });
  });

  group('ServiceTab — warning indicators', () {
    testWidgets('shows warning icon on macro step with no macro number',
        (tester) async {
      final service = Service(
        id: 's1',
        name: 'Mass',
        steps: [
          const ServiceStep(id: 'st1', type: StepType.macro),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [service])));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('shows warning icon on shot step with no camera set',
        (tester) async {
      final service = Service(
        id: 's1',
        name: 'Mass',
        steps: [
          const ServiceStep(id: 'st1', type: StepType.shot),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [service])));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });
  });

  group('ServiceTab — block flattening', () {
    testWidgets('block steps are expanded inline from the sub-service',
        (tester) async {
      final sub = Service(
        id: 'sub1',
        name: 'Intro',
        steps: [
          const ServiceStep(
              id: 'st-a', type: StepType.macro, macroNumber: 10),
          const ServiceStep(
              id: 'st-b', type: StepType.macro, macroNumber: 11),
        ],
      );
      final main = Service(
        id: 'main1',
        name: 'Main Service',
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.block, subServiceId: 'sub1'),
        ],
      );

      await tester.pumpWidget(_wrap(_tab(services: [main, sub])));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main Service').last);
      await tester.pumpAndSettle();

      // The two steps from the sub-service should appear
      expect(find.textContaining('Macro 10'), findsOneWidget);
      expect(find.textContaining('Macro 11'), findsOneWidget);
    });
  });
}
