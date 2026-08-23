import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config_bundle.dart';
import 'abstract/backup_target_abstract.dart';
import 'app_fault.dart';
import 'backup_pointer.dart';
import 'backup_revision.dart';
import 'canonical_json.dart';
import 'config_mutation_notifier.dart';

enum PullOutcome {
  nothingToDo,
  adopted,
  applied,
  rebased,
  conflict,
  targetEmptied,
  needsAdoptionChoice,
}

class PullResult {
  final PullOutcome outcome;
  final BackupRevision? revision;
  const PullResult(this.outcome, {this.revision});
}

enum PushOutcome { noOp, uploaded, conflict, forked }

class PushResult {
  final PushOutcome outcome;
  final BackupRevision? revision;
  final BackupRevision? remoteRevision;
  final List<BackupRevision>? siblings;

  const PushResult(this.outcome,
      {this.revision, this.remoteRevision, this.siblings});
}

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

/// Owns the backup protocol.
///
/// Every operation runs through one single-flight queue. Pulls, debounced
/// pushes, periodic sweeps, manual retries and the backoff timer are
/// otherwise independent callers of the same mutable state, and an older
/// operation completing after a newer one would overwrite status or
/// provenance.
class BackupService {
  static const _backoff = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  final BackupTargetAbstract target;
  final String targetIdentity;
  final Future<String> Function() deviceLabel;
  final Future<Map<String, dynamic>> Function() readBundleJson;

  /// Whether local configuration is untouched — nothing worth protecting.
  /// Only consulted when the pointer is null.
  final Future<bool> Function() localIsPristine;

  Future<void> _queue = Future<void>.value();

  BackupService({
    required this.target,
    required this.targetIdentity,
    required this.deviceLabel,
    required this.readBundleJson,
    required this.localIsPristine,
  });

  /// How long to wait before retrying after [fault], or null when retrying
  /// cannot help.
  ///
  /// The schedule never terminates. A loop that exhausts its attempts and
  /// stops is a silent failure with extra steps: the pill would sit red
  /// forever with nothing trying to clear it.
  static Duration? nextRetryDelay(AppFault fault, int attempt) {
    if (!fault.isRetryable) return null;
    if (fault.sweepOnly) return const Duration(minutes: 10);
    final i = attempt.clamp(0, _backoff.length - 1).toInt();
    return _backoff[i];
  }

  /// Serializes [action] behind every operation already queued.
  Future<T> _single<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<BackupPointer> _pointer() async {
    final p = await BackupPointer.load();
    return p.matchesTarget(targetIdentity) ? p : const BackupPointer();
  }

  Future<PullResult> pull() =>
      _single(() => _withStorageBoundary('pull', _pull));

  Future<PullResult> _pull() async {
    // 1. Metadata only. A pointer from another target is meaningless.
    final head = await target.latest();
    final pointer = await _pointer();

    // 2. Remote empty.
    if (head == null) {
      if (!pointer.isProvenanced) {
        return const PullResult(PullOutcome.nothingToDo);
      }
      await BackupPointer.clear();
      return const PullResult(PullOutcome.targetEmptied);
    }

    final localGeneration = await ConfigMutationNotifier.instance.generation();
    final localBundle = await readBundleJson();
    final localJson = canonicalJsonEncode(localBundle);
    final localHash = canonicalHash(localBundle);
    final localChecksum = bodyChecksumOf(localJson);

    // 3. Unprovenanced. Never auto-apply over local data.
    if (!pointer.isProvenanced) {
      if (!await localIsPristine()) {
        return PullResult(PullOutcome.needsAdoptionChoice, revision: head);
      }
      final applied = await _applyRevision(
        head,
        expectedLocalHash: localHash,
        expectedGeneration: localGeneration,
      );
      return PullResult(
        applied ? PullOutcome.adopted : PullOutcome.needsAdoptionChoice,
        revision: head,
      );
    }

    // 4. Remote has not moved.
    if (head.id == pointer.revisionId) {
      return const PullResult(PullOutcome.nothingToDo);
    }

    // 5. Equivalent content under another id. Judged by the SERVER checksum:
    //    the contentHash at the target is client-written and goes stale if
    //    someone edits the file by hand.
    if (head.bodyChecksum == localChecksum) {
      await BackupPointer.save(
        revisionId: head.id,
        recordedHash: localHash,
        targetIdentity: targetIdentity,
      );
      return PullResult(PullOutcome.rebased, revision: head);
    }

    // 6. Linear descendant, and local unchanged. The ancestry test is
    //    load-bearing: "clean" compares local against its OWN pointer and
    //    says nothing about whether remote descends from it.
    if (head.parentRevisionId == pointer.revisionId &&
        pointer.isCleanAgainst(localHash)) {
      final applied = await _applyRevision(
        head,
        expectedLocalHash: localHash,
        expectedGeneration: localGeneration,
      );
      return PullResult(
        applied ? PullOutcome.applied : PullOutcome.conflict,
        revision: head,
      );
    }

    // 7. Diverged, or local is dirty. Surface it; never a modal.
    return PullResult(PullOutcome.conflict, revision: head);
  }

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

