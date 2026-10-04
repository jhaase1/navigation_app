import 'dart:async';

import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/operator_profile.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../models/service.dart';
import '../services/roland_service.dart';
import '../services/panasonic_service.dart';
import '../services/abstract/panasonic_service_abstract.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/camera_health_monitor.dart';
import '../services/backup/backup_controller.dart';
import '../services/mock/mock_roland_service.dart';
import '../services/mock/mock_panasonic_service.dart';
import '../services/device_config_store.dart';
import '../services/height_range_store.dart';
import '../services/operator_store.dart';
import '../services/people_store.dart';
import '../services/position_store.dart';
import '../services/service_store.dart';
import '../utils/device_feedback.dart';
import 'backup/backup_status_pill.dart';
import 'operator_panel.dart';
import 'people_manager_dialog.dart';
import 'service_tab.dart';
import 'positions_tab.dart';
import 'settings_dialog.dart';

class MultiDeviceControlPage extends StatefulWidget {
  const MultiDeviceControlPage({
    super.key,
    this.backupController,
    this.rolandConnector,
    this.cameraConnector,
    this.cameraHealthInterval = const Duration(seconds: 5),
  });

  /// Injected by tests. Production passes nothing and gets
  /// [BackupController.forEnvironment], which is disabled unless
  /// `--dart-define=BACKUP_MOCK=true`.
  final BackupController? backupController;

  /// Injected by tests. Opens a live switcher link for the given host;
  /// production passes nothing and gets a real [RolandService].
  final Future<RolandServiceAbstract> Function(String host)? rolandConnector;

  /// Injected by tests. Reaches a live camera at the given address;
  /// production passes nothing and gets a real [PanasonicService].
  final Future<PanasonicServiceAbstract> Function(String ip)? cameraConnector;

  /// How often connected cameras are asked whether they are still there.
  final Duration cameraHealthInterval;

  @override
  State<MultiDeviceControlPage> createState() => _MultiDeviceControlPageState();
}

class _MultiDeviceControlPageState extends State<MultiDeviceControlPage> {
  bool _mockMode = false;
  bool _connectingAll = false;

  // Roland
  final TextEditingController _rolandIpController =
      TextEditingController(text: '10.0.1.20');
  RolandServiceAbstract _rolandService = MockRolandService();
  final ValueNotifier<bool> _rolandConnected = ValueNotifier(false);
  final ValueNotifier<bool> _rolandConnecting = ValueNotifier(false);
  final ValueNotifier<String> _rolandConnectionError = ValueNotifier('');
  StreamSubscription<bool>? _rolandLinkSub;
  late final CameraHealthMonitor _cameraHealth;

  // Panasonic
  final List<PanasonicCameraConfig> _panasonicCameras = [];

  // Operators
  List<OperatorProfile> _operators = [OperatorProfile.defaultProfile];
  OperatorProfile _activeOperator = OperatorProfile.defaultProfile;

  // Shared data
  List<Position> _positions = [];
  List<Person> _people = [];
  List<Service> _services = [];
  List<HeightRange> _heightRanges = [];
  late final BackupController _backup;

  @override
  void initState() {
    super.initState();
    // The controller registers itself as a WidgetsBindingObserver, so pull on
    // foreground and flush on background are its business, not this widget's.
    _backup = widget.backupController ?? BackupController.forEnvironment();
    unawaited(_backup.start());
    _cameraHealth = CameraHealthMonitor(
      cameras: () => _panasonicCameras,
      interval: widget.cameraHealthInterval,
      onChange: (camera, up) {
        if (!mounted) return;
        setState(() {});
        _showResponse(up
            ? '${camera.name} is back'
            : '${camera.name} not responding');
      },
    )..start();
    _loadDeviceConfig();
    _loadOperators();
    _loadPositions();
    _loadPeople();
    _loadServices();
    _loadHeightRanges();
  }

