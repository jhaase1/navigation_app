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
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Restored.')));
      } else if (outcome == ResolutionOutcome.localChangedDuringResolve) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'The backup already went back to that version. Other devices will follow it. This machine still has your newer edits.')));
      } else if (outcome == ResolutionOutcome.forkedAgain) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Another machine saved at the same moment. Both copies were kept.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something changed on this machine while that ran. '
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
                  subtitle: Text(relativeAge(r.createdAt.toLocal(), now)),
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

  /// Puts back the local configuration that "Use their copy" replaced, as
  /// the newest backup.
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
      final outcome = await widget.controller.restoreReplacedSnapshot();
      if (!mounted) return;
      if (outcome == ResolutionOutcome.resolved) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Restored.')));
      } else if (outcome == ResolutionOutcome.localChangedDuringResolve) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'The backup already went back to that version. Other devices will follow it. This machine still has your newer edits.')));
      } else if (outcome == ResolutionOutcome.forkedAgain) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Another machine saved at the same moment. Both copies were kept.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something changed on this machine while that ran. '
                'Nothing was restored — try again.')));
      }
    } on AppFault catch (fault) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not put them back: ${fault.message}')));
    }
  }
}
