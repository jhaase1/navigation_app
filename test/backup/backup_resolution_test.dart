import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_pointer.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBackupTarget target;
  late BackupService service;

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
  });

  Future<void> setPositions(List<String> names) => PositionStore.saveAll([
        for (final n in names) Position(id: n.toLowerCase(), name: n),
      ]);

  const emptyBundle = '{"schemaVersion":1,"positions":[],"people":[],'
      '"services":[],"heightRanges":[],"presetNames":{},"visibilities":{}}';

  group('adoptRemote', () {
    test('replaces local state and lands provenanced', () async {
      await setPositions(['Pulpit']);
      await service.push();
      final theirs = (await service.history()).single;

      await setPositions(['Lectern', 'Choir']);
      final result = await service.adoptRemote(theirs);

      expect(result.outcome, ResolutionOutcome.resolved);
      expect((await PositionStore.loadAll()).map((p) => p.name), ['Pulpit']);
      expect((await BackupPointer.load()).revisionId, theirs.id);
      expect((await service.pull()).outcome, PullOutcome.nothingToDo);
    });

    test('keeps a recoverable copy of what it replaced', () async {
      // The spec requires snapshotting local before adopting. Without it the
      // operator's unpushed hour exists nowhere afterwards.
      await setPositions(['Pulpit']);
      await service.push();
      final theirs = (await service.history()).single;
      await setPositions(['Lectern', 'Choir']);

      await service.adoptRemote(theirs);

      final saved = await BackupService.replacedSnapshot();
      expect(saved, isNotNull);
      final positions =
          (saved!['bundle'] as Map<String, dynamic>)['positions'] as List;
      expect(positions.map((p) => p['name']), ['Lectern', 'Choir']);
    });

    test('aborts if an edit lands while the body is in flight', () async {
      await setPositions(['Pulpit']);
      await service.push();
      final theirs = (await service.history()).single;
      await setPositions(['Lectern']);

      target.beforeNextFetch(() => setPositions(['Lectern', 'Balcony']));
      final result = await service.adoptRemote(theirs);

      expect(result.outcome, ResolutionOutcome.localChangedDuringResolve);
      expect((await PositionStore.loadAll()).map((p) => p.name),
          ['Lectern', 'Balcony'],
          reason: 'the operator answered about state that has since changed');
    });
  });

  group('keepLocalAsNewRevision', () {
    test('appends without destroying the remote copy', () async {
      await setPositions(['Pulpit']);
      await service.push();
      final base = (await service.history()).single;

      await target.put(emptyBundle,
          contentHash: 'theirs',
          parentRevisionId: base.id,
          deviceLabel: "Daniel's iPad");
      final theirs = (await target.latest())!;

      await setPositions(['Pulpit', 'Lectern']);
      final result = await service.keepLocalAsNewRevision(theirs);

      expect(result.outcome, ResolutionOutcome.resolved);
      expect(result.revision!.parentRevisionId, theirs.id);
      expect(target.revisions, hasLength(3),
          reason: 'append-only: nothing was overwritten');
      expect((await service.pull()).outcome, PullOutcome.nothingToDo);
    });

    test('refuses when the head moved again', () async {
      await setPositions(['Pulpit']);
      await service.push();
      final stale = (await service.history()).single;
      await target.put(emptyBundle,
          contentHash: 'newer',
          parentRevisionId: stale.id,
          deviceLabel: 'Someone else');

      final result = await service.keepLocalAsNewRevision(stale);

      expect(result.outcome, ResolutionOutcome.remoteMovedAgain);
      expect(target.revisions, hasLength(2), reason: 'nothing was uploaded');
    });

    test('reports a fork when another machine resolved at the same moment',
        () async {
      // Both machines pass the latest() check, both put. Append-only keeps
      // both bodies; saying nothing about it is the failure.
      await setPositions(['Pulpit']);
      await service.push();
      final base = (await service.history()).single;
      await target.put(emptyBundle,
          contentHash: 'theirs',
          parentRevisionId: base.id,
          deviceLabel: "Daniel's iPad");
      final theirs = (await target.latest())!;

      await setPositions(['Pulpit', 'Lectern']);
      target.concurrentWriterBeforePut(
        body: emptyBundle,
        parentRevisionId: theirs.id,
        deviceLabel: 'A third machine',
      );

      final result = await service.keepLocalAsNewRevision(theirs);

      expect(result.outcome, ResolutionOutcome.forkedAgain);
      expect(result.siblings, isNotEmpty);
    });
  });

  group('restoreRevision', () {
    test('leaves the machine clean, not conflicted', () async {
      await setPositions(['Pulpit']);
      await service.push();
      final tuesday = (await service.history()).first;

      await setPositions(['Pulpit', 'Lectern', 'Choir']);
      await service.push();
      expect(target.revisions, hasLength(2));

      final result = await service.restoreRevision(tuesday);

      expect(result.outcome, ResolutionOutcome.resolved);
      expect((await PositionStore.loadAll()).map((p) => p.name), ['Pulpit']);
      expect(target.revisions, hasLength(3),
          reason: 'the restore is appended; the newer revision still exists');
      expect((await target.latest())!.id, result.revision!.id);
      expect((await service.pull()).outcome, PullOutcome.nothingToDo);
      expect((await service.push()).outcome, PushOutcome.noOp);
    });

    test('a failed upload leaves local UNTOUCHED, never half-restored',
        () async {
      // The blocker both reviewers found in the first draft: apply-then-put
      // moved the pointer onto the ancestor, so a failed put left the next
      // pull matching branch 6 and silently re-applying the revision the
      // operator had just undone.
      //
      // The failure has to land on the UPLOAD, with the body already in hand.
      // `failNextWith` fires on the body fetch instead, which both orderings
      // survive identically — a test that could not tell the fixed code from
      // the bug it exists to prevent.
      await setPositions(['Pulpit']);
      await service.push();
      final tuesday = (await service.history()).first;
      await setPositions(['Pulpit', 'Lectern', 'Choir']);
      await service.push();
      final headBefore = (await target.latest())!.id;

      target.failNextPutWith(AppFault.backup(
          BackupFailureKind.offline, 'Could not reach the backup.',
          operation: 'resolve', targetIdentity: 'mock:test'));

      await expectLater(
          service.restoreRevision(tuesday), throwsA(isA<AppFault>()));

      expect(target.revisions, hasLength(2), reason: 'nothing was uploaded');
      expect((await PositionStore.loadAll()).map((p) => p.name),
          ['Pulpit', 'Lectern', 'Choir'],
          reason: 'nothing was applied, so nothing can be silently reverted');
      expect((await BackupPointer.load()).revisionId, headBefore);
      expect((await service.pull()).outcome, PullOutcome.nothingToDo);
    });

    test('an edit landing mid-restore aborts it rather than racing it',
        () async {
      await setPositions(['Pulpit']);
      await service.push();
      final tuesday = (await service.history()).first;
      await setPositions(['Pulpit', 'Lectern']);
      await service.push();

      // The operator saves something while the body is downloading.
      target.beforeNextFetch(() => setPositions(['Pulpit', 'Lectern', 'X']));
      final result = await service.restoreRevision(tuesday);

      expect(result.outcome, ResolutionOutcome.localChangedDuringResolve);
      expect((await PositionStore.loadAll()).map((p) => p.name),
          ['Pulpit', 'Lectern', 'X'],
          reason: 'their edit stands; the restore did not overwrite it');
    });

    test('an upload that lands without its apply is completed by the next pull',
        () async {
      // The process-kill window: `_appendRevision` succeeded and
      // `_applyRevision` never ran. Reconstructed by hand, because killing the
      // isolate between two awaits is not something the mock can stage — and
      // an assertion that never runs a pull cannot claim anything about what
      // the next pull does.
      await setPositions(['Pulpit']);
      await service.push();
      final tuesday = (await service.history()).first;
      await setPositions(['Pulpit', 'Lectern']);
      await service.push();

      // Exactly what restoreRevision does before it applies.
      final body = await service.fetchBody(tuesday);
      await target.put(
        body,
        contentHash: 'restored',
        parentRevisionId: (await target.latest())!.id,
        deviceLabel: 'Mac mini',
      );

      final result = await service.pull();

      expect(result.outcome, PullOutcome.applied,
          reason: 'the appended restore is a linear descendant of our pointer');
      expect((await PositionStore.loadAll()).map((p) => p.name), ['Pulpit'],
          reason: 'the restore completes rather than being reversed');
      expect((await BackupPointer.load()).revisionId,
          (await target.latest())!.id);
      expect((await service.push()).outcome, PushOutcome.noOp,
          reason: 'stores, pointer and head all agree');
    });

    test('restoring the current head rebases rather than duplicating it',
        () async {
      await setPositions(['Pulpit']);
      await service.push();
      final head = (await service.history()).single;

      final result = await service.restoreRevision(head);

      expect(result.outcome, ResolutionOutcome.resolved);
      expect(target.revisions, hasLength(1));
      expect((await BackupPointer.load()).revisionId, head.id);
    });
  });
}
