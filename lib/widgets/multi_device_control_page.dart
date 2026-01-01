import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/roland_service.dart';
import '../services/panasonic_service.dart';
import 'settings_dialog.dart';
import 'basic_tab.dart';
import 'pinp_tab.dart';
import 'panasonic_presets_tab.dart';

class MultiDeviceControlPage extends StatefulWidget {
  const MultiDeviceControlPage({super.key});

  @override
  State<MultiDeviceControlPage> createState() => _MultiDeviceControlPageState();
}

class _MultiDeviceControlPageState extends State<MultiDeviceControlPage> {
  // Mock mode
  bool _mockMode = false;

  // Roland
  final TextEditingController _rolandIpController = TextEditingController(text: '10.0.1.20');
  RolandService? _rolandService;
  bool _rolandConnected = false;
  bool _rolandConnecting = false;
  String _rolandResponse = '';
  String _rolandConnectionError = '';

  // Panasonic - Multiple cameras
  final List<PanasonicCameraConfig> _panasonicCameras = [];
  String _panasonicResponse = '';

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
    _rolandService?.disconnect();
    _rolandIpController.dispose();
    for (var camera in _panasonicCameras) {
      camera.ipController.dispose();
    }
    super.dispose();
  }

  Future<void> _connectRoland() async {
    if (_rolandConnected) {
      _rolandService?.disconnect();
      setState(() {
        _rolandConnected = false;
        _rolandService = null;
        _rolandConnectionError = '';
      });
      return;
    }

    setState(() {
      _rolandConnecting = true;
      _rolandConnectionError = '';
    });

    if (_mockMode) {
      // Mock connection - simulate successful connection
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _rolandConnected = true;
        _rolandConnecting = false;
        _rolandConnectionError = '';
        _rolandResponse = 'Mock Roland V-160HD Connected';
      });
      return;
    }

    final service = RolandService(host: _rolandIpController.text);
    try {
      await service.connect();
      setState(() {
        _rolandService = service;
        _rolandConnected = true;
        _rolandConnecting = false;
        _rolandConnectionError = '';
      });

      service.responseStream.listen((data) {
        setState(() {
          _rolandResponse = data.toString();
        });
      });

    } catch (e) {
      setState(() {
        _rolandConnecting = false;
        _rolandConnectionError = e.toString();
      });
    }
  }

  Future<void> _connectPanasonic(int cameraIndex) async {
    if (cameraIndex >= _panasonicCameras.length) return;

    final camera = _panasonicCameras[cameraIndex];

    if (camera.isConnected) {
      setState(() {
        camera.isConnected = false;
        camera.service = null;
        camera.connectionError = '';
      });
      return;
    }

    setState(() {
      camera.isConnecting = true;
      camera.connectionError = '';
    });

    if (_mockMode) {
      // Mock connection - simulate successful connection
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        camera.isConnected = true;
        camera.isConnecting = false;
        camera.connectionError = '';
        _panasonicResponse = 'Mock ${camera.name} Connected';
      });
      return;
    }

    try {
      final service = PanasonicService(ipAddress: camera.ipController.text);
      setState(() {
        camera.service = service;
        camera.isConnected = true;
        camera.isConnecting = false;
        camera.connectionError = '';
      });
    } catch (e) {
      setState(() {
        camera.isConnecting = false;
        camera.connectionError = e.toString();
      });
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SettingsDialog(
          mockMode: _mockMode,
          onMockModeChanged: (value) {
            setState(() {
              _mockMode = value;
              // Disconnect all when switching modes
              if (_rolandConnected) {
                _rolandService?.disconnect();
                _rolandConnected = false;
                _rolandService = null;
              }
              for (var camera in _panasonicCameras) {
                if (camera.isConnected) {
                  camera.isConnected = false;
                  camera.service = null;
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Basic'),
                Tab(text: 'PinP'),
                Tab(text: 'Panasonic'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  BasicTab(
                    rolandConnected: _rolandConnected,
                    mockMode: _mockMode,
                    onRolandResponse: (response) => setState(() => _rolandResponse = response),
                  ),
                  PinPTab(
                    rolandConnected: _rolandConnected,
                    mockMode: _mockMode,
                    onRolandResponse: (response) => setState(() => _rolandResponse = response),
                  ),
                  PanasonicPresetsTab(
                    panasonicCameras: _panasonicCameras,
                    mockMode: _mockMode,
                    onPanasonicResponse: (response) => setState(() => _panasonicResponse = response),
                    panasonicResponse: _panasonicResponse,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Last Roland Response: $_rolandResponse', style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}