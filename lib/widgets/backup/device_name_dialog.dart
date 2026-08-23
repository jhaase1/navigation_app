import 'package:flutter/material.dart';

import '../../services/backup/backup_controller.dart';
import '../../services/backup/device_label.dart';

/// Lives here — top level, not a method on the settings dialog, because the
/// conflict dialog calls it too.
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

  final name = await showDialog<String>(
    context: context,
    builder: (context) => _NameFieldDialog(initial: suggestion ?? ''),
  );

  final accepted = DeviceLabel.sanitize(name, namesInUse: namesInUse);
  if (accepted == null) {
    if (context.mounted && name != null && name.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('That name is already in use, or is not specific enough. '
                  'Try something that names this machine.')));
    }
    return;
  }
  await DeviceLabel.save(accepted);
}

/// Owns the field. Disposing it the moment `showDialog` returns uses it
/// during the pop animation.
class _NameFieldDialog extends StatefulWidget {
  const _NameFieldDialog({required this.initial});

  final String initial;

  @override
  State<_NameFieldDialog> createState() => _NameFieldDialogState();
}

class _NameFieldDialogState extends State<_NameFieldDialog> {
  late final TextEditingController field;

  @override
  void initState() {
    super.initState();
    field = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
    );
  }
}
