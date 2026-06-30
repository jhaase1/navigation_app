import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/scene.dart';
import '../models/service_order.dart';
import '../services/abstract/roland_service_abstract.dart';

class _FlatMoment {
  final String id;
  final MomentType type;
  final String? roleId;
  final String? sceneId;
  final int? macroNumber;
  final String? cameraIp;
  final int? cameraPresetIndex;

  const _FlatMoment({
    required this.id,
    required this.type,
    this.roleId,
    this.sceneId,
    this.macroNumber,
    this.cameraIp,
    this.cameraPresetIndex,
  });
}

class OrderTab extends StatefulWidget {
  final List<PanasonicCameraConfig> cameras;
  final List<Person> people;
  final List<Role> roles;
  final List<Scene> scenes;
  final List<ServiceOrder> orders;
  final RolandServiceAbstract? rolandService;
  final ValueNotifier<bool>? rolandConnected;
  final ValueChanged<String> onResponse;

  const OrderTab({
    super.key,
    required this.cameras,
    required this.people,
    required this.roles,
    required this.scenes,
    required this.orders,
    required this.rolandService,
    required this.rolandConnected,
    required this.onResponse,
  });

  @override
  State<OrderTab> createState() => _OrderTabState();
}

class _OrderTabState extends State<OrderTab> {
  String? _selectedOrderId;
  int _selectedCameraIndex = 0;
  int? _currentMomentIndex;

  // roleId → personId, set at run time for this service
  final Map<String, String?> _roleAssignments = {};

  ServiceOrder? get _selectedOrder => _selectedOrderId == null
      ? null
      : widget.orders.where((o) => o.id == _selectedOrderId).firstOrNull;

  List<_FlatMoment> get _flatMoments {
    final order = _selectedOrder;
    if (order == null) return [];
    return _flatten(order, {});
  }

  List<_FlatMoment> _flatten(ServiceOrder order, Set<String> visited) {
    if (visited.contains(order.id)) return [];
    final seen = {...visited, order.id};
    final result = <_FlatMoment>[];
    for (final m in order.moments) {
      if (m.type == MomentType.subOrder && m.subOrderId != null) {
        final sub = widget.orders
            .where((o) => o.id == m.subOrderId)
            .firstOrNull;
        if (sub != null) result.addAll(_flatten(sub, seen));
      } else {
        result.add(_FlatMoment(
          id: m.id,
          type: m.type,
          roleId: m.roleId,
          sceneId: m.sceneId,
          macroNumber: m.macroNumber,
          cameraIp: m.cameraIp,
          cameraPresetIndex: m.cameraPresetIndex,
        ));
      }
    }
    return result;
  }

  Set<String> get _referencedRoleIds {
    return _flatMoments
        .where((m) => m.type == MomentType.roleScene && m.roleId != null)
        .map((m) => m.roleId!)
        .toSet();
  }

  @override
  void didUpdateWidget(OrderTab old) {
    super.didUpdateWidget(old);
    if (_selectedOrderId != null &&
        !widget.orders.any((o) => o.id == _selectedOrderId)) {
      _selectedOrderId = null;
      _currentMomentIndex = null;
      _roleAssignments.clear();
    }
  }

  Future<void> _fireMoment(int index) async {
    final flat = _flatMoments;
    if (index < 0 || index >= flat.length) return;
    setState(() => _currentMomentIndex = index);
    final m = flat[index];

    switch (m.type) {
      case MomentType.roleScene:
        await _fireRoleScene(m);
      case MomentType.macro:
        await _fireMacro(m);
      case MomentType.camera:
        await _fireCamera(m);
      case MomentType.subOrder:
        break; // already flattened; should never appear
    }
  }

