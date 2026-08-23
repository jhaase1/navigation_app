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
| **3a — Status surface** | `lane/status-surface` | 1–10 | The app says out loud when a backup is failing, pending, or absent. Read-only: nothing in 3a can overwrite configuration. |
| **3b — Resolution surfaces** | `lane/backup-resolution` | 11–18 | Conflict dialog, diff summary, revision-history restore, device naming. Every destructive action lives here. |

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
    end of every task.** Baseline when this plan was written, before 3a:
    `No issues found!` and `522 tests passed`. **Baseline at the head of lane
    3b, with 3a merged: `No issues found!` and `620 tests passed`** — verified
    on `lane/backup-resolution` off `c407fdd`, 22 Aug 2026. Tasks 11-18 add to
    that number; they never subtract from it.

---

## Deviations from the spec, decided before writing this plan

Recorded here because reviewers should attack them directly.

| # | Spec says | This plan does | Why |
|---|---|---|---|
| D1 | "The active condition is … stored outside the historical ring so eviction can never remove it." | The active condition is held **in memory** on `BackupController` and is **not persisted**. History is persisted. **Task 9 makes app start resume a pending push**, so a failure that was real before the restart re-proves itself within seconds. | What the requirement protects against is *eviction*, and a separate in-memory field satisfies that. Persisting it would leave a red "Sign-in expired" pill across a restart that no completed operation has re-proved — a stale claim, in a surface built to stop stale claims. `gpt-5.6-sol` rejected D1 on the grounds that a restart could hide a failed push behind a successful pull; that hole was real and is closed by the start-up resume rather than by persisting the claim. `grok-4.6` independently accepted D1. |
| D2 | "Dirty — whether the local canonical hash differs from the durable head", and "3 changes pending". | Dirty is computed from the **hash**. The number comes from the mutation generation counter and is shown **only when the hash also differs**. | `OperatorStore.saveActiveId` calls `notify()` (`operator_store.dart:47-55`), so switching operator bumps the generation without changing bundle content. Counting alone would flash amber on every operator switch. Hash alone has no number to show. |
| D3 | "Widget tests — all five pill states; tappable in each; header pins; timestamp ladder boundaries; width cap with a pathological message." | The **derivation** and the **time ladder** are pure functions with Class 1 tests. The pill and popover get **one thin Class 2 wiring test each** and screenshots for everything visual. | `docs/learned/verification.md` says "this file wins where they differ", classes layout and chrome as Class 3 (screenshots, no unit tests), and names "re-running a logic matrix through `pumpWidget`" an anti-pattern. |
| D4 | Phase 3 is listed as "Status surface — pill, popover, log, conflict UI, revision-history picker", implying UI work. | Lane 3b adds **three public methods to `BackupService`** (`adoptRemote`, `keepLocalAsNewRevision`, `restoreRevision`). | The spec's three conflict actions have no engine path today: `push()` refuses outright when `head.id != pointer.revisionId` (`backup_service.dart:274`), and there is no public adopt or restore. The buttons cannot exist without them. |
| D5 | Silent on what happens after restoring an older revision. | Restore **uploads the old revision's content as a new head first, then applies it locally**. | Decided by Daniel, 21 Aug 2026. Restore-and-stop leaves the pointer on an ancestor of the head, which the next pull classifies as a non-descendant divergence — the operator would get "Needs review" seconds after a restore they performed deliberately. The *order* is a review correction: both reviewers found that applying first moves the pointer onto the ancestor, so a failed or interrupted upload leaves the next pull matching branch 6 (`backup_service.dart:165-176`) and **silently re-applying the revision the operator just undid**. Uploading first makes every failure a safe one. |

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
| `lib/services/backup/backup_service.dart` | Extract one fork-checked `_appendRevision` primitive, put `push()` on it, and add `adoptRemote`, `keepLocalAsNewRevision`, `restoreRevision`, `history` and `fetchBody`. |
| `lib/services/backup/backup_controller.dart` | Route resolution outcomes; persist per-revision suppression. |
| `lib/widgets/settings_dialog.dart:445-460` | A "Backup" section: device name and revision history. The controller field is **optional** — required would break `test/settings_dialog_test.dart:27`. |
| `lib/widgets/backup/device_name_dialog.dart` | `nameThisMachine(...)`, called from Settings and from the conflict dialog before any upload. |

**New persisted keys — the Tier 3 surface**

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `backup_log` | String (JSON array) | `BackupLog` | Bounded fault/success history. |
| `backup_last_success_at` | String (ISO-8601 UTC) | `BackupController` | When this machine's configuration was last confirmed stored at the target. |
| `backup_device_label` | String | `DeviceLabel` (3b) | Operator-declared machine name. |
| `backup_conflict_suppressed` | String (revision id) | `BackupController` (3b) | The remote revision the operator chose to decide later about. |
| `backup_replaced_snapshot` | String (JSON object) | `BackupService` (3b, Task 12) | The local configuration that "Use the remote copy" replaced. One slot, most recent wins. |

The first four are added to `RestoreJournal` engine keys — in Task 3
(`backup_log`, `backup_last_success_at`), Task 14 (`backup_conflict_suppressed`)
and Task 17 (`backup_device_label`) — so a rolled-back import cannot strand
them.

**`backup_replaced_snapshot` is deliberately NOT journalled. Do not add it.**
`adoptRemote` writes the slot *before* it calls `_applyRevision`, so the
journal's `capture()` already runs after the write and rolling it back would
restore the value it already holds. On the manual-import path journalling it
would be actively wrong: an import that rolled back would discard the copy of
the settings the operator adopted away from, which is the one thing this slot
exists to keep. It is a recovery affordance for a single action, deliberately
outside the configuration it protects.

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
Expected: `All tests passed!` (11 tests)

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
- Modify: `lib/services/backup/app_fault.dart:8-21` and `:69-78` (one new kind)
- Test: `test/backup/backup_status_test.dart`

