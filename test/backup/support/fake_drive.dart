import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One file as the fake server stores it.
class FakeDriveFile {
  final String id;
  String name;
  final String mimeType;
  final List<String> parents;
  final Map<String, String> appProperties;
  final DateTime createdTime;
  List<int> bytes;
  bool trashed;

  FakeDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.parents,
    required this.appProperties,
    required this.createdTime,
    required this.bytes,
    this.trashed = false,
  });

  bool get isFolder => mimeType == FakeDrive.folderMime;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'parents': parents,
        'appProperties': appProperties,
        'createdTime': createdTime.toUtc().toIso8601String(),
        'trashed': trashed,
        if (!isFolder) 'md5Checksum': md5.convert(bytes).toString(),
        if (!isFolder) 'size': '${bytes.length}',
      };
}

/// A fault the next matching request answers with instead of doing its job.
class _Injected {
  final bool Function(http.Request) matches;
  final int? status;
  final String? reason;
  final Object? throwing;
  _Injected(this.matches, {this.status, this.reason, this.throwing});
}

/// An in-memory Google Drive v3 REST server for tests.
///
/// It sits behind `http/testing`'s [MockClient], so the code under test runs
/// the real `googleapis` client end to end: real URLs, real query strings, the
/// real multipart upload encoding and the real error-body parsing. Only the
/// server is fake.
///
/// It is deliberately narrow. `q` understands only the predicates
/// [DriveBackupTarget] sends, and anything else fails the test loudly rather
/// than quietly returning everything.
class FakeDrive {
  static const folderMime = 'application/vnd.google-apps.folder';

  /// Drive's documented limit on one appProperties key plus value, in bytes.
  static const appPropertyLimit = 124;

  final Map<String, FakeDriveFile> files = {};
  final List<http.Request> requests = [];
  final List<_Injected> _faults = [];

  DateTime clock = DateTime.utc(2026, 1, 1);

  /// When true, files created back to back share one `createdTime`, so tests
  /// can prove ordering does not depend on it alone.
  bool freezeClock = false;

  /// Files `files.list` does not return yet, though `files.get` finds them:
  /// Drive's search index lags a file created moments ago.
  final Set<String> notYetSearchable = {};

  int _seq = 0;

  late final http.Client client = MockClient(_handle);

  void advanceClock(Duration d) => clock = clock.add(d);

  /// The next request for which [where] is true (any request by default)
  /// gets an HTTP error with [status] and, optionally, a Drive error [reason].
  void failNext(int status, {String? reason, bool Function(http.Request)? where}) =>
      _faults.add(_Injected(where ?? (_) => true, status: status, reason: reason));

  /// The next matching request throws [error] instead of answering, the way
  /// a dropped connection does.
  void throwNext(Object error, {bool Function(http.Request)? where}) =>
      _faults.add(_Injected(where ?? (_) => true, throwing: error));

  /// Adds a file directly, as another machine or a person in the web UI would.
  FakeDriveFile seed({
    required String name,
    String mimeType = 'application/json',
    List<String> parents = const [],
    Map<String, String> appProperties = const {},
    String body = '',
    DateTime? createdTime,
    bool trashed = false,
  }) {
    final f = FakeDriveFile(
      id: _nextId(),
      name: name,
      mimeType: mimeType,
      parents: [...parents],
      appProperties: {...appProperties},
      createdTime: createdTime ?? _tick(),
      bytes: utf8.encode(body),
      trashed: trashed,
    );
    files[f.id] = f;
    return f;
  }

  List<FakeDriveFile> get folders =>
      files.values.where((f) => f.isFolder).toList();

  List<FakeDriveFile> childrenOf(String folderId, {bool includeTrashed = false}) =>
      files.values
          .where((f) =>
              f.parents.contains(folderId) && (includeTrashed || !f.trashed))
          .toList();

  String _nextId() => 'file-${(++_seq).toString().padLeft(4, '0')}';

  DateTime _tick() {
    if (!freezeClock) clock = clock.add(const Duration(seconds: 1));
    return clock;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    for (final f in _faults) {
      if (f.matches(request)) {
        _faults.remove(f);
        if (f.throwing != null) throw f.throwing!;
        return _error(f.status!, f.reason ?? 'injected', 'injected failure');
      }
    }

    final path = request.url.path;
    final query = request.url.queryParameters;
    if (request.method == 'POST' && path == '/upload/drive/v3/files') {
      return _createMultipart(request);
    }
    if (request.method == 'POST' && path == '/drive/v3/files') {
      return _create(jsonDecode(request.body) as Map<String, dynamic>, const []);
    }
    if (request.method == 'GET' && path == '/drive/v3/files') {
      return _list(query);
    }
    final single = RegExp(r'^/drive/v3/files/([^/]+)$').firstMatch(path);
    if (single != null) {
      final file = files[single.group(1)];
      if (file == null) return _error(404, 'notFound', 'File not found');
      if (request.method == 'GET') {
        if (query['alt'] == 'media') {
          return http.Response.bytes(file.bytes, 200,
              headers: {'content-type': file.mimeType});
        }
        return _json(file.toJson());
      }
      if (request.method == 'PATCH') {
        final patch = jsonDecode(request.body) as Map<String, dynamic>;
        if (patch['trashed'] is bool) file.trashed = patch['trashed'] as bool;
        return _json(file.toJson());
      }
      if (request.method == 'DELETE') {
        files.remove(file.id);
        return http.Response('', 204);
      }
    }
    throw StateError('FakeDrive: unhandled ${request.method} ${request.url}');
  }

