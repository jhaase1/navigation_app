import 'dart:async';
import 'dart:convert';

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
import 'bundle_diff.dart';
import 'canonical_json.dart';
import 'config_mutation_notifier.dart';
import 'device_label.dart';
import 'mock/mock_backup_target.dart';
import 'relative_time.dart';

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

  /// Which state the mock target should stage, for demonstrating the surface
  /// before Drive exists: `ok`, `authExpired`, `offline`, `conflict`.
  /// Only read when [useMockTarget] is set.
  static const String mockScenario =
      String.fromEnvironment('BACKUP_SCENARIO', defaultValue: 'ok');

  /// The remote revision the operator chose to decide about later. Persisted
  /// so the choice survives a restart; it marks the row deferred and stops
  /// re-logging that revision. It does **not** turn the pill green — the
  /// divergence is still real.
  static const String suppressedKey = 'backup_conflict_suppressed';

  factory BackupController.forEnvironment() {
    if (!useMockTarget) return BackupController.disabled();

    final target = MockBackupTarget();
    final service = BackupService(
      target: target,
      targetIdentity: 'mock:in-memory',
      deviceLabel: DeviceLabel.require,
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
        // push() goes through DeviceLabel.require; without a saved name
        // this branch throws deviceUnnamed and never stages.
        await DeviceLabel.save('This machine');
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
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  var _disposed = false;

  final ValueNotifier<BackupStatus> status =
      ValueNotifier<BackupStatus>(const BackupStatus());

  /// The remote revision behind the current question, for lane 3b's dialog.
  BackupRevision? conflictRevision;

  String? deferredRevisionId;

  /// Whether the operator's "decide later" still applies to what is being
  /// asked. A deferral is about ONE revision; when the other machine saves
  /// again, the question is new and the old answer does not carry over.
  bool get deferralApplies =>
      deferredRevisionId != null &&
      deferredRevisionId == conflictRevision?.id;

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
  factory BackupController.disabled(
          {BackupLog? log, DateTime Function()? now}) =>
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

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    await log.load();
    deferredRevisionId =
        (await SharedPreferences.getInstance()).getString(suppressedKey);
    if (_disposed) return;
    await _enqueue(_refreshFacts);
    if (_disposed) return;

    final scheduler = _scheduler;
    if (scheduler == null) return;

    // Awaited, and before the first pull: a scenario staged afterwards would
    // race the pull it exists to set up.
    await _stageScenario?.call();
    if (_disposed) return;

    _events =
        scheduler.events.listen((event) => _enqueue(() => handleEvent(event)));
    _mutations = ConfigMutationNotifier.instance.onMutated
        .listen((_) => _enqueue(_refreshFacts));

    scheduler.start();
    await scheduler.onAppStart();
  }

  Future<void> _enqueue(Future<void> Function() work) {
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
    return _fold;
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
        : fault.domain != FaultDomain.backup
            ? _deviceKey(fault.domain, fault.targetIdentity ?? '')
            : (fault.operation ?? 'unknown');
    // Remove before insert so insertion order tracks recency.
    _conditions.remove(key);
    _conditions[key] = fault;
  }

  static String _deviceKey(FaultDomain domain, String device) =>
      'device:${domain.name}:$device';

  /// Puts a device that has dropped off on the pill and in the log. The pill
  /// is the one surface for every failure in the app, not only backup's.
  /// Stays until [clearDeviceFault] — no backup success clears it.
  Future<void> reportDeviceFault(AppFault fault) => _enqueue(() async {
        await log.recordFault(fault);
        _raise(fault);
        _applyConditions();
      });

  /// The device is back, or the operator disconnected it on purpose.
  Future<void> clearDeviceFault(FaultDomain domain, String device) =>
      _enqueue(() async {
        if (_conditions.remove(_deviceKey(domain, device)) != null) {
          _applyConditions();
        }
      });

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

  Future<List<BackupRevision>> history() async {
    final backup = service;
    if (backup == null) return const [];
    return backup.history();
  }

  /// Puts back the configuration "Use their copy" replaced, as the newest
  /// backup. Upload first, then apply — the same shape as [restore].
  Future<ResolutionOutcome> restoreReplacedSnapshot() async {
    final backup = service;
    if (backup == null) return ResolutionOutcome.resolved;
    final saved = await BackupService.replacedSnapshot();
    final bundle = saved?['bundle'];
    if (bundle is! Map<String, dynamic>) return ResolutionOutcome.resolved;
    try {
      final result = await backup.restoreSnapshot(bundle);
      if (result.outcome == ResolutionOutcome.resolved) {
        _conditions.remove(_conflictKey);
        _conditions.remove('push');
        _conditions.remove('pull');
        _conditions.remove('resolve');
        conflictRevision = null;
        await _clearDeferred();
        final restored = result.revision!;
        await log.recordSuccess(
          operation: 'restore',
          kind: 'restored',
          message: 'Restored the backup from '
              '${restored.deviceLabel}, '
              '${relativeAge(restored.createdAt.toLocal(), _now())}.',
          targetIdentity: backup.targetIdentity,
        );
        await _markConfirmedStored();
      } else if (result.outcome ==
              ResolutionOutcome.localChangedDuringResolve &&
          result.revision != null) {
        // The append already landed; other machines will pull it. Adopt's
        // abort unwinds and is a local no-op — this one is not.
        _conditions.remove('resolve');
        await _raiseQuestion(
          result.revision,
          BackupFailureKind.conflict,
          'The backup already went back to that version. Other devices will '
          'follow it. This machine still has your newer edits.',
        );
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
        _conditions.remove('resolve');
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
      } else if (result.outcome ==
              ResolutionOutcome.localChangedDuringResolve &&
          result.revision != null) {
        // The append already landed; other machines will pull it. Adopt's
        // abort unwinds and is a local no-op — this one is not.
        _conditions.remove('resolve');
        await _raiseQuestion(
          result.revision,
          BackupFailureKind.conflict,
          'The backup already went back to that version. Other devices will '
          'follow it. This machine still has your newer edits.',
        );
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

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _scheduler?.stop();
    try {
      await _startFuture;
    } finally {
      await _events?.cancel();
      _events = null;
      await _mutations?.cancel();
      _mutations = null;
      await _scheduler?.stop();
      await _fold;
      // `status` and `log.entries` are deliberately NOT disposed. They
      // outlive any one widget, tests tear down in an order that would
      // otherwise use them after disposal, and two undisposed ValueNotifiers
      // on an app-lifetime object leak nothing that matters.
    }
  }
}
