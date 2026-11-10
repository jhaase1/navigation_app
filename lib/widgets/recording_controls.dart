import 'package:flutter/material.dart';

import '../services/service_recorder.dart';
import '../services/service_store.dart';

/// Record / Stop toggle bound to a shared [ServiceRecorder]. Shown on every
/// tab that can add steps, so recording can be stopped from wherever the
/// operator is.
class RecordButton extends StatelessWidget {
  final ServiceRecorder recorder;
  final VoidCallback? onServicesChanged;
  final ValueChanged<String> onResponse;

  const RecordButton({
    super.key,
    required this.recorder,
    required this.onResponse,
    this.onServicesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        if (!recorder.isRecording) {
          return OutlinedButton.icon(
            onPressed: recorder.start,
            icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
            label: const Text('Record'),
          );
        }
        final n = recorder.steps.length;
        return ElevatedButton.icon(
          onPressed: () => finishRecording(
            context,
            recorder,
            onSaved: onServicesChanged,
            onError: onResponse,
          ),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white),
          icon: const Icon(Icons.stop),
          label: Text('Stop ($n step${n == 1 ? '' : 's'})'),
        );
      },
    );
  }
}

/// Stops [recorder] and, if anything was recorded, asks for a name and saves
/// the recording as a new Service.
Future<void> finishRecording(
  BuildContext context,
  ServiceRecorder recorder, {
  VoidCallback? onSaved,
  ValueChanged<String>? onError,
}) async {
  if (recorder.steps.isEmpty) {
    recorder.stop();
    return;
  }

  // Recording stays on until the dialog closes. Stopping first would hide the
  // Positions tab's recording bar, unmount the Stop button that owns
  // [context], and the save below would silently never happen.

  var pendingName = '';
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Save Recording (${recorder.steps.length} steps)'),
      content: TextField(
        autofocus: true,
        onChanged: (v) => pendingName = v,
        decoration: const InputDecoration(
          labelText: 'Service Name',
          hintText: 'e.g. Standard Mass',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = pendingName.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(ctx).pop(trimmed);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (name == null) {
    recorder.clear();
    return;
  }

  try {
    final services = await ServiceStore.loadAll();
    services.add(recorder.toService(name));
    await ServiceStore.saveAll(services);
  } catch (e) {
    onError?.call('Error saving service: $e');
    recorder.stop();
    return;
  }

  recorder.clear();
  onSaved?.call();
}

/// Asks which role [personName] is playing at [positionName], so a recorded
/// shot follows the role, not the person. Returns null if the operator skips.
Future<String?> askForRole(
  BuildContext context, {
  required String personName,
  required String positionName,
  required List<String> existingRoles,
  String? initialRole,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RoleDialog(
        personName: personName,
        positionName: positionName,
        existingRoles: existingRoles,
        initialRole: initialRole,
      ),
    );

class _RoleDialog extends StatefulWidget {
  final String personName;
  final String positionName;
  final List<String> existingRoles;
  final String? initialRole;

  const _RoleDialog({
    required this.personName,
    required this.positionName,
    required this.existingRoles,
    this.initialRole,
  });

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialRole ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _role => _controller.text.trim();

  void _submit() {
    if (_role.isEmpty) return;
    Navigator.of(context).pop(_role);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.personName} at ${widget.positionName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Which role is this? Next time, whoever fills the role '
              'gets this shot.'),
          const SizedBox(height: 12),
          if (widget.existingRoles.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.existingRoles
                  .map((r) => ChoiceChip(
                        label: Text(r),
                        selected: _role == r,
                        onSelected: (_) => setState(() => _controller.text = r),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Role',
              hintText: 'e.g. Lector, Presider, Cantor',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip step'),
        ),
        FilledButton(
          onPressed: _role.isEmpty ? null : _submit,
          child: const Text('Add step'),
        ),
      ],
    );
  }
}