  http.Response _createMultipart(http.Request request) {
    final contentType = request.headers['content-type'] ?? '';
    final boundary =
        RegExp(r'boundary="?([^";]+)"?').firstMatch(contentType)?.group(1);
    if (boundary == null) {
      throw StateError('FakeDrive: multipart upload without a boundary');
    }
    final parts = request.body
        .split('--$boundary')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p != '--')
        .toList();
    if (parts.length != 2) {
      throw StateError('FakeDrive: expected metadata + media, got $parts');
    }
    String partBody(String part) => part.substring(part.indexOf('\r\n\r\n') + 4);
    final metadata = jsonDecode(partBody(parts[0])) as Map<String, dynamic>;
    final media = parts[1];
    final encoded = partBody(media).trim();
    final bytes = media.toLowerCase().contains('content-transfer-encoding: base64')
        ? base64.decode(encoded)
        : utf8.encode(encoded);
    return _create(metadata, bytes);
  }

  http.Response _create(Map<String, dynamic> metadata, List<int> bytes) {
    final props = (metadata['appProperties'] as Map?)
            ?.map((k, v) => MapEntry('$k', '$v')) ??
        <String, String>{};
    for (final e in props.entries) {
      if (utf8.encode(e.key).length + utf8.encode(e.value).length >
          appPropertyLimit) {
        return _error(400, 'invalid',
            'The limit for property ${e.key} has been exceeded.');
      }
    }
    final parents = ((metadata['parents'] as List?) ?? const []).cast<String>();
    for (final p in parents) {
      if (!files.containsKey(p)) return _error(404, 'notFound', 'File not found: $p');
    }
    final f = FakeDriveFile(
      id: _nextId(),
      name: metadata['name'] as String? ?? 'Untitled',
      mimeType: metadata['mimeType'] as String? ?? 'application/octet-stream',
      parents: parents,
      appProperties: props,
      createdTime: _tick(),
      bytes: bytes,
    );
    files[f.id] = f;
    return _json(f.toJson());
  }

  http.Response _list(Map<String, String> query) {
    final predicates = _parseQ(query['q'] ?? '');
    var matched = files.values
        .where((f) =>
            !notYetSearchable.contains(f.id) && predicates.every((p) => p(f)))
        .toList();

    final orderBy = query['orderBy'];
    if (orderBy == 'createdTime desc') {
      // Drive's order among equal createdTime values is unspecified; reverse
      // insertion order here so a client that trusts it gets caught.
      matched = matched.reversed.toList()
        ..sort((a, b) => b.createdTime.compareTo(a.createdTime));
    } else if (orderBy == 'createdTime') {
      matched.sort((a, b) => a.createdTime.compareTo(b.createdTime));
    } else if (orderBy != null) {
      throw StateError('FakeDrive: unsupported orderBy "$orderBy"');
    }

    final pageSize = int.tryParse(query['pageSize'] ?? '') ?? 100;
    final start = int.tryParse(query['pageToken'] ?? '') ?? 0;
    final page = matched.skip(start).take(pageSize).toList();
    final next = start + pageSize < matched.length ? '${start + pageSize}' : null;
    return _json({
      'files': page.map((f) => f.toJson()).toList(),
      if (next != null) 'nextPageToken': next,
    });
  }

  /// Turns the query into predicates. Only the clause shapes the target uses
  /// are understood.
  List<bool Function(FakeDriveFile)> _parseQ(String q) {
    final out = <bool Function(FakeDriveFile)>[];
    var rest = q.trim();
    final clauses = [
      (
        RegExp(r"^mimeType\s*=\s*'([^']+)'"),
        (Match m) => (FakeDriveFile f) => f.mimeType == m.group(1),
      ),
      (
        RegExp(r'^trashed\s*=\s*(true|false)'),
        (Match m) => (FakeDriveFile f) => f.trashed == (m.group(1) == 'true'),
      ),
      (
        RegExp(r"^'([^']+)'\s+in\s+parents"),
        (Match m) => (FakeDriveFile f) => f.parents.contains(m.group(1)),
      ),
      (
        RegExp(r"^appProperties\s+has\s+\{\s*key\s*=\s*'([^']+)'\s+and\s+value\s*=\s*'([^']+)'\s*\}"),
        (Match m) =>
            (FakeDriveFile f) => f.appProperties[m.group(1)] == m.group(2),
      ),
    ];
    while (rest.isNotEmpty) {
      var consumed = false;
      for (final (re, build) in clauses) {
        final m = re.firstMatch(rest);
        if (m != null) {
          out.add(build(m));
          rest = rest.substring(m.end).trim();
          if (rest.startsWith('and ')) rest = rest.substring(4).trim();
          consumed = true;
          break;
        }
      }
      if (!consumed) throw StateError('FakeDrive: unsupported q clause "$rest"');
    }
    return out;
  }

  http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});

  http.Response _error(int status, String reason, String message) =>
      http.Response(
        jsonEncode({
          'error': {
            'code': status,
            'message': message,
            'errors': [
              {'domain': 'global', 'reason': reason, 'message': message}
            ],
          }
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
