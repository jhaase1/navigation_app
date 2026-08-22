import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_fault.dart';

/// One row in the popover. Several occurrences of the same problem collapse
/// into one of these.
class BackupLogEntry {
  final String fingerprint;
  final String domain;
  final String kind;
  final String message;

  /// Varying detail from the most recent occurrence. Kept off [fingerprint]
  /// on purpose: `SocketException: ... timed out after 5002ms` differs on
  /// every attempt, so collapsing on message text collapses nothing.
  final String? lastDetail;

  final DateTime firstSeen;
  final DateTime lastSeen;
  final int count;

  /// The operator has read this. Dismissed rows stay visible in history but
  /// never absorb a later occurrence.
  final bool dismissed;

  /// False for the "backed up" rows that make the log useful when things work.
  final bool isFailure;

  const BackupLogEntry({
    required this.fingerprint,
    required this.domain,
    required this.kind,
    required this.message,
    required this.lastDetail,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.dismissed,
    required this.isFailure,
  });

  BackupLogEntry copyWith({
    String? message,
    String? lastDetail,
    DateTime? lastSeen,
    int? count,
    bool? dismissed,
  }) =>
      BackupLogEntry(
        fingerprint: fingerprint,
        domain: domain,
        kind: kind,
        message: message ?? this.message,
        lastDetail: lastDetail ?? this.lastDetail,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        count: count ?? this.count,
        dismissed: dismissed ?? this.dismissed,
        isFailure: isFailure,
      );

  Map<String, dynamic> toJson() => {
        'fp': fingerprint,
        'dom': domain,
        'kind': kind,
        'msg': message,
        if (lastDetail != null) 'detail': lastDetail,
        'first': firstSeen.toUtc().toIso8601String(),
        'last': lastSeen.toUtc().toIso8601String(),
        'n': count,
        if (dismissed) 'read': true,
        if (!isFailure) 'ok': true,
      };

  factory BackupLogEntry.fromJson(Map<String, dynamic> json) {
    T need<T>(String field) {
      final v = json[field];
      if (v is! T) throw FormatException('log row field "$field"');
      return v;
    }

    return BackupLogEntry(
      fingerprint: need<String>('fp'),
      domain: need<String>('dom'),
      kind: need<String>('kind'),
      message: need<String>('msg'),
      lastDetail: json['detail'] as String?,
      firstSeen: DateTime.parse(need<String>('first')),
      lastSeen: DateTime.parse(need<String>('last')),
      count: need<int>('n'),
      dismissed: json['read'] == true,
      isFailure: json['ok'] != true,
    );
  }
}

/// The history behind the pill.
///
/// Bounded three ways, because each bound alone has a hole: 14 days leaves a
/// retry storm unbounded within a day, 200 rows leaves an unbounded `cause`
/// string free to blow up the stored document, and a byte cap alone would let
/// a year-old row survive.
class BackupLog {
  static const String key = 'backup_log';

  /// When this machine's configuration was last confirmed stored at the
  /// target. Journalled with the engine keys: a rolled-back import that left
  /// this behind would date a restored configuration by a backup it never had.
  static const String lastSuccessKey = 'backup_last_success_at';

  static const int maxRows = 200;
  static const Duration maxAge = Duration(days: 14);
  static const int maxBytes = 64 * 1024;
  static const int maxTextChars = 200;

  BackupLog({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Newest first.
  final ValueNotifier<List<BackupLogEntry>> entries =
      ValueNotifier<List<BackupLogEntry>>(const []);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      entries.value = decoded
          .map((e) => BackupLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Pre-release: no deployed data, so a log that does not parse is
      // discarded rather than migrated. Losing history is survivable; a parse
      // that throws on every launch is not.
      entries.value = const [];
      await prefs.remove(key);
    }
  }

  Future<void> recordFault(AppFault fault) => _record(
        fingerprint: fault.fingerprint,
        domain: fault.domain.name,
        kind: fault.kind,
        message: fault.message,
        detail: fault.cause?.toString(),
        isFailure: true,
      );

  /// Notable successes only — an uploaded revision, an applied restore. The
  /// ten-minute sweep finding nothing to do is not an event.
  Future<void> recordSuccess({
    required String operation,
    required String kind,
    required String message,
    String? targetIdentity,
  }) =>
      _record(
        fingerprint: 'backup/$kind/$operation/${targetIdentity ?? "-"}',
        domain: 'backup',
        kind: kind,
        message: message,
        detail: null,
        isFailure: false,
      );

  Future<void> dismiss(String fingerprint) async {
    entries.value = [
      for (final e in entries.value)
        if (e.fingerprint == fingerprint && !e.dismissed)
          e.copyWith(dismissed: true)
        else
          e,
    ];
    await _persist();
  }

  Future<void> _record({
    required String fingerprint,
    required String domain,
    required String kind,
    required String message,
    required String? detail,
    required bool isFailure,
  }) async {
    final now = _now();
    final text = _truncate(message);
    final trimmedDetail = detail == null ? null : _truncate(detail);

    final next = [...entries.value];
    // Collapse onto the newest LIVE row with this fingerprint. A dismissed row
    // is closed: "I have read this" must not swallow the next occurrence.
    final i =
        next.indexWhere((e) => e.fingerprint == fingerprint && !e.dismissed);
    if (i >= 0) {
      next[i] = next[i].copyWith(
        message: text,
        lastDetail: trimmedDetail ?? next[i].lastDetail,
        lastSeen: now,
        count: next[i].count + 1,
      );
    } else {
      next.add(BackupLogEntry(
        fingerprint: fingerprint,
        domain: domain,
        kind: kind,
        message: text,
        lastDetail: trimmedDetail,
        firstSeen: now,
        lastSeen: now,
        count: 1,
        dismissed: false,
        isFailure: isFailure,
      ));
    }

    entries.value = _bounded(next, now);
    await _persist();
  }

  List<BackupLogEntry> _bounded(List<BackupLogEntry> rows, DateTime now) {
    final cutoff = now.subtract(maxAge);
    var kept = rows.where((e) => !e.lastSeen.isBefore(cutoff)).toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    if (kept.length > maxRows) kept = kept.sublist(0, maxRows);
    while (kept.length > 1 && _encodedBytes(kept) > maxBytes) {
      kept = kept.sublist(0, kept.length - 1);
    }
    return kept;
  }

  static String _truncate(String s) =>
      s.length <= maxTextChars ? s : '${s.substring(0, maxTextChars - 1)}…';

  static String _encode(List<BackupLogEntry> rows) =>
      jsonEncode(rows.map((e) => e.toJson()).toList());

  static int _encodedBytes(List<BackupLogEntry> rows) =>
      utf8.encode(_encode(rows)).length;

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    // Deliberately does not throw. The log is a record, not an authority: a
    // failed write must not take down the operation that produced the entry.
    if (!await prefs.setString(key, _encode(entries.value))) {
      await prefs.reload();
    }
  }
}
