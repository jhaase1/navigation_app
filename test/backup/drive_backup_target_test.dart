import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/canonical_json.dart';
import 'package:navigation_app/services/backup/drive/drive_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_drive.dart';

const _account = 'ops@example.com';
const _folderMarker = {'navBackup': 'root'};
const _revisionMarker = {'navBackup': 'revision'};

void main() {
  late FakeDrive drive;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    drive = FakeDrive();
  });

  DriveBackupTarget target({String account = _account}) => DriveBackupTarget(
        client: drive.client,
        account: account,
        now: () => drive.clock,
      );

  Future<void> putOne(DriveBackupTarget t, [String body = '{"n":1}']) =>
      t.put(body, contentHash: 'h', parentRevisionId: null, deviceLabel: 'm');

  Matcher fault(BackupFailureKind kind) =>
      throwsA(isA<AppFault>().having((e) => e.kind, 'kind', kind.name));

  group('folder identity', () {
    test('creates one visible, marked folder on first use', () async {
      await putOne(target());

      expect(drive.folders, hasLength(1));
      final folder = drive.folders.single;
      expect(folder.name, DriveBackupTarget.folderName);
      expect(folder.appProperties, _folderMarker);
      expect(drive.childrenOf(folder.id), hasLength(1));
    });

    test('a second target on this machine reuses the folder', () async {
      await putOne(target());
      await putOne(target());

      expect(drive.folders, hasLength(1));
      expect(drive.childrenOf(drive.folders.single.id), hasLength(2));
    });

    test('finds the folder another machine already created', () async {
      final theirs = drive.seed(
          name: DriveBackupTarget.folderName,
          mimeType: FakeDrive.folderMime,
          appProperties: _folderMarker);

      await putOne(target());

      expect(drive.folders, hasLength(1));
      expect(drive.childrenOf(theirs.id), hasLength(1));
    });

    test('ignores a same-named folder without our marker', () async {
      final impostor = drive.seed(
          name: DriveBackupTarget.folderName, mimeType: FakeDrive.folderMime);

      await putOne(target());

      expect(drive.childrenOf(impostor.id), isEmpty);
      expect(drive.folders, hasLength(2));
    });

    group('two marked folders', () {
      // Two first runs racing, or a search that had not caught up with a
      // fresh folder, can leave two. Which one holds the real history is a
      // person's call, so backups pause and say why. Nothing is moved.
      late FakeDriveFile older;
      late FakeDriveFile newer;

      setUp(() {
        older = drive.seed(
            name: DriveBackupTarget.folderName,
            mimeType: FakeDrive.folderMime,
            appProperties: _folderMarker);
        newer = drive.seed(
            name: DriveBackupTarget.folderName,
            mimeType: FakeDrive.folderMime,
            appProperties: _folderMarker);
      });

      test('a fresh install says so instead of reading the empty one',
          () async {
        drive.seed(
            name: 'nav_config_sunday.json',
            parents: [newer.id],
            appProperties: {..._revisionMarker, 'contentHash': 'h'},
            body: '{"schemaVersion":1}');

        await expectLater(
            target().latest(), fault(BackupFailureKind.targetAmbiguous));

        // Someone tidies Drive by hand; the next attempt finds the backup.
        older.trashed = true;
        expect(await target().latest(), isNotNull);
      });

      test('a remembered folder does not hide the other one', () async {
        SharedPreferences.setMockInitialValues(
            {DriveBackupTarget.folderPrefsKey: '$_account|${newer.id}'});

        await expectLater(
            putOne(target()), fault(BackupFailureKind.targetAmbiguous));

        expect(drive.childrenOf(older.id), isEmpty);
        expect(drive.childrenOf(newer.id), isEmpty);
        expect(drive.folders.where((f) => !f.trashed), hasLength(2),
            reason: 'nothing in Drive is moved or deleted automatically');
      });
    });

    test('a folder search has not caught up with is still this one',
        () async {
      final t = target();
      await putOne(t);
      drive.notYetSearchable.add(drive.folders.single.id);

      await putOne(target());

      expect(drive.folders, hasLength(1),
          reason: 'search lag must never make a second folder');
      expect(drive.childrenOf(drive.folders.single.id), hasLength(2));
    });

    test('a trashed folder is replaced and reads as empty', () async {
      final t = target();
      await putOne(t);
      drive.folders.single.trashed = true;

      expect(await t.latest(), isNull);
      await putOne(t);

      final live = drive.folders.where((f) => !f.trashed).toList();
      expect(live, hasLength(1));
      expect(drive.childrenOf(live.single.id), hasLength(1));
    });

    test('a deleted folder is replaced and reads as empty', () async {
      final t = target();
      await putOne(t);
      drive.files.remove(drive.folders.single.id);

      expect(await t.latest(), isNull);
    });

    test('a folder remembered for another account is not reused', () async {
      await putOne(target(account: 'someone@else.com'));
      final first = drive.folders.single;
      // Same Drive, different signed-in account: drive.file would not even
      // see the first folder, so the remembered id must not be trusted.
      first.appProperties.clear();

      await putOne(target());

      expect(drive.folders, hasLength(2));
    });
  });

  group('revisions', () {
    test('writes its metadata into appProperties', () async {
      final t = target();
      final parent = await t.put('{"n":1}',
          contentHash: 'h1', parentRevisionId: null, deviceLabel: 'Mac mini');
      await t.put('{"n":2}',
          contentHash: 'h2', parentRevisionId: parent.id, deviceLabel: 'iPad');

      final files = drive.childrenOf(drive.folders.single.id)
        ..sort((a, b) => a.createdTime.compareTo(b.createdTime));
      expect(files[0].appProperties, {
        ..._revisionMarker,
        'contentHash': 'h1',
        'deviceLabel': 'Mac mini',
      });
      expect(files[1].appProperties['parentRevisionId'], parent.id);
      expect(files[1].mimeType, 'application/json');
    });

    test('a long device label is shortened to fit Drive, not rejected',
        () async {
      final label = 'Sanctuary booth Mac mini — ${'é' * 80}';

      final rev = await target().put('{}',
          contentHash: 'h', parentRevisionId: null, deviceLabel: label);

      final stored = drive.childrenOf(drive.folders.single.id).single;
      final value = stored.appProperties['deviceLabel']!;
      expect(utf8.encode('deviceLabel').length + utf8.encode(value).length,
          lessThanOrEqualTo(FakeDrive.appPropertyLimit));
      expect(label.startsWith(value), isTrue);
      expect(rev.deviceLabel, value);
    });

    test('only marked, untrashed files in the folder count as revisions',
        () async {
      final t = target();
      await putOne(t);
      final folder = drive.folders.single;
      drive.seed(name: 'notes.txt', parents: [folder.id], body: 'hi');
      drive.seed(
          name: 'old.json',
          parents: [folder.id],
          appProperties: {..._revisionMarker, 'contentHash': 'x'},
          trashed: true);

      expect(await t.list(), hasLength(1));
    });

    test('equal server times are ordered by id, never by file name',
        () async {
      final t = target();
      drive.freezeClock = true;
      final a = await t.put('{"a":1}',
          contentHash: 'a', parentRevisionId: null, deviceLabel: 'm');
      final b = await t.put('{"b":1}',
          contentHash: 'b', parentRevisionId: null, deviceLabel: 'm');
      // A machine with a wrong clock would write a name that sorts last.
      drive.files[a.id]!.name = 'nav_config_2099-12-31.json';

      expect((await t.latest())!.id, b.id);
      expect((await t.list()).map((r) => r.id), [b.id, a.id]);
    });

    test('list pages through Drive to reach the limit', () async {
      final t = target();
      for (var i = 0; i < 120; i++) {
        await putOne(t, '{"n":$i}');
      }

      final all = await t.list(limit: 120);

      expect(all, hasLength(120));
      expect(all.map((r) => r.id).toSet(), hasLength(120));
      expect(
          drive.requests.where((r) =>
              r.method == 'GET' && r.url.queryParameters['pageToken'] != null),
          isNotEmpty);
    });

    test('the checksum is the server\'s, so a hand edit shows up', () async {
      final t = target();
      final rev = await t.put('{"n":1}',
          contentHash: 'h', parentRevisionId: null, deviceLabel: 'm');
      // Someone edits the file in the Drive web UI. appProperties keep the
      // stale client hash; the server checksum follows the bytes.
      drive.files[rev.id]!.bytes = utf8.encode('{"n":"edited"}');

      final seen = (await t.latest())!;

      expect(seen.contentHash, 'h');
      expect(seen.bodyChecksum, bodyChecksumOf('{"n":"edited"}'));
      expect(await t.fetch(seen), '{"n":"edited"}');
    });

    test('a body that changed after it was listed is not handed over',
        () async {
      final t = target();
      await putOne(t);
      final listed = (await t.latest())!;
      drive.files[listed.id]!.bytes = utf8.encode('{"changed":true}');

      await expectLater(t.fetch(listed), fault(BackupFailureKind.transientServer));
    });

    test('a download that does not match the server checksum is malformed',
        () async {
      final rev = await target().put('{"n":1}',
          contentHash: 'h', parentRevisionId: null, deviceLabel: 'm');
      // Server metadata stays honest; only the bytes in transit are mangled.
      final corrupted = DriveBackupTarget(
          client: _CorruptingDrive(drive, rev.id),
          account: _account,
          now: () => drive.clock);

      await expectLater(
          corrupted.fetch(rev), fault(BackupFailureKind.malformedRemote));
    });

    test('prune moves revisions to the trash rather than deleting them',
        () async {
      final t = target();
      await putOne(t);
      drive.advanceClock(const Duration(days: 100));
      await putOne(t);

      await t.prune(keepCount: 1, keepFor: const Duration(days: 90));

      final all = drive.childrenOf(drive.folders.single.id, includeTrashed: true);
      expect(all, hasLength(2));
      expect(all.where((f) => f.trashed), hasLength(1));
      expect(drive.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });
  });

  group('failures become AppFaults at the boundary', () {
    final cases = <(int, String?, BackupFailureKind)>[
      (401, 'authError', BackupFailureKind.authExpired),
      (403, 'rateLimitExceeded', BackupFailureKind.rateLimited),
      (403, 'userRateLimitExceeded', BackupFailureKind.rateLimited),
      (429, 'rateLimitExceeded', BackupFailureKind.rateLimited),
      (403, 'storageQuotaExceeded', BackupFailureKind.storageFull),
      (403, 'insufficientPermissions', BackupFailureKind.permissionDenied),
      (404, 'notFound', BackupFailureKind.targetMissing),
      (500, 'backendError', BackupFailureKind.transientServer),
      (503, 'backendError', BackupFailureKind.transientServer),
      (400, 'invalid', BackupFailureKind.unknown),
    ];
    // Aimed at the revisions listing: a 404 on the folder check is not a
    // failure at all — it means "folder gone, replace it" (see above).
    bool revisionListing(http.Request r) =>
        r.method == 'GET' &&
        (r.url.queryParameters['q'] ?? '').contains('in parents');

    for (final (status, reason, kind) in cases) {
      test('HTTP $status $reason is ${kind.name}', () async {
        final t = target();
        await putOne(t);
        drive.failNext(status, reason: reason, where: revisionListing);

        await expectLater(t.list(), fault(kind));
      });
    }

    final transport = <(String, Object)>[
      ('SocketException', const SocketException('no route to host')),
      ('ClientException', http.ClientException('connection closed')),
      ('TimeoutException', TimeoutException('slow')),
      ('HandshakeException', const HandshakeException('tls')),
    ];
    for (final (name, error) in transport) {
      test('$name is offline', () async {
        final t = target();
        drive.throwNext(error);

        await expectLater(t.latest(), fault(BackupFailureKind.offline));
      });
    }

    test('every public method reports faults, not raw exceptions', () async {
      final t = target();
      final rev = await t.put('{}',
          contentHash: 'h', parentRevisionId: null, deviceLabel: 'm');
      final calls = <Future<Object?> Function()>[
        () => t.latest(),
        () => t.list(),
        () => t.fetch(rev),
        () => t.put('{}', contentHash: 'h', parentRevisionId: null, deviceLabel: 'm'),
        () => t.prune(keepCount: 0, keepFor: Duration.zero),
      ];
      for (final call in calls) {
        drive.throwNext(const SocketException('down'));
        await expectLater(call(), fault(BackupFailureKind.offline));
      }
    });
  });
}

/// Passes requests through to [drive] but corrupts one file's media download,
/// the way a truncated or mangled transfer would.
class _CorruptingDrive extends http.BaseClient {
  final FakeDrive drive;
  final String fileId;
  _CorruptingDrive(this.drive, this.fileId);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await drive.client.send(request);
    if (request.url.path.endsWith('/$fileId') &&
        request.url.queryParameters['alt'] == 'media') {
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"n":"corrupt"}')), 200,
          headers: response.headers);
    }
    return response;
  }
}
