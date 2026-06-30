import 'package:flutter/material.dart';
import '../models/role.dart';
import '../services/role_store.dart';

class RoleManagerDialog extends StatefulWidget {
  final VoidCallback onSaved;

  const RoleManagerDialog({super.key, required this.onSaved});

  @override
  State<RoleManagerDialog> createState() => _RoleManagerDialogState();
}

class _RoleManagerDialogState extends State<RoleManagerDialog> {
  List<Role> _roles = [];
  bool _loading = true;

  Role? _editingRole;
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    final roles = await RoleStore.loadAll();
    if (mounted) setState(() { _roles = roles; _loading = false; });
  }

  void _startEditing(Role role) {
    _nameCtrl.text = role.name;
    setState(() => _editingRole = role);
  }

  void _addNew() => _startEditing(Role(id: generateRoleId(), name: ''));

  void _save() {
    final name = _nameCtrl.text.trim();
    final updated =
        Role(id: _editingRole!.id, name: name.isEmpty ? 'Role' : name);
    final newRoles = [..._roles];
    final idx = newRoles.indexWhere((r) => r.id == updated.id);
    if (idx >= 0) {
      newRoles[idx] = updated;
    } else {
      newRoles.add(updated);
    }
    RoleStore.saveAll(newRoles).then((_) => widget.onSaved());
    setState(() { _roles = newRoles; _editingRole = null; });
  }

  Future<void> _delete(String roleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Role'),
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
    final newRoles = _roles.where((r) => r.id != roleId).toList();
    await RoleStore.saveAll(newRoles);
    widget.onSaved();
    if (mounted) setState(() => _roles = newRoles);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(_editingRole == null ? 'Manage Roles' : 'Edit Role'),
      content: SizedBox(
        width: 340,
        child: _editingRole == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingRole == null
          ? [
              FilledButton.icon(
                onPressed: _addNew,
                icon: const Icon(Icons.add),
                label: const Text('Add Role'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() => _editingRole = null),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_roles.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'No roles yet.\nTap "Add Role" to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _roles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final role = _roles[i];
        return ListTile(
          leading: const Icon(Icons.badge),
          title: Text(role.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(role),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _delete(role.id),
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
        labelText: 'Role Name',
        hintText: 'e.g. Reader 1, Priest, Deacon',
        border: OutlineInputBorder(),
      ),
    );
  }
}
