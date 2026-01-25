import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/roland_service.dart';
import '../services/panasonic_service.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/mock/mock_roland_service.dart';
import '../services/mock/mock_panasonic_service.dart';
import 'settings_dialog.dart';
import 'basic_tab.dart';
import 'pinp_tab.dart';
import 'panasonic_presets_tab.dart';
import 'unified_control_widget.dart';

class MultiDeviceControlPage extends StatefulWidget {
  const MultiDeviceControlPage({super.key});

  @override
  State<MultiDeviceControlPage> createState() => _MultiDeviceControlPageState();
}

class _MultiDeviceControlPageState extends State<MultiDeviceControlPage> {
  // Mock mode
  bool _mockMode = false;

  // Roland
  final TextEditingController _rolandIpController =
      TextEditingController(text: '10.0.1.20');
  RolandServiceAbstract _rolandService = MockRolandService();
  final ValueNotifier<bool> _rolandConnected = ValueNotifier(false);
  final ValueNotifier<bool> _rolandConnecting = ValueNotifier(false);
  String _rolandResponse = '';
  final ValueNotifier<String> _rolandConnectionError = ValueNotifier('');

  // Panasonic - Multiple cameras
  final List<PanasonicCameraConfig> _panasonicCameras = [];
  String _panasonicResponse = '';

  // Unified control
  String _unifiedResponse = '';

  @override
  void initState() {
    super.initState();
    // Initialize with 3 default cameras
    _panasonicCameras.addAll([
      PanasonicCameraConfig(name: 'Camera 1', ipAddress: '10.0.1.10'),
      PanasonicCameraConfig(name: 'Camera 2', ipAddress: '10.0.1.11'),
      PanasonicCameraConfig(name: 'Camera 3', ipAddress: '10.0.1.12'),
    ]);
  }

  @override
  void dispose() {
    _rolandService.dispose();
    _rolandIpController.dispose();
    for (var camera in _panasonicCameras) {
      camera.service?.dispose();
      camera.ipController.dispose();
    }
    super.dispose();
  }

  Future<void> _connectRoland() async {
    if (_rolandConnected.value) {
      await _rolandService.dispose();
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
      // Mock connection - simulate successful connection
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
        setState(() {
          _rolandResponse = data.toString();
        });
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
      camera.service?.dispose();
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
      // Mock connection - simulate successful connection
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        camera.service = MockPanasonicService();
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
        _panasonicResponse = 'Mock ${camera.name} Connected';
      });
      return;
    }

    try {
      final service = PanasonicService(ipAddress: camera.ipController.text);
      setState(() {
        camera.service = service;
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
    } catch (e) {
      setState(() {
        camera.isConnecting.value = false;
        camera.connectionError.value = e.toString();
      });
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) => SettingsDialog(
            mockMode: _mockMode,
            onMockModeChanged: (value) {
              setState(() {
                _mockMode = value;
                // Disconnect and dispose all when switching modes
                if (_rolandConnected.value) {
                  _rolandService.dispose();
                  _rolandConnected.value = false;
                  _rolandService = MockRolandService();
                }
                for (var camera in _panasonicCameras) {
                  if (camera.isConnected.value) {
                    camera.service?.dispose();
                    camera.isConnected.value = false;
                    camera.service = MockPanasonicService();
                  }
                }
              });
            },
            rolandIpController: _rolandIpController,
            rolandConnected: _rolandConnected,
            rolandConnecting: _rolandConnecting,
            rolandConnectionError: _rolandConnectionError,
            onConnectRoland: _connectRoland,
            panasonicCameras: _panasonicCameras,
            onConnectPanasonic: _connectPanasonic,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if any device is connected
    final isConnected = _mockMode ||
        _rolandConnected.value ||
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
              const SizedBox(height: 8),
              const Text(
                'Please connect to Roland and/or Panasonic devices.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _showSettingsDialog(context),
                child: const Text('Open Settings'),
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
        length: 4,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Unified'),
                Tab(text: 'Basic'),
                Tab(text: 'PinP'),
                Tab(text: 'Panasonic'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  UnifiedControlWidget(
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    cameras: _panasonicCameras,
                    onResponse: (response) =>
                        setState(() => _unifiedResponse = response),
                  ),
                  BasicTab(
                    rolandConnected: _rolandConnected,
                    onRolandResponse: (response) =>
                        setState(() => _rolandResponse = response),
                    rolandService: _rolandService,
                  ),
                  PinPTab(
                    rolandConnected: _rolandConnected,
                    onRolandResponse: (response) =>
                        setState(() => _rolandResponse = response),
                    rolandService: _rolandService,
                  ),
                  PanasonicPresetsTab(
                    panasonicCameras: _panasonicCameras,
                    onPanasonicResponse: (response) =>
                        setState(() => _panasonicResponse = response),
                    panasonicResponse: _panasonicResponse,
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
                  Text('Last Unified Response: $_unifiedResponse',
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