Add `adoptionChoice,` to `BackupFailureKind` and `'adoptionChoice'` to
`_needsHuman`. First run with local data and a non-empty remote is a real
branch in the engine already (`PullOutcome.needsAdoptionChoice`,
`backup_service.dart:132`) and it is **not** a two-machine conflict: on a
brand-new iPad there is no other machine in the story. Giving it its own kind
is what lets the dialog ask the right question.

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
    'unknown': 'Backup failing',
  };

  String label(DateTime now) {
    switch (state) {
      case BackupPillState.failing:
        return failureLabels[activeCondition!.kind] ?? 'Backup failing';
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
```

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/backup_status_test.dart`
Expected: `All tests passed!` (13 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/backup_status.dart \
        lib/services/backup/app_fault.dart \
        test/backup/backup_status_test.dart
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
    // Needs `import 'package:navigation_app/services/backup/restore_journal.dart';`
    // added to this file — `config_bundle_test.dart` does not import it today.
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

### Task 5: `BackupController` — the facts behind the pill

**Test-policy class:** 1 trust contract. This half owns the three facts the pill
is derived from: whether a durable head exists at **this** target, whether local
content differs from it, and when it was last confirmed stored. Getting the
target check wrong shows green over an empty backup.

Split from what was one 600-line task. This task builds the class and its
facts; Task 6 makes it listen to the engine. The seam is real: everything here
is testable without a single engine event.

**Files:**
- Create: `lib/services/backup/backup_controller.dart`
- Test: `test/backup/backup_controller_test.dart`

**Interfaces:**
- Consumes: `BackupService` (`targetIdentity`), `BackupScheduler`
  (`start()`, `stop()`, `onAppStart()`, `onForeground()`, `flushPending()`),
  `BackupStatus` (Task 2), `BackupLog` (Task 3),
  `ConfigBundle.localIsPristine` (Task 4).
- Produces: `class BackupController with WidgetsBindingObserver`;
  `ValueNotifier<BackupStatus> status`; `BackupLog log`;
  `BackupRevision? conflictRevision`; `bool get canRetry`;
  `Future<void> start()`, `Future<void> retryNow()`,
  `Future<void> dismiss(String fingerprint)`, `Future<void> dispose()`;
  factories `BackupController.disabled()`,
  `BackupController.forService(BackupService, {BackupScheduler?, BackupLog?, DateTime Function()?, Future<void> Function()? stageScenario})`.
  The `_fold`, `_events` and `_mutations` fields are declared here and used by
  Task 6 — `dispose()` already tears all three down.

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
  final Future<void> Function()? _stageScenario;

  /// Insertion-ordered, so the most recently raised hard failure is last.
  final Map<String, AppFault> _conditions = <String, AppFault>{};

  /// One in-flight fold at a time.
  ///
  /// `BackupService` serialises its own operations, but this class did not:
  /// with `unawaited(handleEvent(...))` a fault handler could yield while
  /// persisting its log row, a newer success could clear the condition, and
  /// the older handler could then resume and write stale facts over it. Last
  /// writer wins, and the last writer was whichever handler happened to
  /// finish last.
  Future<void> _fold = Future<void>.value();

  StreamSubscription<Object>? _events;
  StreamSubscription<int>? _mutations;

  final ValueNotifier<BackupStatus> status =
      ValueNotifier<BackupStatus>(const BackupStatus());

  /// The remote revision behind the current question, for lane 3b's dialog.
  BackupRevision? conflictRevision;

  BackupController._({
    required this.service,
    required BackupScheduler? scheduler,
    required this.log,
    required DateTime Function() now,
    Future<void> Function()? stageScenario,
  })  : _scheduler = scheduler,
        _now = now,
        _stageScenario = stageScenario;

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
    Future<void> Function()? stageScenario,
  }) =>
      BackupController._(
        service: service,
        scheduler: scheduler ?? BackupScheduler(service: service),
        log: log ?? BackupLog(now: now),
        now: now ?? DateTime.now,
        stageScenario: stageScenario,
      );

  bool get canRetry => _scheduler != null;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await log.load();
    await _refreshFacts();

    final scheduler = _scheduler;
    if (scheduler == null) return;

    // Awaited, and before the first pull: a scenario staged afterwards would
    // race the pull it exists to set up.
    await _stageScenario?.call();

    scheduler.start();
    await scheduler.onAppStart();
  }

  /// The pointer, but only when it belongs to the target we are talking to.
  ///
  /// `BackupService` makes this check internally
  /// (`backup_service.dart:101-104`) and does not clear the raw keys when a
  /// new target is empty. A controller reading `BackupPointer.load()` straight
  /// would keep reporting the previous account's head — green, over nothing.
  Future<BackupPointer> _pointer() async {
    final backup = service;
    if (backup == null) return const BackupPointer();
    final pointer = await BackupPointer.load();
    return pointer.matchesTarget(backup.targetIdentity)
        ? pointer
        : const BackupPointer();
  }

  /// Records "this machine's configuration is stored at the target" — and only
  /// when that is actually true. Any completed operation calls it; the pointer
  /// check decides whether it means anything.
  Future<void> _markConfirmedStored() async {
    final pointer = await _pointer();
    final localHash = canonicalHash((await ConfigBundle.fromStores()).toJson());
    if (!pointer.isCleanAgainst(localHash)) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        BackupLog.lastSuccessKey, _now().toUtc().toIso8601String())) {
      await prefs.reload();
    }
  }

  Future<void> _refreshFacts() async {
    final pointer = await _pointer();
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
      // No durable head means no backup to be aged. A stored timestamp from
      // before a manual import or an emptied target would otherwise have the
      // popover saying "Last backed up 5 minutes ago" about a configuration
      // that has never been backed up at all.
      lastSuccessAt: pointer.isProvenanced && lastRaw != null
          ? DateTime.parse(lastRaw).toLocal()
          : null,
      clearLastSuccess: !pointer.isProvenanced || lastRaw == null,
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
    await _fold;
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
import 'package:navigation_app/services/backup/backup_pointer.dart';
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

  group('facts', () {
    test('a pointer from another target is not this target\'s head', () async {
      // Account or folder changed. The old pointer is still in prefs and the
      // engine ignores it; the controller must too, or it paints green over
      // an empty target.
      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await BackupPointer.save(
        revisionId: 'rev-from-elsewhere',
        recordedHash: 'whatever',
        targetIdentity: 'drive:some-other-folder',
      );

      await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

      expect(controller.status.value.hasDurableHead, isFalse);
      expect(controller.status.value.state, BackupPillState.notBackedUp);
    });

    test('no durable head means no "last backed up" age', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          BackupLog.lastSuccessKey, clock.toUtc().toIso8601String());

      await controller.handleEvent(const PullResult(PullOutcome.targetEmptied));

      expect(controller.status.value.lastSuccessAt, isNull,
          reason: 'a stale age would date a configuration by a backup it has '
              'no claim to');
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
Expected: `All tests passed!` (3 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/backup_controller.dart \
        test/backup/backup_controller_test.dart
git commit -m "feat(backup): controller facts — durable head, dirty, last success"
```

---

### Task 6: The event fold

**Test-policy class:** 1 trust contract. Every rule in Global Constraints 4 and
5 lives here: which condition wins, and what a success is allowed to clear. A
mistake makes the pill lie, which is the failure this phase exists to remove.

The matrix is tested through `handleEvent`, a plain method taking the same
objects `BackupScheduler.events` emits — cheap, deterministic, no timers. **One
end-to-end test drives a real `BackupService` and `BackupScheduler` over
`MockBackupTarget`** so the matrix tests are not vacuous: it proves the
subscription actually fires.

**Rewritten after review.** Four defects in the first draft, all found by both
reviewers or confirmed against the engine:

- **The fold was not serialized.** `unawaited(handleEvent(event))` let an older
  `_refreshFacts` finish after a newer one and write stale facts under the
  current condition — including "Not backed up" over a revision that exists.
- **A conflict outcome left the operation's earlier transport failure
  standing.** Because a hard failure outranks a question, the popover would
  offer "Retry now" forever and the resolution UI became unreachable.
- **`PullOutcome.nothingToDo` cleared a fork warning.** `nothingToDo` only
  means `head.id == pointer` (`backup_service.dart:146-148`); after we win a
  fork race our own revision *is* the head, so the very next pull erased the
  warning while the sibling sat there.
- **First-run adoption was folded in as a conflict**, which it is not.

**Files:**
- Modify: `lib/services/backup/backup_controller.dart` (Task 5)
- Test: `test/backup/backup_controller_test.dart` (Task 5, append)

**Interfaces:**
- Consumes: Task 5's class; `PullResult` / `PullOutcome`, `PushResult` /
  `PushOutcome`, `AppFault`.
- Produces: `@visibleForTesting Future<void> handleEvent(Object event)`;
  `@visibleForTesting void handleEventUnserialized(Object event)` — pushes an
  event through `_enqueue` exactly as the stream listener does, so the error
  path can be exercised; and the private fold — `_enqueue`, `_onPull`,
  `_onPush`, `_raise`, `_clearQuestion`, `_raiseQuestion`, `_applyConditions`.

- [ ] **Step 1: Add the fold to the class**

Insert immediately after `start()`:

```dart
  void _enqueue(Future<void> Function() work) {
    _fold = _fold.then((_) => work()).catchError((Object error) async {
      // Never silently. A fold that throws leaves the pill showing facts from
      // before the event — stale, confident and wrong, which is the precise
      // failure this surface exists to remove. `ConfigBundle.fromStores()`
      // alone can throw: it `jsonDecode`s every `preset_names_*` value with no
      // guard (`config_bundle.dart:180-190`), so one corrupt key is enough.
      final fault = AppFault.backup(
        BackupFailureKind.unknown,
        'The backup status could not be updated.',
        operation: 'status',
        targetIdentity: service?.targetIdentity,
        cause: error,
      );
      await log.recordFault(fault);
      _raise(fault);
      _applyConditions();
    });
  }

  /// Folds one scheduler event into the status. Public for tests: the matrix
  /// here is ordinary logic and does not need timers to exercise.
  /// Queues [event] the way the stream listener does — including the error
  /// path, which awaiting `handleEvent` directly would bypass.
  @visibleForTesting
  void handleEventUnserialized(Object event) =>
      _enqueue(() => handleEvent(event));

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
    // The operation COMPLETED — it reached the target and came back with an
    // answer. Whatever that answer is, this operation's transport failure is
    // no longer true. Leaving it standing was how a recovered network could
    // permanently hide the resolution actions: a hard failure outranks a
    // question, so the popover offered "Retry now" forever.
    _conditions.remove('pull');

    switch (result.outcome) {
      case PullOutcome.applied:
      case PullOutcome.adopted:
      case PullOutcome.rebased:
        // Local and remote now hold the same content. That disproves a
        // divergence.
        _clearQuestion();
        await log.recordSuccess(
          operation: 'pull',
          kind: 'restored',
          message: 'Configuration restored from the backup.',
          targetIdentity: service?.targetIdentity,
        );
        await _markConfirmedStored();
      case PullOutcome.nothingToDo:
        // Deliberately does NOT clear a question. `nothingToDo` means only
        // `head.id == pointer` (`backup_service.dart:146-148`). After we win
        // a fork race our own revision IS the head, so clearing here would
        // erase the fork warning while the sibling is still sitting in the
        // store — and the other machine would be the only one that knew.
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
        await _raiseQuestion(
          result.revision,
          BackupFailureKind.conflict,
          'Another machine saved a different configuration.',
        );
      case PullOutcome.needsAdoptionChoice:
        await _raiseQuestion(
          result.revision,
          BackupFailureKind.adoptionChoice,
          'This device has settings of its own and has never been backed up.',
        );
    }
  }

  Future<void> _onPush(PushResult result) async {
    _conditions.remove('push');

    switch (result.outcome) {
      case PushOutcome.uploaded:
        _clearQuestion();
        await log.recordSuccess(
          operation: 'push',
          kind: 'uploaded',
          message: 'Configuration backed up.',
          targetIdentity: service?.targetIdentity,
        );
        await _markConfirmedStored();
      case PushOutcome.noOp:
        // The bytes at the head ARE ours — that does disprove a divergence.
        // Nothing is logged; nothing happened.
        _clearQuestion();
        await _markConfirmedStored();
      case PushOutcome.conflict:
        await _raiseQuestion(
          result.remoteRevision,
          BackupFailureKind.conflict,
          'Another machine saved a different configuration.',
        );
      case PushOutcome.forked:
        await _raiseQuestion(
          result.siblings?.first,
          BackupFailureKind.conflict,
          'Another machine saved a different configuration at the same '
          'moment. Both copies were kept.',
        );
    }
  }

  void _raise(AppFault fault) {
    final key = BackupStatus.isQuestion(fault.kind)
        ? _conflictKey
        : (fault.operation ?? 'unknown');
    // Remove before insert so insertion order tracks recency.
    _conditions.remove(key);
    _conditions[key] = fault;
  }

  void _clearQuestion() {
    _conditions.remove(_conflictKey);
    conflictRevision = null;
  }

  Future<void> _raiseQuestion(
    BackupRevision? revision,
    BackupFailureKind kind,
    String message,
  ) async {
    conflictRevision = revision;
    final fault = AppFault.backup(
      kind,
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
```

- [ ] **Step 2: Subscribe, inside `start()`**

Add these two lines after `await _stageScenario?.call();` and before
`scheduler.start();`:

```dart
    _events = scheduler.events.listen((event) => _enqueue(() => handleEvent(event)));
    _mutations = ConfigMutationNotifier.instance.onMutated
        .listen((_) => _enqueue(_refreshFacts));
```

They enqueue rather than fire. `BackupService` serialises its own operations;
this class did not, and with `unawaited(...)` a fault handler could yield while
persisting its log row, a newer success could clear the condition, and the
older handler could then resume and write stale facts over it.

- [ ] **Step 3: Append the fold tests**

Add to `test/backup/backup_controller_test.dart`, before the disabled-controller
test:

```dart
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

    test('a completed pull clears its transport failure even when the answer '
        'is a conflict', () async {
      // Otherwise: push conflicts, a pull fails offline, the network comes
      // back, and every later pull returns conflict — so the stale offline
      // fault never clears, outranks the question, and the popover offers
      // "Retry now" instead of "Review". The resolution UI becomes
      // permanently unreachable.
      await controller.handleEvent(offline('pull'));
      expect(controller.status.value.state, BackupPillState.failing);

      await controller.handleEvent(const PullResult(PullOutcome.conflict));

      expect(controller.status.value.state, BackupPillState.needsReview);
    });

    test('a hard failure raised after a question outranks it', () async {
      await controller.handleEvent(const PullResult(PullOutcome.conflict));
      expect(controller.status.value.state, BackupPillState.needsReview);

      await controller.handleEvent(offline('push'));
      expect(controller.status.value.state, BackupPillState.failing);
    });

    test('a question raised after a hard failure does NOT outrank it',
        () async {
      // The discriminating direction, and the only one that separates
      // Global Constraint 4 from "latest event wins". Its neighbours above
      // both expect whatever arrived last, so a naive most-recent-wins
      // implementation passes them and fails here.
      //
      // The push failure is still unresolved: the pull completing says
      // nothing about whether the upload works. Amber here would tell the
      // operator to review a divergence while their edits are stranded.
      await controller.handleEvent(offline('push'));
      expect(controller.status.value.state, BackupPillState.failing);

      await controller.handleEvent(const PullResult(PullOutcome.conflict));

      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.activeCondition!.operation, 'push');
    });

    test('a pull that applies remote content clears a divergence', () async {
      await controller.handleEvent(const PullResult(PullOutcome.conflict));
      await controller.handleEvent(const PullResult(PullOutcome.applied));
      expect(controller.status.value.state, isNot(BackupPillState.needsReview));
    });

    test('nothingToDo does NOT clear a fork warning', () async {
      // We uploaded second, so our revision IS latest and the next pull says
      // nothingToDo. The sibling is still in the store. Clearing here would
      // leave the other machine as the only one that knows.
      await controller.handleEvent(const PushResult(PushOutcome.forked));
      expect(controller.status.value.state, BackupPillState.needsReview);

      await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

      expect(controller.status.value.state, BackupPillState.needsReview);
    });

    test('first-run adoption is its own question, not a conflict', () async {
      await controller.handleEvent(
          const PullResult(PullOutcome.needsAdoptionChoice));
      expect(controller.status.value.activeCondition!.kind, 'adoptionChoice');
      expect(controller.status.value.label(clock), 'Choose a copy');
    });

    test('an emptied target raises targetMissing, never silence', () async {
      await controller.handleEvent(const PullResult(PullOutcome.targetEmptied));
      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.label(clock), 'Backup missing');
    });

    test('a fold that throws goes red, it does not go quiet', () async {
      // One corrupt `preset_names_*` key is enough to make
      // `ConfigBundle.fromStores()` throw. Swallowing that leaves the pill
      // showing whatever it last computed, forever.
      SharedPreferences.setMockInitialValues({
        'preset_names_10.0.1.10': 'not json',
      });

      controller.handleEventUnserialized(const PullResult(PullOutcome.applied));
      await Future<void>.delayed(Duration.zero);

      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.log.entries.value.first.kind, 'unknown');
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

    test('a slow first event cannot repaint the pill after a later success',
        () async {
      // The serialization test. With an unawaited fold, the pull from
      // start() could finish its fact refresh AFTER the push below and write
      // its empty pointer over a green pill.
      target.delayNextBy(const Duration(milliseconds: 40));
      final starting = controller.start();

      await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
      await starting;
      await controller.retryNow();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.status.value.state, BackupPillState.backedUp,
          reason: 'a stale refresh must not outlive the operation it describes');
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
```

- [ ] **Step 4: Run the owning test file**

Run: `flutter test test/backup/backup_controller_test.dart`
Expected: `All tests passed!` (18 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_controller.dart \
        test/backup/backup_controller_test.dart
git commit -m "feat(backup): fold engine events into pill status, serialized"
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
  `dismiss`), `BackupLogEntry`, `relativeAge` (Task 1). Does **not** depend on
  the pill: it is anchored to whatever `BuildContext` opens it.
- Produces: `Future<void> showBackupLogPopover(BuildContext context, BackupController controller)`.

- [ ] **Step 1: Implement**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_log.dart';
import '../../services/backup/backup_status.dart';
import '../../services/backup/relative_time.dart';

const double _popoverWidth = 400;

/// Anchors the panel under [context]'s widget — the pill — and closes on a tap
/// anywhere else.
///
/// An `OverlayEntry` with a `TapRegion`, **not** `showDialog`. A dialog route
/// lays a barrier over the whole screen even when the barrier is transparent,
/// so the first tap after opening the popover is swallowed dismissing it: an
/// operator who glances at the pill mid-service then pays two taps to reach a
/// camera preset instead of one. An overlay entry only occupies its own rect,
/// and `WidgetsApp` already installs the `TapRegionSurface` that reports
/// outside taps (`widgets/app.dart:1836`), so the tap both closes this and
/// lands on whatever was under it.
Future<void> showBackupLogPopover(
  BuildContext context,
  BackupController controller,
) {
  final overlay = Overlay.of(context);
  final anchor = context.findRenderObject() as RenderBox?;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final origin = anchor == null
      ? Offset.zero
      : anchor.localToGlobal(anchor.size.bottomLeft(Offset.zero),
          ancestor: overlayBox);
  final maxLeft = (overlayBox.size.width - _popoverWidth - 8).clamp(8.0, 8.0e3);

  final closed = Completer<void>();
  late final OverlayEntry entry;
  void close() {
    if (closed.isCompleted) return;
    entry.remove();
    closed.complete();
  }

  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: origin.dx.clamp(8.0, maxLeft),
      top: origin.dy + 8,
      width: _popoverWidth,
      child: TapRegion(
        onTapOutside: (_) => close(),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: _BackupLogPanel(controller: controller, onClose: close),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  return closed.future;
}

class _BackupLogPanel extends StatelessWidget {
  const _BackupLogPanel({required this.controller, required this.onClose});

  final BackupController controller;

  /// Closes the popover before opening anything that takes over the screen.
  final VoidCallback onClose;

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
                  _pinnedRow(context, active.message, active.kind,
                      isConflict: BackupStatus.isQuestion(active.kind)),
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
  ///
  /// Coloured by severity, matching the pill. A divergence rendered red here
  /// while the pill calls it amber contradicts the spec's own "it is a
  /// question, not a failure".
  Widget _pinnedRow(
    BuildContext context,
    String message,
    String kind, {
    required bool isConflict,
  }) {
    final swatch = isConflict ? Colors.orange : Colors.red;
    return Container(
        color: swatch.shade50,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isConflict ? Icons.help_outline : Icons.error_outline,
                size: 16, color: swatch.shade800),
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
            // Deviation D6 promises this mark. Without it the operator's
            // "decide later" is invisible on the row it was about, and the
            // pinned amber row reads as though they never answered.
            if (isConflict && controller.deferralApplies)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: swatch.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Deferred',
                    style: TextStyle(fontSize: 10, color: swatch.shade800)),
              ),
          ],
        ),
      );
  }

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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Opened from a plain button, not from the pill: this task ships before the
  // pill does, and a test that needs the next task's widget cannot run.
  Future<BackupController> openPopover(WidgetTester tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    await controller.log.recordFault(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'push', targetIdentity: 'mock:test'));
    controller.status.value = const BackupStatus(configured: true);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showBackupLogPopover(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
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

  testWidgets('a tap outside closes it AND reaches what was underneath',
      (tester) async {
    // The reason this is an overlay and not a dialog route. A transparent
    // barrier still eats the tap, which during a service costs the operator a
    // wasted press on a dead screen before they can hit a camera preset.
    var pressedBehind = 0;
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => showBackupLogPopover(context, controller),
                child: const Text('open'),
              ),
              const SizedBox(height: 300),
              TextButton(
                onPressed: () => pressedBehind++,
                child: const Text('camera preset'),
              ),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Backup'), findsOneWidget);

    await tester.tap(find.text('camera preset'));
    await tester.pumpAndSettle();

    expect(find.text('Backup'), findsNothing, reason: 'the popover closed');
    expect(pressedBehind, 1,
        reason: 'and the tap was not swallowed by a barrier');
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
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showBackupLogPopover(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Shown once — pinned — and not as a dismissable history row.
    expect(find.text('Sign in again.'), findsOneWidget);
    expect(find.byTooltip('Mark as read'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the owning test files**

Run: `flutter test test/backup/backup_log_popover_test.dart`
Expected: `All tests passed!` (3 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/backup/backup_log_popover.dart \
        test/backup/backup_log_popover_test.dart
git commit -m "feat(backup): log popover with pinned condition and dismissals"
```

---

### Task 8: The AppBar pill

**Test-policy class:** 3 presentation, with **one** Class 2 wiring test. The
five-state matrix is already covered as pure logic in Task 2; re-running it
through `pumpWidget` is the anti-pattern `docs/learned/verification.md` names.
The one test asserts the user-visible outcome: the pill shows the derived
label and tapping it opens the popover.

**Files:**
- Create: `lib/widgets/backup/backup_status_pill.dart`
- Test: `test/backup/backup_status_pill_test.dart`

**Interfaces:**
- Consumes: `BackupController.status`, `BackupStatus.label`, and
  `showBackupLogPopover` from Task 7 — which is why the popover is built
  first. The earlier draft had these two the other way round, so following
  the declared order meant this task's test could not compile.
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

### Task 9: Wire it into the app, with lifecycle

**Test-policy class:** 1 for the scheduler's start-up resume (a mutation that
never gets pushed is exactly "lose a configuration that took an hour to
enter"); 2 for the wiring itself — one thin test asserting the pill is in the
AppBar and a real foreground event reaches the engine. Layout is Class 3,
verified by screenshot in Task 10.

**Rewritten after review.** The staged `conflict` scenario in the first draft
could not produce the state it claimed — a pristine machine adopts a lone
remote revision rather than diverging from it, so Task 10 would have
screenshotted green and called it "Needs review". The scenarios below were
each walked through the live pull branches at `backup_service.dart:109-180`.

**Files:**
- Modify: `lib/services/backup/backup_scheduler.dart:91-92` (start-up resume)
- Modify: `lib/services/backup/backup_controller.dart` (scenario staging)
- Modify: `lib/widgets/multi_device_control_page.dart:25-31` (constructor),
  `:32-70` (state and `initState`), `:122-130` (`dispose`), `:396-399` and
  `:467-470` (both AppBars)
- Test: `test/backup/backup_scheduler_test.dart` (append), `test/backup/backup_wiring_test.dart`

**Interfaces:**
- Consumes: `BackupController.forEnvironment()`, `BackupStatusPill`.
- Produces: `MultiDeviceControlPage({super.key, BackupController? backupController})`;
  `BackupController.mockScenario`.

- [ ] **Step 1: Make app start resume pending work, not just pull**

`onAppStart()` only pulls (`backup_scheduler.dart:91-92`). The spec's
durability section promises pending intent is resumed "on next start or
foreground"; today a mutation killed before its 30-second debounce waits for a
foreground event or the ten-minute sweep. On the iPad — where iOS suspends
Dart within seconds, which is the whole reason the generation counter is
persisted — that is the common case, not the rare one.

It also closes the one real hole in deviation D1: with this, a push that was
failing before a restart fails again within seconds of launch and the pill
goes back to red on its own, instead of sitting amber until the sweep.

```dart
  /// Pull on launch, then resume anything the last run left pending.
  ///
  /// The round trip also proves the credential still works.
  Future<void> onAppStart() async {
    await _run(_Op.pull);
    if (!_stopped && await ConfigMutationNotifier.instance.isDirty()) {
      await _run(_Op.push);
    }
  }
```

That is now identical to `onForeground()`. Leave both names: they are called
from different places and one may diverge later.

Test, appended to `test/backup/backup_scheduler_test.dart`:

```dart
  test('app start resumes a push the previous run never finished', () async {
    // The mutation outlived the process; the in-memory debounce timer did not.
    await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue);

    await scheduler.onAppStart();

    expect(scheduler.pushCount, 1);
    expect(target.revisions, hasLength(1));
  });
```

- [ ] **Step 2: Stage demo scenarios that actually reach the state they name**

The pill has five states and only three are reachable by using the app against
an empty in-memory target. Without staging, Task 10's screenshots cannot show
red or "Needs review", and `docs/learned/verification.md` is explicit that
presentation work is not done until the screenshots have been looked at.

Staging must be **awaited before the first pull**, and it must put the machine
in a state the pull actually classifies the way the scenario claims. Replace
`BackupController.forEnvironment()` with:

```dart
  /// Which state the mock target should stage, for demonstrating the surface
  /// before Drive exists: `ok`, `authExpired`, `offline`, `conflict`.
  /// Only read when [useMockTarget] is set.
  static const String mockScenario =
      String.fromEnvironment('BACKUP_SCENARIO', defaultValue: 'ok');

  factory BackupController.forEnvironment() {
    if (!useMockTarget) return BackupController.disabled();

    final target = MockBackupTarget();
    final service = BackupService(
      target: target,
      targetIdentity: 'mock:in-memory',
      deviceLabel: () async => 'This machine',
      readBundleJson: () async => (await ConfigBundle.fromStores()).toJson(),
      localIsPristine: ConfigBundle.localIsPristine,
    );

    return BackupController.forService(
      service,
      stageScenario: () => _stage(mockScenario, target, service),
    );
  }

  /// Runs before the first pull, and is awaited.
  ///
  /// Every branch here was walked against the live pull algorithm
  /// (`backup_service.dart:109-180`). An earlier draft simply dropped one
  /// revision into an empty target and called it a conflict: a pristine
  /// machine with a null pointer **adopts** that revision (branch 3), so the
  /// pill went green and the screenshot would have been of the wrong state.
  static Future<void> _stage(
    String scenario,
    MockBackupTarget target,
    BackupService service,
  ) async {
    switch (scenario) {
      case 'authExpired':
        target.failNextWith(AppFault.backup(
            BackupFailureKind.authExpired, 'Sign in to Google again.',
            operation: 'pull', targetIdentity: 'mock:in-memory'));
      case 'offline':
        target.failNextWith(AppFault.backup(
            BackupFailureKind.offline, 'Could not reach Google Drive.',
            operation: 'pull', targetIdentity: 'mock:in-memory'));
      case 'conflict':
        // Provenance this machine against a first revision, then have another
        // machine write a SIBLING of it. Pull then reaches branch 7: the head
        // is neither our pointer nor a descendant of it.
        final ours = await service.push();
        final base = ours.revision;
        if (base == null) return;
        await target.put(
          '{"schemaVersion":1,"positions":[{"id":"p9","name":"Balcony"}],'
          '"people":[],"services":[],"heightRanges":[],"presetNames":{},'
          '"visibilities":{}}',
          contentHash: 'staged-sibling',
          parentRevisionId: base.parentRevisionId,
          deviceLabel: "Daniel's iPad",
        );
      default:
        break;
    }
  }
```

`BackupController.forService` gains the parameter, and `start()` awaits it
before `scheduler.onAppStart()` — both are in Task 5's implementation.

**`BACKUP_SCENARIO=conflict` needs local configuration to exist first.** Run
it on a machine that has been used, or add one position in Settings and
restart. On a genuinely pristine machine `push()` uploads an empty bundle and
the sibling still diverges from it, so the state is reached either way — but
the difference summary is more useful with real data in it.

- [ ] **Step 3: Own the controller on the page**

In `lib/widgets/multi_device_control_page.dart`, change the widget declaration
(`:25-31`):

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

Add `import 'dart:async';`,
`import '../services/backup/backup_controller.dart';` and
`import 'backup/backup_status_pill.dart';` to the file's imports.

- [ ] **Step 4: Put the pill in both AppBars**

There are two. The disconnected-state `AppBar` at `:397` and the connected one
at `:468`. Both get the same two lines, immediately after `AppBar(`:

```dart
          centerTitle: false,
          title: BackupStatusPill(controller: _backup),
```

`centerTitle: false` is explicit per Global Constraint 8: the connected AppBar
left-aligns today only because it has four action entries, and dropping to one
would silently centre the pill.

- [ ] **Step 5: Write the one wiring test**

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

    // The real signal an operator produces by leaving and coming back.
    // Going through `paused` first is not decoration: `SchedulerBinding`
    // early-returns on a repeated state (`scheduler/binding.dart:414-417`),
    // and a test binding starts out `resumed`.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(scheduler.pullCount, greaterThan(pullsAfterStart),
        reason: 'foregrounding must pull; a dead credential surfaces there');

    await controller.dispose();
  });
}
```

- [ ] **Step 6: Run the owning test files and the full suite**

Run: `flutter test test/backup/backup_wiring_test.dart test/backup/backup_scheduler_test.dart`
Expected: `All tests passed!`

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/multi_device_control_page.dart \
        lib/services/backup/backup_controller.dart \
        lib/services/backup/backup_scheduler.dart \
        test/backup/backup_wiring_test.dart \
        test/backup/backup_scheduler_test.dart
git commit -m "feat(backup): wire the status pill in, resume pending work at launch"
```

---

### Task 10: Lane 3a sweep

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
Task 9. Build and drive with `tools/mock_server/drive_macos_app.sh` per
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

### Task 11: One fork-checked append primitive

**Test-policy class:** 1 trust contract. This is a refactor of the one path
that already writes revisions, so the proof is that the existing push suite
stays green — plus one new test for the race the primitive exists to catch.

Split from what was one 600-line task. This task extracts the primitive and
puts `push()` on it; Task 12 builds the three resolution paths that also need
it. Doing the refactor alone first means a regression here is visible against
`test/backup/backup_service_push_test.dart` before any new behaviour is added
on top.

**Why it exists:** `push()` already handles the fact that Drive's
`files.create` has no compare-and-swap, so `latest()`-then-`put()` is a
time-of-check/time-of-use race (`backup_service.dart:293-305`). The first draft
of this plan wrote "Keep mine" and restore-as-newest as separate protocols that
did **not** check, so two machines resolving the same conflict at the same
moment would both report success and both go green. One primitive, one check.

**Files:**
- Modify: `lib/services/backup/backup_service.dart`
- Test: `test/backup/backup_service_push_test.dart` (append one test)

**Interfaces:**
- Consumes: the existing `_single`, `_withStorageBoundary`, `_applyRevision`.
- Produces: `enum ResolutionOutcome`, `class ResolutionResult`,
  `class _AppendResult`, `Future<_AppendResult> _appendRevision({...})`,
  `Map<String, dynamic> _decodeRevision(BackupRevision, String)`.

- [ ] **Step 1: Extract the append primitive and put `push()` on it**

Add `import 'package:shared_preferences/shared_preferences.dart';` to
`backup_service.dart`, then add above `_withStorageBoundary`:

```dart
enum ResolutionOutcome {
  resolved,
  localChangedDuringResolve,
  remoteMovedAgain,
  forkedAgain,
}

class ResolutionResult {
  final ResolutionOutcome outcome;
  final BackupRevision? revision;
  final List<BackupRevision>? siblings;
  const ResolutionResult(this.outcome, {this.revision, this.siblings});
}

class _AppendResult {
  final BackupRevision revision;
  final List<BackupRevision> siblings;
  const _AppendResult(this.revision, this.siblings);
}
```

and inside `BackupService`:

```dart
  /// Uploads [json] as a child of [parentRevisionId], optionally taking the
  /// pointer with it, and performs the post-write sibling check.
  ///
  /// **Every path that writes a revision goes through here.** Drive's
  /// `files.create` has no compare-and-swap, so `latest()`-then-`put()` is a
  /// time-of-check/time-of-use race on all three of them. `push()` already
  /// handled that; "Keep mine" and restore-as-newest were written as separate
  /// protocols that did not, so two machines resolving the same conflict at
  /// the same moment would both report success and both go green.
  Future<_AppendResult> _appendRevision({
    required String json,
    required String hash,
    required String? parentRevisionId,
    required bool adoptPointer,
    required int generation,
  }) async {
    final revision = await target.put(
      json,
      contentHash: hash,
      parentRevisionId: parentRevisionId,
      deviceLabel: await deviceLabel(),
    );

    if (adoptPointer) {
      await BackupPointer.save(
        revisionId: revision.id,
        recordedHash: hash,
        targetIdentity: targetIdentity,
      );
      await ConfigMutationNotifier.instance.markSynced(generation);
    }

    final recent = await target.list(limit: 10);
    final siblings = recent
        .where((r) =>
            r.id != revision.id &&
            r.parentRevisionId == revision.parentRevisionId)
        .toList();
    return _AppendResult(revision, siblings);
  }
```

Replace `_push()`'s steps 3 and 4 (`backup_service.dart:278-307`) with:

```dart
    // 3-4. Upload, recording where we branched from, then check for a writer
    //      that slipped in between our latest() and our put().
    final appended = await _appendRevision(
      json: json,
      hash: hash,
      parentRevisionId: pointer.revisionId,
      adoptPointer: true,
      generation: generation,
    );
    if (appended.siblings.isNotEmpty) {
      return PushResult(PushOutcome.forked,
          revision: appended.revision, siblings: appended.siblings);
    }
    return PushResult(PushOutcome.uploaded, revision: appended.revision);
```

This is a pure refactor: the existing push tests in
`test/backup/backup_service_push_test.dart` must stay green untouched. Run
them before writing anything else.

- [ ] **Step 2: Extract the revision decoder `_applyRevision` already contains**

`restoreRevision` needs to validate a body before uploading it, and
`_applyRevision` has that logic inline (`backup_service.dart:187-211`). Pull
it out so there is one:

```dart
  Map<String, dynamic> _decodeRevision(BackupRevision revision, String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw AppFault.backup(
        BackupFailureKind.malformedRemote,
        'revision ${revision.id} is not valid JSON',
        operation: 'pull',
        targetIdentity: targetIdentity,
        cause: e,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AppFault.backup(
        BackupFailureKind.malformedRemote,
        'revision ${revision.id} is not a JSON object',
        operation: 'pull',
        targetIdentity: targetIdentity,
      );
    }
    return decoded;
  }
```

and have `_applyRevision` call it in place of its inline block.

- [ ] **Step 3: Prove the primitive catches what it exists to catch**

Append to `test/backup/backup_service_push_test.dart`:

```dart
  test('a writer that slips in between latest() and put() is reported',
      () async {
    await PositionStore.saveAll([Position(id: 'p1', name: 'Pulpit')]);
    target.concurrentWriterBeforePut(
      body: '{"schemaVersion":1,"positions":[],"people":[],"services":[],'
          '"heightRanges":[],"presetNames":{},"visibilities":{}}',
      parentRevisionId: null,
      deviceLabel: "Daniel's iPad",
    );

    final result = await service.push();

    expect(result.outcome, PushOutcome.forked);
    expect(result.siblings, isNotEmpty);
    expect(target.revisions, hasLength(2),
        reason: 'append-only: both bodies survive, and we say so');
  });
```

- [ ] **Step 4: Run the suite this refactored**

Run: `flutter test test/backup/backup_service_push_test.dart test/backup/backup_service_pull_test.dart`
Expected: `All tests passed!` — the existing tests unmodified, plus the new one.

- [ ] **Step 5: Commit**

```bash
git add lib/services/backup/backup_service.dart \
        test/backup/backup_service_push_test.dart
git commit -m "refactor(backup): one fork-checked append primitive behind push"
```

---

### Task 12: The three resolution paths

**Test-policy class:** 1 trust contract. Every one of these overwrites
configuration or writes a revision. This is the highest-consequence code in the
phase.

**Rewritten after review.** Two blockers, both real:

- **Restore applied before uploading.** `_applyRevision` moves the pointer onto
  the restored ancestor, so a failed or killed upload left the next pull
  matching branch 6 (`backup_service.dart:165-176`) and **silently re-applying
  the revision the operator had just undone**. Pull runs before push at every
  trigger, so nothing healed it. Inverted to upload-then-apply.
- **"Use the remote copy" preserved nothing.** The spec requires snapshotting
  local first (`spec:451`); without it an hour of unpushed work existed nowhere
  after the operator chose the other machine's copy.

**Files:**
- Modify: `lib/services/backup/backup_service.dart` (Task 11)
- Test: `test/backup/backup_resolution_test.dart`

**Interfaces:**
- Consumes: `_appendRevision`, `_decodeRevision`, `ResolutionResult` (Task 11).
- Produces: `Future<ResolutionResult> adoptRemote(BackupRevision)`;
  `Future<ResolutionResult> keepLocalAsNewRevision(BackupRevision remoteHead)`;
  `Future<ResolutionResult> restoreRevision(BackupRevision)`;
  `Future<List<BackupRevision>> history({int limit = 50})`;
  `Future<String> fetchBody(BackupRevision)`;
  `static const String replacedSnapshotKey`;
  `static Future<Map<String, dynamic>?> replacedSnapshot()`.

- [ ] **Step 1: "Use the remote copy", preserving what it replaces**

```dart
  /// The local configuration that "Use the remote copy" replaced.
  ///
  /// One slot, most recent wins. The spec requires snapshotting local before
  /// adopting (`spec:451`) and an earlier draft of this plan dropped that
  /// requirement: the operator could have an hour of unpushed work, choose
  /// "Use their copy", and have it vanish with no revision anywhere holding
  /// it. A single recoverable slot is what a recovery UI can actually offer.
  static const String replacedSnapshotKey = 'backup_replaced_snapshot';

  static Future<Map<String, dynamic>?> replacedSnapshot() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(replacedSnapshotKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<ResolutionResult> adoptRemote(BackupRevision revision) =>
      _single(() => _withStorageBoundary('resolve', () async {
            final generation =
                await ConfigMutationNotifier.instance.generation();
            final localBundle = await readBundleJson();
            final localHash = canonicalHash(localBundle);

            // Written BEFORE the fetch. A fetch that fails after the stores
            // were replaced would otherwise leave nothing preserved, and the
            // whole point of this slot is that it exists when it is needed.
            final prefs = await SharedPreferences.getInstance();
            final saved = await prefs.setString(
              replacedSnapshotKey,
              jsonEncode({
                'replacedAt': DateTime.now().toUtc().toIso8601String(),
                'hash': localHash,
                'bundle': localBundle,
              }),
            );
            if (!saved) {
              await prefs.reload();
              throw AppFault.backup(
                BackupFailureKind.storageWriteFailed,
                "Could not keep a copy of this device's settings before "
                'replacing them, so nothing was changed.',
                operation: 'resolve',
                targetIdentity: targetIdentity,
              );
            }

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
```

- [ ] **Step 2: "Keep my copy as a new revision", fork-checked**

```dart
  /// Append-only means this ADDS; the remote copy is not destroyed, it
  /// becomes this revision's parent.
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

            final appended = await _appendRevision(
              json: json,
              hash: hash,
              parentRevisionId: head.id,
              adoptPointer: true,
              generation: generation,
            );
            return ResolutionResult(
              appended.siblings.isEmpty
                  ? ResolutionOutcome.resolved
                  : ResolutionOutcome.forkedAgain,
              revision: appended.revision,
              siblings: appended.siblings,
            );
          }));
```

- [ ] **Step 3: Restore — upload first, then apply**

```dart
  /// Restores [revision] and makes it the newest backup.
  ///
  /// **Upload first, then apply.** The reverse order is a silent data-loss
  /// bug, and it is the one an earlier draft of this plan specified.
  /// `_applyRevision` moves the pointer onto the restored ancestor
  /// (`backup_service.dart:225-229`). If the upload then fails — offline, or
  /// the process is killed — the next pull finds `head.parentRevisionId ==
  /// pointer` with local clean, matches branch 6
  /// (`backup_service.dart:165-176`), and re-applies the exact revision the
  /// operator just undid. Silently. And pull runs before push at every
  /// trigger, so nothing heals it.
  ///
  /// Uploading first inverts every failure into a safe one: a crash before
  /// `put` leaves local untouched, and a crash after `put` leaves one extra
  /// revision at the target whose parent is the current head — which the next
  /// pull applies through branch 6, finishing the restore rather than
  /// reversing it.
  Future<ResolutionResult> restoreRevision(BackupRevision revision) =>
      _single(() => _withStorageBoundary('resolve', () async {
            // Captured BEFORE the fetch. "Did local change while this ran"
            // has to cover the download too — reading these afterwards makes
            // the freshness guard blind to the exact window it exists for,
            // and leaves `localChangedDuringResolve` unreachable. `adoptRemote`
            // reads them in this order for the same reason.
            final generation =
                await ConfigMutationNotifier.instance.generation();
            final localHash = canonicalHash(await readBundleJson());

            final raw = await target.fetch(revision);
            final decoded = _decodeRevision(revision, raw);
            // Throws before anything is written anywhere.
            ConfigBundle.fromJsonValidated(decoded);

            final json = canonicalJsonEncode(decoded);
            final hash = canonicalHash(decoded);

            final head = await target.latest();

            // Restoring the newest revision, or an older one byte-identical
            // to it: there is nothing to append.
            if (head != null && head.bodyChecksum == bodyChecksumOf(json)) {
              final applied = await _applyRevision(
                head,
                expectedLocalHash: localHash,
                expectedGeneration: generation,
              );
              return ResolutionResult(
                applied
                    ? ResolutionOutcome.resolved
                    : ResolutionOutcome.localChangedDuringResolve,
                revision: head,
              );
            }

            final appended = await _appendRevision(
              json: json,
              hash: hash,
              parentRevisionId: head?.id,
              // The pointer moves when the STORES do, not before: a pointer
              // naming a revision whose content is not on this machine makes
              // isCleanAgainst lie.
              adoptPointer: false,
              generation: generation,
            );
            if (appended.siblings.isNotEmpty) {
              return ResolutionResult(ResolutionOutcome.forkedAgain,
                  revision: appended.revision, siblings: appended.siblings);
            }

            final applied = await _applyRevision(
              appended.revision,
              expectedLocalHash: localHash,
              expectedGeneration: generation,
            );
            return ResolutionResult(
              applied
                  ? ResolutionOutcome.resolved
                  : ResolutionOutcome.localChangedDuringResolve,
              revision: appended.revision,
            );
          }));

  /// Revisions for the history picker, newest first.
  Future<List<BackupRevision>> history({int limit = 50}) =>
      _single(() => _withStorageBoundary('history',
          () => target.list(limit: limit)));

  /// A revision's body, for the diff summary and the preview.
  Future<String> fetchBody(BackupRevision revision) => _single(
      () => _withStorageBoundary('history', () => target.fetch(revision)));
```

`_applyRevision(appended.revision)` re-downloads bytes this method already
holds. That is one wasted round trip against Drive and it buys a single apply
path with a single freshness guard; do not optimise it into a second one.

- [ ] **Step 4: Write the behavioral test**

```dart
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
      await setPositions(['Pulpit']);
      await service.push();
      final tuesday = (await service.history()).first;
      await setPositions(['Pulpit', 'Lectern', 'Choir']);
      await service.push();
      final headBefore = (await target.latest())!.id;

      target.failNextWith(AppFault.backup(
          BackupFailureKind.offline, 'Could not reach the backup.',
          operation: 'resolve', targetIdentity: 'mock:test'));

      await expectLater(
          service.restoreRevision(tuesday), throwsA(isA<AppFault>()));

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
```

- [ ] **Step 5: Run the owning test file and the suite it builds on**

Run: `flutter test test/backup/backup_resolution_test.dart test/backup/backup_service_push_test.dart`
Expected: `All tests passed!` (11 new tests, push suite still green)

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/backup_service.dart \
        test/backup/backup_resolution_test.dart
git commit -m "feat(backup): adopt, keep-as-new-revision and upload-first restore"
```

---

### Task 13: The difference summary

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

    // Counted by BUTTON, not by device. Twenty renamed presets on one camera
    // is "20 changed", not "1 changed": an undercount here is exactly the
    // "three unlabelled buttons" problem in a different costume.
    int innerCount(Object? raw, bool Function(String device, String item) keep) {
      if (raw is! Map) return 0;
      var n = 0;
      raw.forEach((device, items) {
        if (items is! Map) return;
        for (final item in items.keys) {
          if (keep('$device', '$item')) n++;
        }
      });
      return n;
    }

    Object? item(Object? raw, String device, String key) {
      if (raw is! Map) return null;
      final items = raw[device];
      return items is Map ? items[key] : null;
    }

    return BundleSectionDiff(
      label: label,
      added: innerCount(theirsRaw,
          (d, i) => item(mineRaw, d, i) == null),
      removed: innerCount(mineRaw,
          (d, i) => item(theirsRaw, d, i) == null),
      changed: innerCount(
          theirsRaw,
          (d, i) =>
              item(mineRaw, d, i) != null &&
              canonicalJsonEncode(item(mineRaw, d, i)) !=
                  canonicalJsonEncode(item(theirsRaw, d, i))),
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

  test('a per-device preset map counts by BUTTON, not by device', () {
    final mine = bundle(presetNames: {
      '10.0.1.10': {'1': 'Pulpit', '2': 'Lectern', '3': 'Choir'}
    });
    final theirs = bundle(presetNames: {
      '10.0.1.10': {'1': 'Pulpit', '2': 'Lectern (new)', '3': 'Choir loft'},
      '10.0.1.11': {'1': 'Balcony'},
    });

    // Two renamed buttons on one camera plus one new button on another.
    expect(BundleDiff.between(mine, theirs).lines,
        contains('Preset labels: 1 more, 2 changed'));
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

### Task 14: Conflict resolution — the controller plumbing

**Test-policy class:** 1 trust contract. This decides what clears a condition,
what a failed resolve leaves behind, and whether an operator's "decide later"
still applies to what is being asked. All of it is testable without mounting a
widget.

Split from what was one 600-line task; Task 15 builds the dialog on top.

**Revised after review.** Three fixes folded in: a successful resolve now
clears its own earlier failure (otherwise one failed attempt left the pill red
forever after the retry succeeded); the deferred revision id is dropped when
the head moves on, instead of labelling a new revision with an old decision;
and first-run adoption is treated as its own question rather than a conflict.

**Files:**
- Modify: `lib/services/backup/backup_controller.dart`
- Modify: `lib/services/backup/restore_journal.dart` (one engine key)
- Test: `test/backup/conflict_resolution_test.dart`

**Interfaces:**
- Consumes: `BackupService.adoptRemote`, `keepLocalAsNewRevision`,
  `fetchBody` (Task 12); `BundleDiff.between` (Task 13).
- Produces on `BackupController`: `static const String suppressedKey`;
  `String? deferredRevisionId`; `bool get deferralApplies`;
  `Future<BundleDiff> conflictDiff()`;
  `Future<ResolutionOutcome> resolveUseRemote()`;
  `Future<ResolutionOutcome> resolveKeepMine()`;
  `Future<void> deferConflict()`.

- [ ] **Step 1: Add the resolution plumbing to `BackupController`**

```dart
  /// The remote revision the operator chose to decide about later. Persisted
  /// so the choice survives a restart; it marks the row deferred and stops
  /// re-logging that revision. It does **not** turn the pill green — the
  /// divergence is still real.
  static const String suppressedKey = 'backup_conflict_suppressed';

  String? deferredRevisionId;

  /// Whether the operator's "decide later" still applies to what is being
  /// asked. A deferral is about ONE revision; when the other machine saves
  /// again, the question is new and the old answer does not carry over.
  bool get deferralApplies =>
      deferredRevisionId != null &&
      deferredRevisionId == conflictRevision?.id;

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
        // Both, not just the question. A resolve that failed once and then
        // succeeded would otherwise leave its own fault standing under
        // `resolve`, and a hard failure outranks everything: the dialog would
        // close, the log would say "resolved", and the pill would stay red.
        _conditions.remove('resolve');
        _clearQuestion();
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
        if (deferredRevisionId != null) await _clearDeferred();
      } else if (result.outcome == ResolutionOutcome.forkedAgain) {
        // Our upload landed, and so did someone else's, from the same parent.
        // Both bodies survive; the honest thing is to say so and re-ask.
        conflictRevision = result.siblings?.first ?? result.revision;
        _conditions.remove('resolve');
        await _raiseQuestion(
          conflictRevision,
          BackupFailureKind.conflict,
          'Another machine saved at the same moment. Both copies were kept.',
        );
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

  /// Disk first, memory only if the disk took it.
  ///
  /// The reverse order — which an earlier draft used — lets the two disagree:
  /// a refused `setString` leaves memory saying "deferred" over a disk that
  /// says nothing, so the operator's decision looks recorded until the next
  /// restart brings the same question back. `_clearDeferred` had the mirror
  /// bug, where a cleared deferral resurrected. Both now fail closed: on a
  /// refused write **neither** changes, so they cannot drift apart, and the
  /// refusal is logged rather than swallowed.
  ///
  /// Neither throws. This is bookkeeping about a question the operator has
  /// already been asked; failing the whole resolution over it would report a
  /// successful upload as a failure.
  Future<void> deferConflict() async {
    final id = conflictRevision?.id;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(suppressedKey, id)) {
      await prefs.reload();
      await log.recordFault(AppFault.backup(
        BackupFailureKind.storageWriteFailed,
        'Could not record that you chose to decide later. '
        'This will be asked again.',
        operation: 'resolve',
        targetIdentity: service?.targetIdentity,
      ));
      return;
    }
    deferredRevisionId = id;
  }

  Future<void> _clearDeferred() async {
    if (deferredRevisionId == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(suppressedKey)) {
      await prefs.reload();
      await log.recordFault(AppFault.backup(
        BackupFailureKind.storageWriteFailed,
        'Could not clear a deferred conflict.',
        operation: 'resolve',
        targetIdentity: service?.targetIdentity,
      ));
      return;
    }
    deferredRevisionId = null;
  }
```

In `start()`, after `await log.load();`, restore the deferred id:

```dart
    deferredRevisionId =
        (await SharedPreferences.getInstance()).getString(suppressedKey);
```

Replace `_raiseQuestion` whole, so a deferred revision stops adding log rows
while the condition itself is still raised — and so a deferral that no longer
applies is dropped rather than mislabelling a newer revision:

```dart
  Future<void> _raiseQuestion(
    BackupRevision? revision,
    BackupFailureKind kind,
    String message,
  ) async {
    conflictRevision = revision;

    // The other machine saved again: this is a different question, and the
    // operator has not answered it. Without this the popover keeps saying
    // "You chose to decide about this later" about a revision they have
    // never seen.
    if (deferredRevisionId != null && deferredRevisionId != revision?.id) {
      await _clearDeferred();
    }

    final fault = AppFault.backup(
      kind,
      message,
      operation: 'resolve',
      targetIdentity: service?.targetIdentity,
    );
    _raise(fault);
    // Deferred means "I have seen this one". The pill stays amber — the
    // divergence is still real — but the sweep stops writing about it.
    if (deferralApplies) return;
    await log.recordFault(fault);
  }
```

Add `BackupController.suppressedKey` to `RestoreJournal.engineKeys`.

`backup_controller.dart` also needs three imports it did not have in Task 5:
`dart:convert` (for `jsonDecode`), `bundle_diff.dart`, and `relative_time.dart`
(used by Task 16's restore log line).

- [ ] **Step 2: Write the behavioral test**

```dart
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Refuses exactly the deferral key, the way
/// `test/backup/backup_pointer_test.dart` refuses the pointer's.
class _RefuseDeferralWriteStore extends InMemorySharedPreferencesStore {
  _RefuseDeferralWriteStore() : super.withData(const {});

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${BackupController.suppressedKey}') return false;
    return super.setValue(valueType, key, value);
  }
}

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

  const emptyBundle = '{"schemaVersion":1,"positions":[],"people":[],'
      '"services":[],"heightRanges":[],"presetNames":{},"visibilities":{}}';

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

  test('"Decide later" is remembered but does not turn the pill green',
      () async {
    await diverge();
    await controller.deferConflict();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackupController.suppressedKey), isNotNull);
    expect(controller.deferralApplies, isTrue);
    expect(controller.status.value.state, BackupPillState.needsReview);
  });

  test('a deferral does not carry over to a newer revision', () async {
    await diverge();
    await controller.deferConflict();

    // The other machine saves again. This is a different question.
    await target.put(emptyBundle,
        contentHash: 'newer-still',
        parentRevisionId: null,
        deviceLabel: "Daniel's iPad");
    await controller.handleEvent(await service.push());

    expect(controller.deferralApplies, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BackupController.suppressedKey), isNull);
  });

  test('a deferral survives a relaunch', () async {
    // `start()` reads it back; nothing proved that until now, and the whole
    // point of persisting it is the machine that gets closed for the week.
    await diverge();
    await controller.deferConflict();
    final deferred = controller.deferredRevisionId;
    expect(deferred, isNotNull);

    final relaunched = BackupController.forService(
      service,
      scheduler: BackupScheduler(
        service: service,
        debounce: const Duration(milliseconds: 1),
        sweepInterval: const Duration(days: 1),
        sleep: (_) async {},
      ),
    );
    await relaunched.start();

    expect(relaunched.deferredRevisionId, deferred);
    await relaunched.dispose();
  });

  test('a head that moved again re-points the question and drops the deferral',
      () async {
    // ResolutionOutcome.remoteMovedAgain was handled in `_resolve` and
    // exercised nowhere. The operator is now being asked about a revision
    // they have never seen, so their earlier "decide later" cannot stand.
    await diverge();
    await controller.deferConflict();
    final deferredAbout = controller.conflictRevision!.id;

    // A third machine writes while the dialog is open.
    await target.put(emptyBundle,
        contentHash: 'newest',
        parentRevisionId: null,
        deviceLabel: 'A third machine');

    final outcome = await controller.resolveKeepMine();

    expect(outcome, ResolutionOutcome.remoteMovedAgain);
    expect(controller.conflictRevision!.id, isNot(deferredAbout));
    expect(controller.deferralApplies, isFalse);
    expect(controller.status.value.state, BackupPillState.needsReview);
  });

  test('a refused write leaves the deferral off BOTH memory and disk',
      () async {
    // Memory and disk must never disagree: a decision that looks recorded and
    // is not comes back as the same question after a restart, and the operator
    // has no way to tell why. The store double below is the pattern
    // `test/backup/backup_pointer_test.dart:6-19` already uses.
    await diverge();
    SharedPreferencesStorePlatform.instance = _RefuseDeferralWriteStore();

    await controller.deferConflict();

    expect(controller.deferredRevisionId, isNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString(BackupController.suppressedKey),
        isNull);
    expect(controller.log.entries.value.first.kind, 'storageWriteFailed');
  });

  test('a resolve that fails once and then succeeds does not stay red',
      () async {
    await diverge();
    target.failNextWith(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'resolve', targetIdentity: 'mock:test'));

    await expectLater(controller.resolveKeepMine(), throwsA(isA<AppFault>()));
    expect(controller.status.value.state, BackupPillState.failing);

    final outcome = await controller.resolveKeepMine();

    expect(outcome, ResolutionOutcome.resolved);
    expect(controller.status.value.activeCondition, isNull,
        reason: 'the failure it is about has been superseded by success');
    expect(controller.status.value.state, BackupPillState.backedUp);
  });
}
```

`shared_preferences_platform_interface` is already a transitive dependency and
already imported this way by `test/backup/backup_pointer_test.dart:4` — no
pubspec change. Register the double inside the one test that needs it; the
`setUp` above resets `SharedPreferences` for every other.

- [ ] **Step 3: Run the owning test file**

Run: `flutter test test/backup/conflict_resolution_test.dart`
Expected: `All tests passed!` (6 tests)

- [ ] **Step 4: Commit**

```bash
git add lib/services/backup/backup_controller.dart \
        lib/services/backup/restore_journal.dart \
        test/backup/conflict_resolution_test.dart
git commit -m "feat(backup): conflict resolution plumbing on the controller"
```

---

### Task 15: The conflict dialog

**Test-policy class:** 2 wiring — one thin test per action asserting the
user-visible outcome, plus one for the comparison-failed state. Layout is
Class 3 and gets screenshots in Task 18.

**Files:**
- Create: `lib/widgets/backup/conflict_dialog.dart`
- Modify: `lib/widgets/backup/backup_log_popover.dart` (header action)
- Test: `test/backup/conflict_dialog_test.dart`

**Interfaces:**
- Consumes: Task 14's controller methods; `BundleDiff` (Task 13);
  `relativeAge` (Task 1); `BackupStatus.isQuestion` / `adoptionKind` (Task 2).
- Produces: `Future<void> showConflictDialog(BuildContext context, BackupController controller)`.

- [ ] **Step 1: Build the dialog**

```dart
import 'package:flutter/material.dart';

import '../../services/backup/app_fault.dart';
import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/backup_status.dart';
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
      case ResolutionOutcome.forkedAgain:
        setState(() => _diff = widget.controller.conflictDiff());
        _tell('Another machine saved at the same moment. Both copies were '
            'kept — here is theirs.');
    }
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final revision = widget.controller.conflictRevision;
    final now = DateTime.now();
    // First run holding local settings against a non-empty backup is NOT a
    // two-machine fight: on a brand-new iPad there is no other machine in the
    // story, and framing it as a conflict misdescribes the only decision that
    // can wipe out the other machine's work.
    final isAdoption = widget.controller.status.value.activeCondition?.kind ==
        BackupStatus.adoptionKind;

    return AlertDialog(
      title: Text(isAdoption
          ? 'Which settings should this device use?'
          : 'Two machines have different settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              revision == null
                  ? 'Another copy exists in the backup.'
                  : isAdoption
                      ? 'This device has settings of its own and has never '
                          'been backed up. The backup holds a copy saved by '
                          '${revision.deviceLabel} '
                          '${relativeAge(revision.createdAt.toLocal(), now)}.'
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
          child: Text(isAdoption ? 'Use the backup' : 'Use their copy'),
        ),
        FilledButton(
          onPressed:
              _working ? null : () => _run(widget.controller.resolveKeepMine),
          child: Text(isAdoption ? "Keep this device's" : 'Keep mine'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add the popover's action**

In `backup_log_popover.dart`'s `_header`, replace the single Retry button with:

```dart
          if (BackupStatus.isQuestion(status.activeCondition?.kind ?? ''))
            TextButton(
              onPressed: () {
                onClose();
                showConflictDialog(context, controller);
              },
              child: Text(
                status.activeCondition!.kind == BackupStatus.adoptionKind
                    ? 'Choose'
                    : 'Review',
              ),
            )
          else if (controller.canRetry)
            TextButton(
              onPressed: () => controller.retryNow(),
              child: const Text('Retry now'),
            ),
```

and add this to the header's `lines` list — keyed on `deferralApplies`, not on
the raw id, so a newer revision does not inherit an old decision:

```dart
      if (controller.deferralApplies)
        'You chose to decide about this later.',
```

- [ ] **Step 3: Write the wiring tests**

Reuse Task 14's `setUp` and `diverge()` helper verbatim — same target, service
and controller construction — with `package:flutter/material.dart` and
`conflict_dialog.dart` added to the imports.

```dart
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
```

(These go inside the reused `main()`, so the fragment ends with the last test —
do not add a closing brace of its own.)

- [ ] **Step 4: Run the owning test file**

Run: `flutter test test/backup/conflict_dialog_test.dart`
Expected: `All tests passed!` (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/backup/conflict_dialog.dart \
        lib/widgets/backup/backup_log_popover.dart \
        test/backup/conflict_dialog_test.dart
git commit -m "feat(backup): conflict dialog with difference summary"
```

---

### Task 16: Revision history and restore

**Test-policy class:** 1 for the restore path — already covered in Task 12,
which is where the guarantee lives. 2 for this sheet: one test that picking a
revision and confirming actually restores it. Layout is Class 3.

**Files:**
- Create: `lib/widgets/backup/revision_history_sheet.dart`
- Modify: `lib/widgets/settings_dialog.dart` (a Backup section)
- Modify: `lib/services/backup/backup_controller.dart` (`history`, `restore`)
- Test: `test/backup/revision_history_test.dart`

**Interfaces:**
- Consumes: `BackupService.history`, `fetchBody`, `restoreRevision` (Task 12);
  `BundleDiff` (Task 13); `relativeAge` (Task 1).
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
        // The copy "Use their copy" set aside. Without a way back to it, the
        // snapshot Task 12 saves is storage nobody can reach.
        FutureBuilder<Map<String, dynamic>?>(
          future: BackupService.replacedSnapshot(),
          builder: (context, snapshot) {
            final saved = snapshot.data;
            if (saved == null) return const SizedBox.shrink();
            return TextButton(
              onPressed: () => _restoreReplacedCopy(saved),
              child: const Text('Undo "Use their copy"'),
            );
          },
        ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }

  /// Applies the local configuration that "Use the remote copy" replaced, and
  /// pushes it as the newest revision — the same shape as any other restore.
  Future<void> _restoreReplacedCopy(Map<String, dynamic> saved) async {
    final bundle = saved['bundle'];
    if (bundle is! Map<String, dynamic>) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Put this device\'s old settings back?'),
        content: Text(
          'These are the settings this device had before you chose to use '
          'the other machine\'s copy, on '
          '${saved['replacedAt'] ?? 'an earlier date'}. They become the '
          'newest backup. Nothing is deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Put them back')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ConfigBundle.fromJsonValidated(bundle).applyTransactionally();
      await widget.controller.retryNow();
      if (mounted) Navigator.of(context).pop();
    } on AppFault catch (fault) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not put them back: ${fault.message}')));
      }
    }
  }
}
```

- [ ] **Step 3: Reach it from Settings**

`SettingsDialog` is a `StatelessWidget` taking ~20 explicit callbacks
(`settings_dialog.dart:17-40`); follow that pattern rather than inventing a
new one. Add one more field beside them — **optional, not required**:

```dart
  /// Null in tests that construct this dialog directly. The tile is hidden
  /// rather than dead when there is nothing to open.
  final BackupController? backupController;
