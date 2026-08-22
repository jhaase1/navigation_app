# Status Surface Implementation Plan (Phase 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every backup failure, pending edit and divergence visible in the
AppBar, and give the operator the three actions that resolve them.

**Architecture:** Phase 2 shipped an engine that returns results and throws
`AppFault`s into a stream nothing listens to. This phase adds one owner —
`BackupController` — that subscribes to `BackupScheduler.events`, folds them
into a three-fact status model (durable head / dirty / active condition),
derives a five-state pill from that model in a pure function, and persists a
bounded, fingerprint-collapsing log. The UI reads a single
`ValueListenable<BackupStatus>`. No widget talks to `BackupService` directly.

**Tech Stack:** Flutter 3.47.0 stable, Dart `>=3.0.0 <4.0.0`. No new runtime
dependencies — `shared_preferences` and `crypto` are already present, and date
formatting is hand-rolled rather than adding `intl` (see Global Constraints).

**Spec:** `docs/superpowers/specs/2026-08-21-drive-backup-and-status-surface-design.md`
(§The status surface, §Conflict handling, §Naming a machine, §Phasing item 3).

**Lane tier:** Tier 3 (full lane) — this phase adds a **new persisted shape**
(`backup_log`, `backup_last_success_at`, `backup_device_label`,
`backup_conflict_suppressed`) and three engine methods that overwrite operator
configuration. Per `docs/superpowers/runbooks/lane-process.md` that is squarely
inside the Tier 3 fence.

---

## Lanes

Phase 3 is nine deliverables. The lane process caps a spec at ~3 shippable
behaviors, so this plan ships as **two lanes, each on its own worktree and
branch, each merged by Daniel separately.**

| Lane | Branch | Tasks | Ships |
|---|---|---|---|
| **3a — Status surface** | `lane/status-surface` | 1–9 | The app says out loud when a backup is failing, pending, or absent. Read-only: nothing in 3a can overwrite configuration. |
| **3b — Resolution surfaces** | `lane/backup-resolution` | 10–15 | Conflict dialog, diff summary, revision-history restore, device naming. Every destructive action lives here. |

3b depends on 3a being merged. Do not start 3b until Daniel has merged 3a.

---

## Global Constraints

Copied from the spec and from decisions taken 21 Aug 2026. Every task's
requirements implicitly include this section.

1. **No new runtime dependencies.** Runtime deps stay `http`,
   `shared_preferences`, `logging`, `cupertino_icons`, `crypto`. Date and time
   formatting is hand-rolled; **do not add `intl`.**
2. **No backward compatibility.** Pre-release, no users, no deployed data. A
   `backup_log` value that does not parse is discarded, not migrated.
3. **No modal dialogs raised by the engine.** A blocking dialog during a live
   service is unacceptable. Every condition surfaces on the pill; the operator
   opens the resolution UI when they choose. The only dialogs are ones the
   operator opened themselves.
4. **Failure outranks agreement, always.** The five-state precedence table is
   evaluated in order, first match wins. An implementation that checks "hash
   equals durable head" before "active failure" shows green while the
   credentials are dead — the exact bug this surface exists to prevent.
5. **Green means the current local state is known to exist durably at the
   target** — not that something recently succeeded. A pull success never
   clears a failed push, a conflict, or dirty state.
6. **The pill is always clickable, in every state,** including green.
7. **Copy strings are exact.** Where this plan gives a string literal, use it
   verbatim. Copy is a spec surface at Tier 3.
8. **`centerTitle: false` is set explicitly** on the AppBar. It left-aligns
   today only because `_getEffectiveCenterTitle` returns `actions.length < 2`
   and this AppBar has four entries — an accident of the current action count.
9. **In production, Phase 3 ships with no backup target.** Drive lands in
   Phase 4. The pill reads grey "Not backed up" and the scheduler never
   starts. A mock-backed controller is available behind
   `--dart-define=BACKUP_MOCK=true`, matching the existing `MOCK_RIG` pattern
   in `device_config_store.dart:23`. **Never run the app against
   `MockBackupTarget` in a build a human might use for real** — an in-memory
   store that evaporates on quit would let the pill go green over nothing.
10. **`flutter analyze` must be clean and the full `flutter test` green at the
    end of every task.** Baseline as of this plan: `No issues found!` and
    `522 tests passed`.

---

## Deviations from the spec, decided before writing this plan

Recorded here because reviewers should attack them directly.

| # | Spec says | This plan does | Why |
|---|---|---|---|
| D1 | "The active condition is … stored outside the historical ring so eviction can never remove it." | The active condition is held **in memory** on `BackupController` and is **not persisted**. History is persisted. | What the requirement protects against is *eviction*, and a separate in-memory field satisfies that. Persisting it would leave a red "Sign-in expired" pill across a restart that no completed operation has re-proved — a stale claim, in a surface built to stop stale claims. On restart the pill falls back to head/dirty facts until the first operation returns. |
| D2 | "Dirty — whether the local canonical hash differs from the durable head", and "3 changes pending". | Dirty is computed from the **hash**. The number comes from the mutation generation counter and is shown **only when the hash also differs**. | `OperatorStore.saveActiveId` calls `notify()` (`operator_store.dart:47-55`), so switching operator bumps the generation without changing bundle content. Counting alone would flash amber on every operator switch. Hash alone has no number to show. |
| D3 | "Widget tests — all five pill states; tappable in each; header pins; timestamp ladder boundaries; width cap with a pathological message." | The **derivation** and the **time ladder** are pure functions with Class 1 tests. The pill and popover get **one thin Class 2 wiring test each** and screenshots for everything visual. | `docs/learned/verification.md` says "this file wins where they differ", classes layout and chrome as Class 3 (screenshots, no unit tests), and names "re-running a logic matrix through `pumpWidget`" an anti-pattern. |
| D4 | Phase 3 is listed as "Status surface — pill, popover, log, conflict UI, revision-history picker", implying UI work. | Lane 3b adds **three public methods to `BackupService`** (`adoptRemote`, `keepLocalAsNewRevision`, `restoreRevision`). | The spec's three conflict actions have no engine path today: `push()` refuses outright when `head.id != pointer.revisionId` (`backup_service.dart:274`), and there is no public adopt or restore. The buttons cannot exist without them. |
| D5 | Silent on what happens after restoring an older revision. | Restore applies the old revision **and immediately pushes it as a new revision parented on the current head**. | Decided by Daniel, 21 Aug 2026. Restore-and-stop leaves the pointer on an ancestor of the head, which the next pull classifies as a non-descendant divergence — the operator would get "Needs review" seconds after a restore they just performed deliberately. |

---

## File Structure

**Lane 3a — created**

| File | Responsibility |
|---|---|
| `lib/services/backup/relative_time.dart` | Two pure formatters: `relativeAge` (popover ladder) and `compactAge` (pill). No `intl`. |
| `lib/services/backup/backup_status.dart` | The three-fact model and the pure five-state derivation, with all pill copy. |
| `lib/services/backup/backup_log.dart` | `BackupLogEntry` + the persisted, fingerprint-collapsing, triple-bounded log. |
| `lib/services/backup/backup_controller.dart` | The one owner. Wires service + scheduler + log + mutation notifier into `ValueListenable<BackupStatus>`; implements `WidgetsBindingObserver`. |
| `lib/widgets/backup/backup_status_pill.dart` | The AppBar pill. Presentation only; reads the controller. |
| `lib/widgets/backup/backup_log_popover.dart` | The popover: fixed header, scrollable history, dismiss controls. |

**Lane 3a — modified**

| File | Change |
|---|---|
| `lib/services/backup/restore_journal.dart:18-40` | Split `_fixedKeys` into public `dataKeys` (the eight stores) and engine bookkeeping, so `localIsPristine` has one authority to read. |
| `lib/services/config_bundle.dart` | Add `static Future<bool> localIsPristine()`. |
| `lib/widgets/multi_device_control_page.dart:32-130, :466-520` | Own a `BackupController`; add `centerTitle: false` and the pill as `AppBar.title`. |

**Lane 3b — created**

| File | Responsibility |
|---|---|
| `lib/services/backup/bundle_diff.dart` | Section-by-section difference counts between two bundle JSON documents. |
| `lib/services/backup/device_label.dart` | Candidate computation, the rejection rules, and the persisted label. |
| `lib/widgets/backup/conflict_dialog.dart` | Non-modal conflict resolution with the three actions and per-revision suppression. |
| `lib/widgets/backup/revision_history_sheet.dart` | The revision list, preview and restore. |

**Lane 3b — modified**

| File | Change |
|---|---|
| `lib/services/backup/backup_service.dart` | Add `adoptRemote`, `keepLocalAsNewRevision`, `restoreRevision`, and a `force` path on `_applyRevision`. |
| `lib/services/backup/backup_controller.dart` | Route resolution outcomes; persist per-revision suppression. |
| `lib/widgets/settings_dialog.dart:445-460` | A "Backup" section: device name field and revision history. |

**New persisted keys — the Tier 3 surface**

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `backup_log` | String (JSON array) | `BackupLog` | Bounded fault/success history. |
| `backup_last_success_at` | String (ISO-8601 UTC) | `BackupController` | When this machine's configuration was last confirmed stored at the target. |
| `backup_device_label` | String | `DeviceLabel` (3b) | Operator-declared machine name. |
| `backup_conflict_suppressed` | String (revision id) | `BackupController` (3b) | The remote revision the operator chose to decide later about. |

All four are added to `RestoreJournal` engine keys in Task 3 and Task 14 so a
rolled-back import cannot strand them.

---

# Lane 3a — Status surface

Open the lane before Task 1:

```bash
git worktree add .worktrees/status-surface -b lane/status-surface
cd .worktrees/status-surface
flutter analyze    # expect: No issues found!
flutter test       # expect: All tests passed! (522)
```

---

### Task 1: The time ladders

**Test-policy class:** 1 trust contract — per `docs/learned/verification.md`.
Boundary arithmetic that silently rounds the wrong way makes the popover claim
a failure happened "3 hours ago" when it happened yesterday. Pure Dart, no
widget mount.

**Files:**
- Create: `lib/services/backup/relative_time.dart`
- Test: `test/backup/relative_time_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `String relativeAge(DateTime then, DateTime now)` and
  `String compactAge(DateTime then, DateTime now)`.

- [ ] **Step 1: Implement**

```dart
/// Human-readable ages, hand-rolled because this project's dependency list is
/// deliberately thin and `intl` would be a runtime dependency bought for four
/// strings.
///
/// Two ladders, because the two surfaces have different budgets: the popover
/// can afford "20 minutes ago", the AppBar pill cannot.
library;

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _clock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The popover ladder, per the spec: under 1 h → "20 minutes ago"; under 24 h
/// → "3 hours ago"; under 7 d → "Sunday 9:42 AM"; older → "11 Aug, 9:42 AM".
///
/// A [then] in the future reads "just now" rather than a negative age. Two
/// machines with skewed clocks are a real case here, and "in -3 minutes" is
/// worse than a small lie.
String relativeAge(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.isNegative || d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) {
    return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  }
  if (d.inHours < 24) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  if (d.inDays < 7) return '${_weekdays[then.weekday - 1]} ${_clock(then)}';
  return '${then.day} ${_months[then.month - 1]}, ${_clock(then)}';
}