  Future<void> _fireRoleScene(_FlatMoment m) async {
    final role = m.roleId == null
        ? null
        : widget.roles.where((r) => r.id == m.roleId).firstOrNull;
    if (role == null) {
      widget.onResponse('Missing role data');
      return;
    }
    final personId = _roleAssignments[role.id];
    if (personId == null) {
      widget.onResponse('No one assigned to "${role.name}" for this service');
      return;
    }
    final person =
        widget.people.where((p) => p.id == personId).firstOrNull;
    final scene = m.sceneId == null
        ? null
        : widget.scenes.where((s) => s.id == m.sceneId).firstOrNull;
    if (person == null || scene == null) {
      widget.onResponse('Missing person or scene data');
      return;
    }
    final cameraIdx =
        _selectedCameraIndex.clamp(0, widget.cameras.length - 1);
    final camera = widget.cameras[cameraIdx];
    final presetIndex = person.scenePresets[scene.id]?[camera.ipController.text];
    if (presetIndex == null) {
      widget.onResponse(
          '${person.name} has no preset for ${camera.name} at "${scene.name}"');
      return;
    }
    if (!camera.isConnected.value || camera.service == null) {
      widget.onResponse('${camera.name} not connected');
      return;
    }
    try {
      final response = await camera.service!.recallPreset(presetIndex);
      widget.onResponse(
          '${role.name} (${person.name}) · ${scene.name} → ${camera.name}: $response');
    } catch (e) {
      widget.onResponse('Error: $e');
    }
  }

  Future<void> _fireMacro(_FlatMoment m) async {
    if (m.macroNumber == null) {
      widget.onResponse('Macro number not set');
      return;
    }
    final connected = widget.rolandConnected?.value ?? false;
    if (!connected || widget.rolandService == null) {
      widget.onResponse('Roland not connected');
      return;
    }
    try {
      await widget.rolandService!.executeMacro(m.macroNumber!);
      widget.onResponse('Macro ${m.macroNumber} executed');
    } catch (e) {
      widget.onResponse('Macro error: $e');
    }
  }

  Future<void> _fireCamera(_FlatMoment m) async {
    if (m.cameraIp == null || m.cameraPresetIndex == null) {
      widget.onResponse('Camera or preset not set');
      return;
    }
    final camera = widget.cameras
        .where((c) => c.ipController.text == m.cameraIp)
        .firstOrNull;
    if (camera == null) {
      widget.onResponse('Camera not found (${m.cameraIp})');
      return;
    }
    if (!camera.isConnected.value || camera.service == null) {
      widget.onResponse('${camera.name} not connected');
      return;
    }
    try {
      final response =
          await camera.service!.recallPreset(m.cameraPresetIndex!);
      widget.onResponse(
          '${camera.name} → Preset ${m.cameraPresetIndex! + 1}: $response');
    } catch (e) {
      widget.onResponse('Error: $e');
    }
  }

  void _goNext() {
    final flat = _flatMoments;
    if (flat.isEmpty) return;
    final next =
        (_currentMomentIndex == null ? 0 : _currentMomentIndex! + 1)
            .clamp(0, flat.length - 1);
    _fireMoment(next);
  }

  void _goPrev() {
    if (_currentMomentIndex == null || _currentMomentIndex! == 0) return;
    _fireMoment(_currentMomentIndex! - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_list_numbered, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('No service orders configured',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Use Settings → Manage Orders to create one',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final flat = _flatMoments;
    final order = _selectedOrder;

    return Column(
      children: [
        // Order + camera selectors
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              Expanded(child: _buildOrderDropdown()),
              if (widget.cameras.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildCameraToggle(),
              ],
            ],
          ),
        ),

        // Role assignments (only when order selected and roles are used)
        if (order != null && _referencedRoleIds.isNotEmpty)
          _buildRoleAssignmentPanel(),

        // Moment list
        Expanded(
          child: order == null
              ? const Center(
                  child: Text('Select an order above',
                      style: TextStyle(color: Colors.grey)))
              : flat.isEmpty
                  ? const Center(
                      child: Text('This order has no moments',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: flat.length,
                      itemBuilder: (context, i) =>
                          _buildMomentTile(flat[i], i),
                    ),
        ),

        // Prev / Next
        if (order != null && flat.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed:
                      (_currentMomentIndex ?? 0) > 0 ? _goPrev : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Prev'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: _currentMomentIndex == null
                        ? const Text('Tap a moment or Next to begin',
                            style: TextStyle(color: Colors.grey))
                        : Text(
                            '${_currentMomentIndex! + 1} / ${flat.length}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: (_currentMomentIndex == null ||
                          _currentMomentIndex! < flat.length - 1)
                      ? _goNext
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOrderDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Order',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedOrderId,
          isDense: true,
          isExpanded: true,
          hint: const Text('Select order…',
              style: TextStyle(color: Colors.grey)),
          items: widget.orders
              .map((o) => DropdownMenuItem<String?>(
                    value: o.id,
                    child: Text(o.name),
                  ))
              .toList(),
          onChanged: (id) => setState(() {
            _selectedOrderId = id;
            _currentMomentIndex = null;
            _roleAssignments.clear();
          }),
        ),
      ),
    );
  }

