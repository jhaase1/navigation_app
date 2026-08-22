import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_log.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBackupTarget target;
  late BackupService service;
  late BackupController controller;
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 8, 16, 9, 0);
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
      log: BackupLog(now: () => clock),
      now: () => clock,
    );
  });

  tearDown(() => controller.dispose());

  AppFault offline(String operation) => AppFault.backup(
      BackupFailureKind.offline, 'Could not reach the backup.',
      operation: operation, targetIdentity: 'mock:test');

  group('facts', () {
    test('a pointer from another target is not this target\'s head', () async {
      // Account or folder changed. The old pointer is still in prefs and the
      // engine ignores it; the controller must too, or it paints green over
      // an empty target.
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await BackupPointer.save(
        revisionId: 'rev-from-elsewhere',
        recordedHash: 'whatever',
        targetIdentity: 'drive:some-other-folder',
      );

      await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

      expect(controller.status.value.hasDurableHead, isFalse);
      expect(controller.status.value.state, BackupPillState.notBackedUp);
    });

    test('no durable head means no "last backed up" age', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          BackupLog.lastSuccessKey, clock.toUtc().toIso8601String());

      await controller.handleEvent(const PullResult(PullOutcome.targetEmptied));

      expect(controller.status.value.lastSuccessAt, isNull,
          reason: 'a stale age would date a configuration by a backup it has '
              'no claim to');
    });
  });
  group('the fold', () {
    test('a pull success does NOT clear a failed push', () async {
      await controller.handleEvent(offline('push'));
      expect(controller.status.value.state, BackupPillState.failing);

      await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

      expect(controller.status.value.state, BackupPillState.failing,
          reason: 'the edits still exist nowhere but this machine');
      expect(controller.status.value.activeCondition!.operation, 'push');
    });

    test("a push success clears the push's own failure", () async {
      await controller.handleEvent(offline('push'));
      await controller.handleEvent(const PushResult(PushOutcome.uploaded));
      expect(controller.status.value.activeCondition, isNull);
    });

    test('a completed pull clears its transport failure even when the answer '
        'is a conflict', () async {
      // Otherwise: push conflicts, a pull fails offline, the network comes
      // back, and every later pull returns conflict — so the stale offline
      // fault never clears, outranks the question, and the popover offers
      // "Retry now" instead of "Review". The resolution UI becomes
      // permanently unreachable.
      await controller.handleEvent(offline('pull'));
      expect(controller.status.value.state, BackupPillState.failing);

      await controller.handleEvent(const PullResult(PullOutcome.conflict));

      expect(controller.status.value.state, BackupPillState.needsReview);
    });

    test('a hard failure raised after a question outranks it', () async {
      await controller.handleEvent(const PullResult(PullOutcome.conflict));
      expect(controller.status.value.state, BackupPillState.needsReview);

      await controller.handleEvent(offline('push'));
      expect(controller.status.value.state, BackupPillState.failing);
    });

    test('a question raised after a hard failure does NOT outrank it',
        () async {
      // The discriminating direction, and the only one that separates
      // Global Constraint 4 from "latest event wins". Its neighbours above
      // both expect whatever arrived last, so a naive most-recent-wins
      // implementation passes them and fails here.
      //
      // The push failure is still unresolved: the pull completing says
      // nothing about whether the upload works. Amber here would tell the
      // operator to review a divergence while their edits are stranded.
      await controller.handleEvent(offline('push'));
      expect(controller.status.value.state, BackupPillState.failing);

      await controller.handleEvent(const PullResult(PullOutcome.conflict));

      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.activeCondition!.operation, 'push');
    });

    test('a pull that applies remote content clears a divergence', () async {
      await controller.handleEvent(const PullResult(PullOutcome.conflict));
      await controller.handleEvent(const PullResult(PullOutcome.applied));
      expect(controller.status.value.state, isNot(BackupPillState.needsReview));
    });

    test('nothingToDo does NOT clear a fork warning', () async {
      // We uploaded second, so our revision IS latest and the next pull says
      // nothingToDo. The sibling is still in the store. Clearing here would
      // leave the other machine as the only one that knows.
      await controller.handleEvent(const PushResult(PushOutcome.forked));
      expect(controller.status.value.state, BackupPillState.needsReview);

      await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

      expect(controller.status.value.state, BackupPillState.needsReview);
    });

    test('first-run adoption is its own question, not a conflict', () async {
      await controller.handleEvent(
          const PullResult(PullOutcome.needsAdoptionChoice));
      expect(controller.status.value.activeCondition!.kind, 'adoptionChoice');
      expect(controller.status.value.label(clock), 'Choose a copy');
    });

    test('an emptied target raises targetMissing, never silence', () async {
      await controller.handleEvent(const PullResult(PullOutcome.targetEmptied));
      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.label(clock), 'Backup missing');
    });

    test('a fold that throws goes red, it does not go quiet', () async {
      // One corrupt `preset_names_*` key is enough to make
      // `ConfigBundle.fromStores()` throw. Swallowing that leaves the pill
      // showing whatever it last computed, forever.
      SharedPreferences.setMockInitialValues({
        'preset_names_10.0.1.10': 'not json',
      });

      controller.handleEventUnserialized(const PullResult(PullOutcome.applied));
      await Future<void>.delayed(Duration.zero);

      expect(controller.status.value.state, BackupPillState.failing);
      // Not `.first`: _onPull(applied) records its 'restored' success row before
      // _markConfirmedStored() throws, both rows carry the same frozen clock, and
      // sorting by lastSeen therefore leaves 'restored' ahead. What this test
      // exists to prove is that the failure is RECORDED, not that it sorts first.
      expect(
        controller.log.entries.value.map((e) => e.kind),
        contains('unknown'),
      );
    });

    test('a retry storm collapses in the log but stays on the pill', () async {
      for (var i = 0; i < 20; i++) {
        clock = clock.add(const Duration(seconds: 30));
        await controller.handleEvent(offline('push'));
      }
      expect(controller.log.entries.value, hasLength(1));
      expect(controller.log.entries.value.single.count, 20);
      expect(controller.status.value.state, BackupPillState.failing);
    });
  });

  group('end to end, through the real scheduler', () {
    test('an edit is backed up and the pill goes green', () async {
      await controller.start();
      expect(controller.status.value.state, BackupPillState.notBackedUp);

      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await controller.retryNow();
      // The scheduler emits onto a stream and the listener enqueues onto the
      // serialized fold, so the status refresh lands a microtask after
      // retryNow() returns. The sibling test below already drains; these two
      // did not, because Round 3 serialized the fold and never propagated the
      // change to its own tests.
      await Future<void>.delayed(Duration.zero);

      expect(target.revisions, hasLength(1));
      expect(controller.status.value.state, BackupPillState.backedUp);
      expect(controller.status.value.label(clock), 'Backed up just now');
    });

    test('a slow first event cannot repaint the pill after a later success',
        () async {
      // The serialization test. With an unawaited fold, the pull from
      // start() could finish its fact refresh AFTER the push below and write
      // its empty pointer over a green pill.
      target.delayNextBy(const Duration(milliseconds: 40));
      final starting = controller.start();

      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await starting;
      await controller.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.status.value.state, BackupPillState.backedUp,
          reason: 'a stale refresh must not outlive the operation it describes');
    });

    test('a failing target paints the pill red through the subscription',
        () async {
      await controller.start();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      target.failNextWith(AppFault.backup(
          BackupFailureKind.authExpired, 'Sign in again.',
          operation: 'pull', targetIdentity: 'mock:test'));

      await controller.retryNow();

      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.label(clock), 'Sign-in expired');
    });

    test('an edit that is not yet pushed reads amber with a count', () async {
      await controller.start();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await controller.retryNow();
      await PositionStore.saveAll([
        Position(id: 'p1', name: 'Pulpit'),
        Position(id: 'p2', name: 'Lectern'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.status.value.state, BackupPillState.pending);
      expect(controller.status.value.label(clock), '1 change pending');
    });

    test('switching operator does not turn the pill amber', () async {
      await controller.start();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await controller.retryNow();
      await Future<void>.delayed(Duration.zero);
      expect(controller.status.value.state, BackupPillState.backedUp);

      await OperatorStore.saveActiveId('someone-else');
      await Future<void>.delayed(Duration.zero);

      expect(controller.status.value.state, BackupPillState.backedUp,
          reason: 'active operator is not bundle content');
    });
  });

  test('a disabled controller never contacts anything and reads grey',
      () async {
    final disabled = BackupController.disabled(now: () => clock);
    await disabled.start();
    expect(disabled.status.value.state, BackupPillState.notBackedUp);
    expect(disabled.canRetry, isFalse);
    await disabled.dispose();
  });
}
