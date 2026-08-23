import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/device_label.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/widgets/backup/conflict_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBackupTarget target;
  late BackupService service;
  late BackupController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // Keep mine now asks for a name first. The service still uses its
      // own lambda; this just lets the upload guard proceed.
      DeviceLabel.key: 'Mac mini',
    });
    target = MockBackupTarget();
    service = BackupService(
      target: target,
      targetIdentity: 'mock:test',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    );
    controller = BackupController.forService(
      service,
      scheduler: BackupScheduler(
        service: service,
        debounce: const Duration(milliseconds: 1),
        sweepInterval: const Duration(days: 1),
        sleep: (_) async {},
      ),
    );
  });

  tearDown(() => controller.dispose());

  /// Puts the machine into a real divergence: ours pushed, theirs wrote a
  /// sibling, ours edited again.
  Future<void> diverge() async {
    await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
    await service.push();
    final base = (await service.history()).single;
    await target.put(
      '{"schemaVersion":1,"positions":[{"id":"p9","name":"Balcony"}],'
      '"people":[],"services":[],"heightRanges":[],"presetNames":{},'
      '"visibilities":{}}',
      contentHash: 'theirs',
      parentRevisionId: base.id,
      deviceLabel: "Daniel's iPad",
    );
    await PositionStore.saveAll([
      Position(id: 'p1', name: 'Pulpit'),
      Position(id: 'p2', name: 'Lectern'),
    ]);
    await controller.handleEvent(await service.push());
  }

  /// `BackupService._single` chains through a Completer. Under the widget
  /// test FakeAsync zone that chain does not resume; `runAsync` lets the
  /// real event loop finish the in-flight fetch/resolve.
  Future<void> flushEngine(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showConflictDialog(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await flushEngine(tester);
    await tester.pump();
  }

  testWidgets('"Use their copy" replaces local and clears the pill',
      (tester) async {
    await tester.runAsync(diverge);
    expect(controller.status.value.state, BackupPillState.needsReview);

    await openDialog(tester);

    expect(find.textContaining("Daniel's iPad"), findsOneWidget);
    expect(find.textContaining('Positions:'), findsOneWidget);

    await tester.tap(find.text('Use their copy'));
    await tester.pump();
    await flushEngine(tester);
    await tester.pumpAndSettle();

    expect((await PositionStore.loadAll()).map((p) => p.name), ['Balcony']);
    expect(controller.status.value.state, isNot(BackupPillState.needsReview));
  });

  testWidgets('"Keep mine" uploads without destroying their copy',
      (tester) async {
    await tester.runAsync(diverge);
    final before = target.revisions.length;

    await openDialog(tester);
    await tester.tap(find.text('Keep mine'));
    await tester.pump();
    await flushEngine(tester);
    await tester.pumpAndSettle();

    expect(target.revisions, hasLength(before + 1));
    expect((await PositionStore.loadAll()).map((p) => p.name),
        ['Pulpit', 'Lectern']);
    expect(controller.status.value.state, BackupPillState.backedUp);
  });

  testWidgets('a failed comparison says so instead of showing no differences',
      (tester) async {
    await tester.runAsync(diverge);
    target.failNextWith(AppFault.backup(
        BackupFailureKind.offline, 'Could not reach the backup.',
        operation: 'history', targetIdentity: 'mock:test'));

    await openDialog(tester);

    expect(
        find.textContaining('Could not download their copy'), findsOneWidget);
  });
}
