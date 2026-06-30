import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';

class ConnectionsDialog extends StatelessWidget {
  final TextEditingController rolandIpController;
  final ValueNotifier<bool> rolandConnected;
  final ValueNotifier<bool> rolandConnecting;
  final ValueNotifier<String> rolandConnectionError;
  final VoidCallback onConnectRoland;
  final List<PanasonicCameraConfig> panasonicCameras;
  final Function(int) onConnectPanasonic;

  const ConnectionsDialog({
    super.key,
    required this.rolandIpController,
    required this.rolandConnected,
    required this.rolandConnecting,
    required this.rolandConnectionError,
    required this.onConnectRoland,
    required this.panasonicCameras,
    required this.onConnectPanasonic,
  });

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
                valueListenable: rolandConnected,
                builder: (context, connected, _) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: rolandConnecting,
                  builder: (context, connecting, _) =>
                      ValueListenableBuilder<String>(
                    valueListenable: rolandConnectionError,
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
                          controller: rolandIpController,
                          enabled: !connected && !connecting,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.router),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: connecting ? null : onConnectRoland,
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
              const Text('Panasonic Cameras',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...List.generate(panasonicCameras.length, (index) {
                final camera = panasonicCameras[index];
                return ValueListenableBuilder<bool>(
                  valueListenable: camera.isConnected,
                  builder: (context, connected, _) =>
                      ValueListenableBuilder<bool>(
                    valueListenable: camera.isConnecting,
                    builder: (context, connecting, _) =>
                        ValueListenableBuilder<String>(
                      valueListenable: camera.connectionError,
                      builder: (context, error, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (index > 0) const SizedBox(height: 16),
                          Row(children: [
                            Text(camera.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 12),
                            _statusDot(connected),
                          ]),
                          const SizedBox(height: 8),
                          TextField(
                            controller: camera.ipController,
                            enabled: !connected && !connecting,
                            decoration: const InputDecoration(
                              labelText: 'IP Address',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.videocam),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: connecting
                                ? null
                                : () => onConnectPanasonic(index),
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
