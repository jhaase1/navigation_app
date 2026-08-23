import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/widgets/backup/revision_history_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBackupTarget target;
  late BackupService service;
  late BackupController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  /// `BackupService._single` chains through a Completer. Under the widget
  /// test FakeAsync zone that chain does not resume; `runAsync` lets the
  /// real event loop finish the in-flight fetch/restore.
  ///
  /// A join on another `service.history()` deadlocks: the dialog's
  /// `_single` is queued on FakeAsync, and awaiting a second `_single`
  /// from `runAsync` waits forever for it. The 50ms flush is the same
  /// pattern Task 15 used; if it is too short the Restore button is
  /// missing and this test goes red rather than passing vacuously.
  Future<void> flushEngine(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('picking an older revision and confirming restores it',
      (tester) async {
    await tester.runAsync(() async {
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await service.push();
      await PositionStore.saveAll([
        Position(id: 'p1', name: 'Pulpit'),
        Position(id: 'p2', name: 'Lectern'),
      ]);
      await service.push();
    });

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showRevisionHistory(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await flushEngine(tester);

    // Newest first, so the older revision is the second row.
    await tester.tap(find.text('Restore'));
    await tester.pump();
    await flushEngine(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pump();
    await flushEngine(tester);
    await tester.pumpAndSettle();

    expect((await PositionStore.loadAll()).map((p) => p.name), ['Pulpit']);
    expect(target.revisions, hasLength(3),
        reason: 'the restore is appended, the newer revision survives');
    expect(controller.status.value.state, BackupPillState.backedUp);
  });
}
