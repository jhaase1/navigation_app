import 'dart:async';

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
    if (_disposed) return;
    await _refreshFacts();
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
