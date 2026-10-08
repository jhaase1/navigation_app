import 'app_fault.dart';
import 'relative_time.dart';

/// The five pill states, in precedence order. The order of this enum is the
/// order of the spec's table and the order [BackupStatus.state] evaluates.
enum BackupPillState { failing, needsReview, notBackedUp, pending, backedUp }

/// Three independent facts, and the one derivation that turns them into a
/// colour.
///
/// Colour cannot come from "the most recent attempt", because pull and push
/// are both attempts: a push of new edits fails, the app is foregrounded, its
/// pull succeeds — and a most-recent-attempt rule paints the pill green while
/// the edits exist nowhere but this machine.
class BackupStatus {
  /// [AppFault.kind] for a divergence. Amber, not red: it is a question, not
  /// a failure.
  static const String conflictKind = 'conflict';

  /// First run holding local data against a non-empty remote. Also a
  /// question, and a different one: nobody else has edited anything, this
  /// machine simply has to say which copy wins.
  static const String adoptionKind = 'adoptionChoice';

  static bool isQuestion(String kind) =>
      kind == conflictKind || kind == adoptionKind;

  /// The unresolved operation-specific state, if any.
  final AppFault? activeCondition;

  /// Whether a revision is known to exist at the target holding content this
  /// machine can name.
  final bool hasDurableHead;

  /// Whether the local canonical hash differs from the durable head's.
  final bool isDirty;

  /// Mutations recorded since the last successful push. Displayed only when
  /// [isDirty] also holds — see the plan's deviation D2.
  final int pendingCount;

  final DateTime? lastSuccessAt;

  /// False until a backup target exists. Phase 3 ships with none.
  final bool configured;

  const BackupStatus({
    this.activeCondition,
    this.hasDurableHead = false,
    this.isDirty = false,
    this.pendingCount = 0,
    this.lastSuccessAt,
    this.configured = false,
  });

  /// Evaluated in order, first match wins. **Failure outranks agreement.**
  /// Checking the hash first shows green while the credentials are dead.
  BackupPillState get state {
    final condition = activeCondition;
    if (condition != null && !isQuestion(condition.kind)) {
      return BackupPillState.failing;
    }
    if (condition != null) return BackupPillState.needsReview;
    if (!configured || !hasDurableHead) return BackupPillState.notBackedUp;
    if (isDirty) return BackupPillState.pending;
    return BackupPillState.backedUp;
  }

  /// Operation-specific copy. Exact strings: copy is a spec surface here.
  static const Map<String, String> failureLabels = {
    'offline': 'Backup offline',
    'authExpired': 'Sign-in expired',
    'permissionDenied': 'Access denied',
    'rateLimited': 'Backup throttled',
    'transientServer': 'Backup failing',
    'storageFull': 'Drive full',
    'storageWriteFailed': 'Save failed',
    'unsupportedSchema': 'App update needed',
    'malformedRemote': 'Backup unreadable',
    'targetMissing': 'Backup missing',
    'deviceUnnamed': 'Name this machine',
    'unknown': 'Backup failing',
  };

  String label(DateTime now) {
    switch (state) {
      case BackupPillState.failing:
        final condition = activeCondition!;
        return switch (condition.domain) {
          FaultDomain.roland => 'Switcher offline',
          FaultDomain.camera => '${condition.targetIdentity ?? 'Camera'} offline',
          FaultDomain.backup =>
            failureLabels[condition.kind] ?? 'Backup failing',
        };
      case BackupPillState.needsReview:
        return activeCondition!.kind == adoptionKind
            ? 'Choose a copy'
            : 'Needs review';
      case BackupPillState.notBackedUp:
        return 'Not backed up';
      case BackupPillState.pending:
        if (pendingCount == 1) return '1 change pending';
        if (pendingCount > 1) return '$pendingCount changes pending';
        return 'Changes pending';
      case BackupPillState.backedUp:
        final at = lastSuccessAt;
        return at == null ? 'Backed up' : 'Backed up ${compactAge(at, now)}';
    }
  }

  BackupStatus copyWith({
    AppFault? activeCondition,
    bool clearCondition = false,
    bool? hasDurableHead,
    bool? isDirty,
    int? pendingCount,
    DateTime? lastSuccessAt,
    // Without this, a manual import or an emptied target leaves the popover
    // saying "Last backed up 5 minutes ago" about a configuration that has
    // never been backed up at all.
    bool clearLastSuccess = false,
    bool? configured,
  }) =>
      BackupStatus(
        activeCondition:
            clearCondition ? null : (activeCondition ?? this.activeCondition),
        hasDurableHead: hasDurableHead ?? this.hasDurableHead,
        isDirty: isDirty ?? this.isDirty,
        pendingCount: pendingCount ?? this.pendingCount,
        lastSuccessAt:
            clearLastSuccess ? null : (lastSuccessAt ?? this.lastSuccessAt),
        configured: configured ?? this.configured,
      );

  // ValueNotifier compares with ==; without this every scheduler tick would
  // rebuild the AppBar whether or not anything changed.
  @override
  bool operator ==(Object other) =>
      other is BackupStatus &&
      other.activeCondition?.fingerprint == activeCondition?.fingerprint &&
      other.activeCondition?.message == activeCondition?.message &&
      other.hasDurableHead == hasDurableHead &&
      other.isDirty == isDirty &&
      other.pendingCount == pendingCount &&
      other.lastSuccessAt == lastSuccessAt &&
      other.configured == configured;

  @override
  int get hashCode => Object.hash(
        activeCondition?.fingerprint,
        activeCondition?.message,
        hasDurableHead,
        isDirty,
        pendingCount,
        lastSuccessAt,
        configured,
      );
}