/// The pill ladder. Same boundaries, fewer characters, because this sits in an
/// AppBar next to four other actions.
String compactAge(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.isNegative || d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return 'on ${then.day} ${_months[then.month - 1]}';
}
```

- [ ] **Step 2: Write the behavioral test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/relative_time.dart';

void main() {
  // Sunday 9:42 AM, so the weekday branch has a name worth asserting on.
  final now = DateTime(2026, 8, 16, 9, 42);

  group('relativeAge', () {
    test('under a minute is "just now"', () {
      expect(relativeAge(now.subtract(const Duration(seconds: 59)), now),
          'just now');
    });

    test('a future timestamp reads "just now", never a negative age', () {
      expect(relativeAge(now.add(const Duration(minutes: 5)), now), 'just now');
    });

    test('exactly one minute crosses into the minutes ladder, singular', () {
      expect(relativeAge(now.subtract(const Duration(seconds: 60)), now),
          '1 minute ago');
    });

    test('59 minutes stays in minutes', () {
      expect(relativeAge(now.subtract(const Duration(minutes: 59)), now),
          '59 minutes ago');
    });

    test('exactly 60 minutes crosses into hours, singular', () {
      expect(relativeAge(now.subtract(const Duration(minutes: 60)), now),
          '1 hour ago');
    });

    test('23h59m stays in hours', () {
      expect(
          relativeAge(
              now.subtract(const Duration(hours: 23, minutes: 59)), now),
          '23 hours ago');
    });

    test('exactly 24 hours crosses into the weekday ladder', () {
      expect(relativeAge(now.subtract(const Duration(hours: 24)), now),
          'Saturday 9:42 AM');
    });

    test('6d23h stays on the weekday ladder', () {
      expect(
          relativeAge(now.subtract(const Duration(days: 6, hours: 23)), now),
          'Sunday 10:42 AM');
    });

    test('exactly 7 days crosses to the absolute date', () {
      expect(relativeAge(now.subtract(const Duration(days: 7)), now),
          '9 Aug, 9:42 AM');
    });

    test('midnight and noon render as 12, not 0', () {
      expect(relativeAge(DateTime(2026, 8, 1, 0, 5), now), '1 Aug, 12:05 AM');
      expect(relativeAge(DateTime(2026, 8, 1, 12, 5), now), '1 Aug, 12:05 PM');
    });
  });

  group('compactAge', () {
    test('ladders at the same boundaries in fewer characters', () {
      expect(compactAge(now.subtract(const Duration(seconds: 59)), now),
          'just now');
      expect(
          compactAge(now.subtract(const Duration(minutes: 59)), now), '59m ago');
      expect(compactAge(now.subtract(const Duration(minutes: 60)), now), '1h ago');
      expect(compactAge(now.subtract(const Duration(hours: 23)), now), '23h ago');
      expect(compactAge(now.subtract(const Duration(hours: 24)), now), '1d ago');
      expect(compactAge(now.subtract(const Duration(days: 6)), now), '6d ago');
      expect(compactAge(now.subtract(const Duration(days: 7)), now), 'on 9 Aug');
    });
  });
}
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/relative_time_test.dart`
Expected: `All tests passed!` (13 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/relative_time.dart test/backup/relative_time_test.dart
git commit -m "feat(backup): relative and compact age ladders"
```

---

### Task 2: The three-fact status model and its derivation

**Test-policy class:** 1 trust contract. This is the function that decides
whether the operator sees green while the credentials are dead. Pure Dart —
mounting a widget to test a switch statement is the anti-pattern the policy
names by name.

**Files:**
- Create: `lib/services/backup/backup_status.dart`
- Test: `test/backup/backup_status_test.dart`

**Interfaces:**
- Consumes: `AppFault` (`app_fault.dart`), `compactAge` (Task 1).
- Produces: `enum BackupPillState { failing, needsReview, notBackedUp, pending, backedUp }`;
  `class BackupStatus` with fields `activeCondition`, `hasDurableHead`,
  `isDirty`, `pendingCount`, `lastSuccessAt`, `configured`; getter
  `BackupPillState get state`; `String label(DateTime now)`;
  `BackupStatus copyWith({...})`.

- [ ] **Step 1: Implement**

```dart
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
    if (condition != null && condition.kind != conflictKind) {
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
    'unknown': 'Backup failing',
  };

  String label(DateTime now) {
    switch (state) {
      case BackupPillState.failing:
        return failureLabels[activeCondition!.kind] ?? 'Backup failing';
      case BackupPillState.needsReview:
        return 'Needs review';
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
    bool? configured,
  }) =>
      BackupStatus(
        activeCondition:
            clearCondition ? null : (activeCondition ?? this.activeCondition),
        hasDurableHead: hasDurableHead ?? this.hasDurableHead,
        isDirty: isDirty ?? this.isDirty,
        pendingCount: pendingCount ?? this.pendingCount,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
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
```

- [ ] **Step 2: Write the behavioral test**

```dart
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

  test('a conflict does not hide a concurrent hard failure', () {
    // Precedence, not recency: red outranks amber whichever arrived last.
    final s = backedUp.copyWith(activeCondition: fault(BackupFailureKind.storageFull));
    expect(s.state, BackupPillState.failing);
    expect(s.label(now), 'Drive full');
  });

  test('every backup failure kind has copy that is not the fallback', () {
    for (final kind in BackupFailureKind.values) {
      if (kind == BackupFailureKind.conflict) continue;
      expect(BackupStatus.failureLabels[kind.name], isNotNull,
          reason: '${kind.name} has no pill copy');
    }
  });

  test('equal statuses compare equal so the AppBar does not rebuild', () {
    expect(backedUp.copyWith(isDirty: true), backedUp.copyWith(isDirty: true));
    expect(backedUp.copyWith(isDirty: true) == backedUp, isFalse);
  });
}
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/backup_status_test.dart`
Expected: `All tests passed!` (12 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/backup_status.dart test/backup/backup_status_test.dart
git commit -m "feat(backup): three-fact status model with ordered precedence"
```

---

### Task 3: The bounded, fingerprint-collapsing log

**Test-policy class:** 1 trust contract. This is a **new persisted shape** and
the thing that decides which failure the operator still sees an hour later. A
collapse key that does not collapse fills the cap with retry noise and evicts
the auth failure that mattered.

**Files:**
- Create: `lib/services/backup/backup_log.dart`
- Modify: `lib/services/backup/restore_journal.dart:18-40`
- Test: `test/backup/backup_log_test.dart`

**Interfaces:**
- Consumes: `AppFault` and its existing `fingerprint` getter
  (`app_fault.dart:90`) — `'${domain}/$kind/${operation ?? "-"}/${targetIdentity ?? "-"}'`.
- Produces: `class BackupLogEntry` (fields `fingerprint`, `domain`, `kind`,
  `message`, `lastDetail`, `firstSeen`, `lastSeen`, `count`, `dismissed`,
  `isFailure`; `toJson()` / `fromJson()`); `class BackupLog` with
  `ValueNotifier<List<BackupLogEntry>> entries`, `Future<void> load()`,
  `Future<void> recordFault(AppFault)`,
  `Future<void> recordSuccess({required String operation, required String kind, required String message, String? targetIdentity})`,
  `Future<void> dismiss(String fingerprint)`; constants `key`, `maxRows`,
  `maxAge`, `maxBytes`, `maxTextChars`.

- [ ] **Step 1: Implement the log**

```dart
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
```

- [ ] **Step 2: Give `RestoreJournal` a public data-key list**

The pristine check (Task 4) and the log both need to know which keys are
bundle-owned. There is already one list; make it the only one rather than
adding a second. Replace `restore_journal.dart:18-40` with:

```dart
  /// The eight stores' keys — the configuration itself.
  static const dataKeys = <String>[
    'positions',
    'people',
    'services',
    'height_ranges',
    'operators',
    'active_operator_id',
    'roland_ip',
    'panasonic_cameras',
  ];

  /// Per-device keys, one per connected device, enumerated by prefix.
  static const dataPrefixes = <String>['preset_names_', 'item_visibility_'];

  /// Engine bookkeeping. Restoring stores without these would leave the
  /// generation ahead of the data, so isDirty would lie and the next push
  /// would surface a phantom conflict.
  static const engineKeys = <String>[
    ConfigMutationNotifier.generationKey,
    ConfigMutationNotifier.syncedKey,
    BackupPointer.revisionKey,
    BackupPointer.hashKey,
    BackupPointer.targetKey,
    BackupLog.lastSuccessKey,
  ];

  static bool isJournalled(String k) =>
      dataKeys.contains(k) ||
      engineKeys.contains(k) ||
      dataPrefixes.any(k.startsWith);
```

Add `import 'backup_log.dart';` to `restore_journal.dart`, and add the
last-success key to `backup_log.dart` alongside the log's own key — it is
written by the controller but journalled with the rest of the engine state:

```dart
  /// When this machine's configuration was last confirmed stored at the
  /// target. Journalled with the engine keys: a rolled-back import that left
  /// this behind would date a restored configuration by a backup it never had.
  static const String lastSuccessKey = 'backup_last_success_at';
```

**`backup_log` itself is deliberately NOT journalled.** A rollback restores
configuration; it must not erase the record of the failure that caused it.

- [ ] **Step 3: Write the behavioral test**

```dart
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

  test('the auth failure survives a retry storm that would evict it', () async {
    final log = newLog();
    await log.recordFault(AppFault.backup(
        BackupFailureKind.authExpired, 'Sign in again.',
        operation: 'pull', targetIdentity: 'drive:folder-1'));
    for (var i = 0; i < 500; i++) {
      clock = clock.add(const Duration(seconds: 30));
      await log.recordFault(socketTimeout(i));
    }
    expect(
      log.entries.value.map((e) => e.kind),
      contains('authExpired'),
    );
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
```

- [ ] **Step 4: Run the owning test file and the journal's**

Run: `flutter test test/backup/backup_log_test.dart test/backup/restore_journal_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_log.dart \
        lib/services/backup/restore_journal.dart \
        test/backup/backup_log_test.dart
git commit -m "feat(backup): bounded fault log collapsing on structured fingerprints"
```

---

### Task 4: Production `localIsPristine`

**Test-policy class:** 1 trust contract. `BackupService` consults this exactly
where it decides whether to adopt a remote snapshot without asking
(`backup_service.dart:130-143`). A false positive silently replaces an hour of
typing.

**Files:**
- Modify: `lib/services/config_bundle.dart` (add a static method near
  `fromStores`)
- Test: `test/config_bundle_test.dart` (append a group)

**Interfaces:**
- Consumes: `RestoreJournal.dataKeys`, `RestoreJournal.dataPrefixes` (Task 3).
- Produces: `static Future<bool> ConfigBundle.localIsPristine()`.

- [ ] **Step 1: Implement**

```dart
  /// Whether this machine holds no configuration of its own.
  ///
  /// Presence, not emptiness. Three of the eight stores return **defaults**
  /// rather than nothing when unwritten — `OperatorProfile.defaultProfile`,
  /// `DeviceConfigStore.defaultRolandIp`, `defaultCameras` — so "everything
  /// reads empty" is never true on a real machine and an emptiness check would
  /// classify every install as having data. Equality-against-defaults is the
  /// other tempting answer and it is worse: under
  /// `--dart-define=MOCK_RIG=true`, `loadRolandIp` ignores SharedPreferences
  /// entirely (`device_config_store.dart:43-47`), so a machine with saved
  /// device config would compare equal to the mock defaults and read pristine.
  ///
  /// A key that exists means somebody wrote it. That is the whole test, and it
  /// errs toward asking rather than overwriting: a store written and then
  /// cleared reads as not-pristine, which costs one adoption question and
  /// risks nothing.
  static Future<bool> localIsPristine() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (RestoreJournal.dataKeys.contains(key)) return false;
      if (RestoreJournal.dataPrefixes.any(key.startsWith)) return false;
    }
    return true;
  }
```

- [ ] **Step 2: Write the behavioral test**

```dart
  group('localIsPristine', () {
    test('a machine that has never been configured is pristine', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ConfigBundle.localIsPristine(), isTrue);
    });

    test('engine bookkeeping alone does not count as configuration', () async {
      SharedPreferences.setMockInitialValues({
        'backup_mutation_generation': 4,
        'backup_synced_generation': 4,
        'backup_source_revision': 'rev-1',
        'backup_log': '[]',
      });
      expect(await ConfigBundle.localIsPristine(), isTrue);
    });

    for (final key in RestoreJournal.dataKeys) {
      test('a written "$key" makes the machine non-pristine', () async {
        SharedPreferences.setMockInitialValues({key: '[]'});
        expect(await ConfigBundle.localIsPristine(), isFalse);
      });
    }

    test('a single preset name makes the machine non-pristine', () async {
      SharedPreferences.setMockInitialValues({
        'preset_names_10.0.1.10': '{"1":"Pulpit"}',
      });
      expect(await ConfigBundle.localIsPristine(), isFalse);
    });

    test('a single visibility entry makes the machine non-pristine', () async {
      SharedPreferences.setMockInitialValues({
        'item_visibility_roland_10.0.1.20': '{"1":"hidden"}',
      });
      expect(await ConfigBundle.localIsPristine(), isFalse);
    });

    test('a real save through any store ends pristineness', () async {
      SharedPreferences.setMockInitialValues({});
      await PositionStore.saveAll(
          [Position(id: 'p1', name: 'Pulpit')]);
      expect(await ConfigBundle.localIsPristine(), isFalse);
    });
  });
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/config_bundle_test.dart`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/services/config_bundle.dart test/config_bundle_test.dart
git commit -m "feat(backup): production emptiness check across the eight stores"
```

---

### Task 5: `BackupController` — the one owner

**Test-policy class:** 1 trust contract. Every rule in Global Constraints 4 and
5 lives here: which condition wins, and what a success is allowed to clear. A
mistake makes the pill lie, which is the failure this phase exists to remove.

The matrix is tested through `handleEvent`, a plain method taking the same
objects `BackupScheduler.events` emits — cheap, deterministic, no timers. **One
end-to-end test drives a real `BackupService` and `BackupScheduler` over
`MockBackupTarget`** so the matrix tests are not vacuous: it proves the
subscription actually fires.

**Files:**
- Create: `lib/services/backup/backup_controller.dart`
- Test: `test/backup/backup_controller_test.dart`

**Interfaces:**
- Consumes: `BackupService` (`pull()`, `push()`, `targetIdentity`),
  `BackupScheduler` (`events`, `start()`, `stop()`, `onAppStart()`,
  `onForeground()`, `flushPending()`), `PullResult` / `PullOutcome`,
  `PushResult` / `PushOutcome`, `BackupStatus` (Task 2), `BackupLog` (Task 3),
  `ConfigBundle.localIsPristine` (Task 4).
- Produces: `class BackupController with WidgetsBindingObserver`;
  `ValueNotifier<BackupStatus> status`; `BackupLog log`;
  `BackupRevision? conflictRevision`; `bool get canRetry`;
  `Future<void> start()`, `Future<void> retryNow()`,
  `Future<void> dismiss(String fingerprint)`, `Future<void> dispose()`,
  `@visibleForTesting Future<void> handleEvent(Object event)`;
  factories `BackupController.disabled()`, `BackupController.forService(...)`,
  `BackupController.forEnvironment()`.

- [ ] **Step 1: Implement**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config_bundle.dart';
import 'app_fault.dart';
import 'backup_log.dart';
import 'backup_pointer.dart';
import 'backup_revision.dart';
import 'backup_scheduler.dart';
import 'backup_service.dart';
import 'backup_status.dart';
import 'canonical_json.dart';
import 'config_mutation_notifier.dart';
import 'mock/mock_backup_target.dart';

/// The only thing that reads the engine and the only thing the UI reads.
///
/// `BackupScheduler` already emits every result and fault onto a stream. Until
/// now nothing listened, which made the whole engine a silent failure of the
/// exact kind this app is known for.
class BackupController with WidgetsBindingObserver {
  /// Set via `flutter run --dart-define=BACKUP_MOCK=true`. Drives the full
  /// surface against an in-memory target so the states can be seen and
  /// screenshotted before Drive exists.
  ///
  /// **Never ship a build with this set.** An in-memory store evaporates on
  /// quit, so a green pill over it is a lie.
  static const bool useMockTarget = bool.fromEnvironment('BACKUP_MOCK');

  static const String _conflictKey = 'conflict';

  final BackupService? service;
  final BackupScheduler? _scheduler;
  final BackupLog log;
  final DateTime Function() _now;

  /// Insertion-ordered, so the most recently raised hard failure is last.
  final Map<String, AppFault> _conditions = <String, AppFault>{};

  StreamSubscription<Object>? _events;
  StreamSubscription<int>? _mutations;

  final ValueNotifier<BackupStatus> status =
      ValueNotifier<BackupStatus>(const BackupStatus());

  /// The remote revision behind the current conflict, for lane 3b's dialog.
  BackupRevision? conflictRevision;

  BackupController._({
    required this.service,
    required BackupScheduler? scheduler,
    required this.log,
    required DateTime Function() now,
  })  : _scheduler = scheduler,
        _now = now;

  /// No target. Phase 3's production configuration: the pill reads
  /// "Not backed up" and nothing ever contacts anything.
  factory BackupController.disabled({BackupLog? log, DateTime Function()? now}) =>
      BackupController._(
        service: null,
        scheduler: null,
        log: log ?? BackupLog(now: now),
        now: now ?? DateTime.now,
      );

  factory BackupController.forService(
    BackupService service, {
    BackupScheduler? scheduler,
    BackupLog? log,
    DateTime Function()? now,
  }) =>
      BackupController._(
        service: service,
        scheduler: scheduler ?? BackupScheduler(service: service),
        log: log ?? BackupLog(now: now),
        now: now ?? DateTime.now,
      );

  factory BackupController.forEnvironment() {
    if (!useMockTarget) return BackupController.disabled();
    return BackupController.forService(BackupService(
      target: MockBackupTarget(),
      targetIdentity: 'mock:in-memory',
      deviceLabel: () async => 'This machine',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    ));
  }

  bool get canRetry => _scheduler != null;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await log.load();
    await _refreshFacts();

    final scheduler = _scheduler;
    if (scheduler == null) return;

    _events = scheduler.events.listen((event) => unawaited(handleEvent(event)));
    _mutations = ConfigMutationNotifier.instance.onMutated
        .listen((_) => unawaited(_refreshFacts()));
    scheduler.start();
    await scheduler.onAppStart();
  }

  /// Folds one scheduler event into the status. Public for tests: the matrix
  /// here is ordinary logic and does not need timers to exercise.
  @visibleForTesting
  Future<void> handleEvent(Object event) async {
    if (event is AppFault) {
      await log.recordFault(event);
      _raise(event);
    } else if (event is PullResult) {
      await _onPull(event);
    } else if (event is PushResult) {
      await _onPush(event);
    }
    _applyConditions();
    await _refreshFacts();
  }

  Future<void> _onPull(PullResult result) async {
    switch (result.outcome) {
      case PullOutcome.nothingToDo:
      case PullOutcome.applied:
      case PullOutcome.adopted:
      case PullOutcome.rebased:
        // A clean round trip clears this operation's failure AND any
        // divergence: both have just been disproved. It does NOT clear a
        // failed push — that condition is keyed separately.
        _conditions.remove('pull');
        _conditions.remove(_conflictKey);
        conflictRevision = null;
        if (result.outcome == PullOutcome.applied ||
            result.outcome == PullOutcome.adopted) {
          await log.recordSuccess(
            operation: 'pull',
            kind: 'restored',
            message: 'Configuration restored from the backup.',
            targetIdentity: service?.targetIdentity,
          );
        }
        await _markConfirmedStored();
      case PullOutcome.targetEmptied:
        _raise(AppFault.backup(
          BackupFailureKind.targetMissing,
          'The backup this device was synced to no longer exists.',
          operation: 'pull',
          targetIdentity: service?.targetIdentity,
        ));
        await log.recordFault(_conditions['pull']!);
      case PullOutcome.conflict:
        await _raiseConflict(result.revision,
            'Another machine saved a different configuration.');
      case PullOutcome.needsAdoptionChoice:
        await _raiseConflict(result.revision,
            'This device has configuration of its own and has never been backed up.');
    }
  }

  Future<void> _onPush(PushResult result) async {
    switch (result.outcome) {
      case PushOutcome.uploaded:
        _conditions.remove('push');
        _conditions.remove(_conflictKey);
        conflictRevision = null;
        await log.recordSuccess(
          operation: 'push',
          kind: 'uploaded',
          message: 'Configuration backed up.',
          targetIdentity: service?.targetIdentity,
        );
        await _markConfirmedStored();
      case PushOutcome.noOp:
        // Nothing changed, so nothing is logged — but the round trip did
        // prove the bytes are there.
        _conditions.remove('push');
        _conditions.remove(_conflictKey);
        conflictRevision = null;
        await _markConfirmedStored();
      case PushOutcome.conflict:
        await _raiseConflict(result.remoteRevision,
            'Another machine saved a different configuration.');
      case PushOutcome.forked:
        await _raiseConflict(
            result.siblings?.first,
            'Another machine saved a different configuration at the same '
            'moment. Both copies were kept.');
    }
  }

  void _raise(AppFault fault) {
    final key = fault.kind == BackupStatus.conflictKind
        ? _conflictKey
        : (fault.operation ?? 'unknown');
    // Remove before insert so insertion order tracks recency.
    _conditions.remove(key);
    _conditions[key] = fault;
  }

  Future<void> _raiseConflict(BackupRevision? revision, String message) async {
    conflictRevision = revision;
    final fault = AppFault.backup(
      BackupFailureKind.conflict,
      message,
      operation: 'resolve',
      targetIdentity: service?.targetIdentity,
    );
    _raise(fault);
    await log.recordFault(fault);
  }

  void _applyConditions() {
    final hard = [
      for (final entry in _conditions.entries)
        if (entry.key != _conflictKey) entry.value
    ];
    final chosen = hard.isNotEmpty ? hard.last : _conditions[_conflictKey];
    status.value = chosen == null
        ? status.value.copyWith(clearCondition: true)
        : status.value.copyWith(activeCondition: chosen);
  }

  /// Records "this machine's configuration is stored at the target" — and only
  /// when that is actually true. Any successful operation calls it; the
  /// pointer check decides whether it means anything.
  Future<void> _markConfirmedStored() async {
    final pointer = await BackupPointer.load();
    final localHash = canonicalHash((await ConfigBundle.fromStores()).toJson());
    if (!pointer.isCleanAgainst(localHash)) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        BackupLog.lastSuccessKey, _now().toUtc().toIso8601String())) {
      await prefs.reload();
    }
  }

  Future<void> _refreshFacts() async {
    final pointer = await BackupPointer.load();
    final localHash = canonicalHash((await ConfigBundle.fromStores()).toJson());
    final generation = await ConfigMutationNotifier.instance.generation();
    final synced = await ConfigMutationNotifier.instance.syncedGeneration();
    final prefs = await SharedPreferences.getInstance();
    final lastRaw = prefs.getString(BackupLog.lastSuccessKey);

    status.value = status.value.copyWith(
      configured: service != null,
      hasDurableHead: pointer.isProvenanced,
      // Hash, not the counter: switching operator calls notify() without
      // changing bundle content, and a count-driven pill would flash amber
      // every time the operator changes.
      isDirty: pointer.isProvenanced && pointer.recordedHash != localHash,
      pendingCount: (generation - synced).clamp(0, 1 << 30),
      lastSuccessAt: lastRaw == null ? null : DateTime.parse(lastRaw).toLocal(),
    );
  }

  Future<void> retryNow() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    await scheduler.onForeground();
  }

  Future<void> dismiss(String fingerprint) => log.dismiss(fingerprint);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(scheduler.onForeground());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Best-effort. Correctness rests on the persisted generation, not on
        // this completing — iOS suspends Dart within seconds of a background.
        unawaited(scheduler.flushPending());
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _events?.cancel();
    await _mutations?.cancel();
    await _scheduler?.stop();
    // `status` and `log.entries` are deliberately NOT disposed. They outlive
    // any one widget, tests tear down in an order that would otherwise use
    // them after disposal, and two undisposed ValueNotifiers on an
    // app-lifetime object leak nothing that matters.
  }
}
```

- [ ] **Step 2: Write the behavioral test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_log.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBackupTarget target;
  late BackupService service;
  late BackupController controller;
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 8, 16, 9, 0);
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
      log: BackupLog(now: () => clock),
      now: () => clock,
    );
  });

  tearDown(() => controller.dispose());

  AppFault offline(String operation) => AppFault.backup(
      BackupFailureKind.offline, 'Could not reach the backup.',
      operation: operation, targetIdentity: 'mock:test');

  group('the fold', () {
    test('a pull success does NOT clear a failed push', () async {
      await controller.handleEvent(offline('push'));
      expect(controller.status.value.state, BackupPillState.failing);

      await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

      expect(controller.status.value.state, BackupPillState.failing,
          reason: 'the edits still exist nowhere but this machine');
      expect(controller.status.value.activeCondition!.operation, 'push');
    });

    test("a push success clears the push's own failure", () async {
      await controller.handleEvent(offline('push'));
      await controller.handleEvent(const PushResult(PushOutcome.uploaded));
      expect(controller.status.value.activeCondition, isNull);
    });

    test('a hard failure outranks a conflict whichever arrived last', () async {
      await controller.handleEvent(const PullResult(PullOutcome.conflict));
      expect(controller.status.value.state, BackupPillState.needsReview);

      await controller.handleEvent(offline('pull'));
      expect(controller.status.value.state, BackupPillState.failing);
    });

    test('a clean round trip clears a divergence', () async {
      await controller.handleEvent(const PullResult(PullOutcome.conflict));
      expect(controller.conflictRevision, isNull); // no revision on this result
      await controller.handleEvent(const PullResult(PullOutcome.applied));
      expect(controller.status.value.state, isNot(BackupPillState.needsReview));
    });

    test('an emptied target raises targetMissing, never silence', () async {
      await controller.handleEvent(const PullResult(PullOutcome.targetEmptied));
      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.label(clock), 'Backup missing');
    });

    test('a fork tells the operator both copies were kept', () async {
      await controller.handleEvent(const PushResult(PushOutcome.forked));
      expect(controller.status.value.state, BackupPillState.needsReview);
      expect(controller.log.entries.value.first.message,
          contains('Both copies were kept'));
    });

    test('a retry storm collapses in the log but stays on the pill', () async {
      for (var i = 0; i < 20; i++) {
        clock = clock.add(const Duration(seconds: 30));
        await controller.handleEvent(offline('push'));
      }
      expect(controller.log.entries.value, hasLength(1));
      expect(controller.log.entries.value.single.count, 20);
      expect(controller.status.value.state, BackupPillState.failing);
    });
  });

  group('end to end, through the real scheduler', () {
    test('an edit is backed up and the pill goes green', () async {
      await controller.start();
      expect(controller.status.value.state, BackupPillState.notBackedUp);

      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await controller.retryNow();

      expect(target.revisions, hasLength(1));
      expect(controller.status.value.state, BackupPillState.backedUp);
      expect(controller.status.value.label(clock), 'Backed up just now');
    });

    test('a failing target paints the pill red through the subscription',
        () async {
      await controller.start();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      target.failNextWith(AppFault.backup(
          BackupFailureKind.authExpired, 'Sign in again.',
          operation: 'pull', targetIdentity: 'mock:test'));

      await controller.retryNow();

      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.label(clock), 'Sign-in expired');
    });

    test('an edit that is not yet pushed reads amber with a count', () async {
      await controller.start();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await controller.retryNow();
      await PositionStore.saveAll([
        Position(id: 'p1', name: 'Pulpit'),
        Position(id: 'p2', name: 'Lectern'),
      ]);
      // The debounced push has not run.
      await Future<void>.delayed(Duration.zero);

      expect(controller.status.value.state, BackupPillState.pending);
      expect(controller.status.value.label(clock), '1 change pending');
    });

    test('switching operator does not turn the pill amber', () async {
      await controller.start();
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await controller.retryNow();
      expect(controller.status.value.state, BackupPillState.backedUp);

      await OperatorStore.saveActiveId('someone-else');
      await Future<void>.delayed(Duration.zero);

      expect(controller.status.value.state, BackupPillState.backedUp,
          reason: 'active operator is not bundle content');
    });
  });

  test('a disabled controller never contacts anything and reads grey',
      () async {
    final disabled = BackupController.disabled(now: () => clock);
    await disabled.start();
    expect(disabled.status.value.state, BackupPillState.notBackedUp);
    expect(disabled.canRetry, isFalse);
    await disabled.dispose();
  });
}
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/backup_controller_test.dart`
Expected: `All tests passed!` (12 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/backup_controller.dart \
        test/backup/backup_controller_test.dart
git commit -m "feat(backup): controller folding engine events into pill status"
```

