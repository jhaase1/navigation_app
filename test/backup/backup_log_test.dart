import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 8, 16, 9, 0);
  });

  BackupLog newLog() => BackupLog(now: () => clock);

  AppFault socketTimeout(int ms) => AppFault.backup(
        BackupFailureKind.offline,
        'Could not reach Google Drive.',
        operation: 'push',
        targetIdentity: 'drive:folder-1',
        cause: 'SocketException: timed out after ${ms}ms',
      );

  test('a retry storm collapses to one row on the structured fingerprint',
      () async {
    final log = newLog();
    for (var i = 0; i < 50; i++) {
      clock = clock.add(const Duration(seconds: 30));
      await log.recordFault(socketTimeout(5000 + i));
    }
    expect(log.entries.value, hasLength(1));
    expect(log.entries.value.single.count, 50);
    // Changing detail belongs on the row, not in the key.
    expect(log.entries.value.single.lastDetail, contains('5049ms'));
  });

  test('a different operation is a different row', () async {
    final log = newLog();
    await log.recordFault(socketTimeout(1));
    await log.recordFault(AppFault.backup(
      BackupFailureKind.offline,
      'Could not reach Google Drive.',
      operation: 'pull',
      targetIdentity: 'drive:folder-1',
    ));
    expect(log.entries.value, hasLength(2));
  });

  test('the row cap CAN evict an old auth failure — which is why the pill '
      'holds the active condition instead', () async {
    // The earlier draft of this test pushed 500 faults that all shared one
    // fingerprint. They collapsed to a single row, the 200-row cap was never
    // approached, and the assertion would have passed even if `_bounded`
    // returned its input untouched. It proved nothing.
    //
    // The honest version: 250 DISTINCT fingerprints do evict, and the log is
    // therefore NOT where an unresolved condition is kept alive. That is the
    // controller's in-memory active condition (Task 6, deviation D1).
    final log = newLog();
    await log.recordFault(AppFault.backup(
        BackupFailureKind.authExpired, 'Sign in again.',
        operation: 'pull', targetIdentity: 'drive:folder-1'));
    for (var i = 0; i < 250; i++) {
      clock = clock.add(const Duration(seconds: 30));
      await log.recordFault(AppFault.backup(
          BackupFailureKind.transientServer, 'Drive error $i',
          operation: 'push-$i', targetIdentity: 'drive:folder-1'));
    }

    expect(log.entries.value, hasLength(BackupLog.maxRows));
    expect(log.entries.value.map((e) => e.kind), isNot(contains('authExpired')),
        reason: 'history is bounded; the ACTIVE condition is held elsewhere');
  });

  test('a dismissed row does not absorb the next occurrence', () async {
    final log = newLog();
    await log.recordFault(socketTimeout(1));
    await log.dismiss(log.entries.value.single.fingerprint);
    clock = clock.add(const Duration(minutes: 5));
    await log.recordFault(socketTimeout(2));

    expect(log.entries.value, hasLength(2));
    expect(log.entries.value.first.dismissed, isFalse);
    expect(log.entries.value.last.dismissed, isTrue);
  });

  test('rows older than 14 days are dropped', () async {
    final log = newLog();
    await log.recordFault(socketTimeout(1));
    clock = clock.add(const Duration(days: 15));
    await log.recordSuccess(
        operation: 'push', kind: 'uploaded', message: 'Backed up.');
    expect(log.entries.value, hasLength(1));
    expect(log.entries.value.single.kind, 'uploaded');
  });

  test('the row cap keeps the newest 200', () async {
    final log = newLog();
    for (var i = 0; i < 250; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await log.recordFault(AppFault.backup(
          BackupFailureKind.unknown, 'failure $i',
          operation: 'op$i'));
    }
    expect(log.entries.value, hasLength(BackupLog.maxRows));
    expect(log.entries.value.first.message, 'failure 249');
  });

  test('an unbounded cause string cannot blow past the byte cap', () async {
    final log = newLog();
    for (var i = 0; i < 250; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await log.recordFault(AppFault.backup(
        BackupFailureKind.unknown,
        'x' * 5000,
        operation: 'op$i',
        cause: 'y' * 50000,
      ));
    }
    final prefs = await SharedPreferences.getInstance();
    expect(utf8.encode(prefs.getString(BackupLog.key)!).length,
        lessThanOrEqualTo(BackupLog.maxBytes));
    expect(log.entries.value.first.message.length,
        lessThanOrEqualTo(BackupLog.maxTextChars));
  });

  test('survives a restart', () async {
    final log = newLog();
    await log.recordFault(socketTimeout(1));
    await log.dismiss(log.entries.value.single.fingerprint);

    final reloaded = newLog();
    await reloaded.load();
    expect(reloaded.entries.value, hasLength(1));
    expect(reloaded.entries.value.single.dismissed, isTrue);
    expect(reloaded.entries.value.single.count, 1);
  });

  test('a corrupt stored log is discarded, not thrown', () async {
    SharedPreferences.setMockInitialValues({BackupLog.key: 'not json'});
    final log = newLog();
    await log.load();
    expect(log.entries.value, isEmpty);
  });
}