```

`this.backupController` in the constructor with no `required`. Making it
required breaks `test/settings_dialog_test.dart:27`, which constructs
`SettingsDialog` with today's arguments and would stop compiling — taking the
whole suite with it, contrary to Global Constraint 10.

Pass `backupController: _backup` from `_showSettingsDialog`
(`multi_device_control_page.dart:299`). Then the `Data` section (`:445-460`)
gains a third tile, guarded:

```dart
              if (backupController != null)
                _tile(
                  icon: Icons.history,
                  title: 'Backup History',
                  subtitle: 'Restore an earlier version of your configuration',
                  onTap: () =>
                      showRevisionHistory(context, backupController!),
                ),
```

Run `flutter test test/settings_dialog_test.dart` immediately after this edit,
before writing anything else in the task. It must stay green untouched.

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

(Reuse the `setUp` block from Task 14's test file — same target, service and
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

### Task 17: Naming this machine

**Test-policy class:** 1 for the rejection rules — a machine labelled
`localhost` is a lie the conflict dialog repeats back, and two iPads both
called `localhost` make the whole conflict UI useless. 2 for the settings
field.

**Files:**
- Create: `lib/services/backup/device_label.dart`
- Create: `lib/widgets/backup/device_name_dialog.dart`
- Modify: `lib/widgets/backup/conflict_dialog.dart` (name before uploading)
- Modify: `lib/services/backup/app_fault.dart` (one new kind)
- Test: `test/backup/device_label_test.dart`, `test/backup/device_name_dialog_test.dart`
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

  /// Whether two labels name the same machine, under the same normalisation
  /// the collision check uses.
  static bool isSameName(String? a, String? b) =>
      a != null && b != null && _normalize(a) == _normalize(b);

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
/// Lives in `lib/widgets/backup/device_name_dialog.dart` — top level, not a
/// method on the settings dialog, because the conflict dialog calls it too.
Future<void> nameThisMachine(
  BuildContext context,
  BackupController controller,
) async {
    final saved = await DeviceLabel.load();
    // A DIFFERENT machine's name is a collision; our own is not. Without this
    // exclusion, reopening the field after the first backup sanitises the
    // saved name against our own revisions, blanks the field, and then
    // refuses to save the same name back. The spec's word is "different".
    final namesInUse = [
      for (final r in await controller.history())
        if (!DeviceLabel.isSameName(r.deviceLabel, saved)) r.deviceLabel,
    ];
    final suggestion = DeviceLabel.sanitize(
      saved ?? DeviceLabel.hostCandidate(),
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
header when `status.activeCondition?.kind == 'deviceUnnamed'`:

```dart
          if (status.activeCondition?.kind == 'deviceUnnamed')
            TextButton(
              onPressed: () => nameThisMachine(context, controller),
              child: const Text('Name this machine'),
            )
          else if (...)