---

### Task 6: The AppBar pill

**Test-policy class:** 3 presentation, with **one** Class 2 wiring test. The
five-state matrix is already covered as pure logic in Task 2; re-running it
through `pumpWidget` is the anti-pattern `docs/learned/verification.md` names.
The one test asserts the user-visible outcome: the pill shows the derived
label and tapping it opens the popover.

**Files:**
- Create: `lib/widgets/backup/backup_status_pill.dart`
- Test: `test/backup/backup_status_pill_test.dart`

**Interfaces:**
- Consumes: `BackupController.status`, `BackupStatus.label`,
  `showBackupLogPopover` (Task 7 — write Task 7 first if executing out of
  order; the import will not resolve otherwise).
- Produces: `class BackupStatusPill extends StatefulWidget` taking
  `{required BackupController controller}`.

- [ ] **Step 1: Implement**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_status.dart';
import 'backup_log_popover.dart';

/// The always-visible backup indicator, and the entry point to the log.
///
/// Visually a sibling of the Live/Demo chip: radius 12, `shade100` fill,
/// `shade800` bold 12 px label. Colour never carries the meaning alone — the
/// icon and the words do, so this reads correctly to an operator who cannot
/// distinguish amber from green under stage lighting.
class BackupStatusPill extends StatefulWidget {
  const BackupStatusPill({super.key, required this.controller});