  Future<void> _loadDeviceConfig() async {
    final rolandIp = await DeviceConfigStore.loadRolandIp();
    final cameras = await DeviceConfigStore.loadCameras();
    if (!mounted) return;
    setState(() {
      _rolandIpController.text = rolandIp;
      _panasonicCameras
        ..clear()
        ..addAll(cameras
            .map((e) => PanasonicCameraConfig(name: e.name, ipAddress: e.ip)));
    });
  }

  Future<void> _loadOperators() async {
    final operators = await OperatorStore.loadAll();
    final activeId = await OperatorStore.loadActiveId();
    if (!mounted) return;
    final active = operators.firstWhere(
      (o) => o.id == activeId,
      orElse: () => operators.first,
    );
    setState(() {
      _operators = operators;
      _activeOperator = active;
    });
  }

  void _setActiveOperator(OperatorProfile op) {
    setState(() => _activeOperator = op);
    OperatorStore.saveActiveId(op.id);
  }

  void _applyDeviceConfig(String rolandIp, List<CameraEntry> entries) {
    for (final c in _panasonicCameras) {
      c.isConnected.value = false;
      c.service = null;
      c.dispose();
    }
    setState(() {
      _rolandIpController.text = rolandIp;
      if (_rolandConnected.value) _releaseRoland();
      _panasonicCameras
        ..clear()
        ..addAll(entries
            .map((e) => PanasonicCameraConfig(name: e.name, ipAddress: e.ip)));
    });
    DeviceConfigStore.save(rolandIp, entries);
  }

  void _showResponse(String message) {
    if (mounted) showDeviceResponse(context, message);
  }

  /// Keeps the Live badge truthful: when the switcher's link drops underneath
  /// us, flip the shared flag instead of waiting for the next failed command.
  void _watchRolandLink(RolandServiceAbstract service) {
    _rolandLinkSub?.cancel();
    _rolandLinkSub = service.connectionChanges.listen((up) {
      if (!up && mounted && identical(_rolandService, service)) {
        setState(() => _rolandConnected.value = false);
        _showResponse('Roland connection lost');
      }
    });
  }

  static Future<PanasonicServiceAbstract> _openCamera(String ip) async {
    final service = PanasonicService(ipAddress: ip);
    await service.probe();
    return service;
  }

  static Future<RolandServiceAbstract> _openRoland(String host) async {
    final service = RolandService(host: host);
    await service.connect();
    return service;
  }

  /// Deliberately lets go of the switcher. The link watcher is cancelled
  /// first so our own disconnect is not reported as a lost connection.
  void _releaseRoland() {
    _rolandLinkSub?.cancel();
    _rolandLinkSub = null;
    _rolandService.disconnect();
    _rolandConnected.value = false;
    _rolandService = MockRolandService();
  }

  @override
  void dispose() {
    _cameraHealth.stop();
    _rolandLinkSub?.cancel();
    _rolandService.disconnect();
    _rolandIpController.dispose();
    for (final camera in _panasonicCameras) {
      camera.ipController.dispose();
    }
    unawaited(_backup.dispose());
    super.dispose();
  }

  Future<void> _loadPositions() async {
    final positions = await PositionStore.loadAll();
    if (mounted) setState(() => _positions = positions);
  }

  Future<void> _loadPeople() async {
    final people = await PeopleStore.loadAll();
    if (mounted) setState(() => _people = people);
  }

  Future<void> _loadServices() async {
    final services = await ServiceStore.loadAll();
    if (mounted) setState(() => _services = services);
  }

  Future<void> _loadHeightRanges() async {
    final heightRanges = await HeightRangeStore.loadAll();
    if (mounted) setState(() => _heightRanges = heightRanges);
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
      setState(() {
        _releaseRoland();
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
      });
      return;
    }

