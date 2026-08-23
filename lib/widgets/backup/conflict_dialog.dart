import 'package:flutter/material.dart';

import '../../services/backup/app_fault.dart';
import '../../services/backup/backup_controller.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/backup_status.dart';
import '../../services/backup/bundle_diff.dart';
import '../../services/backup/device_label.dart';
import '../../services/backup/relative_time.dart';
import 'device_name_dialog.dart';

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

  Future<void> _runUpload(Future<ResolutionOutcome> Function() action) async {
    if (await DeviceLabel.load() == null) {
      if (!mounted) return;
      await nameThisMachine(context, widget.controller);
      if (!mounted || await DeviceLabel.load() == null) return;
    }
    await _run(action);
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
          onPressed: _working
              ? null
              : () => _runUpload(widget.controller.resolveKeepMine),
          child: Text(isAdoption ? "Keep this device's" : 'Keep mine'),
        ),
      ],
    );
  }
}
