import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/backup/app_fault.dart';
import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_log.dart';
import '../../services/backup/backup_status.dart';
import '../../services/backup/relative_time.dart';
import 'conflict_dialog.dart';
import 'device_name_dialog.dart';

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
                          separatorBuilder: (_, __) => const Divider(height: 1),
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
      if (!status.configured) 'Google Drive sign-in arrives in a later update.',
      if (controller.deferralApplies) 'You chose to decide about this later.',
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
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          if (status.activeCondition?.kind == 'deviceUnnamed')
            TextButton(
              onPressed: () => nameThisMachine(context, controller),
              child: const Text('Name this machine'),
            )
          else if (BackupStatus.isQuestion(status.activeCondition?.kind ?? ''))
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
          else if (controller.canRetry &&
              (status.activeCondition?.domain ?? FaultDomain.backup) ==
                  FaultDomain.backup)
            // Retry re-runs the backup; it cannot bring a camera back.
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
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
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
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54)),
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