```

**Also guard the conflict dialog's uploading actions.** `require()` throws from
inside `put`, so on an unnamed machine "Keep mine" would fail with a red pill
instead of asking the one question that unblocks it — and "Keep mine" *is* a
first push. In `conflict_dialog.dart`, before running an action that uploads:

```dart
  Future<void> _runUpload(Future<ResolutionOutcome> Function() action) async {
    if (await DeviceLabel.load() == null) {
      await nameThisMachine(context, widget.controller);
      if (!mounted || await DeviceLabel.load() == null) return;
    }
    await _run(action);
  }
```

and call `_runUpload` for "Keep mine" / "Keep this device's". "Use their copy"
does not upload and needs no name.

`_nameThisMachine` therefore moves out of `settings_dialog.dart` into
`lib/widgets/backup/device_name_dialog.dart` as a public
`Future<void> nameThisMachine(BuildContext, BackupController)`, called from
both places. Same body, one home.

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

  test('this machine\'s OWN name is not a collision with itself', () {
    // Every revision we have ever pushed carries our label. Counting those as
    // collisions makes the name field unusable the moment it works.
    expect(DeviceLabel.isSameName('Sanctuary-Mac-mini', 'Sanctuary Mac mini'),
        isTrue);
    expect(DeviceLabel.isSameName("Daniel's iPad", 'Sanctuary Mac mini'),
        isFalse);
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

- [ ] **Step 4: Write the one wiring test for the field**

This task declares a Class 2 obligation and the first draft delivered no test
for it — the field, the offered default, and the save were asserted nowhere.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/device_label.dart';
import 'package:navigation_app/widgets/backup/device_name_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, BackupController controller) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => nameThisMachine(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a typed name is saved and unblocks the first backup',
      (tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    await open(tester, controller);

    await tester.enterText(find.byType(TextField), 'Sanctuary Mac mini');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(await DeviceLabel.load(), 'Sanctuary Mac mini');
    expect(await DeviceLabel.require(), 'Sanctuary Mac mini');
  });

  testWidgets('a worthless name is refused and nothing is saved',
      (tester) async {
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    await open(tester, controller);

    await tester.enterText(find.byType(TextField), 'localhost');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(await DeviceLabel.load(), isNull,
        reason: 'a machine labelled localhost is a lie the conflict UI '
            'would repeat back');
    expect(find.textContaining('not specific enough'), findsOneWidget);
  });

  testWidgets('reopening it offers the saved name back, not a blank field',
      (tester) async {
    // The collision check used to count this machine's own revisions, which
    // blanked the field the moment the name started working.
    await DeviceLabel.save('Sanctuary Mac mini');
    final controller = BackupController.disabled();
    addTearDown(controller.dispose);
    await open(tester, controller);

    expect(find.widgetWithText(TextField, 'Sanctuary Mac mini'),
        findsOneWidget);
  });
}
```

