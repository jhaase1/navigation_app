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
                    // A camera fault names the camera and its address, which
                    // can outrun a narrow AppBar: shorten it, don't overflow.
                    Flexible(
                      child: Text(
                        status.label(DateTime.now()),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: swatch.shade800,
                        ),
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