  Widget _buildCameraToggle() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ToggleButtons(
        isSelected: List.generate(
            widget.cameras.length, (i) => i == _selectedCameraIndex),
        onPressed: (i) => setState(() => _selectedCameraIndex = i),
        children: widget.cameras
            .map((c) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(c.name),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildRoleAssignmentPanel() {
    final roles = _referencedRoleIds
        .map((id) => widget.roles.where((r) => r.id == id).firstOrNull)
        .whereType<Role>()
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Role assignments for this service',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...roles.map((role) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(role.name,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _roleAssignments[role.id],
                            isDense: true,
                            isExpanded: true,
                            hint: const Text('— unassigned —',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— unassigned —',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              ...widget.people.map((p) =>
                                  DropdownMenuItem<String?>(
                                    value: p.id,
                                    child: Text(p.name),
                                  )),
                            ],
                            onChanged: (personId) => setState(
                                () => _roleAssignments[role.id] = personId),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMomentTile(_FlatMoment m, int index) {
    final isCurrent = _currentMomentIndex == index;

    String title = '${index + 1}. ';
    String? subtitle;
    bool hasWarning = false;
    IconData typeIcon = Icons.circle_outlined;

    switch (m.type) {
      case MomentType.roleScene:
        final role = m.roleId == null
            ? null
            : widget.roles.where((r) => r.id == m.roleId).firstOrNull;
        final scene = m.sceneId == null
            ? null
            : widget.scenes.where((s) => s.id == m.sceneId).firstOrNull;
        typeIcon = Icons.badge;
        if (role == null || scene == null) {
          title += 'Missing role/scene';
          hasWarning = true;
        } else {
          title += '${role.name}  ·  ${scene.name}';
          final personId = _roleAssignments[role.id];
          if (personId == null) {
            subtitle = '${role.name} not assigned';
            hasWarning = true;
          } else {
            final person =
                widget.people.where((p) => p.id == personId).firstOrNull;
            subtitle = person?.name ?? 'Unknown person';
          }
        }

      case MomentType.macro:
        typeIcon = Icons.settings_remote;
        title += m.macroNumber != null
            ? 'Macro ${m.macroNumber}'
            : 'Macro (not set)';
        if (m.macroNumber == null) hasWarning = true;

      case MomentType.camera:
        typeIcon = Icons.videocam;
        final camera = m.cameraIp == null
            ? null
            : widget.cameras
                .where((c) => c.ipController.text == m.cameraIp)
                .firstOrNull;
        if (camera == null || m.cameraPresetIndex == null) {
          title += 'Camera (not set)';
          hasWarning = true;
        } else {
          title += '${camera.name}  ·  Preset ${m.cameraPresetIndex! + 1}';
        }

      case MomentType.subOrder:
        typeIcon = Icons.subdirectory_arrow_right;
        title += 'Sub-order';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isCurrent
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: isCurrent
            ? Icon(Icons.play_arrow,
                color: Theme.of(context).colorScheme.primary)
            : Icon(typeIcon,
                size: 18,
                color: isCurrent ? null : Colors.grey.shade500),
        title: Text(title,
            style: TextStyle(
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.normal)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: hasWarning
            ? const Icon(Icons.warning_amber, color: Colors.orange)
            : null,
        onTap: () => _fireMoment(index),
      ),
    );
  }
}