- [ ] **Step 5: Run the owning test files**

Run: `flutter test test/backup/device_label_test.dart test/backup/device_name_dialog_test.dart test/backup/backup_status_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/backup/device_label.dart \
        lib/services/backup/app_fault.dart \
        lib/services/backup/backup_status.dart \
        lib/services/backup/backup_controller.dart \
        lib/services/backup/restore_journal.dart \
        lib/widgets/backup/device_name_dialog.dart \
        lib/widgets/backup/conflict_dialog.dart \
        lib/widgets/settings_dialog.dart \
        test/backup/device_label_test.dart \
        test/backup/device_name_dialog_test.dart
git commit -m "feat(backup): explicit machine naming with rejected defaults"
```

---

### Task 18: Lane 3b sweep

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
| 5-state priority pill (`red` > `amber` conflict > `grey` > `amber` dirty > `green`) | 2 (derivation), 8 (widget) |
| Popover: pinned active conditions | 7 |
| Popover: collapse on `(domain, kind, operation, targetIdentity)` | 3 — the fingerprint already exists at `app_fault.dart:90` |
| Popover: dismiss controls (`x`) | 3 (`dismiss`), 7 (the control) |
| Popover: relative time ladders | 1 |
| Conflict dialog: machine identity, timestamp, diff summary | 13 (diff), 15 (dialog) |
| Conflict dialog: three explicit actions | 12 (engine paths), 15 (buttons) |
| Conflict dialog: per-revision prompt suppression | 14 (persistence), 7 (the `Deferred` chip), 15 (the button), as deviation D6 |
| Revision history picker: preview and restore | 16, resting on 12's restore guarantee |
| First-run device naming, rejecting invalid defaults | 17 |
| Lifecycle: `WidgetsBindingObserver`, pull on foreground, flush on background | 5 (the observer), 9 (registration) |
| Production `localIsPristine` across all 8 stores | 4 |
| Bounds: 14 days, 200 rows, byte cap, per-message truncation | 3 |
| `backup_log` persisted in `SharedPreferences` | 3 |
| Pill always clickable, green included | 8 |
| `centerTitle: false` set explicitly | 9 |
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
One forward reference remains, and it is intended: Task 17's pill copy makes
Task 2's coverage test fail until it lands. The pill/popover forward reference
that the first draft carried is gone — the popover is now built before the
pill that opens it.