  final BackupController controller;

  @override
  State<BackupStatusPill> createState() => _BackupStatusPillState();
}

class _BackupStatusPillState extends State<BackupStatusPill> {
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    // "Backed up just now" would otherwise still say "just now" an hour later:
    // the age is derived at build time and nothing else rebuilds this.
    _ageTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  static MaterialColor _swatch(BackupPillState state) => switch (state) {
        BackupPillState.failing => Colors.red,
        // Orange rather than Material amber: this AppBar already pairs
        // orange.shade100 with orange.shade800 for the Demo chip, and amber's
        // shade800 on shade100 is markedly weaker contrast.
        BackupPillState.needsReview => Colors.orange,
        BackupPillState.pending => Colors.orange,
        BackupPillState.notBackedUp => Colors.grey,
        BackupPillState.backedUp => Colors.green,
      };

  static IconData _icon(BackupPillState state) => switch (state) {
        BackupPillState.failing => Icons.error_outline,
        BackupPillState.needsReview => Icons.help_outline,
        BackupPillState.pending => Icons.cloud_upload_outlined,
        BackupPillState.notBackedUp => Icons.cloud_off_outlined,
        BackupPillState.backedUp => Icons.cloud_done_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackupStatus>(
      valueListenable: widget.controller.status,
      builder: (context, status, _) {
        final swatch = _swatch(status.state);
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: 'Backup status — tap for details',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              // Clickable in EVERY state, green included: the popover is the
              // log, and the log is useful when things are working.
              onTap: () => showBackupLogPopover(context, widget.controller),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: swatch.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon(status.state), size: 14, color: swatch.shade800),
                    const SizedBox(width: 6),
                    Text(
                      status.label(DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: swatch.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Write the one wiring test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/widgets/backup/backup_status_pill.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the derived label and opens the log when tapped',
      (tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    controller.status.value = const BackupStatus(
      configured: true,
      hasDurableHead: true,
      isDirty: true,
      pendingCount: 3,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: BackupStatusPill(controller: controller),
        ),
      ),
    ));

    expect(find.text('3 changes pending'), findsOneWidget);

    await tester.tap(find.text('3 changes pending'));
    await tester.pumpAndSettle();

    expect(find.text('Backup'), findsOneWidget); // the popover header
  });

  testWidgets('a red condition is still tappable', (tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    controller.status.value = BackupStatus(
      configured: true,
      hasDurableHead: true,
      activeCondition: AppFault.backup(
          BackupFailureKind.authExpired, 'Sign in again.',
          operation: 'pull'),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: BackupStatusPill(controller: controller),
        ),
      ),
    ));

    expect(find.text('Sign-in expired'), findsOneWidget);
    await tester.tap(find.text('Sign-in expired'));
    await tester.pumpAndSettle();
    expect(find.text('Backup'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/backup_status_pill_test.dart`
Expected: `All tests passed!` (2 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/backup/backup_status_pill.dart \
        test/backup/backup_status_pill_test.dart
git commit -m "feat(backup): AppBar status pill"
```

---

### Task 7: The log popover

**Test-policy class:** 3 presentation, with **one** Class 2 wiring test
covering the two behaviours that are not layout: the active condition is
pinned and cannot be dismissed, and dismissing a history row persists.

**Files:**
- Create: `lib/widgets/backup/backup_log_popover.dart`
- Test: `test/backup/backup_log_popover_test.dart`

**Interfaces:**
- Consumes: `BackupController` (`status`, `log`, `canRetry`, `retryNow`,
  `dismiss`), `BackupLogEntry`, `relativeAge` (Task 1).
- Produces: `Future<void> showBackupLogPopover(BuildContext context, BackupController controller)`.

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/material.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_log.dart';
import '../../services/backup/backup_status.dart';
import '../../services/backup/relative_time.dart';

const double _popoverWidth = 400;

/// Anchors the panel under [context]'s widget — the pill — and dismisses on a
/// tap outside. `showDialog` with a transparent barrier gives that dismissal
/// for free and traps focus correctly; a bare `Overlay` entry would need both
/// hand-written.
Future<void> showBackupLogPopover(
  BuildContext context,
  BackupController controller,
) {
  final anchor = context.findRenderObject() as RenderBox?;
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final origin = anchor == null
      ? Offset.zero
      : anchor.localToGlobal(anchor.size.bottomLeft(Offset.zero),
          ancestor: overlayBox);
  final maxLeft = (overlayBox.size.width - _popoverWidth - 8).clamp(8.0, 8.0e3);

  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => Stack(
      children: [
        Positioned(
          left: origin.dx.clamp(8.0, maxLeft),
          top: origin.dy + 8,
          width: _popoverWidth,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: _BackupLogPanel(controller: controller),
          ),
        ),
      ],
    ),
  );
}

class _BackupLogPanel extends StatelessWidget {
  const _BackupLogPanel({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackupStatus>(
      valueListenable: controller.status,
      builder: (context, status, _) {
        return ValueListenableBuilder<List<BackupLogEntry>>(
          valueListenable: controller.log.entries,
          builder: (context, entries, _) {
            final active = status.activeCondition;
            // The pinned row is shown once. While it is active it is filtered
            // out of history; when it clears it reappears there as an ordinary
            // dismissable row, so the recovery does not erase the evidence.
            final history = [
              for (final e in entries)
                if (e.fingerprint != active?.fingerprint) e
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, status),
                const Divider(height: 1),
                if (active != null)
                  _pinnedRow(context, active.message, active.kind),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: history.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nothing to report.',
                              style: TextStyle(color: Colors.black54)),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: history.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _historyRow(context, history[i]),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(BuildContext context, BackupStatus status) {
    final now = DateTime.now();
    final at = status.lastSuccessAt;
    final lines = <String>[
      at == null
          ? 'This configuration has never been backed up.'
          : 'Last backed up ${relativeAge(at, now)}.',
      if (status.isDirty && status.pendingCount > 0)
        '${status.pendingCount} change${status.pendingCount == 1 ? '' : 's'} not yet backed up.',
      if (!status.configured)
        'Google Drive sign-in arrives in a later update.',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Backup',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final line in lines)
                  Text(line,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          if (controller.canRetry)
            TextButton(
              onPressed: () => controller.retryNow(),
              child: const Text('Retry now'),
            ),
        ],
      ),
    );
  }

  /// No dismiss control, by design: an unresolved condition is not something
  /// the operator gets to mark as read.
  Widget _pinnedRow(BuildContext context, String message, String kind) =>
      Container(
        color: Colors.red.shade50,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: const TextStyle(fontSize: 13)),
                  Text(kind,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _historyRow(BuildContext context, BackupLogEntry entry) {
    final now = DateTime.now();
    final subtitle = StringBuffer(entry.kind)
      ..write(' · ')
      ..write(relativeAge(entry.lastSeen, now));
    if (entry.count > 1) subtitle.write(' · ${entry.count}×');

    return Opacity(
      opacity: entry.dismissed ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              entry.isFailure ? Icons.warning_amber_rounded : Icons.check,
              size: 16,
              color: entry.isFailure ? Colors.orange.shade800 : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Soft-wraps rather than clipping: the width cap is the
                  // constraint, not the message.
                  Text(entry.message, style: const TextStyle(fontSize: 13)),
                  Text(subtitle.toString(),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                  if (entry.lastDetail != null)
                    Text(entry.lastDetail!,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38)),
                ],
              ),
            ),
            if (!entry.dismissed)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Mark as read',
                onPressed: () => controller.dismiss(entry.fingerprint),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the one wiring test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/widgets/backup/backup_status_pill.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<BackupController> openPopover(WidgetTester tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    await controller.log.recordFault(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'push', targetIdentity: 'mock:test'));
    controller.status.value = const BackupStatus(configured: true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: BackupStatusPill(controller: controller),
        ),
      ),
    ));
    await tester.tap(find.byType(BackupStatusPill));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('a history row can be marked as read, and it sticks',
      (tester) async {
    final controller = await openPopover(tester);

    expect(find.text('Drive returned an error.'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark as read'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Mark as read'), findsNothing);
    expect(controller.log.entries.value.single.dismissed, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backup_log'), contains('"read":true'));
  });

  testWidgets('the active condition is pinned and has no dismiss control',
      (tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    final fault = AppFault.backup(
        BackupFailureKind.authExpired, 'Sign in again.',
        operation: 'pull', targetIdentity: 'mock:test');
    await controller.log.recordFault(fault);
    controller.status.value =
        BackupStatus(configured: true, activeCondition: fault);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: BackupStatusPill(controller: controller),
        ),
      ),
    ));
    await tester.tap(find.byType(BackupStatusPill));
    await tester.pumpAndSettle();

