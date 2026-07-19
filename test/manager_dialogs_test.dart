import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/services/service_store.dart';
import 'package:navigation_app/widgets/people_manager_dialog.dart';
import 'package:navigation_app/widgets/position_manager_dialog.dart';
import 'package:navigation_app/widgets/service_manager_dialog.dart';

// Open a dialog widget via showDialog so Navigator.pop works normally.
Future<void> _open(
    WidgetTester tester, Widget Function(BuildContext) builder) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Builder(
        builder: (ctx) => TextButton(
              onPressed: () =>
                  showDialog<void>(context: ctx, builder: builder),
              child: const Text('Open'),
            )),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// ─── PositionManagerDialog ────────────────────────────────────────────────────

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PositionManagerDialog — list view', () {
    testWidgets('shows empty state when no positions exist', (tester) async {
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));
      expect(find.textContaining('No positions yet'), findsOneWidget);
    });

    testWidgets('shows positions loaded from store', (tester) async {
      await PositionStore.saveAll([
        Position(id: 'p1', name: 'Lectern'),
        Position(id: 'p2', name: 'Pulpit'),
      ]);
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));
      expect(find.text('Lectern'), findsOneWidget);
      expect(find.text('Pulpit'), findsOneWidget);
    });

    testWidgets('shows Add Position button', (tester) async {
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));
      expect(find.text('Add Position'), findsOneWidget);
    });
  });

  group('PositionManagerDialog — add / edit', () {
    testWidgets('Add Position opens the editor', (tester) async {
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));
      await tester.tap(find.text('Add Position'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Position'), findsOneWidget);
    });

    testWidgets('saving a new position adds it to the list', (tester) async {
      bool saved = false;
      await _open(
          tester, (_) => PositionManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.text('Add Position'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Baptistry');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Baptistry'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('Cancel from editor returns to list without saving',
        (tester) async {
      bool saved = false;
      await _open(
          tester, (_) => PositionManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.text('Add Position'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Temporary');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Temporary'), findsNothing);
      expect(find.text('Add Position'), findsOneWidget);
      expect(saved, isFalse);
    });

    testWidgets('editing an existing position updates its name',
        (tester) async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Old Name')]);
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('Old Name'), findsNothing);
    });

    testWidgets('blank name defaults to "New Position"', (tester) async {
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));
      await tester.tap(find.text('Add Position'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('New Position'), findsOneWidget);
    });
  });

  group('PositionManagerDialog — delete', () {
    testWidgets('delete shows confirmation dialog', (tester) async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Chapel')]);
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Delete Position'), findsOneWidget);
    });

    testWidgets('confirming delete removes the position', (tester) async {
      bool saved = false;
      await PositionStore.saveAll([Position(id: 'p1', name: 'Chapel')]);
      await _open(
          tester, (_) => PositionManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Chapel'), findsNothing);
      expect(saved, isTrue);
    });

    testWidgets('cancelling delete keeps the position', (tester) async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Chapel')]);
      await _open(tester, (_) => PositionManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Chapel'), findsOneWidget);
    });
  });

  // ─── PeopleManagerDialog ─────────────────────────────────────────────────

  group('PeopleManagerDialog — list view', () {
    testWidgets('shows empty state when no people exist', (tester) async {
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.textContaining('No people yet'), findsOneWidget);
    });

    testWidgets('shows people loaded from store', (tester) async {
      await PeopleStore.saveAll([
        Person(id: 'p1', name: 'Alice'),
        Person(id: 'p2', name: 'Bob'),
      ]);
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('subtitle shows position count', (tester) async {
      await PeopleStore.saveAll([
        Person(
            id: 'p1',
            name: 'Alice',
            positionPresets: {
              'pos1': {'10.0.0.1': 0}
            }),
      ]);
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.textContaining('1 position configured'), findsOneWidget);
    });
  });

  group('PeopleManagerDialog — editor', () {
    testWidgets('Add Person with no positions shows positions-first warning',
        (tester) async {
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add positions first'), findsOneWidget);
    });

    testWidgets('Add Person with no cameras shows no-cameras warning',
        (tester) async {
      await _open(
          tester,
          (_) => PeopleManagerDialog(
                positions: [Position(id: 'pos1', name: 'Lectern')],
                cameras: const [],
                onSaved: () {},
              ));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No cameras'), findsOneWidget);
    });

    testWidgets('Add Person with positions and cameras shows preset grid',
        (tester) async {
      final cam =
          PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await _open(
          tester,
          (_) => PeopleManagerDialog(
                positions: [Position(id: 'pos1', name: 'Lectern')],
                cameras: [cam],
                onSaved: () {},
              ));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();

      expect(find.text('Lectern'), findsOneWidget);
      expect(find.text('Cam 1'), findsOneWidget);
    });

    testWidgets('saving a new person adds them to the list', (tester) async {
      bool saved = false;
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));

      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Carol');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Carol'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('blank name defaults to "Unnamed"', (tester) async {
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Unnamed'), findsOneWidget);
    });
  });

  group('PeopleManagerDialog — delete', () {
    testWidgets('confirming delete removes person and calls onSaved',
        (tester) async {
      bool saved = false;
      await PeopleStore.saveAll([Person(id: 'p1', name: 'Dave')]);
      await _open(
          tester,
          (_) => PeopleManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Dave'), findsNothing);
      expect(saved, isTrue);
    });
  });

  // ─── ServiceManagerDialog ─────────────────────────────────────────────────

  group('ServiceManagerDialog — list view', () {
    testWidgets('shows empty state when no services exist', (tester) async {
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.textContaining('No services yet'), findsOneWidget);
    });

    testWidgets('shows services loaded from store', (tester) async {
      await ServiceStore.saveAll([
        Service(id: 's1', name: 'Standard Mass'),
        Service(id: 's2', name: 'Vespers'),
      ]);
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.text('Standard Mass'), findsOneWidget);
      expect(find.text('Vespers'), findsOneWidget);
    });

    testWidgets('subtitle shows step count', (tester) async {
      await ServiceStore.saveAll([
        Service(
          id: 's1',
          name: 'Mass',
          steps: [
            const ServiceStep(
                id: 'st1', type: StepType.macro, macroNumber: 1),
            const ServiceStep(
                id: 'st2', type: StepType.macro, macroNumber: 2),
          ],
        ),
      ]);
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      expect(find.textContaining('2 step'), findsOneWidget);
    });
  });

  group('ServiceManagerDialog — editor', () {
    testWidgets('Add Service opens the editor', (tester) async {
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();
      expect(find.text('Add Step'), findsOneWidget);
    });

    testWidgets('Add Step button adds a step row', (tester) async {
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Step'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1.'), findsOneWidget);
      expect(find.textContaining('2.'), findsOneWidget);
    });

    testWidgets('remove icon on a step deletes that row', (tester) async {
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Step'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('1.'), findsNothing);
    });

    testWidgets('saving a new service adds it to the list', (tester) async {
      bool saved = false;
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Christmas Vigil');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Christmas Vigil'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('blank name defaults to "New Service"', (tester) async {
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('New Service'), findsOneWidget);
    });

    testWidgets('Cancel from editor returns to list without saving',
        (tester) async {
      bool saved = false;
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Service'), findsOneWidget);
      expect(saved, isFalse);
    });

    testWidgets('can add and remove a participant inline', (tester) async {
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));
      await tester.tap(find.text('Add Service'));
      await tester.pumpAndSettle();

      // Find the participant name field and type a name
      final participantField =
          find.widgetWithText(TextField, 'Participant name');
      await tester.enterText(participantField, 'Reader 1');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Reader 1'), findsOneWidget);

      // Remove it with ×
      await tester.tap(find.text('×'));
      await tester.pumpAndSettle();

      expect(find.text('Reader 1'), findsNothing);
    });
  });

  group('ServiceManagerDialog — delete', () {
    testWidgets('confirming delete removes service and calls onSaved',
        (tester) async {
      bool saved = false;
      await ServiceStore.saveAll([Service(id: 's1', name: 'Advent')]);
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [],
              cameras: const [],
              onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Advent'), findsNothing);
      expect(saved, isTrue);
    });

    testWidgets('cancelling delete keeps the service', (tester) async {
      await ServiceStore.saveAll([Service(id: 's1', name: 'Advent')]);
      await _open(
          tester,
          (_) => ServiceManagerDialog(
              positions: const [], cameras: const [], onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Advent'), findsOneWidget);
    });
  });
}
