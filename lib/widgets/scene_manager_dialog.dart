import 'package:flutter/material.dart';
import '../models/scene.dart';
import '../services/scene_store.dart';

class SceneManagerDialog extends StatefulWidget {
  final VoidCallback onSaved;

  const SceneManagerDialog({super.key, required this.onSaved});

  @override
  State<SceneManagerDialog> createState() => _SceneManagerDialogState();
}

class _SceneManagerDialogState extends State<SceneManagerDialog> {
  List<Scene> _scenes = [];
  bool _loading = true;

  Scene? _editingScene;
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadScenes();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadScenes() async {
    final scenes = await SceneStore.loadAll();
    if (mounted) setState(() { _scenes = scenes; _loading = false; });
  }

  void _startEditing(Scene scene) {
    _nameCtrl.text = scene.name;
    setState(() => _editingScene = scene);
  }

  void _addNewScene() {
    _startEditing(Scene(id: generateSceneId(), name: ''));
  }

  void _saveScene() {
    final name = _nameCtrl.text.trim();
    final updated =
        Scene(id: _editingScene!.id, name: name.isEmpty ? 'New Scene' : name);

    final newScenes = [..._scenes];
    final idx = newScenes.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) {
      newScenes[idx] = updated;
    } else {
      newScenes.add(updated);
    }

    SceneStore.saveAll(newScenes).then((_) => widget.onSaved());
    setState(() { _scenes = newScenes; _editingScene = null; });
  }

  Future<void> _deleteScene(String sceneId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Scene'),
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

    final newScenes = _scenes.where((s) => s.id != sceneId).toList();
    await SceneStore.saveAll(newScenes);
    widget.onSaved();
    if (mounted) setState(() => _scenes = newScenes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(_editingScene == null ? 'Manage Scenes' : 'Edit Scene'),
      content: SizedBox(
        width: 380,
        child: _editingScene == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingScene == null
          ? [
              FilledButton.icon(
                onPressed: _addNewScene,
                icon: const Icon(Icons.add),
                label: const Text('Add Scene'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingScene = null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _saveScene,
                child: const Text('Save'),
              ),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()));
    }
    if (_scenes.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No scenes yet.\nTap "Add Scene" to create a position.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _scenes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final scene = _scenes[i];
        return ListTile(
          leading: const Icon(Icons.place),
          title: Text(scene.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(scene),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteScene(scene.id),
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
        labelText: 'Scene Name',
        hintText: 'e.g. Lectern, Pulpit, Altar',
        border: OutlineInputBorder(),
      ),
    );
  }
}
