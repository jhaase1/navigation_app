import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';

class SettingsDialog extends StatefulWidget {
  final bool mockMode;
  final ValueChanged<bool> onMockModeChanged;
  final TextEditingController rolandIpController;
  final bool rolandConnected;
  final bool rolandConnecting;
  final String rolandConnectionError;
  final VoidCallback onConnectRoland;
  final List<PanasonicCameraConfig> panasonicCameras;
  final Function(int) onConnectPanasonic;

  const SettingsDialog({
    super.key,
    required this.mockMode,
    required this.onMockModeChanged,
    required this.rolandIpController,
    required this.rolandConnected,
    required this.rolandConnecting,
    required this.rolandConnectionError,
    required this.onConnectRoland,
    required this.panasonicCameras,
    required this.onConnectPanasonic,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Device Settings'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mock Mode Toggle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.mockMode ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.mockMode ? Colors.orange.shade200 : Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.mockMode ? Icons.visibility : Icons.wifi,
                      color: widget.mockMode ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.mockMode ? 'Demo Mode Active' : 'Live Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: widget.mockMode ? Colors.orange.shade900 : Colors.blue.shade900,
                            ),
                          ),
                          Text(
                            widget.mockMode
                                ? 'UI preview without real devices'
                                : 'Connecting to actual hardware',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.mockMode ? Colors.orange.shade700 : Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: widget.mockMode,
                      onChanged: widget.onMockModeChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('Roland V-160HD', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.rolandConnected ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.rolandIpController,
                decoration: const InputDecoration(
                  labelText: 'IP Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.router),
                ),
                enabled: !widget.rolandConnected && !widget.rolandConnecting,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.rolandConnecting ? null : () {
                  widget.onConnectRoland();
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: widget.rolandConnected ? Colors.red : null,
                ),
                child: widget.rolandConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.rolandConnected ? 'Disconnect' : 'Connect'),
              ),
              if (widget.rolandConnectionError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    'Connection failed. Check IP address.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              
              // Panasonic Cameras Section
              const Text('Panasonic Cameras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...List.generate(widget.panasonicCameras.length, (index) {
                final camera = widget.panasonicCameras[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (index > 0) const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(camera.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: camera.isConnected ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: camera.ipController,
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.videocam),
                      ),
                      enabled: !camera.isConnected && !camera.isConnecting,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: camera.isConnecting ? null : () {
                        widget.onConnectPanasonic(index);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: camera.isConnected ? Colors.red : null,
                      ),
                      child: camera.isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(camera.isConnected ? 'Disconnect' : 'Connect'),
                    ),
                    if (camera.connectionError.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          'Connection failed. Check IP address.',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}