import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/role.dart';
import 'package:navigation_app/models/scene.dart';
import 'package:navigation_app/models/service_order.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/services/role_store.dart';
import 'package:navigation_app/services/scene_store.dart';
import 'package:navigation_app/services/service_order_store.dart';
import 'package:navigation_app/widgets/order_manager_dialog.dart';
import 'package:navigation_app/widgets/people_manager_dialog.dart';
import 'package:navigation_app/widgets/role_manager_dialog.dart';
import 'package:navigation_app/widgets/scene_manager_dialog.dart';

// Open a dialog widget via showDialog so Navigator.pop works normally.
Future<void> _open(WidgetTester tester, Widget Function(BuildContext) builder) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Builder(builder: (ctx) => TextButton(
      onPressed: () => showDialog<void>(context: ctx, builder: builder),
      child: const Text('Open'),
    )),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// ─── SceneManagerDialog ──────────────────────────────────────────────────────

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SceneManagerDialog — list view', () {
    testWidgets('shows empty state when no scenes exist', (tester) async {
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));
      expect(find.textContaining('No scenes yet'), findsOneWidget);
    });

    testWidgets('shows scenes loaded from store', (tester) async {
      await SceneStore.saveAll([
        Scene(id: 's1', name: 'Lectern'),
        Scene(id: 's2', name: 'Pulpit'),
      ]);
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));
      expect(find.text('Lectern'), findsOneWidget);
      expect(find.text('Pulpit'), findsOneWidget);
    });

    testWidgets('shows Add Scene button', (tester) async {
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));
      expect(find.text('Add Scene'), findsOneWidget);
    });
  });

  group('SceneManagerDialog — add / edit', () {
    testWidgets('Add Scene opens the editor', (tester) async {
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));
      await tester.tap(find.text('Add Scene'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Scene'), findsOneWidget);
    });

    testWidgets('saving a new scene adds it to the list', (tester) async {
      bool saved = false;
      await _open(tester,
          (_) => SceneManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.text('Add Scene'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Baptistry');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Baptistry'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('Cancel from editor returns to list without saving', (tester) async {
      bool saved = false;
      await _open(tester,
          (_) => SceneManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.text('Add Scene'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Temporary');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Temporary'), findsNothing);
      expect(find.text('Add Scene'), findsOneWidget);
      expect(saved, isFalse);
    });

    testWidgets('editing an existing scene updates its name', (tester) async {
      await SceneStore.saveAll([Scene(id: 's1', name: 'Old Name')]);
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('Old Name'), findsNothing);
    });

    testWidgets('blank name defaults to "New Scene"', (tester) async {
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));
      await tester.tap(find.text('Add Scene'));
      await tester.pumpAndSettle();
      // Leave name empty
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('New Scene'), findsOneWidget);
    });
  });

  group('SceneManagerDialog — delete', () {
    testWidgets('delete shows confirmation dialog', (tester) async {
      await SceneStore.saveAll([Scene(id: 's1', name: 'Chapel')]);
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Delete Scene'), findsOneWidget);
    });

    testWidgets('confirming delete removes the scene', (tester) async {
      bool saved = false;
      await SceneStore.saveAll([Scene(id: 's1', name: 'Chapel')]);
      await _open(tester,
          (_) => SceneManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Chapel'), findsNothing);
      expect(saved, isTrue);
    });

    testWidgets('cancelling delete keeps the scene', (tester) async {
      await SceneStore.saveAll([Scene(id: 's1', name: 'Chapel')]);
      await _open(tester, (_) => SceneManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Chapel'), findsOneWidget);
    });
  });

  // ─── RoleManagerDialog ────────────────────────────────────────────────────

  group('RoleManagerDialog — list view', () {
    testWidgets('shows empty state when no roles exist', (tester) async {
      await _open(tester, (_) => RoleManagerDialog(onSaved: () {}));
      expect(find.textContaining('No roles yet'), findsOneWidget);
    });

    testWidgets('shows roles loaded from store', (tester) async {
      await RoleStore.saveAll([
        Role(id: 'r1', name: 'Reader 1'),
        Role(id: 'r2', name: 'Priest'),
      ]);
      await _open(tester, (_) => RoleManagerDialog(onSaved: () {}));
      expect(find.text('Reader 1'), findsOneWidget);
      expect(find.text('Priest'), findsOneWidget);
    });
  });

  group('RoleManagerDialog — add / edit', () {
    testWidgets('Add Role opens the editor', (tester) async {
      await _open(tester, (_) => RoleManagerDialog(onSaved: () {}));
      await tester.tap(find.text('Add Role'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Role'), findsOneWidget);
    });

    testWidgets('saving a new role adds it to the list', (tester) async {
      bool saved = false;
      await _open(tester,
          (_) => RoleManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.text('Add Role'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Deacon');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Deacon'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('blank name defaults to "Role"', (tester) async {
      await _open(tester, (_) => RoleManagerDialog(onSaved: () {}));
      await tester.tap(find.text('Add Role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Role'), findsOneWidget);
    });

    testWidgets('Cancel from editor returns to list without saving', (tester) async {
      bool saved = false;
      await _open(tester,
          (_) => RoleManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.text('Add Role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Role'), findsOneWidget);
      expect(saved, isFalse);
    });

    testWidgets('editing an existing role updates its name', (tester) async {
      await RoleStore.saveAll([Role(id: 'r1', name: 'Acolyte')]);
      await _open(tester, (_) => RoleManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sub-deacon');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Sub-deacon'), findsOneWidget);
      expect(find.text('Acolyte'), findsNothing);
    });
  });

  group('RoleManagerDialog — delete', () {
    testWidgets('confirming delete removes the role and calls onSaved',
        (tester) async {
      bool saved = false;
      await RoleStore.saveAll([Role(id: 'r1', name: 'Cantor')]);
      await _open(tester,
          (_) => RoleManagerDialog(onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Cantor'), findsNothing);
      expect(saved, isTrue);
    });

    testWidgets('cancelling delete keeps the role', (tester) async {
      await RoleStore.saveAll([Role(id: 'r1', name: 'Cantor')]);
      await _open(tester, (_) => RoleManagerDialog(onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Cantor'), findsOneWidget);
    });
  });

  // ─── PeopleManagerDialog ─────────────────────────────────────────────────

  group('PeopleManagerDialog — list view', () {
    testWidgets('shows empty state when no people exist', (tester) async {
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () {}));
      expect(find.textContaining('No people yet'), findsOneWidget);
    });

    testWidgets('shows people loaded from store', (tester) async {
      await PeopleStore.saveAll([
        Person(id: 'p1', name: 'Alice'),
        Person(id: 'p2', name: 'Bob'),
      ]);
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () {}));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('subtitle shows scene count', (tester) async {
      await PeopleStore.saveAll([
        Person(id: 'p1', name: 'Alice', scenePresets: {'s1': {'10.0.0.1': 0}}),
      ]);
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () {}));
      expect(find.textContaining('1 scene configured'), findsOneWidget);
    });
  });

  group('PeopleManagerDialog — editor', () {
    testWidgets('Add Person with no scenes shows scenes-first warning',
        (tester) async {
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () {}));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add scenes first'), findsOneWidget);
    });

    testWidgets('Add Person with no cameras shows no-cameras warning',
        (tester) async {
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [Scene(id: 's1', name: 'Lectern')],
        cameras: [],
        onSaved: () {},
      ));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No cameras'), findsOneWidget);
    });

    testWidgets('Add Person with scenes and cameras shows preset grid',
        (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [Scene(id: 's1', name: 'Lectern')],
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
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () => saved = true));

      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Carol');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Carol'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('blank name defaults to "Unnamed"', (tester) async {
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () {}));
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
      await _open(tester, (_) => PeopleManagerDialog(
        scenes: [], cameras: [], onSaved: () => saved = true));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Dave'), findsNothing);
      expect(saved, isTrue);
    });
  });

  // ─── OrderManagerDialog ───────────────────────────────────────────────────

  group('OrderManagerDialog — list view', () {
    testWidgets('shows empty state when no orders exist', (tester) async {
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      expect(find.textContaining('No orders yet'), findsOneWidget);
    });

    testWidgets('shows orders loaded from store', (tester) async {
      await ServiceOrderStore.saveAll([
        ServiceOrder(id: 'o1', name: 'Standard Mass', moments: []),
        ServiceOrder(id: 'o2', name: 'Vespers', moments: []),
      ]);
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      expect(find.text('Standard Mass'), findsOneWidget);
      expect(find.text('Vespers'), findsOneWidget);
    });

    testWidgets('subtitle shows moment count', (tester) async {
      await ServiceOrderStore.saveAll([
        ServiceOrder(id: 'o1', name: 'Mass', moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
          const OrderMoment(id: 'm2', type: MomentType.macro, macroNumber: 2),
        ]),
      ]);
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      expect(find.textContaining('2 moments'), findsOneWidget);
    });
  });

  group('OrderManagerDialog — editor', () {
    testWidgets('Add Order opens the editor', (tester) async {
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      await tester.tap(find.text('Add Order'));
      await tester.pumpAndSettle();
      expect(find.text('Add Moment'), findsOneWidget);
    });

    testWidgets('Add Moment button adds a moment row', (tester) async {
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      await tester.tap(find.text('Add Order'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Moment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Moment'));
      await tester.pumpAndSettle();

      // Two moment rows numbered 1. and 2.
      expect(find.textContaining('1.'), findsOneWidget);
      expect(find.textContaining('2.'), findsOneWidget);
    });

    testWidgets('remove icon on a moment deletes that row', (tester) async {
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      await tester.tap(find.text('Add Order'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Moment'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('1.'), findsNothing);
    });

    testWidgets('saving a new order adds it to the list', (tester) async {
      bool saved = false;
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [],
        onSaved: () => saved = true,
      ));
      await tester.tap(find.text('Add Order'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '').first,
          'Christmas Vigil');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Christmas Vigil'), findsOneWidget);
      expect(saved, isTrue);
    });

    testWidgets('blank name defaults to "New Order"', (tester) async {
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));
      await tester.tap(find.text('Add Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('New Order'), findsOneWidget);
    });

    testWidgets('Cancel from editor returns to list without saving',
        (tester) async {
      bool saved = false;
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [],
        onSaved: () => saved = true,
      ));
      await tester.tap(find.text('Add Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Order'), findsOneWidget);
      expect(saved, isFalse);
    });
  });

  group('OrderManagerDialog — delete', () {
    testWidgets('confirming delete removes order and calls onSaved',
        (tester) async {
      bool saved = false;
      await ServiceOrderStore.saveAll(
          [ServiceOrder(id: 'o1', name: 'Advent', moments: [])]);
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [],
        onSaved: () => saved = true,
      ));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Advent'), findsNothing);
      expect(saved, isTrue);
    });

    testWidgets('cancelling delete keeps the order', (tester) async {
      await ServiceOrderStore.saveAll(
          [ServiceOrder(id: 'o1', name: 'Advent', moments: [])]);
      await _open(tester, (_) => OrderManagerDialog(
        roles: [], scenes: [], cameras: [], onSaved: () {}));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Advent'), findsOneWidget);
    });
  });
}
