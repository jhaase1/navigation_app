import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/widgets/backup/backup_status_pill.dart';
import 'package:navigation_app/widgets/multi_device_control_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the pill is in the AppBar and the lifecycle reaches the engine',
      (tester) async {
    final target = MockBackupTarget();
    final service = BackupService(
      target: target,
      targetIdentity: 'mock:test',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    );
    final scheduler = BackupScheduler(
      service: service,
      debounce: const Duration(milliseconds: 1),
      sweepInterval: const Duration(days: 1),
      sleep: (_) async {},
    );
    final controller =
        BackupController.forService(service, scheduler: scheduler);

    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(backupController: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BackupStatusPill), findsOneWidget);
    expect(find.text('Not backed up'), findsOneWidget);

    final pullsAfterStart = scheduler.pullCount;

    // The real signal an operator produces by leaving and coming back.
    // Going through `paused` first is not decoration: `SchedulerBinding`
    // early-returns on a repeated state (`scheduler/binding.dart:414-417`),
    // and a test binding starts out `resumed`.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(scheduler.pullCount, greaterThan(pullsAfterStart),
        reason: 'foregrounding must pull; a dead credential surfaces there');

    // Stream cancellation must leave the widget-test fake clock before the
    // page starts its own unawaited controller disposal.
    await tester.runAsync(scheduler.stop);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('dispose during start cannot install subscriptions afterwards',
      () async {
    final stageEntered = Completer<void>();
    final releaseStage = Completer<void>();
    final target = MockBackupTarget();
    final service = BackupService(
      target: target,
      targetIdentity: 'mock:test',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    );
    final scheduler = BackupScheduler(
      service: service,
      sweepInterval: const Duration(days: 1),
    );
    final controller = BackupController.forService(
      service,
      scheduler: scheduler,
      stageScenario: () {
        stageEntered.complete();
        return releaseStage.future;
      },
    );

    final starting = controller.start();
    await stageEntered.future;
    final disposing = controller.dispose();
    releaseStage.complete();
    await Future.wait([starting, disposing]);

    var statusChanges = 0;
    controller.status.addListener(() => statusChanges++);
    await ConfigMutationNotifier.instance.notify();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    try {
      expect(statusChanges, 0,
          reason: 'disposed controllers must not retain mutation listeners');
      expect(scheduler.pullCount, 0,
          reason: 'startup must not reach the scheduler after disposal');
    } finally {
      // Cleans up the intentionally reproduced orphan on the RED run.
      await controller.dispose();
    }
  });
}
