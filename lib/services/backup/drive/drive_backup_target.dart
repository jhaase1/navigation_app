import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../abstract/backup_target_abstract.dart';
import '../app_fault.dart';
import '../backup_revision.dart';

/// Append-only revision storage in one visible Google Drive folder.
///
/// Every revision is its own immutable file. Ordering, identity and
/// checksums all come from the server; nothing the client wrote — not the
/// file name, not the `contentHash` in `appProperties` — is trusted to decide
/// which revision is newest or whether bytes are intact.
class DriveBackupTarget implements BackupTargetAbstract {
  static const folderName = 'Production Control Backups';

  /// `<account>|<folderId>`. Scoped to the account so a folder id learned
  /// under one Google account is never tried under another.
  static const folderPrefsKey = 'backup_drive_folder';

  static const _marker = 'navBackup';
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _fileFields =
      'id,name,createdTime,md5Checksum,size,appProperties,trashed';

  /// Drive's limit on one appProperties key plus value, in UTF-8 bytes.
  static const _appPropertyLimit = 124;

  final drive.DriveApi _api;
  final String account;
  final DateTime Function() _now;
  String? _folderId;

  DriveBackupTarget({
    required http.Client client,
    required String account,
    DateTime Function()? now,
  })  : _api = drive.DriveApi(client),
        account = account.trim().toLowerCase(),
        _now = now ?? DateTime.now;

  // ── BackupTargetAbstract ──────────────────────────────────────────────────

  @override
  Future<BackupRevision> put(
    String json, {
    required String contentHash,
    required String? parentRevisionId,
    required String deviceLabel,
  }) =>
      _guard(() async {
        final folder = await _folder();
        final bytes = utf8.encode(json);
        final schemaVersion = _schemaVersionOf(json);
        final file = await _api.files.create(
          drive.File(
            name: _fileName(),
            parents: [folder],
            mimeType: 'application/json',
            appProperties: {
              _marker: 'revision',
              'contentHash': contentHash,
              'deviceLabel': _fit('deviceLabel', deviceLabel),
              if (parentRevisionId != null) 'parentRevisionId': parentRevisionId,
              if (schemaVersion != null) 'schemaVersion': '$schemaVersion',
            },
          ),
          uploadMedia: drive.Media(Stream.value(bytes), bytes.length,
              contentType: 'application/json'),
          $fields: _fileFields,
        );
        return _revision(file);
      });

  @override
  Future<BackupRevision?> latest() => _guard(() async {
        final revisions = await _list(1);
        return revisions.isEmpty ? null : revisions.first;
      });

  @override
  Future<List<BackupRevision>> list({int limit = 50}) => _guard(() async {
        if (limit < 0) {
          throw AppFault.backup(
              BackupFailureKind.unknown, 'limit must not be negative');
        }
        return _list(limit);
      });

