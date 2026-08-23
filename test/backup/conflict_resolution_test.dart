import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_revision.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Refuses exactly the deferral key, the way
/// `test/backup/backup_pointer_test.dart` refuses the pointer's.
class _RefuseDeferralWriteStore extends InMemorySharedPreferencesStore {
  _RefuseDeferralWriteStore() : super.withData(const {});

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${BackupController.suppressedKey}') return false;
    return super.setValue(valueType, key, value);
  }
}

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

  const emptyBundle = '{"schemaVersion":1,"positions":[],"people":[],'
      '"services":[],"heightRanges":[],"presetNames":{},"visibilities":{}}';

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

  /// Two linear revisions, returning the older one — the restore target.
  Future<BackupRevision> twoRevisions() async {
    await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
    await service.push();
    final tuesday = (await service.history()).first;
    await PositionStore.saveAll([
      Position(id: 'p1', name: 'Pulpit'),
      Position(id: 'p2', name: 'Lectern'),
    ]);
    await service.push();
    return tuesday;
  }

  test('"Decide later" is remembered but does not turn the pill green',
      () async {
    await diverge();
    await controller.deferConflict();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackupController.suppressedKey), isNotNull);
    expect(controller.deferralApplies, isTrue);
    expect(controller.status.value.state, BackupPillState.needsReview);
  });

  test('a deferral does not carry over to a newer revision', () async {
    await diverge();
    await controller.deferConflict();

    // The other machine saves again. This is a different question.
    await target.put(emptyBundle,
        contentHash: 'newer-still',
        parentRevisionId: null,
        deviceLabel: "Daniel's iPad");
    await controller.handleEvent(await service.push());

    expect(controller.deferralApplies, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackupController.suppressedKey), isNull);
  });

  test('a deferral survives a relaunch', () async {
    // `start()` reads it back; nothing proved that until now, and the whole
    // point of persisting it is the machine that gets closed for the week.
    await diverge();
    await controller.deferConflict();
    final deferred = controller.deferredRevisionId;
    expect(deferred, isNotNull);

    final relaunched = BackupController.forService(
      service,
      scheduler: BackupScheduler(
        service: service,
        debounce: const Duration(milliseconds: 1),
        sweepInterval: const Duration(days: 1),
        sleep: (_) async {},
      ),
    );
    await relaunched.start();

    expect(relaunched.deferredRevisionId, deferred);
    await relaunched.dispose();
  });

  test('a head that moved again re-points the question and drops the deferral',
      () async {
    // ResolutionOutcome.remoteMovedAgain was handled in `_resolve` and
    // exercised nowhere. The operator is now being asked about a revision
    // they have never seen, so their earlier "decide later" cannot stand.
    await diverge();
    await controller.deferConflict();
    final deferredAbout = controller.conflictRevision!.id;

    // A third machine writes while the dialog is open.
    await target.put(emptyBundle,
        contentHash: 'newest',
        parentRevisionId: null,
        deviceLabel: 'A third machine');

    final outcome = await controller.resolveKeepMine();

    expect(outcome, ResolutionOutcome.remoteMovedAgain);
    expect(controller.conflictRevision!.id, isNot(deferredAbout));
    expect(controller.deferralApplies, isFalse);
    expect(controller.status.value.state, BackupPillState.needsReview);
  });

  test('a refused write leaves the deferral off BOTH memory and disk',
      () async {
    // Memory and disk must never disagree: a decision that looks recorded and
    // is not comes back as the same question after a restart, and the operator
    // has no way to tell why. The store double below is the pattern
    // `test/backup/backup_pointer_test.dart:6-19` already uses.
    await diverge();
    SharedPreferencesStorePlatform.instance = _RefuseDeferralWriteStore();

    await controller.deferConflict();

    expect(controller.deferredRevisionId, isNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString(BackupController.suppressedKey),
        isNull);
    expect(controller.log.entries.value.first.kind, 'storageWriteFailed');
  });

  test('a resolve that fails once and then succeeds does not stay red',
      () async {
    await diverge();
    target.failNextWith(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'resolve', targetIdentity: 'mock:test'));

    await expectLater(controller.resolveKeepMine(), throwsA(isA<AppFault>()));
    expect(controller.status.value.state, BackupPillState.failing);

    final outcome = await controller.resolveKeepMine();

    expect(outcome, ResolutionOutcome.resolved);
    expect(controller.status.value.activeCondition, isNull,
        reason: 'the failure it is about has been superseded by success');
    expect(controller.status.value.state, BackupPillState.backedUp);
  });

  test('an abort after append restore is visible', () async {
    final tuesday = await twoRevisions();
    target.failNextPutWith(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'resolve', targetIdentity: 'mock:test'));
    await expectLater(controller.restore(tuesday), throwsA(isA<AppFault>()));
    expect(controller.status.value.state, BackupPillState.failing);

    target.beforeNextFetch(() => PositionStore.saveAll([
          Position(id: 'p1', name: 'Pulpit'),
          Position(id: 'p2', name: 'Lectern'),
          Position(id: 'p3', name: 'X'),
        ]));
    final outcome = await controller.restore(tuesday);

    expect(outcome, ResolutionOutcome.localChangedDuringResolve);
    expect((await target.latest())!.id, controller.conflictRevision!.id,
        reason: 'the restore is live at the target; the question names it');
    expect(controller.status.value.state, BackupPillState.needsReview,
        reason: 'a prior resolve fault must not outrank the abort question');
    expect(
      controller.status.value.activeCondition!.message,
      'The backup already went back to that version. Other devices will '
      'follow it. This machine still has your newer edits.',
    );
  });

  test('a restore that fails once and then succeeds does not stay red',
      () async {
    final tuesday = await twoRevisions();
    target.failNextPutWith(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'resolve', targetIdentity: 'mock:test'));

    await expectLater(controller.restore(tuesday), throwsA(isA<AppFault>()));
    expect(controller.status.value.state, BackupPillState.failing);

    final outcome = await controller.restore(tuesday);

    expect(outcome, ResolutionOutcome.resolved);
    expect(controller.status.value.activeCondition, isNull,
        reason: 'the failure it is about has been superseded by success');
    expect(controller.status.value.state, BackupPillState.backedUp);
  });

  test('a restore that forks re-asks rather than going quiet', () async {
    final tuesday = await twoRevisions();
    final head = (await target.latest())!;
    target.concurrentWriterBeforePut(
      body: emptyBundle,
      parentRevisionId: head.id,
      deviceLabel: 'A third machine',
    );

    final outcome = await controller.restore(tuesday);

    expect(outcome, ResolutionOutcome.forkedAgain);
    expect(controller.status.value.state, BackupPillState.needsReview);
    expect(
      controller.status.value.activeCondition!.message,
      'Another machine saved at the same moment. Both copies were kept.',
    );
    expect(controller.conflictRevision, isNotNull);
  });
}