    // Shown once — pinned — and not as a dismissable history row.
    expect(find.text('Sign in again.'), findsOneWidget);
    expect(find.byTooltip('Mark as read'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the owning test files**

Run: `flutter test test/backup/backup_log_popover_test.dart test/backup/backup_status_pill_test.dart`
Expected: `All tests passed!` (4 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/backup/backup_log_popover.dart \
        test/backup/backup_log_popover_test.dart
git commit -m "feat(backup): log popover with pinned condition and dismissals"
```

---

### Task 8: Wire it into the app, with lifecycle

**Test-policy class:** 2 wiring. One thin test asserting the user-visible
outcome — the pill is in the AppBar and a foreground event reaches the
scheduler. Everything else here is layout, verified by screenshot in Task 9.

**Files:**
- Modify: `lib/widgets/multi_device_control_page.dart:25-31` (constructor),
  `:32-70` (state and `initState`), `:122-130` (`dispose`), `:396-399` and
  `:467-470` (both AppBars)
- Modify: `lib/services/backup/backup_controller.dart` (scenario knob)
- Test: `test/backup/backup_wiring_test.dart`

**Interfaces:**
- Consumes: `BackupController.forEnvironment()`, `BackupStatusPill`.
- Produces: `MultiDeviceControlPage({super.key, BackupController? backupController})`.

- [ ] **Step 1: Add the demo scenario knob to `BackupController`**

The pill has five states and only three of them are reachable by using the app
against an in-memory target. Without this, Task 9's screenshots cannot show red
or "Needs review", and `docs/learned/verification.md` is explicit that
presentation work is not done until the screenshots have been looked at.

Replace `BackupController.forEnvironment()` with:

```dart
  /// Which failure the mock target should stage, for demonstrating the
  /// surface before Drive exists: `ok`, `authExpired`, `offline`, `conflict`.
  /// Only read when [useMockTarget] is set.
  static const String mockScenario =
      String.fromEnvironment('BACKUP_SCENARIO', defaultValue: 'ok');

  factory BackupController.forEnvironment() {
    if (!useMockTarget) return BackupController.disabled();

    final target = MockBackupTarget();
    switch (mockScenario) {
      case 'authExpired':
        target.failNextWith(AppFault.backup(
            BackupFailureKind.authExpired, 'Sign in to Google again.',
            operation: 'pull', targetIdentity: 'mock:in-memory'));
      case 'offline':
        target.failNextWith(AppFault.backup(
            BackupFailureKind.offline, 'Could not reach Google Drive.',
            operation: 'pull', targetIdentity: 'mock:in-memory'));
      case 'conflict':
        // A revision from another machine that this one has no provenance
        // for, which pull classifies as a divergence.
        unawaited(target.put(
          '{"schemaVersion":1,"positions":[],"people":[],"services":[],'
          '"heightRanges":[],"presetNames":{},"visibilities":{}}',
          contentHash: 'staged',
          parentRevisionId: null,
          deviceLabel: "Daniel's iPad",
        ));
      default:
        break;
    }

    return BackupController.forService(BackupService(
      target: target,
      targetIdentity: 'mock:in-memory',
      deviceLabel: () async => 'This machine',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    ));
  }
```

- [ ] **Step 2: Own the controller on the page**

In `lib/widgets/multi_device_control_page.dart`, change the widget declaration
(`:25-31`) to accept an injected controller so tests do not need a real
scheduler:

```dart
class MultiDeviceControlPage extends StatefulWidget {
  const MultiDeviceControlPage({super.key, this.backupController});

  /// Injected by tests. Production passes nothing and gets
  /// [BackupController.forEnvironment], which is disabled unless
  /// `--dart-define=BACKUP_MOCK=true`.
  final BackupController? backupController;

  @override
  State<MultiDeviceControlPage> createState() =>
      _MultiDeviceControlPageState();
}
```

Add the field beside the other state (after `:55`, `List<HeightRange> _heightRanges = [];`):

```dart
  late final BackupController _backup;
```

In `initState` (`:58-66`), after `super.initState();`:

```dart
    // The controller registers itself as a WidgetsBindingObserver, so pull on
    // foreground and flush on background are its business, not this widget's.
    _backup = widget.backupController ?? BackupController.forEnvironment();
    unawaited(_backup.start());
```

In `dispose` (`:122-130`), before `super.dispose();`:

```dart
    unawaited(_backup.dispose());
```

Add `import 'dart:async';` and
`import '../services/backup/backup_controller.dart';` plus
`import 'backup/backup_status_pill.dart';` to the file's imports.

- [ ] **Step 3: Put the pill in both AppBars**

There are two. The disconnected-state `AppBar` at `:397` and the connected one
at `:468`. Both get the same two lines, immediately after `AppBar(`:

```dart
          centerTitle: false,
          title: BackupStatusPill(controller: _backup),
```

`centerTitle: false` is explicit per Global Constraint 8: the connected AppBar
left-aligns today only because it has four action entries, and dropping to one
would silently centre the pill.

- [ ] **Step 4: Write the one wiring test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/widgets/backup/backup_status_pill.dart';
import 'package:navigation_app/widgets/multi_device_control_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the pill is in the AppBar and the lifecycle reaches the engine',
      (tester) async {
    final target = MockBackupTarget();
    final service = BackupService(
      target: target,
      targetIdentity: 'mock:test',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    );
    final scheduler = BackupScheduler(
      service: service,
      debounce: const Duration(milliseconds: 1),
      sweepInterval: const Duration(days: 1),
      sleep: (_) async {},
    );
    final controller =
        BackupController.forService(service, scheduler: scheduler);

    await tester.pumpWidget(MaterialApp(
      home: MultiDeviceControlPage(backupController: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BackupStatusPill), findsOneWidget);
    expect(find.text('Not backed up'), findsOneWidget);

    final pullsAfterStart = scheduler.pullCount;

    // The real signal an operator produces by switching back to the app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(scheduler.pullCount, greaterThan(pullsAfterStart),
        reason: 'foregrounding must pull; a dead credential surfaces there');

    await controller.dispose();
  });
}
```

- [ ] **Step 5: Run the owning test file and the full suite**

Run: `flutter test test/backup/backup_wiring_test.dart`
Expected: `All tests passed!` (1 test)

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/multi_device_control_page.dart \
        lib/services/backup/backup_controller.dart \
        test/backup/backup_wiring_test.dart
git commit -m "feat(backup): wire the status pill and lifecycle into the app"
```

---

### Task 9: Lane 3a sweep

**Test-policy class:** 3 presentation — the screenshots ARE the verification,
and per `docs/learned/verification.md` this task is not done until they have
been **looked at**, not merely captured.

**Files:**
- Modify: `LEARNED.md` (Architecture section — the pill is now shipped
  behaviour, and the "known silent failures" note about the status surface
  being "a design, not shipped behaviour" is now half wrong)
- Create: `docs/superpowers/lanes/status-surface/progress.md`

- [ ] **Step 1: Run the full sweep**

```bash
flutter analyze                    # expect: No issues found!
flutter test                       # expect: All tests passed!
flutter test integration_test/     # expect: All tests passed!
```

- [ ] **Step 2: Capture the five states against the real app**

Three are reachable by using the app; two need the staged scenarios from
Task 8. Build and drive with `tools/mock_server/drive_macos_app.sh` per
`LEARNED.md`. Remember screenshots come out at the display's backing scale —
halve image coordinates before feeding them back to the script.

```bash
# 1. grey — the production configuration, no target at all
flutter run -d macos
#    → pill reads "Not backed up"

# 2. amber pending / 3. green — mock target, happy path
flutter run -d macos --dart-define=BACKUP_MOCK=true --dart-define=MOCK_RIG=true
#    → edit a position in Settings → pill reads "1 change pending"
#    → wait out the 30 s debounce → pill reads "Backed up just now"

# 4. red
flutter run -d macos --dart-define=BACKUP_MOCK=true --dart-define=BACKUP_SCENARIO=authExpired
#    → pill reads "Sign-in expired"; popover pins it with no dismiss control

# 5. amber needs-review
flutter run -d macos --dart-define=BACKUP_MOCK=true --dart-define=BACKUP_SCENARIO=conflict
#    → pill reads "Needs review"
```

Capture, for each: the AppBar with the pill, and the popover open. Save to
`docs/superpowers/lanes/status-surface/screenshots/`.

- [ ] **Step 3: Write `progress.md` with a `## Limitations` section**

It must name every acceptance criterion not fully met, or state that there are
none. Silence reads as unqualified success. At minimum this lane's limitations
include: no real backup target ships (Phase 4); conflict and adoption
conditions are surfaced but **not resolvable** until lane 3b; and the active
condition is not persisted across a restart (deviation D1).

- [ ] **Step 4: Commit and hand to Daniel**

```bash
git add docs/superpowers/lanes/status-surface/ LEARNED.md
git commit -m "docs: status surface lane progress and screenshots"
```

**Stop here. The merge is Daniel's, always.** Do not merge, do not push, do not
delete the branch.

---

# Lane 3b — Resolution surfaces

**Do not start until Daniel has merged lane 3a.** Open the lane off the merged
`main`:

```bash
git worktree add .worktrees/backup-resolution -b lane/backup-resolution
cd .worktrees/backup-resolution
flutter analyze && flutter test
```

### One more deviation, decided here

| # | Spec says | This plan does | Why |
|---|---|---|---|
| D6 | "*Decide later* — **suppresses prompting for that specific remote revision id** until the operator reopens it from the popover. Without the suppression, the next sweep ten minutes later re-raises the same prompt during the service." | Persists the deferred revision id, marks the popover's conflict row **"Deferred"**, and stops re-logging that revision. The pill **stays amber**. | There is no prompt to suppress: Global Constraint 3 means nothing opens a dialog by itself, so the sweep cannot re-raise anything. What survives of the requirement is the operator's stated intent, and that is worth recording. **Making the pill go green would be a lie** — the divergence is still there. |

---

### Task 10: The three resolution paths in the engine

**Test-policy class:** 1 trust contract. Every one of these overwrites
configuration or writes a revision. This is the highest-consequence code in the
phase.

**Files:**
- Modify: `lib/services/backup/backup_service.dart` (add public methods and a
  `history`/`fetchBody` passthrough)
- Test: `test/backup/backup_resolution_test.dart`

**Interfaces:**
- Consumes: the existing private `_single`, `_withStorageBoundary`,
  `_applyRevision`, `_pointer`.
- Produces: `enum ResolutionOutcome { resolved, localChangedDuringResolve, remoteMovedAgain }`;
  `class ResolutionResult { final ResolutionOutcome outcome; final BackupRevision? revision; }`;
  `Future<ResolutionResult> adoptRemote(BackupRevision)`;
  `Future<ResolutionResult> keepLocalAsNewRevision(BackupRevision remoteHead)`;
  `Future<ResolutionResult> restoreRevision(BackupRevision)`;
  `Future<List<BackupRevision>> history({int limit = 50})`;
  `Future<String> fetchBody(BackupRevision)`.

- [ ] **Step 1: Implement**

Append to `backup_service.dart`, above `_withStorageBoundary`:

```dart
enum ResolutionOutcome { resolved, localChangedDuringResolve, remoteMovedAgain }

class ResolutionResult {
  final ResolutionOutcome outcome;
  final BackupRevision? revision;
  const ResolutionResult(this.outcome, {this.revision});
}
```

and these methods inside `BackupService`:

```dart
  /// "Use the remote copy." Applies [revision] over local state.
  ///
  /// Aborts rather than discarding an edit that landed while the body was in
  /// flight: the operator answered a question about the state they were
  /// looking at, and that state has changed underneath them.
  Future<ResolutionResult> adoptRemote(BackupRevision revision) =>
      _single(() => _withStorageBoundary('resolve', () async {
            final generation =
                await ConfigMutationNotifier.instance.generation();
            final localHash = canonicalHash(await readBundleJson());
            final applied = await _applyRevision(
              revision,
              expectedLocalHash: localHash,
              expectedGeneration: generation,
            );
            return ResolutionResult(
              applied
                  ? ResolutionOutcome.resolved
                  : ResolutionOutcome.localChangedDuringResolve,
              revision: revision,
            );
          }));

  /// "Keep my copy as a new revision." Append-only means this ADDS; the
  /// remote copy is not destroyed, it becomes this revision's parent.
  Future<ResolutionResult> keepLocalAsNewRevision(BackupRevision remoteHead) =>
      _single(() => _withStorageBoundary('resolve', () async {
            final generation =
                await ConfigMutationNotifier.instance.generation();
            final bundle = await readBundleJson();
            final json = canonicalJsonEncode(bundle);
            final hash = canonicalHash(bundle);

            // Parenting on a head that has moved again would fork a second
            // time, silently.
            final head = await target.latest();
            if (head == null || head.id != remoteHead.id) {
              return ResolutionResult(ResolutionOutcome.remoteMovedAgain,
                  revision: head);
            }

            final revision = await target.put(
              json,
              contentHash: hash,
              parentRevisionId: head.id,
              deviceLabel: await deviceLabel(),
            );
            await BackupPointer.save(
              revisionId: revision.id,
              recordedHash: hash,
              targetIdentity: targetIdentity,
            );
            await ConfigMutationNotifier.instance.markSynced(generation);
            return ResolutionResult(ResolutionOutcome.resolved,
                revision: revision);
          }));

  /// Restores an older revision and makes it the current backup.
  ///
  /// The second half is not optional. Applying an ancestor leaves the pointer
  /// on a revision the head is not descended from, which the very next pull
  /// classifies as a divergence — the operator would be asked to resolve a
  /// conflict they created deliberately, seconds earlier. Appending the
  /// restored content as a new head lands the machine clean, and destroys
  /// nothing: the newer revisions remain in the store.
  Future<ResolutionResult> restoreRevision(BackupRevision revision) =>
      _single(() => _withStorageBoundary('resolve', () async {
            final generation =
                await ConfigMutationNotifier.instance.generation();
            final localHash = canonicalHash(await readBundleJson());
            final applied = await _applyRevision(
              revision,
              expectedLocalHash: localHash,
              expectedGeneration: generation,
            );
            if (!applied) {
              return ResolutionResult(
                  ResolutionOutcome.localChangedDuringResolve,
                  revision: revision);
            }

            final restoredGeneration =
                await ConfigMutationNotifier.instance.generation();
            final restored = await readBundleJson();
            final json = canonicalJsonEncode(restored);
            final hash = canonicalHash(restored);

            final head = await target.latest();
            if (head != null && head.bodyChecksum == bodyChecksumOf(json)) {
              // The restored content already IS the head — restoring the
              // newest revision, or an older one identical to it.
              await BackupPointer.save(
                revisionId: head.id,
                recordedHash: hash,
                targetIdentity: targetIdentity,
              );
              await ConfigMutationNotifier.instance
                  .markSynced(restoredGeneration);
              return ResolutionResult(ResolutionOutcome.resolved,
                  revision: head);
            }

            final appended = await target.put(
              json,
              contentHash: hash,
              parentRevisionId: head?.id,
              deviceLabel: await deviceLabel(),
            );
            await BackupPointer.save(
              revisionId: appended.id,
              recordedHash: hash,
              targetIdentity: targetIdentity,
            );
            await ConfigMutationNotifier.instance.markSynced(restoredGeneration);
            return ResolutionResult(ResolutionOutcome.resolved,
                revision: appended);
          }));

  /// Revisions for the history picker, newest first.
  Future<List<BackupRevision>> history({int limit = 50}) =>
      _single(() => _withStorageBoundary('history',
          () => target.list(limit: limit)));

  /// A revision's body, for the diff summary and the preview.
  Future<String> fetchBody(BackupRevision revision) => _single(
      () => _withStorageBoundary('history', () => target.fetch(revision)));
```

- [ ] **Step 2: Write the behavioral test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
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

  test('adoptRemote replaces local state and lands provenanced', () async {
    await setPositions(['Pulpit']);
    await service.push();
    final theirs = (await service.history()).single;

    await setPositions(['Lectern', 'Choir']);
    final result = await service.adoptRemote(theirs);

    expect(result.outcome, ResolutionOutcome.resolved);
    expect((await PositionStore.loadAll()).map((p) => p.name), ['Pulpit']);
    final pointer = await BackupPointer.load();
    expect(pointer.revisionId, theirs.id);
    // Clean: the next pull has nothing to say.
    expect((await service.pull()).outcome, PullOutcome.nothingToDo);
  });

  test('adoptRemote aborts if an edit lands while the body is in flight',
      () async {
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

  test('keepLocalAsNewRevision appends without destroying the remote copy',
      () async {
    await setPositions(['Pulpit']);
    await service.push();
    final base = (await service.history()).single;

    // Another machine writes a sibling; ours becomes stale.
    await target.put(
      '{"schemaVersion":1,"positions":[],"people":[],"services":[],'
      '"heightRanges":[],"presetNames":{},"visibilities":{}}',
      contentHash: 'theirs',
      parentRevisionId: base.id,
      deviceLabel: "Daniel's iPad",
    );
    final theirs = (await target.latest())!;

    await setPositions(['Pulpit', 'Lectern']);
    final result = await service.keepLocalAsNewRevision(theirs);

    expect(result.outcome, ResolutionOutcome.resolved);
    expect(result.revision!.parentRevisionId, theirs.id);
    expect(target.revisions, hasLength(3),
        reason: 'append-only: nothing was overwritten');
    expect((await service.pull()).outcome, PullOutcome.nothingToDo);
  });

  test('keepLocalAsNewRevision refuses when the head moved again', () async {
    await setPositions(['Pulpit']);
    await service.push();
    final stale = (await service.history()).single;
    await target.put(
      '{"schemaVersion":1,"positions":[],"people":[],"services":[],'
      '"heightRanges":[],"presetNames":{},"visibilities":{}}',
      contentHash: 'newer',
      parentRevisionId: stale.id,
      deviceLabel: 'Someone else',
    );

    final result = await service.keepLocalAsNewRevision(stale);

    expect(result.outcome, ResolutionOutcome.remoteMovedAgain);
    expect(target.revisions, hasLength(2), reason: 'nothing was uploaded');
  });

  test('restoring an older revision leaves the machine clean, not conflicted',
      () async {
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
    // The point of the whole exercise: no divergence follows a restore.
    expect((await service.pull()).outcome, PullOutcome.nothingToDo);
    expect((await service.push()).outcome, PushOutcome.noOp);
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
}
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/backup_resolution_test.dart`
Expected: `All tests passed!` (6 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/backup_service.dart \
        test/backup/backup_resolution_test.dart
git commit -m "feat(backup): adopt, keep-as-new-revision and restore paths"
```

---

### Task 11: The difference summary

**Test-policy class:** 1 trust contract. "Three unlabelled buttons are not a
decision anyone can make" — this is the text the operator decides on, and a
summary that undercounts is worse than none.

**Files:**
- Create: `lib/services/backup/bundle_diff.dart`
- Test: `test/backup/bundle_diff_test.dart`

**Interfaces:**
- Consumes: nothing beyond the two bundle JSON documents.
- Produces: `class BundleSectionDiff { final String label; final int added, removed, changed; bool get isEmpty; String get summary; }`;
  `class BundleDiff { final List<BundleSectionDiff> sections; static BundleDiff between(Map<String, dynamic> mine, Map<String, dynamic> theirs); bool get isEmpty; List<String> get lines; }`.

- [ ] **Step 1: Implement**

```dart
import 'canonical_json.dart';

/// One section's difference, in the operator's language.
class BundleSectionDiff {
  final String label;
  final int added;
  final int removed;
  final int changed;

  const BundleSectionDiff({
    required this.label,
    this.added = 0,
    this.removed = 0,
    this.changed = 0,
  });

  bool get isEmpty => added == 0 && removed == 0 && changed == 0;

  /// Phrased from the remote copy's point of view, because that is what the
  /// operator is deciding whether to take: "3 more people" means their copy
  /// has three this machine does not.
  String get summary {
    final parts = <String>[
      if (added > 0) '$added more',
      if (removed > 0) '$removed missing',
      if (changed > 0) '$changed changed',
    ];
    return '$label: ${parts.join(', ')}';
  }
}

/// What differs between this machine's configuration and another's.
class BundleDiff {
  final List<BundleSectionDiff> sections;

  const BundleDiff(this.sections);

  bool get isEmpty => sections.every((s) => s.isEmpty);

  List<String> get lines =>
      [for (final s in sections) if (!s.isEmpty) s.summary];

  static const Map<String, String> _listSections = {
    'positions': 'Positions',
    'people': 'People',
    'services': 'Services',
    'heightRanges': 'Height ranges',
    'operators': 'Operator panels',
  };

  static const Map<String, String> _mapSections = {
    'presetNames': 'Preset labels',
    'visibilities': 'Button visibility',
  };

  static BundleDiff between(
    Map<String, dynamic> mine,
    Map<String, dynamic> theirs,
  ) {
    final sections = <BundleSectionDiff>[];

    _listSections.forEach((field, label) {
      sections.add(_diffIdList(label, mine[field], theirs[field]));
    });

    _mapSections.forEach((field, label) {
      sections.add(_diffKeyedMap(label, mine[field], theirs[field]));
    });

    // No ids to key on: cameras are a name/address list and the switcher is a
    // single string. Same-or-different is all this can honestly say.
    final camerasDiffer = canonicalJsonEncode(mine['cameras']) !=
        canonicalJsonEncode(theirs['cameras']);
    if (camerasDiffer) {
      sections.add(const BundleSectionDiff(label: 'Camera addresses', changed: 1));
    }
    if (mine['rolandIp'] != theirs['rolandIp']) {
      sections.add(
          const BundleSectionDiff(label: 'Switcher address', changed: 1));
    }

    return BundleDiff(sections);
  }

  static BundleSectionDiff _diffIdList(
      String label, Object? mineRaw, Object? theirsRaw) {
    Map<String, String> index(Object? raw) {
      if (raw is! List) return const {};
      final out = <String, String>{};
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        // Fall back to position for anything without an id, so an unkeyed
        // list still reports "changed" rather than silently reading equal.
        final key = item is Map && item['id'] is String
            ? item['id'] as String
            : 'index:$i';
        out[key] = canonicalJsonEncode(item);
      }
      return out;
    }

    final mine = index(mineRaw);
    final theirs = index(theirsRaw);
    return BundleSectionDiff(
      label: label,
      added: theirs.keys.where((k) => !mine.containsKey(k)).length,
      removed: mine.keys.where((k) => !theirs.containsKey(k)).length,
      changed: theirs.entries
          .where((e) => mine.containsKey(e.key) && mine[e.key] != e.value)
          .length,
    );
  }

  static BundleSectionDiff _diffKeyedMap(
      String label, Object? mineRaw, Object? theirsRaw) {
    Map<String, String> index(Object? raw) {
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries)
          '${entry.key}': canonicalJsonEncode(entry.value)
      };
    }

    final mine = index(mineRaw);
    final theirs = index(theirsRaw);
    return BundleSectionDiff(
      label: label,
      added: theirs.keys.where((k) => !mine.containsKey(k)).length,
      removed: mine.keys.where((k) => !theirs.containsKey(k)).length,
      changed: theirs.entries
          .where((e) => mine.containsKey(e.key) && mine[e.key] != e.value)
          .length,
    );
  }
}
```

- [ ] **Step 2: Write the behavioral test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/bundle_diff.dart';

void main() {
  Map<String, dynamic> bundle({
    List<Map<String, dynamic>> people = const [],
    List<Map<String, dynamic>> positions = const [],
    Map<String, dynamic> presetNames = const {},
    String? rolandIp,
  }) =>
      {
        'schemaVersion': 1,
        'positions': positions,
        'people': people,
        'services': const [],
        'heightRanges': const [],
        'presetNames': presetNames,
        'visibilities': const {},
        if (rolandIp != null) 'rolandIp': rolandIp,
      };

  test('identical bundles report nothing', () {
    final b = bundle(people: [
      {'id': 'p1', 'name': 'Joel'}
    ]);
    expect(BundleDiff.between(b, b).isEmpty, isTrue);
    expect(BundleDiff.between(b, b).lines, isEmpty);
  });

  test('key order does not fake a difference', () {
    // The whole hash guard rests on canonical ordering; the diff must agree.
    final mine = bundle(people: [
      {'id': 'p1', 'name': 'Joel'}
    ]);
    final theirs = bundle(people: [
      {'name': 'Joel', 'id': 'p1'}
    ]);
    expect(BundleDiff.between(mine, theirs).isEmpty, isTrue);
  });

  test('counts additions, removals and edits separately', () {
    final mine = bundle(people: [
      {'id': 'p1', 'name': 'Joel'},
      {'id': 'p2', 'name': 'Isaiah'},
    ]);
    final theirs = bundle(people: [
      {'id': 'p1', 'name': 'Joel Greig'},
      {'id': 'p3', 'name': 'Katherine'},
    ]);

    expect(BundleDiff.between(mine, theirs).lines,
        contains('People: 1 more, 1 missing, 1 changed'));
  });

  test('a per-device preset map counts by device, not by button', () {
    final mine = bundle(presetNames: {
      '10.0.1.10': {'1': 'Pulpit'}
    });
    final theirs = bundle(presetNames: {
      '10.0.1.10': {'1': 'Pulpit', '2': 'Lectern'},
      '10.0.1.11': {'1': 'Balcony'},
    });

    expect(BundleDiff.between(mine, theirs).lines,
        contains('Preset labels: 1 more, 1 changed'));
  });

  test('device addresses report as changed, not counted', () {
    final mine = bundle(rolandIp: '10.0.1.20');
    final theirs = bundle(rolandIp: '10.0.1.21');
    expect(BundleDiff.between(mine, theirs).lines,
        contains('Switcher address: 1 changed'));
  });

  test('a list with no ids still reports a difference', () {
    final mine = bundle(positions: [
      {'name': 'Pulpit'}
    ]);
    final theirs = bundle(positions: [
      {'name': 'Lectern'}
    ]);
    expect(BundleDiff.between(mine, theirs).isEmpty, isFalse);
  });
}
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/bundle_diff_test.dart`
Expected: `All tests passed!` (6 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/bundle_diff.dart test/backup/bundle_diff_test.dart
git commit -m "feat(backup): section-by-section bundle difference summary"
```

---

### Task 12: Conflict resolution

**Test-policy class:** 1 for the controller's resolution plumbing (it decides
what clears a condition and what a failed resolve does), 2 for the dialog —
one thin test per action asserting the user-visible outcome. Layout is Class 3
and gets screenshots in Task 15.

**Files:**
- Modify: `lib/services/backup/backup_controller.dart`
- Create: `lib/widgets/backup/conflict_dialog.dart`
- Modify: `lib/widgets/backup/backup_log_popover.dart` (header action)
- Test: `test/backup/conflict_resolution_test.dart`

**Interfaces:**
- Consumes: `BackupService.adoptRemote`, `keepLocalAsNewRevision`,
  `fetchBody` (Task 10); `BundleDiff.between` (Task 11).
- Produces on `BackupController`: `static const String suppressedKey = 'backup_conflict_suppressed'`;
  `String? deferredRevisionId`; `Future<BundleDiff> conflictDiff()`;
  `Future<ResolutionOutcome> resolveUseRemote()`;
  `Future<ResolutionOutcome> resolveKeepMine()`;
  `Future<void> deferConflict()`.
  Produces as a widget: `Future<void> showConflictDialog(BuildContext context, BackupController controller)`.

- [ ] **Step 1: Add the resolution plumbing to `BackupController`**

```dart
  /// The remote revision the operator chose to decide about later. Persisted
  /// so the choice survives a restart; it marks the row deferred and stops
  /// re-logging that revision. It does **not** turn the pill green — the
  /// divergence is still real.
  static const String suppressedKey = 'backup_conflict_suppressed';

  String? deferredRevisionId;

  /// What differs between this machine and the conflicting revision.
  /// Downloads the remote body: conflicts are detected from metadata alone,
  /// so there is nothing to compare until this runs. Throws [AppFault] if the
  /// download fails — the dialog renders that rather than an empty summary.
  Future<BundleDiff> conflictDiff() async {
    final revision = conflictRevision;
    final backup = service;
    if (revision == null || backup == null) return const BundleDiff([]);
    final body = await backup.fetchBody(revision);
    final theirs = jsonDecode(body) as Map<String, dynamic>;
    final mine = (await ConfigBundle.fromStores()).toJson();
    return BundleDiff.between(mine, theirs);
  }

  Future<ResolutionOutcome> resolveUseRemote() =>
      _resolve((backup, revision) => backup.adoptRemote(revision),
          'Configuration replaced with the other machine\'s copy.');

  Future<ResolutionOutcome> resolveKeepMine() => _resolve(
      (backup, revision) => backup.keepLocalAsNewRevision(revision),
      'This machine\'s configuration saved as the newest revision.');

  Future<ResolutionOutcome> _resolve(
    Future<ResolutionResult> Function(BackupService, BackupRevision) action,
    String successMessage,
  ) async {
    final revision = conflictRevision;
    final backup = service;
    if (revision == null || backup == null) {
      return ResolutionOutcome.resolved;
    }
    try {
      final result = await action(backup, revision);
      if (result.outcome == ResolutionOutcome.resolved) {
        _conditions.remove(_conflictKey);
        conflictRevision = null;
        await _clearDeferred();
        await log.recordSuccess(
          operation: 'resolve',
          kind: 'resolved',
          message: successMessage,
          targetIdentity: backup.targetIdentity,
        );
        await _markConfirmedStored();
      } else if (result.outcome == ResolutionOutcome.remoteMovedAgain) {
        // Re-point at the new head rather than leaving the operator deciding
        // about a revision that is no longer there.
        conflictRevision = result.revision;
      }
      _applyConditions();
      await _refreshFacts();
      return result.outcome;
    } on AppFault catch (fault) {
      await log.recordFault(fault);
      _raise(fault);
      _applyConditions();
      await _refreshFacts();
      rethrow;
    }
  }

  Future<void> deferConflict() async {
    final id = conflictRevision?.id;
    if (id == null) return;
    deferredRevisionId = id;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(suppressedKey, id)) await prefs.reload();
  }

  Future<void> _clearDeferred() async {
    deferredRevisionId = null;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(suppressedKey)) await prefs.reload();
  }
```

In `start()`, after `await log.load();`, restore the deferred id:

```dart
    deferredRevisionId =
        (await SharedPreferences.getInstance()).getString(suppressedKey);
```

Replace `_raiseConflict` whole, so the deferred revision stops adding log rows
while the condition itself is still raised:

```dart
  Future<void> _raiseConflict(BackupRevision? revision, String message) async {
    conflictRevision = revision;
    final fault = AppFault.backup(
      BackupFailureKind.conflict,
      message,
      operation: 'resolve',
      targetIdentity: service?.targetIdentity,
    );
    _raise(fault);
    // Deferred means "I have seen this one". The pill stays amber — the
    // divergence is still real — but the sweep stops writing about it.
    if (revision != null && revision.id == deferredRevisionId) return;
    await log.recordFault(fault);
  }
```

Add `BackupController.suppressedKey` to `RestoreJournal.engineKeys`.

`backup_controller.dart` also needs three imports it did not have in Task 5:
`dart:convert` (for `jsonDecode`), `bundle_diff.dart`, and `relative_time.dart`
(used by Task 13's restore log line).

- [ ] **Step 2: Build the dialog**

```dart
import 'package:flutter/material.dart';

import '../../services/backup/app_fault.dart';
import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/bundle_diff.dart';
import '../../services/backup/relative_time.dart';

/// Conflict resolution. Opened by the operator from the popover — never
/// raised by the engine, and never during a service unless they ask for it.
Future<void> showConflictDialog(
  BuildContext context,
  BackupController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ConflictDialog(controller: controller),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.controller});

  final BackupController controller;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  late Future<BundleDiff> _diff;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _diff = widget.controller.conflictDiff();
  }

  Future<void> _run(Future<ResolutionOutcome> Function() action) async {
    setState(() => _working = true);
    String? problem;
    ResolutionOutcome? outcome;
    try {
      outcome = await action();
    } on AppFault catch (fault) {
      problem = fault.message;
    }
    if (!mounted) return;
    setState(() => _working = false);

    if (problem != null) {
      _tell('That did not work: $problem');
      return;
    }
    switch (outcome!) {
      case ResolutionOutcome.resolved:
        Navigator.of(context).pop();
      case ResolutionOutcome.localChangedDuringResolve:
        setState(() => _diff = widget.controller.conflictDiff());
        _tell('Something changed on this machine while that ran. '
            'Here is the comparison again.');
      case ResolutionOutcome.remoteMovedAgain:
        setState(() => _diff = widget.controller.conflictDiff());
        _tell('The other machine saved again. Here is the newer copy.');
    }
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final revision = widget.controller.conflictRevision;
    final now = DateTime.now();

    return AlertDialog(
      title: const Text('Two machines have different settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              revision == null
                  ? 'Another copy exists in the backup.'
                  : '${revision.deviceLabel} saved a copy '
                      '${relativeAge(revision.createdAt.toLocal(), now)}.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FutureBuilder<BundleDiff>(
              future: _diff,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Comparing…'),
                    ]),
                  );
                }
                // The comparison needs the remote body, and that download can
                // fail. Saying so beats an empty list that reads as "nothing
                // differs" — which would make "Use their copy" look harmless.
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Text(
                    'Could not download their copy to compare: '
                    '${error is AppFault ? error.message : error}',
                    style: TextStyle(color: Colors.red.shade800),
                  );
                }
                final lines = snapshot.data!.lines;
                if (lines.isEmpty) {
                  return const Text(
                      'The settings themselves look the same. Only the '
                      'backup history differs.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Their copy, compared with this machine:'),
                    const SizedBox(height: 6),
                    for (final line in lines) Text('•  $line'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working
              ? null
              : () async {
                  await widget.controller.deferConflict();
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('Decide later'),
        ),
        TextButton(
          onPressed:
              _working ? null : () => _run(widget.controller.resolveUseRemote),
          child: const Text('Use their copy'),
        ),
        FilledButton(
          onPressed:
              _working ? null : () => _run(widget.controller.resolveKeepMine),
          child: const Text('Keep mine'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Add the popover's action**

In `backup_log_popover.dart`'s `_header`, replace the single Retry button with:

```dart
          if (status.activeCondition?.kind == BackupStatus.conflictKind)
            TextButton(
              onPressed: () => showConflictDialog(context, controller),
              child: const Text('Review'),
            )
          else if (controller.canRetry)
            TextButton(
              onPressed: () => controller.retryNow(),
              child: const Text('Retry now'),
            ),
```

and add `if (controller.deferredRevisionId != null) 'You chose to decide about this later.'` to the header's `lines` list.

- [ ] **Step 4: Write the tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/position_store.dart';
import 'package:navigation_app/widgets/backup/conflict_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('"Use their copy" replaces local and clears the pill',
      (tester) async {
    await diverge();
    expect(controller.status.value.state, BackupPillState.needsReview);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showConflictDialog(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Daniel's iPad"), findsOneWidget);
    expect(find.textContaining('Positions:'), findsOneWidget);

    await tester.tap(find.text('Use their copy'));
    await tester.pumpAndSettle();

    expect((await PositionStore.loadAll()).map((p) => p.name), ['Balcony']);
    expect(controller.status.value.state, isNot(BackupPillState.needsReview));
  });

  testWidgets('"Keep mine" uploads without destroying their copy',
      (tester) async {
    await diverge();
    final before = target.revisions.length;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showConflictDialog(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();

    expect(target.revisions, hasLength(before + 1));
    expect((await PositionStore.loadAll()).map((p) => p.name),
        ['Pulpit', 'Lectern']);
    expect(controller.status.value.state, BackupPillState.backedUp);
  });

  testWidgets('a failed comparison says so instead of showing no differences',
      (tester) async {
    await diverge();
    target.failNextWith(AppFault.backup(
        BackupFailureKind.offline, 'Could not reach the backup.',
        operation: 'history', targetIdentity: 'mock:test'));

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showConflictDialog(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not download their copy'), findsOneWidget);
  });

  test('"Decide later" is remembered but does not turn the pill green',
      () async {
    await diverge();
    await controller.deferConflict();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackupController.suppressedKey), isNotNull);
    expect(controller.status.value.state, BackupPillState.needsReview);
  });
}
```

- [ ] **Step 5: Run the owning test file**

Run: `flutter test test/backup/conflict_resolution_test.dart`
Expected: `All tests passed!` (4 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/backup_controller.dart \
        lib/widgets/backup/conflict_dialog.dart \
        lib/widgets/backup/backup_log_popover.dart \
        lib/services/backup/restore_journal.dart \
        test/backup/conflict_resolution_test.dart
git commit -m "feat(backup): conflict resolution dialog with difference summary"
```

---

### Task 13: Revision history and restore

**Test-policy class:** 1 for the restore path — already covered in Task 10,
which is where the guarantee lives. 2 for this sheet: one test that picking a
revision and confirming actually restores it. Layout is Class 3.

**Files:**
- Create: `lib/widgets/backup/revision_history_sheet.dart`
- Modify: `lib/widgets/settings_dialog.dart` (a Backup section)
- Modify: `lib/services/backup/backup_controller.dart` (`history`, `restore`)
- Test: `test/backup/revision_history_test.dart`

**Interfaces:**
- Consumes: `BackupService.history`, `fetchBody`, `restoreRevision` (Task 10);
  `BundleDiff` (Task 11); `relativeAge` (Task 1).
- Produces on `BackupController`: `Future<List<BackupRevision>> history()`;
  `Future<ResolutionOutcome> restore(BackupRevision revision)`.
  As a widget: `Future<void> showRevisionHistory(BuildContext context, BackupController controller)`.

- [ ] **Step 1: Add the two controller methods**

```dart
  Future<List<BackupRevision>> history() async {
    final backup = service;
    if (backup == null) return const [];
    return backup.history();
  }

  /// Restores [revision] and makes it the newest backup. Nothing is deleted:
  /// the revisions that came after it stay in the store.
  Future<ResolutionOutcome> restore(BackupRevision revision) async {
    final backup = service;
    if (backup == null) return ResolutionOutcome.resolved;
    try {
      final result = await backup.restoreRevision(revision);
      if (result.outcome == ResolutionOutcome.resolved) {
        _conditions.remove(_conflictKey);
        _conditions.remove('push');
        _conditions.remove('pull');
        conflictRevision = null;
        await _clearDeferred();
        await log.recordSuccess(
          operation: 'restore',
          kind: 'restored',
          message: 'Restored the backup from '
              '${revision.deviceLabel}, '
              '${relativeAge(revision.createdAt.toLocal(), _now())}.',
          targetIdentity: backup.targetIdentity,
        );
        await _markConfirmedStored();
      }
      _applyConditions();
      await _refreshFacts();
      return result.outcome;
    } on AppFault catch (fault) {
      await log.recordFault(fault);
      _raise(fault);
      _applyConditions();
      await _refreshFacts();
      rethrow;
    }
  }
```

- [ ] **Step 2: Build the sheet**

```dart
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/backup/app_fault.dart';
import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_revision.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/bundle_diff.dart';
import '../../services/backup/relative_time.dart';
import '../../services/config_bundle.dart';

/// The revision picker. Without one, "recoverable" is a claim nobody can act
/// on: the operator would be reading JSON out of Drive by hand.
Future<void> showRevisionHistory(
  BuildContext context,
  BackupController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RevisionHistoryDialog(controller: controller),
  );
}

class _RevisionHistoryDialog extends StatefulWidget {
  const _RevisionHistoryDialog({required this.controller});

  final BackupController controller;

  @override
  State<_RevisionHistoryDialog> createState() => _RevisionHistoryDialogState();
}

class _RevisionHistoryDialogState extends State<_RevisionHistoryDialog> {
  late Future<List<BackupRevision>> _revisions;

  @override
  void initState() {
    super.initState();
    _revisions = widget.controller.history();
  }

  Future<void> _confirmAndRestore(BackupRevision revision) async {
    final now = DateTime.now();
    final diff = await _describe(revision);
    if (!mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this version?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved by ${revision.deviceLabel}, '
                '${relativeAge(revision.createdAt.toLocal(), now)}.'),
            const SizedBox(height: 12),
            if (diff == null)
              const Text('Could not compare it with what is on this machine.')
            else if (diff.isEmpty)
              const Text('It matches what is on this machine already.')
            else ...[
              const Text('Compared with this machine:'),
              const SizedBox(height: 6),
              for (final line in diff.lines) Text('•  $line'),
            ],
            const SizedBox(height: 12),
            const Text(
              'This machine will go back to that version, and it becomes the '
              'newest backup. Nothing is deleted — newer versions stay in the '
              'history.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (go != true || !mounted) return;

    try {
      final outcome = await widget.controller.restore(revision);
      if (!mounted) return;
      if (outcome == ResolutionOutcome.resolved) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Restored.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Something changed on this machine while that ran. '
                'Nothing was restored — try again.')));
      }
    } on AppFault catch (fault) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore: ${fault.message}')));
    }
  }

  Future<BundleDiff?> _describe(BackupRevision revision) async {
    final backup = widget.controller.service;
    if (backup == null) return null;
    try {
      final body = jsonDecode(await backup.fetchBody(revision));
      final mine = (await ConfigBundle.fromStores()).toJson();
      return BundleDiff.between(mine, body as Map<String, dynamic>);
    } on AppFault {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      title: const Text('Backup history'),
      content: SizedBox(
        width: 460,
        height: 380,
        child: FutureBuilder<List<BackupRevision>>(
          future: _revisions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Center(
                child: Text(
                  'Could not read the backup history: '
                  '${error is AppFault ? error.message : error}',
                  style: TextStyle(color: Colors.red.shade800),
                ),
              );
            }
            final revisions = snapshot.data!;
            if (revisions.isEmpty) {
              return const Center(child: Text('No backups yet.'));
            }
            return ListView.separated(
              itemCount: revisions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = revisions[i];
                return ListTile(
                  title: Text(r.deviceLabel),
                  subtitle:
                      Text(relativeAge(r.createdAt.toLocal(), now)),
                  trailing: TextButton(
                    onPressed: () => _confirmAndRestore(r),
                    child: Text(i == 0 ? 'Re-apply' : 'Restore'),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }
}
```

- [ ] **Step 3: Reach it from Settings**

`SettingsDialog` is a `StatelessWidget` taking ~20 explicit callbacks
(`settings_dialog.dart:17-40`); follow that pattern rather than inventing a
new one. Add one more field beside them:

```dart
  final BackupController backupController;
```

make it `required this.backupController` in the constructor, and pass
`backupController: _backup` from `_showSettingsDialog`
(`multi_device_control_page.dart:299`). Then the `Data` section (`:445-460`)
gains a third tile:

```dart
              _tile(
                icon: Icons.history,
                title: 'Backup History',
                subtitle: 'Restore an earlier version of your configuration',
                onTap: () => showRevisionHistory(context, backupController),
              ),
```

- [ ] **Step 4: Write the one wiring test**

```dart
  testWidgets('picking an older revision and confirming restores it',
      (tester) async {
    await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
    await service.push();
    await PositionStore.saveAll([
      Position(id: 'p1', name: 'Pulpit'),
      Position(id: 'p2', name: 'Lectern'),
    ]);
    await service.push();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showRevisionHistory(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Newest first, so the older revision is the second row.
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    expect((await PositionStore.loadAll()).map((p) => p.name), ['Pulpit']);
    expect(target.revisions, hasLength(3),
        reason: 'the restore is appended, the newer revision survives');
    expect(controller.status.value.state, BackupPillState.backedUp);
  });
```

(Reuse the `setUp` block from Task 12's test file — same target, service and
controller construction.)

- [ ] **Step 5: Run the owning test file**

Run: `flutter test test/backup/revision_history_test.dart`
Expected: `All tests passed!` (1 test)

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/backup/revision_history_sheet.dart \
        lib/widgets/settings_dialog.dart \
        lib/widgets/multi_device_control_page.dart \
        lib/services/backup/backup_controller.dart \
        test/backup/revision_history_test.dart
git commit -m "feat(backup): revision history with restore-as-newest"
```

---

### Task 14: Naming this machine

**Test-policy class:** 1 for the rejection rules — a machine labelled
`localhost` is a lie the conflict dialog repeats back, and two iPads both
called `localhost` make the whole conflict UI useless. 2 for the settings
field.

**Files:**
- Create: `lib/services/backup/device_label.dart`
- Modify: `lib/services/backup/app_fault.dart` (one new kind)
- Modify: `lib/services/backup/backup_status.dart` (its pill copy)
- Modify: `lib/services/backup/backup_controller.dart` (wire the label into
  the service, and the naming action into the popover)
- Modify: `lib/widgets/settings_dialog.dart`
- Test: `test/backup/device_label_test.dart`

**Interfaces:**
- Consumes: `RestoreJournal.engineKeys`.
- Produces: `class DeviceLabel` with `static const String key`,
  `static String? sanitize(String? candidate, {required Iterable<String> namesInUse})`,
  `static String? hostCandidate()`, `static Future<String?> load()`,
  `static Future<void> save(String label)`,
  `static Future<String> require()`. Adds
  `BackupFailureKind.deviceUnnamed`.

- [ ] **Step 1: Implement**

```dart
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_fault.dart';

/// The machine's name, as the conflict dialog will say it back.
///
/// Getting the DEFAULT right matters more than it looks, because a bad
/// default is worse than none: it looks like a real answer. There is no
/// reliable automatic name on iPad — `Platform.localHostname` returns
/// `"localhost"` since iOS 17, and `UIDevice.current.name` returns a generic
/// `"iPad"` since iOS 16 unless Apple grants an entitlement they gate behind
/// an approval process. So the rule is: propose a candidate, reject it if it
/// is worthless, and otherwise ask once.
class DeviceLabel {
  static const String key = 'backup_device_label';

  /// Names that are not names. Compared lowercase, with a trailing `.local`
  /// stripped first — macOS hostnames arrive as `Studio-Mac-mini.local`.
  static const Set<String> _worthless = {
    'localhost',
    'ipad',
    'iphone',
    'ipod',
    'ipod touch',
    'mac',
    'macbook',
    'macbook pro',
    'macbook air',
    'mac mini',
    'imac',
    'unknown',
  };

  static String _normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.endsWith('.local')) s = s.substring(0, s.length - '.local'.length);
    return s.replaceAll('-', ' ').replaceAll('_', ' ');
  }

  /// The proposed default, or null when there is nothing worth proposing.
  ///
  /// [namesInUse] are the labels on recent revisions in the store. A candidate
  /// already carried by another machine is rejected too — that is what catches
  /// two Macs sharing a hostname, and two iPads that would both call
  /// themselves the same thing.
  static String? sanitize(
    String? candidate, {
    required Iterable<String> namesInUse,
  }) {
    if (candidate == null) return null;
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return null;
    final normal = _normalize(trimmed);
    if (normal.isEmpty) return null;
    if (_worthless.contains(normal)) return null;
    if (namesInUse.any((n) => _normalize(n) == normal)) return null;
    return trimmed.endsWith('.local')
        ? trimmed.substring(0, trimmed.length - '.local'.length)
        : trimmed;
  }

  /// The machine's own idea of its name. Nothing on iOS: both routes there
  /// return a constant, and a constant is worse than a blank field.
  static String? hostCandidate() =>
      Platform.isIOS ? null : Platform.localHostname;

  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(key);

  static Future<void> save(String label) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, label.trim())) {
      await prefs.reload();
      throw StateError('Could not persist the device name');
    }
  }

  /// For `BackupService.deviceLabel`. Throws rather than inventing one:
  /// an unlabelled machine is honest, a machine labelled `localhost` is not.
  static Future<String> require() async {
    final saved = await load();
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    throw AppFault.backup(
      BackupFailureKind.deviceUnnamed,
      'Name this machine before its first backup, so the other machine can '
      'tell whose settings are whose.',
      operation: 'push',
    );
  }
}
```

Add to `app_fault.dart`: `deviceUnnamed,` in `BackupFailureKind` and
`'deviceUnnamed'` in `_needsHuman`. Add to `backup_status.dart`'s
`failureLabels`: `'deviceUnnamed': 'Name this machine'`. **Task 2's test
`every backup failure kind has copy that is not the fallback` fails until that
last line lands** — that is the test doing its job.

Add `DeviceLabel.key` to `RestoreJournal.engineKeys`: a rolled-back import
must not rename the machine.

- [ ] **Step 2: Offer the default where the operator names the machine**

In `settings_dialog.dart`'s `Configure` section, a tile opening a one-field
dialog. The default is offered, never silently accepted:

```dart
  Future<void> _nameThisMachine(
    BuildContext context,
    BackupController controller,
  ) async {
    final namesInUse = [
      for (final r in await controller.history()) r.deviceLabel,
    ];
    final suggestion = DeviceLabel.sanitize(
      await DeviceLabel.load() ?? DeviceLabel.hostCandidate(),
      namesInUse: namesInUse,
    );
    if (!context.mounted) return;

    final field = TextEditingController(text: suggestion ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this machine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'When two machines have different settings, this is the name '
              'you will see. "The Mac mini" or "Daniel\'s iPad" — whatever '
              'you would actually say out loud.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    field.dispose();

    final accepted = DeviceLabel.sanitize(name, namesInUse: namesInUse);
    if (accepted == null) {
      if (context.mounted && name != null && name.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'That name is already in use, or is not specific enough. '
                'Try something that names this machine.')));
      }
      return;
    }
    await DeviceLabel.save(accepted);
  }
```

Wire `BackupController.forEnvironment()`'s `deviceLabel:` to
`DeviceLabel.require`, and add a `Name this machine` action to the popover
header when `status.activeCondition?.kind == 'deviceUnnamed'`.

- [ ] **Step 3: Write the behavioral test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/device_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sanitize rejects a default that is not an answer', () {
    for (final worthless in [
      'localhost',
      'localhost.local',
      'iPad',
      'iPhone',
      'Mac mini',
      'MacBook-Pro',
      '   ',
      '',
    ]) {
      test('"$worthless" is refused', () {
        expect(DeviceLabel.sanitize(worthless, namesInUse: const []), isNull);
      });
    }

    test('null in, null out', () {
      expect(DeviceLabel.sanitize(null, namesInUse: const []), isNull);
    });
  });

  test('a real macOS hostname is accepted, without .local', () {
    expect(
      DeviceLabel.sanitize('Sanctuary-Mac-mini.local', namesInUse: const []),
      'Sanctuary-Mac-mini',
    );
  });

  test('a name another machine already uses is refused', () {
    // Two Macs sharing a hostname, or two iPads: the conflict dialog would be
    // actively misleading.
    expect(
      DeviceLabel.sanitize('Sanctuary Mac mini',
          namesInUse: const ['sanctuary-mac-mini']),
      isNull,
    );
  });

  test('require() refuses to invent a name', () async {
    await expectLater(
      DeviceLabel.require(),
      throwsA(isA<AppFault>()
          .having((f) => f.kind, 'kind', 'deviceUnnamed')
          .having((f) => f.needsUserAction, 'needsUserAction', isTrue)),
    );
  });

  test('require() returns the saved name once there is one', () async {
    await DeviceLabel.save('  The Mac mini  ');
    expect(await DeviceLabel.require(), 'The Mac mini');
  });
}
```

- [ ] **Step 4: Run the owning test files**

Run: `flutter test test/backup/device_label_test.dart test/backup/backup_status_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/device_label.dart \
        lib/services/backup/app_fault.dart \
        lib/services/backup/backup_status.dart \
        lib/services/backup/backup_controller.dart \
        lib/services/backup/restore_journal.dart \
        lib/widgets/settings_dialog.dart \
        test/backup/device_label_test.dart
git commit -m "feat(backup): explicit machine naming with rejected defaults"
```

---

### Task 15: Lane 3b sweep

**Test-policy class:** 3 presentation — the screenshots are the verification,
and this task is not done until they have been looked at.

- [ ] **Step 1: Run the full sweep**

```bash
flutter analyze                    # expect: No issues found!
flutter test                       # expect: All tests passed!
flutter test integration_test/     # expect: All tests passed!
```

- [ ] **Step 2: Screenshot every new surface**

```bash
flutter run -d macos --dart-define=BACKUP_MOCK=true --dart-define=BACKUP_SCENARIO=conflict
```

Capture: the popover with the "Review" action; the conflict dialog with a real
difference summary; the conflict dialog's comparison-failed state; the backup
history list; the restore confirmation; the name-this-machine dialog with a
good default and with a rejected one. Save to
`docs/superpowers/lanes/backup-resolution/screenshots/`.

- [ ] **Step 3: Write `progress.md` with a `## Limitations` section**

Naming, at minimum: no real backup target ships until Phase 4; "Decide later"
is recorded but suppresses nothing that could have fired (deviation D6); the
device-name uniqueness check can only see revisions the store returns, so two
machines named offline can still collide until their first push.

- [ ] **Step 4: Commit and hand to Daniel**

```bash
git add docs/superpowers/lanes/backup-resolution/
git commit -m "docs: backup resolution lane progress and screenshots"
```

**Stop here. The merge is Daniel's, always.**

---

## Self-Review

Run against the spec after writing the plan, per the `writing-plans` skill.

**1. Spec coverage.** Every Phase 3 requirement maps to a task:

| Spec requirement | Task |
|---|---|
| 5-state priority pill (`red` > `amber` conflict > `grey` > `amber` dirty > `green`) | 2 (derivation), 6 (widget) |
| Popover: pinned active conditions | 7 |
| Popover: collapse on `(domain, kind, operation, targetIdentity)` | 3 — the fingerprint already exists at `app_fault.dart:90` |
| Popover: dismiss controls (`x`) | 3 (`dismiss`), 7 (the control) |
| Popover: relative time ladders | 1 |
| Conflict dialog: machine identity, timestamp, diff summary | 11 (diff), 12 (dialog) |
| Conflict dialog: three explicit actions | 10 (engine paths), 12 (buttons) |
| Conflict dialog: per-revision prompt suppression | 12, as deviation D6 |
| Revision history picker: preview and restore | 13, resting on 10's restore guarantee |
| First-run device naming, rejecting invalid defaults | 14 |
| Lifecycle: `WidgetsBindingObserver`, pull on foreground, flush on background | 5 (the observer), 8 (registration) |
| Production `localIsPristine` across all 8 stores | 4 |
| Bounds: 14 days, 200 rows, byte cap, per-message truncation | 3 |
| `backup_log` persisted in `SharedPreferences` | 3 |
| Pill always clickable, green included | 6 |
| `centerTitle: false` set explicitly | 8 |
| Width capped at 400 px with wrapping | 7 |

**Two spec lines are deliberately not implemented as written**, both recorded
above with their reasoning: the active condition is not persisted (D1), and
"Decide later" suppresses log rows rather than a prompt that cannot fire (D6).
Reviewers should attack both.

**Spec items belonging to other phases, not this plan:** `DriveBackupTarget`,
auth, folder identity and checksum verification (Phase 4); Roland and camera
faults in the pill (Phase 5).

**2. Placeholder scan.** No `TODO`, no "implement later", no "similar to Task
N", no "add appropriate error handling". Every code step carries the code.
Two forward references are explicit rather than vague: Task 6 imports Task 7's
`showBackupLogPopover` (noted in the task), and Task 14's pill copy makes Task
2's coverage test fail until it lands (noted, and intended).

**3. Type consistency.** Checked across tasks:

- `BackupStatus` field names (`activeCondition`, `hasDurableHead`, `isDirty`,
  `pendingCount`, `lastSuccessAt`, `configured`) are identical in Tasks 2, 5,
  6, 7 and 12.
- `BackupController` members used by the widgets — `status`, `log`, `canRetry`,
  `retryNow`, `dismiss`, `conflictRevision`, `conflictDiff`,
  `resolveUseRemote`, `resolveKeepMine`, `deferConflict`, `history`, `restore`,
  `service` — are each defined in Task 5, 12 or 13 before first use.
- `ResolutionOutcome` / `ResolutionResult` are defined in Task 10 and consumed
  in 12 and 13 with the same shape.
- `BackupLog.lastSuccessKey` is defined in Task 3 and read in Task 5.
- `RestoreJournal.dataKeys` / `dataPrefixes` / `engineKeys` are defined in
  Task 3 and consumed in Tasks 4, 12 and 14.
- `BundleDiff.between(mine, theirs)` argument order is the same in Tasks 11,
  12 and 13 — **mine first**, and the copy is phrased from theirs.

**4. Things a reviewer should push on hardest.**

- **`_applyRevision`'s freshness guard is reused for a deliberate overwrite.**
  Task 10's `adoptRemote` aborts when local changed during the fetch. That is
  defensible, and it is also a path where the operator pressed a button and
  nothing happened. Is a re-prompt the right answer, or should adopt force?
- **The status recomputes the full bundle hash on every event and every
  mutation.** `ConfigBundle.fromStores()` reads every key and re-encodes.
  That is cheap against in-memory `SharedPreferences`, but it happens on every
  keystroke-driven save. Should it be debounced or cached against the
  generation counter?
- **Deviation D1** leaves a real hole: a machine that fails to authenticate,
  then restarts, shows grey rather than red until the first pull returns. Is
  the honesty worth the gap?
- **`restoreRevision` writes twice** — apply, then upload — and there is no
  single-flight *boundary* between them beyond `_single`, so a crash in the
  middle leaves local restored and the head unmoved. That state is coherent and
  self-healing on the next push, but it is worth saying out loud.
- **The device-name uniqueness check reads `list(limit: 50)`,** so a machine
  named while the target is unreachable can still collide.

---

## Limitations of this plan

Stated here rather than discovered at merge:

1. **Nothing in Phase 3 backs anything up.** Both lanes ship against no target
   in production. The first real backup happens in Phase 4.
2. **`MockBackupTarget` cannot fail mid-`put`,** so no test here covers a
   partial upload. That is Phase 4's problem, with a real transport.
3. **No integration test drives the pill through the mock rig.** The rig fakes
   the Roland and the cameras, not a backup target, and adding one would be
   ops work outside this lane.
4. **The popover is not keyboard-navigable** beyond what `showDialog` gives for
   free. Nobody operates this app by keyboard today.
5. **Deviations D1 and D6 change spec-stated behaviour.** Both are argued
   above; neither is a silent departure.
