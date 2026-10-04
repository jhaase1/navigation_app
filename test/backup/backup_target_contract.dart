import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/abstract/backup_target_abstract.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';

/// A target under test plus a way to age what it holds.
class ContractHarness {
  final BackupTargetAbstract target;
  final void Function(Duration) advanceClock;
  const ContractHarness(this.target, this.advanceClock);
}

/// The behaviour every [BackupTargetAbstract] must share.
///
/// The engine was proven against `MockBackupTarget` in Phases 1-3. Running
/// the same suite against `DriveBackupTarget` is what makes that proof carry
/// over: any way Drive behaves differently from the mock shows up here, not
/// on a Sunday.
void runBackupTargetContract(
  String name,
  Future<ContractHarness> Function() create,
) {
  group('$name honours the backup target contract', () {
    late ContractHarness h;
    setUp(() async => h = await create());

    Future<void> expectFault(Future<Object?> f, BackupFailureKind kind) =>
        expectLater(
          f,
          throwsA(isA<AppFault>().having((e) => e.kind, 'kind', kind.name)),
        );

    test('an empty store has no latest revision and lists nothing', () async {
      expect(await h.target.latest(), isNull);
      expect(await h.target.list(), isEmpty);
    });

    test('put returns the metadata it stored, with a server checksum',
        () async {
      const body = '{"schemaVersion":1,"é":"accented"}';
      final rev = await h.target.put(body,
          contentHash: 'hash-1', parentRevisionId: null, deviceLabel: 'Mac mini');

      expect(rev.id, isNotEmpty);
      expect(rev.contentHash, 'hash-1');
      expect(rev.parentRevisionId, isNull);
      expect(rev.deviceLabel, 'Mac mini');
      expect(rev.bodyChecksum, bodyChecksumOf(body));
      expect(rev.sizeBytes, utf8.encode(body).length);
    });

    test('latest and list report what put stored, field for field', () async {
      final first = await h.target.put('{"n":1}',
          contentHash: 'h1', parentRevisionId: null, deviceLabel: 'Mac mini');
      final put = await h.target.put('{"n":2}',
          contentHash: 'h2', parentRevisionId: first.id, deviceLabel: 'iPad');

      final latest = (await h.target.latest())!;
      for (final seen in [latest, (await h.target.list()).first]) {
        expect(seen.id, put.id);
        expect(seen.contentHash, 'h2');
        expect(seen.parentRevisionId, first.id);
        expect(seen.deviceLabel, 'iPad');
        expect(seen.bodyChecksum, put.bodyChecksum);
        expect(seen.sizeBytes, put.sizeBytes);
        expect(seen.createdAt, put.createdAt);
      }
    });

    test('put never overwrites: identical bodies become two revisions',
        () async {
      final a = await h.target.put('{"same":true}',
          contentHash: 'h', parentRevisionId: null, deviceLabel: 'Mac mini');
      final b = await h.target.put('{"same":true}',
          contentHash: 'h', parentRevisionId: null, deviceLabel: 'Mac mini');

      expect(a.id, isNot(b.id));
      expect(await h.target.list(), hasLength(2));
    });

    test('list is newest first and honours the limit', () async {
      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        h.advanceClock(const Duration(minutes: 1));
        ids.add((await h.target.put('{"n":$i}',
                contentHash: 'h$i', parentRevisionId: null, deviceLabel: 'm'))
            .id);
      }

      expect((await h.target.list()).map((r) => r.id), ids.reversed);
      expect((await h.target.list(limit: 2)).map((r) => r.id),
          ids.reversed.take(2));
      expect((await h.target.latest())!.id, ids.last);
    });

    test('a negative list limit is refused', () async {
      await expectFault(h.target.list(limit: -1), BackupFailureKind.unknown);
    });

    test('fetch returns the exact bytes that were put', () async {
      const body = '{"positions":[{"id":"p1","name":"Pulpit — left"}]}';
      final rev = await h.target.put(body,
          contentHash: 'h', parentRevisionId: null, deviceLabel: 'm');

      expect(await h.target.fetch(rev), body);
    });

    group('prune', () {
      Future<List<String>> putN(int n, String tag) async {
        final ids = <String>[];
        for (var i = 0; i < n; i++) {
          ids.add((await h.target.put('{"$tag":$i}',
                  contentHash: '$tag$i', parentRevisionId: null, deviceLabel: 'm'))
              .id);
        }
        return ids;
      }

      Future<Set<String>> remaining() async =>
          (await h.target.list(limit: 100)).map((r) => r.id).toSet();

      test('removes only revisions that are both beyond the count and old',
          () async {
        final old = await putN(5, 'old');
        h.advanceClock(const Duration(days: 100));
        final young = await putN(1, 'young');

        await h.target.prune(keepCount: 2, keepFor: const Duration(days: 90));

        // Newest two by count: young[0] and old[4]. Everything else is old
        // AND beyond the count, so it goes.
        expect(await remaining(), {young[0], old[4]});
      });

      test('keeps young revisions even beyond the count', () async {
        final ids = await putN(4, 'r');

        await h.target.prune(keepCount: 1, keepFor: const Duration(days: 90));

        expect(await remaining(), ids.toSet());
      });

      test('keeps old revisions inside the count', () async {
        final ids = await putN(3, 'r');
        h.advanceClock(const Duration(days: 365));

        await h.target.prune(keepCount: 3, keepFor: const Duration(days: 90));

        expect(await remaining(), ids.toSet());
      });

      test('a pruned revision can no longer be fetched', () async {
        final old = await h.target.put('{"old":1}',
            contentHash: 'o', parentRevisionId: null, deviceLabel: 'm');
        h.advanceClock(const Duration(days: 100));
        await putN(1, 'new');

        await h.target.prune(keepCount: 1, keepFor: const Duration(days: 90));

        await expectFault(h.target.fetch(old), BackupFailureKind.targetMissing);
      });

      test('a negative keepCount is refused', () async {
        await expectFault(
            h.target.prune(keepCount: -1, keepFor: Duration.zero),
            BackupFailureKind.unknown);
      });
    });
  });
}
