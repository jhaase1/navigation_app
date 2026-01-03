import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';

class SettingsDialog extends StatelessWidget {
  final bool mockMode;
  final ValueChanged<bool> onMockModeChanged;
  final TextEditingController rolandIpController;
  final ValueNotifier<bool> rolandConnected;
  final ValueNotifier<bool> rolandConnecting;
  final ValueNotifier<String> rolandConnectionError;
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
                  color: mockMode ? Colors.orange.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: mockMode
                          ? Colors.orange.shade200
                          : Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      mockMode ? Icons.visibility : Icons.wifi,
                      color: mockMode ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mockMode ? 'Demo Mode Active' : 'Live Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: mockMode
                                  ? Colors.orange.shade900
                                  : Colors.blue.shade900,
                            ),
                          ),
                          Text(
                            mockMode
                                ? 'UI preview without real devices'
                                : 'Connecting to actual hardware',
                            style: TextStyle(
                              fontSize: 12,
                              color: mockMode
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: mockMode,
                      onChanged: onMockModeChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ValueListenableBuilder<bool>(
                valueListenable: rolandConnected,
                builder: (context, rolandConnectedValue, child) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: rolandConnecting,
                  builder: (context, rolandConnectingValue, child) =>
                      ValueListenableBuilder<String>(
                    valueListenable: rolandConnectionError,
                    builder: (context, rolandErrorValue, child) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Text('Roland V-160HD',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: rolandConnectedValue
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: rolandIpController,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.router),
                          ),
                          enabled:
                              !rolandConnectedValue && !rolandConnectingValue,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: rolandConnectingValue
                              ? null
                              : () {
                                  onConnectRoland();
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                rolandConnectedValue ? Colors.red : null,
                          ),
                          child: rolandConnectingValue
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(rolandConnectedValue
                                  ? 'Disconnect'
                                  : 'Connect'),
                        ),
                        if (rolandErrorValue.isNotEmpty) ...[
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
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Panasonic Cameras Section
              const Text('Panasonic Cameras',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...List.generate(panasonicCameras.length, (index) {
                final camera = panasonicCameras[index];
                return ValueListenableBuilder<bool>(
                  valueListenable: camera.isConnected,
                  builder: (context, isConnectedValue, child) =>
                      ValueListenableBuilder<bool>(
                    valueListenable: camera.isConnecting,
                    builder: (context, isConnectingValue, child) =>
                        ValueListenableBuilder<String>(
                      valueListenable: camera.connectionError,
                      builder: (context, connectionErrorValue, child) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (index > 0) const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(camera.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isConnectedValue
                                      ? Colors.green
                                      : Colors.grey,
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
                            enabled: !isConnectedValue && !isConnectingValue,
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: isConnectingValue
                                ? null
                                : () {
                                    onConnectPanasonic(index);
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  isConnectedValue ? Colors.red : null,
                            ),
                            child: isConnectingValue
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(isConnectedValue
                                    ? 'Disconnect'
                                    : 'Connect'),
                          ),
                          if (connectionErrorValue.isNotEmpty) ...[
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
                                style: TextStyle(
                                    color: Colors.red.shade700, fontSize: 12),
                              ),
                            ),
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
}
