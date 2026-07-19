import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/role.dart';
import '../models/scene.dart';
import '../models/service_order.dart';
import '../services/roland_service.dart';
import '../services/panasonic_service.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/mock/mock_roland_service.dart';
import '../services/mock/mock_panasonic_service.dart';
import '../services/device_config_store.dart';
import '../services/people_store.dart';
import '../services/role_store.dart';
import '../services/scene_store.dart';
import '../services/service_order_store.dart';
import '../services/visibility_store.dart';
import 'basic_tab.dart';
import 'filtered_control_widget.dart';
import 'order_tab.dart';
import 'scenes_tab.dart';
import 'settings_dialog.dart';

class MultiDeviceControlPage extends StatefulWidget {
  const MultiDeviceControlPage({super.key});

  @override
  State<MultiDeviceControlPage> createState() => _MultiDeviceControlPageState();
}

class _MultiDeviceControlPageState extends State<MultiDeviceControlPage> {
  bool _mockMode = true;
  bool _connectingAll = false;

  // Roland
  final TextEditingController _rolandIpController =
      TextEditingController(text: '10.0.1.20');
  RolandServiceAbstract _rolandService = MockRolandService();
  final ValueNotifier<bool> _rolandConnected = ValueNotifier(false);
  final ValueNotifier<bool> _rolandConnecting = ValueNotifier(false);
  String _rolandResponse = '';
  final ValueNotifier<String> _rolandConnectionError = ValueNotifier('');

  // Panasonic
  final List<PanasonicCameraConfig> _panasonicCameras = [];

  // Shared data
  List<Scene> _scenes = [];
  List<Person> _people = [];
  List<Role> _roles = [];
  List<ServiceOrder> _serviceOrders = [];

