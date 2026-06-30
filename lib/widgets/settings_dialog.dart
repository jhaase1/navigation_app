import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/abstract/roland_service_abstract.dart';
import 'connections_dialog.dart';
import 'master_control_widget.dart';
import 'pinp_tab.dart';

class SettingsDialog extends StatelessWidget {
  final bool mockMode;
  final ValueChanged<bool> onMockModeChanged;
  final RolandServiceAbstract? rolandService;
  final TextEditingController rolandIpController;
  final ValueNotifier<bool> rolandConnected;
  final ValueNotifier<bool> rolandConnecting;
  final ValueNotifier<String> rolandConnectionError;
  final VoidCallback onConnectRoland;
  final List<PanasonicCameraConfig> panasonicCameras;
  final Function(int) onConnectPanasonic;
  final ValueChanged<String> onResponse;

  const SettingsDialog({
    super.key,
    required this.mockMode,
    required this.onMockModeChanged,
    required this.rolandService,
    required this.rolandIpController,
    required this.rolandConnected,
    required this.rolandConnecting,
    required this.rolandConnectionError,
    required this.onConnectRoland,
    required this.panasonicCameras,
    required this.onConnectPanasonic,
    required this.onResponse,
  });

  void _openConnections(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ConnectionsDialog(
        rolandIpController: rolandIpController,
        rolandConnected: rolandConnected,
        rolandConnecting: rolandConnecting,
        rolandConnectionError: rolandConnectionError,
        onConnectRoland: onConnectRoland,
        panasonicCameras: panasonicCameras,
        onConnectPanasonic: onConnectPanasonic,
      ),
    );
  }

  void _openMasterControl(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Master Control'),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 700,
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: MasterControlWidget(
            rolandService: rolandService,
            rolandConnected: rolandConnected,
            rolandIpController: rolandIpController,
            cameras: panasonicCameras,
            onResponse: onResponse,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openPinP(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PinP'),
        content: SizedBox(
          width: 500,
          child: PinPTab(
            rolandConnected: rolandConnected,
            onRolandResponse: onResponse,
            rolandService: rolandService,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Demo / Live mode toggle
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
                          mockMode ? 'Demo Mode' : 'Live Mode',
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
                  Switch(value: mockMode, onChanged: onMockModeChanged),
                ],
              ),
            ),
            const SizedBox(height: 8),

            ListTile(
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('Manage Connections'),
              subtitle: const Text('Configure device IPs and connect/disconnect'),
              trailing: const Icon(Icons.chevron_right),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () => _openConnections(context),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize),
              title: const Text('Master Control'),
              subtitle: const Text('Manage macros and presets, assign visibility'),
              trailing: const Icon(Icons.chevron_right),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () => _openMasterControl(context),
            ),
            ListTile(
              leading: const Icon(Icons.picture_in_picture),
              title: const Text('PinP'),
              subtitle: const Text('Picture-in-picture source and position'),
              trailing: const Icon(Icons.chevron_right),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () => _openPinP(context),
            ),
          ],
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
