import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../services/people_store.dart';

class PeopleManagerDialog extends StatefulWidget {
  final List<Position> positions;
  final List<PanasonicCameraConfig> cameras;
  final VoidCallback onSaved;

  const PeopleManagerDialog({
    super.key,
    required this.positions,
    required this.cameras,
    required this.onSaved,
  });

  @override
  State<PeopleManagerDialog> createState() => _PeopleManagerDialogState();
}

class _PeopleManagerDialogState extends State<PeopleManagerDialog> {
  List<Person> _people = [];
  bool _loading = true;

  Person? _editingPerson;
  final TextEditingController _nameCtrl = TextEditingController();
  // positionId → cameraIp → controller (preset number, 1-based display)
  final Map<String, Map<String, TextEditingController>> _presetCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _disposePresetControllers();
    super.dispose();
  }

  void _disposePresetControllers() {
    for (final m in _presetCtrls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _presetCtrls.clear();
  }

  Future<void> _loadPeople() async {
    final people = await PeopleStore.loadAll();
    if (mounted) setState(() { _people = people; _loading = false; });
  }

  void _startEditing(Person person) {
    _disposePresetControllers();
    _nameCtrl.text = person.name;
    for (final position in widget.positions) {
      _presetCtrls[position.id] = {};
      for (final camera in widget.cameras) {
        final ip = camera.ipController.text;
        final idx = person.positionPresets[position.id]?[ip];
        _presetCtrls[position.id]![ip] =
            TextEditingController(text: idx != null ? '${idx + 1}' : '');
      }
    }
    setState(() => _editingPerson = person);
  }

  void _addNewPerson() {
    _startEditing(Person(id: generatePositionId(), name: ''));
  }

  void _savePerson() {
    final name = _nameCtrl.text.trim();
    final positionPresets = <String, Map<String, int>>{};
    for (final position in widget.positions) {
      final cameraMap = <String, int>{};
      for (final camera in widget.cameras) {
        final ip = camera.ipController.text;
        final text = _presetCtrls[position.id]?[ip]?.text.trim() ?? '';
        final num = int.tryParse(text);
        if (num != null && num >= 1 && num <= 100) {
          cameraMap[ip] = num - 1;
        }
      }
      if (cameraMap.isNotEmpty) positionPresets[position.id] = cameraMap;
    }

    final updated = Person(
      id: _editingPerson!.id,
      name: name.isEmpty ? 'Unnamed' : name,
      positionPresets: positionPresets,
    );

    final newPeople = [..._people];
    final idx = newPeople.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      newPeople[idx] = updated;
    } else {
      newPeople.add(updated);
    }

    PeopleStore.saveAll(newPeople).then((_) => widget.onSaved());
    setState(() { _people = newPeople; _editingPerson = null; });
  }

  Future<void> _deletePerson(String personId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Person'),
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

    final newPeople = _people.where((p) => p.id != personId).toList();
    await PeopleStore.saveAll(newPeople);
    widget.onSaved();
    if (mounted) setState(() => _people = newPeople);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editingPerson == null
          ? 'Manage People'
          : _editingPerson!.name.isEmpty
              ? 'New Person'
              : _editingPerson!.name),
      content: SizedBox(
        width: 480,
        child: _editingPerson == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingPerson == null
          ? [
              FilledButton.icon(
                onPressed: _addNewPerson,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Person'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingPerson = null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _savePerson,
                child: const Text('Save'),
              ),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (_people.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No people yet.\nTap "Add Person" to create a profile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _people.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final person = _people[i];
        final positionCount = person.positionPresets.length;
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(person.name),
          subtitle: Text(positionCount == 0
              ? 'No presets configured'
              : '$positionCount position${positionCount == 1 ? '' : 's'} configured'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(person),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deletePerson(person.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    final noPositions = widget.positions.isEmpty;
    final noCameras = widget.cameras.isEmpty;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Fr. John, Deacon Mike',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (noPositions || noCameras)
            Text(
              noPositions
                  ? 'Add positions first (Settings → Manage Positions).'
                  : 'No cameras configured.',
              style: const TextStyle(color: Colors.grey),
            )
          else
            ...widget.positions.map((position) => _buildPositionSection(position)),
        ],
      ),
    );
  }

  Widget _buildPositionSection(Position position) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(position.name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          ...widget.cameras.map((camera) {
            final ip = camera.ipController.text;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(camera.name,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _presetCtrls[position.id]?[ip],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Preset #',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('(1–100)',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
