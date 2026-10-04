import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_log.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> doc(String marker) => {
      'schemaVersion': 1,
      'positions': [
        {'id': marker, 'name': marker}
      ],
      'people': <dynamic>[],
      'services': <dynamic>[],
      'heightRanges': <dynamic>[],
    };

void main() {
  late MockBackupTarget target;
  late BackupService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    target = MockBackupTarget();
    service = BackupService(
      target: target,
      targetIdentity: 'drive:ops@example.com',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => doc('local'),
      localIsPristine: () async => false,
    );
  });

  Future<void> putN(int n) async {
    for (var i = 0; i < n; i++) {
      await target.put('{"n":$i}',
          contentHash: 'h$i', parentRevisionId: null, deviceLabel: 'm');
    }
  }

  Matcher faultWith(String kind, String operation) => throwsA(isA<AppFault>()
      .having((f) => f.kind, 'kind', kind)
      .having((f) => f.operation, 'operation', operation)
      .having((f) => f.targetIdentity, 'targetIdentity', 'drive:ops@example.com'));

  group('the retention policy', () {
    test('keeps the newest 50 once everything is older than 90 days',
        () async {
      await putN(60);
      target.advanceClock(const Duration(days: 91));

      await service.prune();

      expect(target.revisions, hasLength(BackupService.retentionKeepCount));
      expect(BackupService.retentionKeepCount, 50);
    });

    test('keeps everything younger than 90 days, however many', () async {
      await putN(60);
      target.advanceClock(const Duration(days: 89));

      await service.prune();

      expect(target.revisions, hasLength(60));
      expect(BackupService.retentionKeepFor, const Duration(days: 90));
    });
  });

  group('faults from the target carry the engine\'s context', () {
    // A target knows nothing of pull or push. Without this the controller
    // files the fault under "unknown", and no later success ever clears it.
    test('pull', () async {
      target.failNextWith(
          AppFault.backup(BackupFailureKind.offline, 'Could not reach Drive.'));

      await expectLater(service.pull(), faultWith('offline', 'pull'));
    });

    test('push', () async {
      target.failNextWith(
          AppFault.backup(BackupFailureKind.authExpired, 'Sign in again.'));

      await expectLater(service.push(), faultWith('authExpired', 'push'));
    });

    test('prune', () async {
      target.failNextWith(
          AppFault.backup(BackupFailureKind.transientServer, 'Drive 503.'));

      await expectLater(service.prune(), faultWith('transientServer', 'prune'));
    });

    test('an operation the target already named is left alone', () async {
      target.failNextWith(AppFault.backup(BackupFailureKind.offline, 'x',
          operation: 'pull', targetIdentity: 'mock:in-memory'));

      await expectLater(
          service.push(),
          throwsA(isA<AppFault>()
              .having((f) => f.operation, 'operation', 'pull')
              .having((f) => f.targetIdentity, 't', 'mock:in-memory')));
    });
  });

  group('the sweep prunes', () {
    late DateTime now;
    late BackupScheduler scheduler;

    setUp(() {
      now = DateTime.utc(2026, 10, 3, 9);
      scheduler = BackupScheduler(
        service: service,
        sweepInterval: const Duration(days: 365),
        now: () => now,
        sleep: (_) async {},
      );
    });

    tearDown(() => scheduler.stop());

    test('at most once a day', () async {
      await scheduler.sweep();
      await scheduler.sweep();
      expect(scheduler.pruneCount, 1);

      now = now.add(const Duration(hours: 25));
      await scheduler.sweep();
      expect(scheduler.pruneCount, 2);
    });

    test('and a failed prune neither blocks the push nor loops', () async {
      final events = <Object>[];
      final sub = scheduler.events.listen(events.add);
      await ConfigMutationNotifier.instance.notify();
      target.failNextPruneWith(
          AppFault.backup(BackupFailureKind.transientServer, 'Drive 503.'));

      await scheduler.sweep();
      await Future<void>.delayed(Duration.zero);

      expect(target.revisions, hasLength(1), reason: 'the push still landed');
      expect(events.whereType<AppFault>().single.operation, 'prune');
      expect(scheduler.pruneCount, 1, reason: 'no retry loop for prune');
      await sub.cancel();
    });
  });

  test('a successful prune clears a standing prune fault from the pill',
      () async {
    final controller = BackupController.forService(service,
        scheduler: BackupScheduler(service: service),
        log: BackupLog(now: () => DateTime.utc(2026, 10, 3)),
        now: () => DateTime.utc(2026, 10, 3));

    await controller.handleEvent(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive 503.',
        operation: 'prune', targetIdentity: 'drive:ops@example.com'));
    expect(controller.status.value.activeCondition?.operation, 'prune');

    await controller.handleEvent(const PruneResult());

    expect(controller.status.value.activeCondition, isNull);
  });
}