    try {
      final service = await (widget.rolandConnector ?? _openRoland)(
          _rolandIpController.text);
      if (!mounted) return;
      setState(() {
        _rolandService = service;
        _watchRolandLink(service);
        _rolandConnected.value = true;
        _rolandConnecting.value = false;
        _rolandConnectionError.value = '';
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
      _cameraHealth.forget(camera);
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
      final service = await (widget.cameraConnector ?? _openCamera)(
          camera.ipController.text);
      if (!mounted) return;
      setState(() {
        camera.service = service;
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
    } catch (e) {
      setState(() {
        camera.isConnecting.value = false;
        camera.connectionError.value =
            'Could not reach camera: ${e.toString()}';
      });
    }
  }

  void _showOperatorPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Operator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _operators.map((op) {
            final selected = op.id == _activeOperator.id;
            return ListTile(
              leading: Icon(selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(op.name),
              onTap: () {
                _setActiveOperator(op);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openPeopleManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PeopleManagerDialog(
        positions: _positions,
        cameras: _panasonicCameras,
        heightRanges: _heightRanges,
        onSaved: _loadPeople,
      ),
    );
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
                if (_rolandConnected.value) _releaseRoland();
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
            onResponse: _showResponse,
            positions: _positions,
            heightRanges: _heightRanges,
            onPositionsChanged: () async {
              await _loadPositions();
              setDialogState(() {});
            },
            onServicesChanged: () async {
              await _loadServices();
              setDialogState(() {});
            },
            onHeightRangesChanged: () async {
              await _loadHeightRanges();
              setDialogState(() {});
            },
            onPeopleChanged: () async {
              await _loadPeople();
              setDialogState(() {});
            },
            onAllDataChanged: () async {
              await Future.wait([
                _loadPositions(),
                _loadPeople(),
                _loadServices(),
                _loadHeightRanges(),
              ]);
              setDialogState(() {});
            },
            onDeviceConfigSaved: _applyDeviceConfig,
            onOperatorsChanged: () async {
              await _loadOperators();
              setDialogState(() {});
            },
            backupController: _backup,
          ),
        );
      },
    );
  }

  /// Shown above the tabs while nothing is connected, so service prep, rosters
  /// and cue review stay available at home or before the rack is powered on.
  Widget _buildOfflineBanner() {
    final modeColor =
        _mockMode ? Colors.orange.shade800 : Colors.blue.shade800;
    return Material(
      color: Colors.grey.shade200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            const Icon(Icons.link_off, color: Colors.grey),
            const Text('No devices connected',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_mockMode ? 'Demo Mode' : 'Live Mode',
                style: TextStyle(fontWeight: FontWeight.w600, color: modeColor)),
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
              label: Text(_connectingAll ? 'Connecting…' : 'Connect All'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isConnected = _rolandConnected.value ||
        _panasonicCameras.any((c) => c.isConnected.value);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: BackupStatusPill(controller: _backup),
        actions: [
          Tooltip(
            message: 'Switch operator',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showOperatorPicker(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_activeOperator.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: !isConnected
                            ? Colors.grey.shade300
                            : _mockMode
                                ? Colors.orange.shade100
                                : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        !isConnected
                            ? 'Offline'
                            : _mockMode
                                ? 'Demo'
                                : 'Live',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: !isConnected
                              ? Colors.grey.shade800
                              : _mockMode
                                  ? Colors.orange.shade800
                                  : Colors.blue.shade800,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Manage People',
            onPressed: () => _openPeopleManager(context),
          ),
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
            if (!isConnected) _buildOfflineBanner(),
            const TabBar(
              tabs: [
                Tab(text: 'Service'),
                Tab(text: 'Panel'),
                Tab(text: 'Positions'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ServiceTab(
                    cameras: _panasonicCameras,
                    people: _people,
                    positions: _positions,
                    services: _services,
                    heightRanges: _heightRanges,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    rolandIpController: _rolandIpController,
                    onResponse: _showResponse,
                  ),
                  OperatorPanel(
                    operator: _activeOperator,
                    rolandService: _rolandService,
                    rolandConnected: _rolandConnected,
                    rolandIpController: _rolandIpController,
                    cameras: _panasonicCameras,
                    onResponse: _showResponse,
                    onServicesChanged: _loadServices,
                  ),
                  PositionsTab(
                    cameras: _panasonicCameras,
                    positions: _positions,
                    people: _people,
                    heightRanges: _heightRanges,
                    onResponse: _showResponse,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
