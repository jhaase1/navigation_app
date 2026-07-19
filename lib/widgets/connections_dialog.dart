import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/device_config_store.dart';

typedef DeviceConfigCallback = void Function(
    String rolandIp, List<CameraEntry> cameras);

class ConnectionsDialog extends StatefulWidget {
  final TextEditingController rolandIpController;
  final ValueNotifier<bool> rolandConnected;
  final ValueNotifier<bool> rolandConnecting;
  final ValueNotifier<String> rolandConnectionError;
  final VoidCallback onConnectRoland;
  final List<PanasonicCameraConfig> panasonicCameras;
  final Function(int) onConnectPanasonic;
  final DeviceConfigCallback onSaved;

  const ConnectionsDialog({
    super.key,
    required this.rolandIpController,
    required this.rolandConnected,
    required this.rolandConnecting,
    required this.rolandConnectionError,
    required this.onConnectRoland,
    required this.panasonicCameras,
    required this.onConnectPanasonic,
    required this.onSaved,
  });

  @override
  State<ConnectionsDialog> createState() => _ConnectionsDialogState();
}

class _ConnectionsDialogState extends State<ConnectionsDialog> {
  // Local editable copies of camera name/ip — separate from the live
  // PanasonicCameraConfig objects so add/remove can be previewed before save.
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _ipControllers;

  @override
  void initState() {
    super.initState();
    _nameControllers = widget.panasonicCameras
        .map((c) => TextEditingController(text: c.name))
        .toList();
    _ipControllers = widget.panasonicCameras
        .map((c) => TextEditingController(text: c.ipController.text))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _ipControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCamera() {
    setState(() {
      _nameControllers
          .add(TextEditingController(text: 'Camera ${_nameControllers.length + 1}'));
      _ipControllers.add(TextEditingController());
    });
  }

  void _removeCamera(int index) {
    setState(() {
      _nameControllers[index].dispose();
      _ipControllers[index].dispose();
      _nameControllers.removeAt(index);
      _ipControllers.removeAt(index);
    });
  }

  List<CameraEntry> _buildEntries() => List.generate(
        _nameControllers.length,
        (i) => CameraEntry(
          name: _nameControllers[i].text.trim().isEmpty
              ? 'Camera ${i + 1}'
              : _nameControllers[i].text.trim(),
          ip: _ipControllers[i].text.trim(),
        ),
      );

  void _save() {
    widget.onSaved(widget.rolandIpController.text.trim(), _buildEntries());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Connections'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Roland
              ValueListenableBuilder<bool>(
                valueListenable: widget.rolandConnected,
                builder: (context, connected, _) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: widget.rolandConnecting,
                  builder: (context, connecting, _) =>
                      ValueListenableBuilder<String>(
                    valueListenable: widget.rolandConnectionError,
                    builder: (context, error, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          const Text('Roland V-160HD',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          _statusDot(connected),
                        ]),
                        const SizedBox(height: 12),
                        TextField(
                          controller: widget.rolandIpController,
                          enabled: !connected && !connecting,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.router),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: connecting ? null : widget.onConnectRoland,
                          style: FilledButton.styleFrom(
                              backgroundColor: connected ? Colors.red : null),
                          child: connecting
                              ? _spinner()
                              : Text(connected ? 'Disconnect' : 'Connect'),
                        ),
                        if (error.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _errorBox(error),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Panasonic cameras
              Row(
                children: [
                  const Text('Panasonic Cameras',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addCamera,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(_nameControllers.length, (index) {
                final isLive = index < widget.panasonicCameras.length;
                final connected = isLive
                    ? widget.panasonicCameras[index].isConnected
                    : ValueNotifier(false);
                final connecting = isLive
                    ? widget.panasonicCameras[index].isConnecting
                    : ValueNotifier(false);
                final error = isLive
                    ? widget.panasonicCameras[index].connectionError
                    : ValueNotifier('');

                return ValueListenableBuilder<bool>(
                  valueListenable: connected,
                  builder: (context, conn, _) =>
                      ValueListenableBuilder<bool>(
                    valueListenable: connecting,
                    builder: (context, cnting, _) =>
                        ValueListenableBuilder<String>(
                      valueListenable: error,
                      builder: (context, err, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (index > 0) const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _nameControllers[index],
                                enabled: !conn && !cnting,
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _statusDot(conn),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Remove camera',
                              onPressed: conn || cnting
                                  ? null
                                  : () => _removeCamera(index),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _ipControllers[index],
                            enabled: !conn && !cnting,
                            decoration: const InputDecoration(
                              labelText: 'IP Address',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.videocam),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: !isLive || cnting
                                ? null
                                : () => widget.onConnectPanasonic(index),
                            style: FilledButton.styleFrom(
                                backgroundColor: conn ? Colors.red : null),
                            child: !isLive
                                ? const Text('Save first')
                                : cnting
                                    ? _spinner()
                                    : Text(conn ? 'Disconnect' : 'Connect'),
                          ),
                          if (err.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _errorBox(err),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save & Close'),
        ),
      ],
    );
  }

  Widget _statusDot(bool connected) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? Colors.green : Colors.grey,
        ),
      );

  Widget _spinner() => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );

  Widget _errorBox(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text('Connection failed. Check IP address.',
            style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
      );
}
