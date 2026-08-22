import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_status.dart';

void main() {
  final now = DateTime(2026, 8, 16, 9, 42);

  AppFault fault(BackupFailureKind kind) =>
      AppFault.backup(kind, 'whatever', operation: 'push');

  const backedUp = BackupStatus(
    configured: true,
    hasDurableHead: true,
    isDirty: false,
  );

  group('precedence, evaluated in order', () {
    test('row 1: an active non-conflict failure is red', () {
      final s = backedUp.copyWith(activeCondition: fault(BackupFailureKind.offline));
      expect(s.state, BackupPillState.failing);
      expect(s.label(now), 'Backup offline');
    });

    test('row 2: an unresolved conflict is amber, not red', () {
      final s = backedUp.copyWith(activeCondition: fault(BackupFailureKind.conflict));
      expect(s.state, BackupPillState.needsReview);
      expect(s.label(now), 'Needs review');
    });

    test('row 3: no durable head is grey', () {
      const s = BackupStatus(configured: true, hasDurableHead: false);
      expect(s.state, BackupPillState.notBackedUp);
      expect(s.label(now), 'Not backed up');
    });

    test('row 3: no target configured is grey even with a head recorded', () {
      const s = BackupStatus(configured: false, hasDurableHead: true);
      expect(s.state, BackupPillState.notBackedUp);
    });

    test('row 4: dirty is amber and counts the pending mutations', () {
      final s = backedUp.copyWith(isDirty: true, pendingCount: 3);
      expect(s.state, BackupPillState.pending);
      expect(s.label(now), '3 changes pending');
    });

    test('row 4: one pending change reads singular', () {
      expect(backedUp.copyWith(isDirty: true, pendingCount: 1).label(now),
          '1 change pending');
    });

    test('row 4: dirty with no counted mutations still says so', () {
      // A restore leaves content differing from the head without the
      // generation counter moving. Amber with no number beats a wrong number.
      expect(backedUp.copyWith(isDirty: true, pendingCount: 0).label(now),
          'Changes pending');
    });

    test('row 5: local equals the durable head is green', () {
      final s = backedUp.copyWith(
          lastSuccessAt: now.subtract(const Duration(hours: 2)));
      expect(s.state, BackupPillState.backedUp);
      expect(s.label(now), 'Backed up 2h ago');
    });
  });

  test('clean local plus a dead credential renders RED, not green', () {
    // The bug this whole surface exists to prevent: nothing edited locally, so
    // "hash equals durable head" is true — and the background sweep's pull
    // just died on authExpired.
    final s = backedUp.copyWith(
      lastSuccessAt: now.subtract(const Duration(minutes: 5)),
      activeCondition: fault(BackupFailureKind.authExpired),
    );
    expect(s.state, BackupPillState.failing);
    expect(s.label(now), 'Sign-in expired');
  });

  test('a hard failure outranks a conflict regardless of which arrived last',
      () {
    // The earlier draft of this test set ONE condition and claimed to prove
    // precedence between two. It could not fail for the reason it named.
    // BackupStatus holds a single activeCondition, so precedence between two
    // simultaneous conditions is the CONTROLLER's job (Task 6) — what this
    // function must guarantee is only that a conflict-kind condition and a
    // hard-failure condition land in different states.
    final conflicted =
        backedUp.copyWith(activeCondition: fault(BackupFailureKind.conflict));
    final failing =
        backedUp.copyWith(activeCondition: fault(BackupFailureKind.storageFull));

    expect(conflicted.state, BackupPillState.needsReview);
    expect(failing.state, BackupPillState.failing);
    expect(failing.label(now), 'Drive full');
    // Enum order IS the precedence order, and the controller relies on it.
    expect(BackupPillState.failing.index,
        lessThan(BackupPillState.needsReview.index));
  });

  test('every backup failure kind has copy that is not the fallback', () {
    for (final kind in BackupFailureKind.values) {
      if (BackupStatus.isQuestion(kind.name)) continue;
      expect(BackupStatus.failureLabels[kind.name], isNotNull,
          reason: '${kind.name} has no pill copy');
    }
  });

  test('first-run adoption is amber, and asks its own question', () {
    final s = backedUp.copyWith(
        hasDurableHead: false,
        activeCondition: fault(BackupFailureKind.adoptionChoice));
    expect(s.state, BackupPillState.needsReview);
    expect(s.label(now), 'Choose a copy',
        reason: 'a brand-new iPad has no "other machine" to conflict with');
  });

  test('equal statuses compare equal so the AppBar does not rebuild', () {
    expect(backedUp.copyWith(isDirty: true), backedUp.copyWith(isDirty: true));
    expect(backedUp.copyWith(isDirty: true) == backedUp, isFalse);
  });
}
