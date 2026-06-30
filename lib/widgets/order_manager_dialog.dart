import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/role.dart';
import '../models/scene.dart';
import '../models/service_order.dart';
import '../services/service_order_store.dart';

class _WorkingMoment {
  final String id;
  MomentType type;
  String? roleId;
  String? sceneId;
  String? cameraIp;
  String? subOrderId;

  _WorkingMoment({
    required this.id,
    this.type = MomentType.roleScene,
    this.roleId,
    this.sceneId,
    this.cameraIp,
    this.subOrderId,
  });
}

class OrderManagerDialog extends StatefulWidget {
  final List<Role> roles;
  final List<Scene> scenes;
  final List<PanasonicCameraConfig> cameras;
  final VoidCallback onSaved;

  const OrderManagerDialog({
    super.key,
    required this.roles,
    required this.scenes,
    required this.cameras,
    required this.onSaved,
  });

  @override
  State<OrderManagerDialog> createState() => _OrderManagerDialogState();
}

class _OrderManagerDialogState extends State<OrderManagerDialog> {
  List<ServiceOrder> _orders = [];
  bool _loading = true;

  ServiceOrder? _editingOrder;
  final TextEditingController _nameCtrl = TextEditingController();
  List<_WorkingMoment> _editingMoments = [];

  // Per-moment controllers for numeric inputs
  final Map<String, TextEditingController> _macroNumCtrls = {};
  final Map<String, TextEditingController> _presetNumCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _disposeNumericControllers();
    super.dispose();
  }

  void _disposeNumericControllers() {
    for (final c in _macroNumCtrls.values) { c.dispose(); }
    _macroNumCtrls.clear();
    for (final c in _presetNumCtrls.values) { c.dispose(); }
    _presetNumCtrls.clear();
  }

  Future<void> _loadOrders() async {
    final orders = await ServiceOrderStore.loadAll();
    if (mounted) setState(() { _orders = orders; _loading = false; });
  }

  void _ensureNumericControllers(_WorkingMoment m, {OrderMoment? source}) {
    _macroNumCtrls[m.id] ??= TextEditingController(
      text: source?.macroNumber != null ? '${source!.macroNumber}' : '',
    );
    _presetNumCtrls[m.id] ??= TextEditingController(
      text: source?.cameraPresetIndex != null
          ? '${source!.cameraPresetIndex! + 1}'
          : '',
    );
  }

  void _startEditing(ServiceOrder order) {
    _disposeNumericControllers();
    _nameCtrl.text = order.name;
    _editingMoments = order.moments.map((m) {
      final wm = _WorkingMoment(
        id: m.id,
        type: m.type,
        roleId: m.roleId,
        sceneId: m.sceneId,
        cameraIp: m.cameraIp,
        subOrderId: m.subOrderId,
      );
      _ensureNumericControllers(wm, source: m);
      return wm;
    }).toList();
    setState(() => _editingOrder = order);
  }

  void _addNewOrder() =>
      _startEditing(ServiceOrder(id: generateOrderId(), name: ''));

  void _addMoment() {
    final wm =
        _WorkingMoment(id: generateOrderId(), type: MomentType.roleScene);
    _ensureNumericControllers(wm);
    setState(() => _editingMoments.add(wm));
  }

  void _removeMoment(int index) {
    final id = _editingMoments[index].id;
    _macroNumCtrls.remove(id)?.dispose();
    _presetNumCtrls.remove(id)?.dispose();
    setState(() => _editingMoments.removeAt(index));
  }

  void _changeMomentType(int index, MomentType newType) {
    setState(() => _editingMoments[index].type = newType);
  }

  void _saveOrder() {
    final name = _nameCtrl.text.trim();
    final moments = _editingMoments.map((m) {
      int? macroNum;
      int? presetIdx;
      if (m.type == MomentType.macro) {
        final n = int.tryParse(_macroNumCtrls[m.id]?.text.trim() ?? '');
        if (n != null && n >= 1 && n <= 100) macroNum = n;
      }
      if (m.type == MomentType.camera) {
        final n = int.tryParse(_presetNumCtrls[m.id]?.text.trim() ?? '');
        if (n != null && n >= 1 && n <= 100) presetIdx = n - 1;
      }
      return OrderMoment(
        id: m.id,
        type: m.type,
        roleId: m.roleId,
        sceneId: m.sceneId,
        macroNumber: macroNum,
        cameraIp: m.cameraIp,
        cameraPresetIndex: presetIdx,
        subOrderId: m.subOrderId,
      );
    }).toList();

    final updated = ServiceOrder(
      id: _editingOrder!.id,
      name: name.isEmpty ? 'New Order' : name,
      moments: moments,
    );

    final newOrders = [..._orders];
    final idx = newOrders.indexWhere((o) => o.id == updated.id);
    if (idx >= 0) {
      newOrders[idx] = updated;
    } else {
      newOrders.add(updated);
    }

    ServiceOrderStore.saveAll(newOrders).then((_) => widget.onSaved());
    setState(() { _orders = newOrders; _editingOrder = null; });
  }

  Future<void> _deleteOrder(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Order'),
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
    final newOrders = _orders.where((o) => o.id != orderId).toList();
    await ServiceOrderStore.saveAll(newOrders);
    widget.onSaved();
    if (mounted) setState(() => _orders = newOrders);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editingOrder == null
          ? 'Manage Orders'
          : _editingOrder!.name.isEmpty
              ? 'New Order'
              : _editingOrder!.name),
      content: SizedBox(
        width: 520,
        child: _editingOrder == null ? _buildList() : _buildEditor(),
      ),
      actions: _editingOrder == null
          ? [
              FilledButton.icon(
                onPressed: _addNewOrder,
                icon: const Icon(Icons.add),
                label: const Text('Add Order'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => setState(() { _editingOrder = null; _disposeNumericControllers(); }),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: _saveOrder, child: const Text('Save')),
            ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (_orders.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No orders yet.\nTap "Add Order" to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final order = _orders[i];
        return ListTile(
          leading: const Icon(Icons.format_list_numbered),
          title: Text(order.name),
          subtitle: Text(
              '${order.moments.length} moment${order.moments.length == 1 ? '' : 's'}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _startEditing(order),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteOrder(order.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Order Name',
              hintText: 'e.g. Standard Mass, Christmas Vigil',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Moments',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          ..._editingMoments.asMap().entries.map((e) =>
              _buildMomentRow(e.key, e.value)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _addMoment,
            icon: const Icon(Icons.add),
            label: const Text('Add Moment'),
          ),
        ],
      ),
    );
  }

  Widget _buildMomentRow(int index, _WorkingMoment m) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${index + 1}.',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<MomentType>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: MomentType.roleScene,
                          label: Text('Role')),
                      ButtonSegment(
                          value: MomentType.macro,
                          label: Text('Macro')),
                      ButtonSegment(
                          value: MomentType.camera,
                          label: Text('Camera')),
                      ButtonSegment(
                          value: MomentType.subOrder,
                          label: Text('Order')),
                    ],
                    selected: {m.type},
                    onSelectionChanged: (s) =>
                        _changeMomentType(index, s.first),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => _removeMoment(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildMomentFields(m),
          ],
        ),
      ),
    );
  }

  Widget _buildMomentFields(_WorkingMoment m) {
    switch (m.type) {
      case MomentType.roleScene:
        return Row(
          children: [
            Expanded(
              child: _dropdown<String?>(
                hint: 'Role',
                value: m.roleId,
                items: widget.roles
                    .map((r) => DropdownMenuItem<String?>(
                          value: r.id,
                          child: Text(r.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => m.roleId = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown<String?>(
                hint: 'Scene',
                value: m.sceneId,
                items: widget.scenes
                    .map((s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(s.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => m.sceneId = v),
              ),
            ),
          ],
        );

      case MomentType.macro:
        return SizedBox(
          width: 120,
          child: TextField(
            controller: _macroNumCtrls[m.id],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Macro #',
              hintText: '1–100',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );

      case MomentType.camera:
        return Row(
          children: [
            Expanded(
              child: _dropdown<String?>(
                hint: 'Camera',
                value: m.cameraIp,
                items: widget.cameras
                    .map((c) => DropdownMenuItem<String?>(
                          value: c.ipController.text,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => m.cameraIp = v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _presetNumCtrls[m.id],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Preset #',
                  hintText: '1–100',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        );

      case MomentType.subOrder:
        // Exclude self and any order that would include this one (simple: exclude self)
        final available = _orders
            .where((o) => o.id != _editingOrder?.id)
            .toList();
        return _dropdown<String?>(
          hint: 'Select sub-order',
          value: m.subOrderId,
          items: available
              .map((o) => DropdownMenuItem<String?>(
                    value: o.id,
                    child: Text(o.name),
                  ))
              .toList(),
          onChanged: (v) => setState(() => m.subOrderId = v),
        );
    }
  }

  Widget _dropdown<T>({
    required String hint,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        hintText: hint,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(hint,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 13)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