  Future<bool> _applyRevision(
    BackupRevision revision, {
    required String expectedLocalHash,
    required int expectedGeneration,
  }) async {
    final raw = await target.fetch(revision);
    final decoded = _decodeRevision(revision, raw);

    // Throws AppFault on anything malformed, before a single store is touched.
    final bundle = ConfigBundle.fromJsonValidated(decoded);
    return ConfigMutationNotifier.instance.runExclusive(() async {
      final currentGeneration =
          await ConfigMutationNotifier.instance.generation();
      final currentLocalHash = canonicalHash(await readBundleJson());
      if (currentGeneration != expectedGeneration ||
          currentLocalHash != expectedLocalHash) {
        return false;
      }
      await bundle.applyTransactionally(markAsPending: false);

      // applyTransactionally deliberately clears the pointer, because an
      // import is unprovenanced. Applying a fetched revision is the one case
      // where we know exactly what it came from, so re-establish it here.
      await BackupPointer.save(
        revisionId: revision.id,
        recordedHash: canonicalHash(decoded),
        targetIdentity: targetIdentity,
      );
      await ConfigMutationNotifier.instance.markSynced(expectedGeneration);
      return true;
    });
  }

  Future<PushResult> push() =>
      _single(() => _withStorageBoundary('push', _push));

  Future<PushResult> _push() async {
    final generation = await ConfigMutationNotifier.instance.generation();
    final bundle = await readBundleJson();
    final json = canonicalJsonEncode(bundle);
    final hash = canonicalHash(bundle);
    final localChecksum = bodyChecksumOf(json);

    final head = await target.latest();
    final pointer = await _pointer();

    if (head == null && pointer.isProvenanced) {
      await BackupPointer.clear();
      throw AppFault.backup(
        BackupFailureKind.targetMissing,
        'The backup revision this device last synced no longer exists.',
        operation: 'push',
        targetIdentity: targetIdentity,
      );
    }

    // 1. The bytes are already there. Judged by the SERVER checksum: the
    //    contentHash we wrote is client metadata and goes stale if the file
    //    is edited by hand at the target.
    if (head != null && head.bodyChecksum == localChecksum) {
      if (pointer.revisionId != head.id) {
        await BackupPointer.save(
          revisionId: head.id,
          recordedHash: hash,
          targetIdentity: targetIdentity,
        );
      }
      await ConfigMutationNotifier.instance.markSynced(generation);
      return const PushResult(PushOutcome.noOp);
    }

    // 2. Remote moved since we last synced.
    if (head != null && head.id != pointer.revisionId) {
      return PushResult(PushOutcome.conflict, remoteRevision: head);
    }

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
  }

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

  /// The local configuration that "Use the remote copy" replaced.
  ///
  /// One slot, most recent wins. The spec requires snapshotting local before
  /// adopting and an earlier draft of this plan dropped that requirement: the
  /// operator could have an hour of unpushed work, choose "Use their copy",
  /// and have it vanish with no revision anywhere holding it. A single
  /// recoverable slot is what a recovery UI can actually offer.
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

  /// Restores [revision] and makes it the newest backup.
  ///
  /// **Upload first, then apply.** The reverse order is a silent data-loss
  /// bug, and it is the one an earlier draft of this plan specified.
  /// [_applyRevision] moves the pointer onto the restored ancestor. If the
  /// upload then fails — offline, or the process is killed — the next pull
  /// finds `head.parentRevisionId == pointer` with local clean, matches
  /// branch 6 of [_pull], and re-applies the exact revision the operator just
  /// undid. Silently. And pull runs before push at every trigger, so nothing
  /// heals it.
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
            // and leaves localChangedDuringResolve unreachable. adoptRemote
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
  Future<List<BackupRevision>> history({int limit = 50}) => _single(
      () => _withStorageBoundary('history', () => target.list(limit: limit)));

  /// A revision's body, for the diff summary and the preview.
  Future<String> fetchBody(BackupRevision revision) => _single(
      () => _withStorageBoundary('history', () => target.fetch(revision)));

  Future<T> _withStorageBoundary<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on AppFault {
      rethrow;
    } on StateError catch (error) {
      throw AppFault.backup(
        BackupFailureKind.storageWriteFailed,
        'Could not persist backup state during $operation.',
        operation: operation,
        targetIdentity: targetIdentity,
        cause: error,
      );
    }
  }
}
