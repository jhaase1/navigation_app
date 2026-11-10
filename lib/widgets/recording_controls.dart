import 'package:flutter/material.dart';

import '../services/service_recorder.dart';
import '../services/service_store.dart';

/// Top-bar indicator for a recording in progress: a red dot, the step count,
/// and Stop. Takes no space when nothing is being recorded, so the live view
/// is unchanged. Recording is started from Settings → Record a Service.
class RecordingIndicator extends StatelessWidget {
  final ServiceRecorder recorder;
  final VoidCallback? onServicesChanged;
  final ValueChanged<String> onResponse;

  const RecordingIndicator({
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
        if (!recorder.isRecording) return const SizedBox.shrink();
        final n = recorder.steps.length;
        final saving = recorder.isSaving;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FilledButton.icon(
            onPressed: saving
                ? null
                : () => finishRecording(
                      context,
                      recorder,
                      onSaved: onServicesChanged,
                      onError: onResponse,
                    ),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            icon: const Icon(Icons.stop),
            label: Text(saving
                ? 'Saving…'
                : 'Recording · $n step${n == 1 ? '' : 's'} · Stop'),
          ),
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
  if (recorder.isSaving) return;
  if (recorder.steps.isEmpty) {
    recorder.stop();
    return;
  }

  // Every dialog hangs off the root navigator, which outlives the Stop
  // button: the page swaps app bars when devices drop, and a failure must
  // still be shown after that.
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  recorder.isSaving = true;
  try {
    await _nameAndSave(rootContext, recorder,
        onSaved: onSaved, onError: onError);
  } finally {
    recorder.isSaving = false;
  }
}

/// What the operator chose in the name dialog. A dialog dismissed any other
/// way (tap outside, Esc) returns null and keeps the recording.
class _NameChoice {
  final String? name; // null = Discard
  const _NameChoice(this.name);
}

Future<void> _nameAndSave(
  BuildContext context,
  ServiceRecorder recorder, {
  VoidCallback? onSaved,
  ValueChanged<String>? onError,
}) async {
  // Recording stays on until the save has landed. Staying on after a failed
  // or dismissed save is what keeps the top-bar Stop reachable for a retry.
  var pendingName = '';
  final choice = await showDialog<_NameChoice>(
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
          onPressed: () => Navigator.of(ctx).pop(const _NameChoice(null)),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = pendingName.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(ctx).pop(_NameChoice(trimmed));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  // Dismissed without choosing: nothing is thrown away, recording goes on.
  if (choice == null) return;

  final name = choice.name;
  if (name == null) {
    recorder.clear();
    return;
  }

  try {
    // Replace, don't append: a retry after a half-landed save must not
    // leave two copies.
    final service = recorder.toService(name);
    final services = await ServiceStore.loadAll()
      ..removeWhere((s) => s.id == service.id);
    services.add(service);
    await ServiceStore.saveAll(services);
  } catch (e) {
    onError?.call('Error saving service: $e');
    // Never silent: the operator may have an hour of steps in here.
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Couldn't save the recording"),
          content: Text('Your ${recorder.steps.length} recorded steps are '
              'still here, and recording is still on: anything you fire now '
              'is added too. Tap Stop to try saving again.\n\n$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
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
                        selected: _role.toLowerCase() == r.toLowerCase(),
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