  @override
  Future<String> fetch(BackupRevision revision) => _guard(() async {
        final meta = await _api.files.get(revision.id,
            $fields: 'id,trashed,md5Checksum') as drive.File;
        if (meta.trashed ?? false) {
          throw AppFault.backup(BackupFailureKind.targetMissing,
              'That backup is no longer on Google Drive.');
        }
        if (meta.md5Checksum != revision.bodyChecksum) {
          // Edited between listing and reading. Retrying re-lists and sees
          // the current bytes; handing these over would apply content the
          // engine never reasoned about.
          throw AppFault.backup(BackupFailureKind.transientServer,
              'A backup changed on Google Drive while it was being read.');
        }
        final media = await _api.files.get(revision.id,
            downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final bytes = await media.stream
            .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
        if (md5.convert(bytes).toString() != meta.md5Checksum) {
          throw AppFault.backup(BackupFailureKind.malformedRemote,
              'A backup downloaded from Google Drive did not match its checksum.');
        }
        return utf8.decode(bytes);
      });

  @override
  Future<void> prune({required int keepCount, required Duration keepFor}) =>
      _guard(() async {
        if (keepCount < 0) {
          throw AppFault.backup(
              BackupFailureKind.unknown, 'keepCount must not be negative');
        }
        final all = await _list(null);
        final cutoff = _now().subtract(keepFor);
        for (var i = keepCount; i < all.length; i++) {
          if (all[i].createdAt.isBefore(cutoff)) {
            // Trash, never delete: a wrong prune stays recoverable for 30
            // days from the Drive web UI.
            await _api.files.update(drive.File(trashed: true), all[i].id,
                $fields: 'id');
          }
        }
      });

  // ── Listing ───────────────────────────────────────────────────────────────

  /// Revisions newest first, up to [limit] (all of them when null).
  Future<List<BackupRevision>> _list(int? limit) async {
    if (limit == 0) return const [];
    final folder = await _folder();
    final files = <drive.File>[];
    String? token;
    do {
      final page = await _api.files.list(
        q: "'$folder' in parents and trashed = false and "
            "appProperties has { key='$_marker' and value='revision' }",
        orderBy: 'createdTime desc',
        pageSize: 100,
        pageToken: token,
        $fields: 'nextPageToken,files($_fileFields)',
      );
      files.addAll(page.files ?? const []);
      token = page.nextPageToken;
    } while (token != null && !_enough(files, limit));

    final revisions = files.map(_revision).toList()
      ..sort((a, b) {
        // Server time first. Drive cannot order by id, so equal times are
        // broken here — deterministically, the same way the mock does.
        final byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return limit == null ? revisions : revisions.take(limit).toList();
  }

  /// Whether [files] already holds the newest [limit] — including any file
  /// that ties with the last one on time, which could still sort ahead of it.
  static bool _enough(List<drive.File> files, int? limit) {
    if (limit == null || files.length <= limit) return false;
    return files.last.createdTime != files[limit - 1].createdTime;
  }

  BackupRevision _revision(drive.File f) {
    final props = f.appProperties ?? const <String, String>{};
    final id = f.id;
    final created = f.createdTime;
    final checksum = f.md5Checksum;
    final contentHash = props['contentHash'];
    if (id == null || created == null || checksum == null || contentHash == null) {
      throw AppFault.backup(BackupFailureKind.malformedRemote,
          'A backup on Google Drive is missing its details.');
    }
    return BackupRevision(
      id: id,
      filename: f.name ?? '',
      createdAt: created.toUtc(),
      contentHash: contentHash,
      bodyChecksum: checksum,
      parentRevisionId: props['parentRevisionId'],
      sizeBytes: int.tryParse(f.size ?? '') ?? 0,
      deviceLabel: props['deviceLabel'] ?? '',
    );
  }

  // ── Folder identity ───────────────────────────────────────────────────────

  /// The backup folder's id, resolved live on every operation.
  ///
  /// Every marked folder is listed each time, not only the one this machine
  /// remembers. Two first runs racing can leave two, and a machine that
  /// trusted its own remembered folder would keep writing there while a
  /// fresh install read the other and found no backup at all. Which folder
  /// holds the real history is a person's call, so more than one pauses
  /// backups with a fault that says so. Nothing in Drive is moved or deleted.
  ///
  /// The listing skips trashed folders. Listing the children of a trashed
  /// folder returns an empty list, not an error, so without that a trashed
  /// folder would read as "no backups" and the next push would write into
  /// the trash. A fresh folder reads as empty too, which the engine already
  /// treats as the backup having gone missing (pull branch 2), so replacing
  /// it here needs no special case.
  Future<String> _folder() async {
    final prefs = await SharedPreferences.getInstance();
    final found = await _markedFolders();
    // Search lags a folder created moments ago. The remembered one is asked
    // for directly, so that lag never makes a second folder.
    final remembered = _folderId ?? _remembered(prefs);
    if (remembered != null &&
        !found.contains(remembered) &&
        await _isOurs(remembered)) {
      found.add(remembered);
    }
    if (found.length > 1) {
      throw AppFault.backup(
          BackupFailureKind.targetAmbiguous,
          'Backups are paused: Google Drive has more than one '
          '"$folderName" folder. Move every backup into one of them, put the '
          'others in the trash, then tap Retry now.');
    }
    final id = found.isEmpty ? await _createFolder() : found.single;
    if (_remembered(prefs) != id) {
      await prefs.setString(folderPrefsKey, '$account|$id');
    }
    return _folderId = id;
  }

  String? _remembered(SharedPreferences prefs) {
    final raw = prefs.getString(folderPrefsKey);
    if (raw == null) return null;
    final split = raw.lastIndexOf('|');
    if (split < 0 || raw.substring(0, split) != account) return null;
    return raw.substring(split + 1);
  }

  /// Whether [folderId] is still one of our folders and not in the trash.
  Future<bool> _isOurs(String folderId) async {
    try {
      final f = await _api.files.get(folderId,
          $fields: 'id,trashed,appProperties') as drive.File;
      return !(f.trashed ?? false) && f.appProperties?[_marker] == 'root';
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

  /// Every untrashed folder carrying our marker. Drive may return a short
  /// page before the end, so this follows the page token to the last one.
  Future<List<String>> _markedFolders() async {
    final ids = <String>[];
    String? token;
    do {
      final page = await _api.files.list(
        q: "mimeType = '$_folderMime' and trashed = false and "
            "appProperties has { key='$_marker' and value='root' }",
        pageSize: 100,
        pageToken: token,
        $fields: 'nextPageToken,files(id)',
      );
      ids.addAll(
          page.files?.map((f) => f.id).whereType<String>() ?? const []);
      token = page.nextPageToken;
    } while (token != null);
    return ids;
  }

  Future<String> _createFolder() async {
    final f = await _api.files.create(
      drive.File(
        name: folderName,
        mimeType: _folderMime,
        appProperties: {_marker: 'root'},
      ),
      $fields: 'id',
    );
    return f.id!;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Display only. Ordering never reads it: a machine with a wrong clock
  /// writes a wrong name, and nothing breaks.
  String _fileName() {
    final t = _now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'nav_config_${t.year}${two(t.month)}${two(t.day)}T'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}Z.json';
  }

  /// [value] shortened, on a character boundary, until [key] plus it fit
  /// Drive's per-property limit. Drive rejects the whole upload otherwise.
  static String _fit(String key, String value) {
    final budget = _appPropertyLimit - utf8.encode(key).length;
    var runes = value.runes.toList();
    while (utf8.encode(String.fromCharCodes(runes)).length > budget) {
      runes = runes.sublist(0, runes.length - 1);
    }
    return String.fromCharCodes(runes);
  }

  static Object? _schemaVersionOf(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map ? decoded['schemaVersion'] : null;
    } on FormatException {
      return null;
    }
  }

  /// Every exception becomes an [AppFault] here, and nowhere else.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AppFault {
      rethrow;
    } on drive.DetailedApiRequestError catch (e) {
      throw _fromHttp(e);
    } on drive.ApiRequestError catch (e) {
      throw AppFault.backup(
          BackupFailureKind.unknown, 'Google Drive rejected the request.',
          cause: e);
    } on SocketException catch (e) {
      throw _offline(e);
    } on TlsException catch (e) {
      throw _offline(e);
    } on http.ClientException catch (e) {
      throw _offline(e);
    } on TimeoutException catch (e) {
      throw _offline(e);
    } on FormatException catch (e) {
      throw AppFault.backup(BackupFailureKind.malformedRemote,
          'Google Drive sent back something unreadable.',
          cause: e);
    }
  }

  static AppFault _offline(Object cause) => AppFault.backup(
      BackupFailureKind.offline, 'Could not reach Google Drive.',
      cause: cause);

  static AppFault _fromHttp(drive.DetailedApiRequestError e) {
    final status = e.status ?? 0;
    final reasons = e.errors.map((d) => d.reason).whereType<String>().toSet();
    final (kind, message) = switch (status) {
      401 => (
          BackupFailureKind.authExpired,
          'Google Drive needs you to sign in again.'
        ),
      429 => (
          BackupFailureKind.rateLimited,
          'Google Drive asked us to slow down. Retrying.'
        ),
      403 when reasons.contains('rateLimitExceeded') ||
            reasons.contains('userRateLimitExceeded') =>
        (
          BackupFailureKind.rateLimited,
          'Google Drive asked us to slow down. Retrying.'
        ),
      403 when reasons.contains('storageQuotaExceeded') => (
          BackupFailureKind.storageFull,
          'The Google Drive account is out of storage.'
        ),
      403 => (
          BackupFailureKind.permissionDenied,
          'Google Drive refused access to the backup folder.'
        ),
      404 => (
          BackupFailureKind.targetMissing,
          'A backup on Google Drive is gone.'
        ),
      >= 500 && < 600 => (
          BackupFailureKind.transientServer,
          'Google Drive had a temporary problem. Retrying.'
        ),
      _ => (BackupFailureKind.unknown, 'Google Drive rejected the request.'),
    };
    return AppFault.backup(kind, message, cause: e);
  }
}
