// Regression test for: "altering operator settings does not change what
// shows up in the Panel tab". Mimics the real wiring between
// OperatorManagerDialog (edits + persists via OperatorStore) and
// OperatorPanel (reads the active OperatorProfile), the same way
// MultiDeviceControlPage wires them together.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/widgets/operator_manager_dialog.dart';
import 'package:navigation_app/widgets/operator_panel.dart';

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  OperatorProfile _active = OperatorProfile.defaultProfile;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ops = await OperatorStore.loadAll();
    final activeId = await OperatorStore.loadActiveId();
    final active = ops.firstWhere((o) => o.id == activeId,
        orElse: () => ops.first);
    if (mounted) setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: false),
      home: Scaffold(
        body: Column(
          children: [
            Builder(builder: (context) {
              return TextButton(
                child: const Text('open manager'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => OperatorManagerDialog(
                    rolandStorageKey: 'roland_',
                    cameras: const [],
                    onSaved: _reload,
                  ),
                ),
              );
            }),
            Expanded(
              child: OperatorPanel(
                operator: _active,
                rolandService: null,
                rolandConnected: ValueNotifier(false),
                cameras: const [],
                onResponse: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'editing a custom operator\'s items updates the Panel tab',
      (tester) async {
    // Seed a custom (non-default) operator that is already active, with
    // only macro 1 visible.
    const custom = OperatorProfile(
      id: 'op1',
      name: 'Camera Op',
      items: {'roland_': [1]},
    );
    await OperatorStore.saveAll([OperatorProfile.defaultProfile, custom]);
    await OperatorStore.saveActiveId('op1');

    await tester.pumpWidget(const _Harness());
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNWidgets(1));

    // Open the manager, edit the active operator to add macro 2 as well.
    await tester.tap(find.text('open manager'));
    await tester.pumpAndSettle();

    final camOpTile = find.ancestor(
      of: find.text('Camera Op'),
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(
      of: camOpTile,
      matching: find.byIcon(Icons.edit),
    ));
    await tester.pumpAndSettle();

    // Select macro "M2" chip (currently unselected).
    await tester.ensureVisible(find.text('M2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M2'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Panel should now show 2 buttons (macro 1 and macro 2).
    expect(find.byType(FilledButton), findsNWidgets(2));
  });

  group('Default operator', () {
    testWidgets('shows all items when never configured', (tester) async {
      await OperatorStore.saveAll([OperatorProfile.defaultProfile]);
      await OperatorStore.saveActiveId(OperatorProfile.defaultId);

      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNWidgets(100));
    });

    testWidgets('respects an explicit item selection saved via the manager',
        (tester) async {
      await OperatorStore.saveAll([OperatorProfile.defaultProfile]);
      await OperatorStore.saveActiveId(OperatorProfile.defaultId);

      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNWidgets(100));

      await tester.tap(find.text('open manager'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pumpAndSettle();

      // Deselect everything via "None".
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // The Panel now reflects the explicit "show nothing" selection.
      expect(find.byType(FilledButton), findsNothing);
      expect(find.textContaining('No items configured'), findsOneWidget);
    });
  });
}