  String _masterResponse = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceConfig();
    _loadScenes();
    _loadPeople();
    _loadRoles();
    _loadOrders();
  }

  Future<void> _loadDeviceConfig() async {
    final rolandIp = await DeviceConfigStore.loadRolandIp();
    final cameras = await DeviceConfigStore.loadCameras();
    if (!mounted) return;
    setState(() {
      _rolandIpController.text = rolandIp;
      _panasonicCameras
        ..clear()
        ..addAll(cameras.map(
            (e) => PanasonicCameraConfig(name: e.name, ipAddress: e.ip)));
    });
  }

  void _applyDeviceConfig(String rolandIp, List<CameraEntry> entries) {
    // Disconnect and dispose cameras that are being replaced.
    for (final c in _panasonicCameras) {
      c.isConnected.value = false;
      c.service = null;
      c.dispose();
    }
    setState(() {
      _rolandIpController.text = rolandIp;
      if (_rolandConnected.value) {
        _rolandService.disconnect();
        _rolandConnected.value = false;
        _rolandService = MockRolandService();
      }
      _panasonicCameras
        ..clear()
        ..addAll(entries.map(
            (e) => PanasonicCameraConfig(name: e.name, ipAddress: e.ip)));
    });
    DeviceConfigStore.save(rolandIp, entries);
  }

  @override
  void dispose() {
    _rolandService.disconnect();
    _rolandIpController.dispose();
    for (final camera in _panasonicCameras) {
      camera.ipController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadScenes() async {
    final scenes = await SceneStore.loadAll();
    if (mounted) setState(() => _scenes = scenes);
  }

  Future<void> _loadPeople() async {
    final people = await PeopleStore.loadAll();
    if (mounted) setState(() => _people = people);
  }

  Future<void> _loadRoles() async {
    final roles = await RoleStore.loadAll();
    if (mounted) setState(() => _roles = roles);
  }

  void _loadAll() {
    _loadScenes();
    _loadPeople();
    _loadRoles();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final orders = await ServiceOrderStore.loadAll();
    if (mounted) setState(() => _serviceOrders = orders);
  }

  Future<void> _connectAll() async {
    setState(() => _connectingAll = true);
    await Future.wait([
      _connectRoland(),
      ...List.generate(_panasonicCameras.length, _connectPanasonic),
    ]);
    if (mounted) setState(() => _connectingAll = false);
  }

  Future<void> _connectRoland() async {
    if (_rolandConnected.value) {
      await _rolandService.disconnect();
      setState(() {
        _rolandConnected.value = false;
        _rolandService = MockRolandService();
        _rolandConnectionError.value = '';
      });
      return;
    }

    setState(() {
      _rolandConnecting.value = true;
      _rolandConnectionError.value = '';
    });

    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _rolandService = MockRolandService();
        _rolandConnected.value = true;
        _rolandConnecting.value = false;
        _rolandConnectionError.value = '';
        _rolandResponse = 'Mock Roland V-160HD Connected';
      });
      return;
    }

    final service = RolandService(host: _rolandIpController.text);
    try {
      await service.connect();
      setState(() {
        _rolandService = service;
        _rolandConnected.value = true;
        _rolandConnecting.value = false;
        _rolandConnectionError.value = '';
      });
      service.responseStream.listen((data) {
        setState(() => _rolandResponse = data.toString());
      });
    } catch (e) {
      setState(() {
        _rolandConnecting.value = false;
        _rolandConnectionError.value = e.toString();
      });
    }
  }

  Future<void> _connectPanasonic(int cameraIndex) async {
    if (cameraIndex >= _panasonicCameras.length) return;
    final camera = _panasonicCameras[cameraIndex];

    if (camera.isConnected.value) {
      setState(() {
        camera.isConnected.value = false;
        camera.service = MockPanasonicService();
        camera.connectionError.value = '';
      });
      return;
    }

    setState(() {
      camera.isConnecting.value = true;
      camera.connectionError.value = '';
    });

    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        camera.service = MockPanasonicService();
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
      return;
    }

    try {
      final service = PanasonicService(ipAddress: camera.ipController.text);
      await service.getCameraInfo();
      setState(() {
        camera.service = service;
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
    } catch (e) {
      setState(() {
        camera.isConnecting.value = false;
        camera.connectionError.value = 'Could not reach camera: ${e.toString()}';
      });
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => SettingsDialog(
            mockMode: _mockMode,
            onMockModeChanged: (value) {
              setDialogState(() {
                _mockMode = value;
                if (_rolandConnected.value) {
                  _rolandService.disconnect();
                  _rolandConnected.value = false;
                  _rolandService = MockRolandService();
                }
                for (final camera in _panasonicCameras) {
                  if (camera.isConnected.value) {
                    camera.isConnected.value = false;
                    camera.service = MockPanasonicService();
                  }
                }
              });
            },
            rolandService: _rolandService,
            rolandIpController: _rolandIpController,
            rolandConnected: _rolandConnected,
            rolandConnecting: _rolandConnecting,
            rolandConnectionError: _rolandConnectionError,
            onConnectRoland: _connectRoland,
            panasonicCameras: _panasonicCameras,
            onConnectPanasonic: _connectPanasonic,
            onResponse: (r) => setState(() => _masterResponse = r),
            scenes: _scenes,
            people: _people,
            roles: _roles,
            onScenesChanged: _loadScenes,
            onPeopleChanged: _loadPeople,
            onRolesChanged: _loadRoles,
            onOrdersChanged: _loadOrders,
            onAllDataChanged: _loadAll,
            onDeviceConfigSaved: _applyDeviceConfig,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _rolandConnected.value ||
        _panasonicCameras.any((c) => c.isConnected.value);

    if (!isConnected) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Multi-device control app'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showSettingsDialog(context),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.devices, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No devices connected',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _mockMode
                      ? Colors.orange.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _mockMode ? 'Demo Mode' : 'Live Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _mockMode
                        ? Colors.orange.shade800
                        : Colors.blue.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _connectingAll ? null : _connectAll,
                icon: _connectingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.power_settings_new),
                label: Text(_connectingAll ? 'Connecting...' : 'Connect All'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showSettingsDialog(context),
                icon: const Icon(Icons.settings),
                label: const Text('Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roland V-160HD Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 5,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Basic'),
                Tab(text: 'Advanced'),
                Tab(text: 'Scenes'),
                Tab(text: 'Order'),
                Tab(text: 'Switching'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  FilteredControlWidget(
                    title: 'Basic',
                    filter: ItemVisibility.basic,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    rolandIpController: _rolandIpController,
                    cameras: _panasonicCameras,
                    onResponse: (r) => setState(() => _masterResponse = r),
                  ),
                  FilteredControlWidget(
                    title: 'Advanced',
                    filter: ItemVisibility.expanded,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    rolandIpController: _rolandIpController,
                    cameras: _panasonicCameras,
                    onResponse: (r) => setState(() => _masterResponse = r),
                  ),
                  ScenesTab(
                    cameras: _panasonicCameras,
                    scenes: _scenes,
                    people: _people,
                    onResponse: (r) => setState(() => _masterResponse = r),
                  ),
                  OrderTab(
                    cameras: _panasonicCameras,
                    people: _people,
                    roles: _roles,
                    scenes: _scenes,
                    orders: _serviceOrders,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    onResponse: (r) => setState(() => _masterResponse = r),
                  ),
                  BasicTab(
                    rolandConnected: _rolandConnected,
                    onRolandResponse: (r) => setState(() => _rolandResponse = r),
                    rolandService: _rolandService,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last Roland Response: $_rolandResponse',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('Last Response: $_masterResponse',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
