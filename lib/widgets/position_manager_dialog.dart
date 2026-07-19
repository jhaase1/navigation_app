import 'package:flutter/material.dart';
import '../models/position.dart';
import '../services/position_store.dart';

class PositionManagerDialog extends StatefulWidget {
  final VoidCallback onSaved;

  const PositionManagerDialog({super.key, required this.onSaved});

  @override
  State<PositionManagerDialog> createState() => _PositionManagerDialogState();
}

class _PositionManagerDialogState extends State<PositionManagerDialog> {
  List<Position> _positions = [];
  bool _loading = true;

  Position? _editingPosition;
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPositions() async {
    final positions = await PositionStore.loadAll();
    if (mounted) setState(() { _positions = positions; _loading = false; });
  }

  void _startEditing(Position position) {
    _nameCtrl.text = position.name;
    setState(() => _editingPosition = position);
  }

  void _addNew() {
    _startEditing(Position(id: generatePositionId(), name: ''));
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final updated = Position(
        id: _editingPosition!.id, name: name.isEmpty ? 'New Position' : name);

    final newPositions = [..._positions];
    final idx = newPositions.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      newPositions[idx] = updated;
    } else {
      newPositions.add(updated);
    }

    PositionStore.saveAll(newPositions).then((_) => widget.onSaved());
    setState(() { _positions = newPositions; _editingPosition = null; });
  }

  Future<void> _delete(String positionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Position'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final newPositions = _positions.where((p) => p.id != positionId).toList();
    await PositionStore.saveAll(newPositions);
    widget.onSaved();
    if (mounted) setState(() => _positions = newPositions);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editingPosition == null ? 'Manage Positions' : 'Edit Position'),
      content: SizedBox(
        width: 380,
        child: _editingPosition == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingPosition == null
          ? [
              FilledButton.icon(
                onPressed: _addNew,
                icon: const Icon(Icons.add),
                label: const Text('Add Position'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingPosition = null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_positions.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No positions yet.\nTap "Add Position" to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _positions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final position = _positions[i];
        return ListTile(
          leading: const Icon(Icons.place),
          title: Text(position.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(position),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _delete(position.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    return TextField(
      controller: _nameCtrl,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Position Name',
        hintText: 'e.g. Lectern, Pulpit, Altar',
        border: OutlineInputBorder(),
      ),
    );
  }
}