**3. Type consistency.** Checked across tasks:

- `BackupStatus` field names (`activeCondition`, `hasDurableHead`, `isDirty`,
  `pendingCount`, `lastSuccessAt`, `configured`) are identical in Tasks 2, 5,
  6, 7 and 12.
- `BackupController` members used by the widgets — `status`, `log`, `canRetry`,
  `retryNow`, `dismiss`, `conflictRevision`, `conflictDiff`,
  `resolveUseRemote`, `resolveKeepMine`, `deferConflict`, `history`, `restore`,
  `service` — are each defined in Tasks 5–6, 14 or 16 before first use.
- `ResolutionOutcome` / `ResolutionResult` are defined in Task 11 and consumed
  in 12 and 13 with the same shape.
- `BackupLog.lastSuccessKey` is defined in Task 3 and read in Task 5.
- `RestoreJournal.dataKeys` / `dataPrefixes` / `engineKeys` are defined in
  Task 3 and consumed in Tasks 4, 14 and 17.
- `BundleDiff.between(mine, theirs)` argument order is the same in Tasks 11,
  12 and 13 — **mine first**, and the copy is phrased from theirs.

**4. Where the two reviews landed.** Ten findings changed the plan
materially; two were refuted with receipts. The full disposition is in the
[Revision log](#revision-log). What remains genuinely open, and what a third
reader should attack:

- **The replaced-copy slot holds one snapshot.** Adopt twice and the first
  local copy is gone. A second adopt within minutes of the first is the
  realistic way to lose it.
- **The status recomputes the full bundle hash on every event and every
  mutation.** `ConfigBundle.fromStores()` reads every key and re-encodes it.
  Cheap against in-memory `SharedPreferences`, but it runs on every save.
  Should it be cached against the generation counter?
- **`restoreRevision` re-downloads bytes it already holds** so that there is
  one apply path with one freshness guard. One wasted Drive round trip.
- **The popover is an `OverlayEntry` + `TapRegion`, and nothing owns it but the
  future it returns.** If the page is torn down while it is open the entry
  leaks. There is one route in this app, so it cannot happen today; it would
  the moment there are two.
- **The device-name collision check reads `list(limit: 50)`,** so two machines
  named while the target is unreachable can still collide until their first
  push.

---

## Limitations of this plan

Stated here rather than discovered at merge:

1. **Nothing in Phase 3 backs anything up.** Both lanes ship against no target
   in production. The first real backup happens in Phase 4.
2. **`MockBackupTarget` cannot fail mid-`put`,** so no test here covers a
   partial upload. That is Phase 4's problem, with a real transport. The
   interrupted-restore test stands in for it by failing the apply instead.
3. **The replaced-copy slot holds exactly one snapshot.** A second "Use their
   copy" overwrites the first. Recoverable, once.
4. **No integration test drives the pill through the mock rig.** The rig fakes
   the Roland and the cameras, not a backup target, and adding one would be
   ops work outside this lane.
5. **The popover is not keyboard-navigable and does not trap focus.** That is
   the price of it being a non-blocking overlay rather than a dialog route —
   the right trade during a service, and nobody operates this app by keyboard
   today.
6. **Deviations D1 and D6 change spec-stated behaviour.** Both are argued
   above, both were attacked in review, and D1's one real hole — a failed push
   hidden across a restart — is closed by Task 9's start-up resume rather than
   by persisting a claim nothing has re-proved.
7. **Two reviewer findings were refuted, not fixed.** If either receipt is
   wrong, the plan is wrong with it; both are reproducible in one command and
   named in the revision log.

---

## Revision log

Two cold cross-family reviewers on the committed plan at `d8cce3a`, per
`docs/superpowers/runbooks/lane-process.md` step 7, dispatched via
`scripts/handoff-to-agent.sh`:

- **`codex` / `gpt-5.6-sol`, high effort** (pid 22648, model in argv) —
  `BLOCKERS: 10`, verdict *not ready to execute*.
- **`grok` / `grok-4.6`, high effort** (pid 23641) — `BLOCKERS: 5`, verdict
  *not ready to execute*.

Both got the same brief, the whole artifact, an open mandate, and the three
standing questions. Severity below is **as filed**. Findings the two raised
independently are merged into one row and marked *both*.

### Refuted — receipts, no change made

| Filed | Claim | Receipt |
|---|---|---|
| `gpt-5.6-sol` BLOCKER 8 | "`num.clamp()` returns `num`; `pendingCount` and `Positioned.left` will not compile." | **False.** The analyzer special-cases `clamp` when receiver and both bounds share a type. Compiled the exact two expressions in a scratch package: `dart analyze` → `No issues found!`. Unchanged. |
| `grok-4.6` BLOCKER 5 | "`TestWidgetsFlutterBinding` is already `resumed`; the duplicate state no-ops and `didChangeAppLifecycleState` never runs, so Task 9's test fails." | **False.** `WidgetsBinding.handleAppLifecycleStateChanged` (`widgets/binding.dart:1330-1335`) calls `super` first — where the dedupe lives (`scheduler/binding.dart:414-417`) — and then notifies observers **unconditionally**. Probe test with a real observer saw `[resumed, paused, resumed]`, including the duplicate. The plan now goes `paused → resumed` anyway, because that is the sequence an operator actually produces, but the stated reason was wrong. |

### Accepted — blockers

| Filed | Finding | What changed | Receipt |
|---|---|---|---|
| BLOCKER, *both* | Restore applied before uploading, so a failed or killed upload leaves the pointer on the ancestor, the next pull matches branch 6, and the restore is **silently reversed**. | Task 12 `restoreRevision` inverted to **upload first, then apply**. New test `a failed upload leaves local UNTOUCHED, never half-restored`, plus one for the interrupted case. Deviation D5 rewritten. | Branch 6 at `backup_service.dart:165-176`; pointer save inside `_applyRevision` at `:225-229`; pull-before-push at `backup_scheduler.dart:91-99`. |
| BLOCKER, `gpt-5.6-sol` 1 | "Use the remote copy" discarded local work with nothing preserving it; the spec requires snapshotting local first. | Task 12 `adoptRemote` writes `backup_replaced_snapshot` **before the fetch**, and refuses to proceed if that write fails. Task 16 surfaces it as *Undo "Use their copy"*. | `spec:451` — "snapshot local first, then apply transactionally". |
| BLOCKER, *both* | `keepLocalAsNewRevision` and `restoreRevision` had no post-write sibling check, so two machines resolving the same conflict both reported success and both went green. | Task 11 extracts `_appendRevision` — put, optional pointer move, sibling scan — and Tasks 11–12 put `push()`, keep-mine and restore on it. New test using `MockBackupTarget.concurrentWriterBeforePut`. | The check they omitted is live at `backup_service.dart:293-305`. |
| BLOCKER, `gpt-5.6-sol` 4 | A conflict outcome left the operation's earlier transport failure standing; hard failures outrank questions, so the popover offered "Retry now" forever and the resolution UI was unreachable. | Task 6 `_onPull`/`_onPush` clear that operation's condition on **any** completed result. New test: `a completed pull clears its transport failure even when the answer is a conflict`. | — |
| BLOCKER, `gpt-5.6-sol` 5 | A successful resolve never cleared its own earlier `resolve` failure, so a retry that worked still left the pill red. | Task 14 `_resolve` removes `_conditions['resolve']` on success. New test: `a resolve that fails once and then succeeds does not stay red`. | — |
| BLOCKER, `gpt-5.6-sol` 7 | `_refreshFacts` read the raw pointer with no target-identity check, so an account or folder change could paint green over an empty target. | Task 5 adds `_pointer()`, mirroring the engine's own check. New test: `a pointer from another target is not this target's head`. | Engine equivalent at `backup_service.dart:101-104`. |
| BLOCKER, *both* | The controller's fold was unserialized (`unawaited(handleEvent)`), so an older `_refreshFacts` could finish last and write stale facts — "Not backed up" over a revision that exists. | Task 6 adds a `_fold` queue; the stream and mutation listeners enqueue instead of firing. New test: `a slow first event cannot repaint the pill after a later success`. | — |
| BLOCKER, `grok-4.6` 3 | `BACKUP_SCENARIO=conflict` staged one revision into an empty target — which a pristine machine **adopts** (branch 3), so Task 10 would have screenshotted green and labelled it "Needs review". Staging was also unawaited. | Task 9 replaces it with `_stage`, awaited before the first pull, which provenances the machine and then writes a **sibling** so pull reaches branch 7. | Branch 3 at `backup_service.dart:130-142`; branch 7 at `:178-179`. |
| BLOCKER, *both* | Making `SettingsDialog.backupController` required breaks an existing test and takes the whole suite down. | Task 16 makes it nullable and hides the tile when absent; the task now runs that file immediately after the edit. | `test/settings_dialog_test.dart:27`. |
| BLOCKER, *both* | The pill's task imported a file the popover's task created; the declared order was not executable. | The two swapped — popover first (Task 7), pill second (Task 8) — and the popover's test no longer mounts the pill. | — |
| BLOCKER, `grok-4.6` 6 (filed MAJOR) | `PullOutcome.nothingToDo` cleared a fork warning. After winning a fork race our revision **is** the head, so the next pull erased the warning while the sibling sat in the store. | Task 6 `_onPull` no longer clears the question on `nothingToDo`. New test. Promoted to blocker: it is silent, reachable, and loses the only warning this machine gets. | `nothingToDo` means only `head.id == pointer`, `backup_service.dart:146-148`. |

### Accepted — majors and minors

| Filed | Finding | What changed |
|---|---|---|
| MAJOR, *both* | `lastSuccessAt` could not be cleared, so the popover could date an unbacked configuration by an old backup. | `copyWith` gains `clearLastSuccess`; Task 5 shows an age only while the pointer is provenanced. New test. |
| MAJOR, *both* | Device-name uniqueness counted **this** machine's own revisions, so the field blanked itself and refused to re-save the current name after the first push. | `DeviceLabel.isSameName`; Task 17 excludes our own label. New test. |
| MAJOR, `grok-4.6` 8 | `DeviceLabel.require()` throws from inside `put`, so "Keep mine" on an unnamed machine failed red instead of asking the one question that unblocks it. | Task 17 extracts `nameThisMachine(...)` into its own widget file and the conflict dialog calls it before any uploading action. |
| MAJOR, `grok-4.6` 10 | First-run adoption was framed as "Two machines have different settings" — a lie on a brand-new iPad. | New `BackupFailureKind.adoptionChoice` and `BackupStatus.adoptionKind`; pill reads "Choose a copy"; the dialog asks its own question with its own button words. New tests in Tasks 2 and 5. |
| MAJOR, `gpt-5.6-sol` 13 | Deferral was not rescoped: a newer revision inherited an old "decide later". | `deferralApplies` compares against the **current** revision, and `_raiseQuestion` clears a deferral that no longer applies. New test. |
| MAJOR, *both* | Vacuous tests: the log-eviction test used 500 identical fingerprints that collapsed to one row and could not fail; the "conflict does not hide a hard failure" test constructed no conflict. | Both rewritten. The eviction test now uses 250 distinct fingerprints and asserts the opposite, honest thing — history **is** evictable, which is exactly why D1 keeps the active condition elsewhere. |
| MAJOR, `gpt-5.6-sol` 17 | `onAppStart()` only pulls, so a mutation killed before its debounce waits for a foreground event or the ten-minute sweep. | Task 9 Step 1 makes app start resume a pending push, with a test. This also closes the D1 objection. |
| MINOR, `grok-4.6` | Preset/visibility diff counted devices, not buttons: twenty renamed presets read "1 changed". | Task 13 counts inner entries. Test rewritten. |
| MINOR, *both* | The pinned popover row was always red, contradicting the pill's own amber for a question. | Coloured by severity, with a matching icon. |
| MINOR, `grok-4.6` | Task 1 claimed 13 tests; the snippet has 11. | Corrected. |
| MINOR, `grok-4.6` | Task 4's test group uses `RestoreJournal` without naming the import. | Import named in the task. |
| MINOR, `grok-4.6` | The File Structure blurb promised a `force` path on `_applyRevision` that Task 12 never adds. | Removed from the blurb; the freshness abort is the intended behaviour. |
| MINOR, `grok-4.6` | Unused `relative_time.dart` import on the controller at Task 14 would fail `flutter analyze` before Task 16 uses it. | The import note moved to Task 16, where the first use is. |
| MINOR, `grok-4.6` | "`showDialog` as the popover is a modal route. Tapping the pill during a service blocks camera buttons." | **Initially waved off, then verified and fixed.** A transparent barrier is still a barrier: the first tap after opening is spent dismissing it. Rebuilt as an `OverlayEntry` + `TapRegion`; `WidgetsApp` already installs the `TapRegionSurface` it needs (`widgets/app.dart:1836`). New test asserts the outside tap both closes the popover **and** reaches the button under it. |
| MINOR, `gpt-5.6-sol` 13b / `grok-4.6` | "The promised 'Deferred' row is not implemented; only an unqualified header line exists." | **Found still unfixed on a second audit** — deviation D6's own table claimed the row existed. Now rendered as a `Deferred` chip on the pinned row, gated on `deferralApplies`. |
| MAJOR, `gpt-5.6-sol` 16c | "Task 14 declares a Class 2 settings-field obligation but supplies no widget test for the field, default, save action, or first-push recovery." | **Found still unfixed on a second audit.** Task 17 gains `device_name_dialog_test.dart`: a typed name saves and unblocks `require()`, a worthless one is refused and saves nothing, and reopening offers the saved name back rather than a blank field. |
| MAJOR, `gpt-5.6-sol` 16d | "No resolution test covers … restart persistence." | **Found still unfixed on a second audit.** `start()` read the deferred id back and nothing asserted it. Task 14 gains `a deferral survives a relaunch`. |

### Round 3 — `gpt-5.6-sol`, read-only, relayed by a peer session

Five blockers, filed against the plan as it stood after round 2's fold. I
re-verified each independently before touching anything; **all five held**, and
two were worse than filed. One further defect of the same class turned up while
checking.

| Filed | Finding | Verified? | What changed |
|---|---|---|---|
| BLOCKER 1 | Task 12's test block has 19 `{` against 20 `}` — it will not compile. | **Yes.** A brace-balance sweep over every `dart` fence (strings and comments stripped, strings first so a `//` inside a literal is not mistaken for a comment) found it. | Stray brace removed. |
| — (found while checking) | A **second** unbalanced fence: Task 15's test fragment carries a closing `}` for a `main()` that lives in Task 14's file, which the reader is told to reuse. | Same sweep. | Brace removed, and the fragment now says in words that it goes inside the reused `main()`. |
| BLOCKER 2 | `an interrupted restore finishes on the next pull, never reverses` never calls `service.pull()`. | **Yes — and worse.** The test also asserts the wrong outcome. `restoreRevision` read `generation` and `localHash` *after* its `fetch`, so the mutation `beforeNextFetch` injects is already reflected in the expected values, `_applyRevision`'s guard matches, and the outcome is `resolved`, not `localChangedDuringResolve`. The test fails as written. | Two fixes. `restoreRevision` now captures freshness **before** the fetch, matching `adoptRemote` — otherwise the guard is blind to the window it exists for and `localChangedDuringResolve` is unreachable. The test is split: one for a mid-restore edit, and a new `an upload that lands without its apply is completed by the next pull` that reconstructs the post-kill state by hand and asserts on stores, pointer, a real `pull()`, and a following no-op `push()`. |
| BLOCKER 3 | The two precedence tests both expect whatever arrived last, so a naive most-recent-wins implementation passes both. The discriminating case — `offline('push')` **then** conflict, which Global Constraint 4 requires to stay red — is never constructed. | **Yes.** The implementation is correct (`_onPull` removes only `'pull'`), but nothing proved it. | Neighbour renamed to what it actually shows, and the missing direction added, asserting both the state and that the surviving condition is the push. |
| BLOCKER 4 | `_enqueue` swallows every exception via an empty `catchError`. | **Yes**, and it is reachable: `ConfigBundle.fromStores()` `jsonDecode`s every `preset_names_*` value with no guard (`config_bundle.dart:180-190`), so one corrupt key throws inside the fold. The pill would keep showing pre-event facts forever. | The handler records an `unknown` fault and raises it. New test drives it through `_enqueue` — via a `handleEventUnserialized` seam, because awaiting `handleEvent` directly bypasses the very error path under test. |
| BLOCKER 5 | `deferConflict` mutates memory before a `setString` that can fail; `_clearDeferred` has the mirror bug. Memory and disk drift, and the drift only shows up after a restart. | **Yes**, and inconsistent with this codebase's own convention — `BackupPointer.save` rolls back and `ConfigMutationNotifier._notify` throws rather than let the two disagree. | Both now write disk first and mutate memory only on success, so a refused write leaves **neither** changed; the refusal is logged rather than swallowed. Neither throws: this is bookkeeping about a question already asked, and failing a successful upload over it would be a worse lie. Two new tests — a refused write (using the `InMemorySharedPreferencesStore` double `test/backup/backup_pointer_test.dart:6-19` already uses, verified present) and `remoteMovedAgain`, an outcome `_resolve` handled and nothing exercised. |

The peer also relayed, and had already retracted, a claim that Task 4's stated
dependency on Task 3 makes a 1→4→3 probe order impossible. It does depend on
Task 3 — that is stated deliberately, and the retraction was correct.

Why round 3 happened at all: Daniel is evaluating whether a local model can
execute this plan task by task. Four of these five would have surfaced as
*executor* failures — a model faithfully reproducing the plan's own bug, or
passing a test that cannot discriminate — and been blamed on the model.

### Standing questions, as answered

Both reviewers answered all three. Their shared answer to (1) and (2) — *one
append primitive behind every writer, and make destructive resolution
recoverable* — is now the shape of Tasks 11–12. Their answer to (3) was **no**,
citing the missing snapshot, the unsafe restore order, the missing fork checks
and the unreachable resolution UI; those are the four blockers above.

Neither reviewer challenged the architecture. The three-fact model, the
precedence order, `localIsPristine` as key-presence, the 3a/3b split, and
deviations D2, D3, D4 and D6 were endorsed by both, independently.
