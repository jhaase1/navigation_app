import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/scene.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/config_bundle.dart';
import 'connections_dialog.dart';
import 'master_control_widget.dart';
import 'order_manager_dialog.dart';
import 'people_manager_dialog.dart';
import 'pinp_tab.dart';
import 'role_manager_dialog.dart';
import 'scene_manager_dialog.dart';

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
  final List<Scene> scenes;
  final List<Person> people;
  final List<Role> roles;
  final VoidCallback onScenesChanged;
  final VoidCallback onPeopleChanged;
  final VoidCallback onRolesChanged;
  final VoidCallback onOrdersChanged;
  final VoidCallback onAllDataChanged;

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
    required this.scenes,
    required this.people,
    required this.roles,
    required this.onScenesChanged,
    required this.onPeopleChanged,
    required this.onRolesChanged,
    required this.onOrdersChanged,
    required this.onAllDataChanged,
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

  void _openSceneManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => SceneManagerDialog(onSaved: onScenesChanged),
    );
  }

  void _openPeopleManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PeopleManagerDialog(
        scenes: scenes,
        cameras: panasonicCameras,
        onSaved: onPeopleChanged,
      ),
    );
  }

  void _openRoleManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => RoleManagerDialog(onSaved: onRolesChanged),
    );
  }

  void _openOrderManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => OrderManagerDialog(
        roles: roles,
        scenes: scenes,
        cameras: panasonicCameras,
        onSaved: onOrdersChanged,
      ),
    );
  }

  Future<void> _exportConfig(BuildContext context) async {
    final pathCtrl = TextEditingController(
        text: ConfigBundle.suggestedExportPath());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export Configuration'),
        content: TextField(
          controller: pathCtrl,
          decoration: const InputDecoration(
            labelText: 'Save path',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Export')),
        ],
      ),
    );

    final path = pathCtrl.text.trim();
    pathCtrl.dispose();
    if (confirmed != true || path.isEmpty || !context.mounted) return;

    try {
      final bundle = await ConfigBundle.fromStores();
      if (!context.mounted) return;
      await ConfigBundle.writeToPath(path, bundle);
      onResponse('Exported to $path');
    } catch (e) {
      if (context.mounted) onResponse('Export failed: $e');
    }
  }

  Future<void> _importConfig(BuildContext context) async {
    final pathCtrl = TextEditingController();

    final enteredPath = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import Configuration'),
        content: TextField(
          controller: pathCtrl,
          decoration: InputDecoration(
            labelText: 'File path',
            hintText: ConfigBundle.suggestedExportPath(),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Load')),
        ],
      ),
    );

    final path = pathCtrl.text.trim();
    pathCtrl.dispose();
    if (enteredPath != true || path.isEmpty || !context.mounted) return;

    ConfigBundle bundle;
    try {
      bundle = await ConfigBundle.readFromPath(path);
    } catch (e) {
      if (context.mounted) onResponse('Import failed: $e');
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Replace all configuration?'),
        content: Text(
          'This will overwrite everything with:\n'
          '  • ${bundle.scenes.length} scene${bundle.scenes.length == 1 ? '' : 's'}\n'
          '  • ${bundle.people.length} person${bundle.people.length == 1 ? '' : 's'}\n'
          '  • ${bundle.roles.length} role${bundle.roles.length == 1 ? '' : 's'}\n'
          '  • ${bundle.orders.length} service order${bundle.orders.length == 1 ? '' : 's'}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace all'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await bundle.saveToStores();
    onAllDataChanged();
    onResponse('Configuration imported successfully');
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            _tile(
              icon: Icons.settings_ethernet,
              title: 'Manage Connections',
              subtitle: 'Configure device IPs and connect/disconnect',
              onTap: () => _openConnections(context),
            ),
            _tile(
              icon: Icons.dashboard_customize,
              title: 'Master Control',
              subtitle: 'Manage macros and presets, assign visibility',
              onTap: () => _openMasterControl(context),
            ),
            _tile(
              icon: Icons.theaters,
              title: 'Manage Scenes',
              subtitle: 'Link camera presets for real-world positions',
              onTap: () => _openSceneManager(context),
            ),
            _tile(
              icon: Icons.badge,
              title: 'Manage Roles',
              subtitle: 'Define generic roles (Reader 1, Priest, Deacon…)',
              onTap: () => _openRoleManager(context),
            ),
            _tile(
              icon: Icons.people,
              title: 'Manage People',
              subtitle: 'Create profiles with per-scene height preferences',
              onTap: () => _openPeopleManager(context),
            ),
            _tile(
              icon: Icons.format_list_numbered,
              title: 'Manage Orders',
              subtitle: 'Build service sequences of person + scene moments',
              onTap: () => _openOrderManager(context),
            ),
            _tile(
              icon: Icons.picture_in_picture,
              title: 'PinP',
              subtitle: 'Picture-in-picture source and position',
              onTap: () => _openPinP(context),
            ),
            const Divider(),
            _tile(
              icon: Icons.upload_file,
              title: 'Export Configuration',
              subtitle: 'Save scenes, people, roles & orders to a JSON file',
              onTap: () => _exportConfig(context),
            ),
            _tile(
              icon: Icons.download,
              title: 'Import Configuration',
              subtitle: 'Replace all data from a previously exported file',
              onTap: () => _importConfig(context),
            ),
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

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}
