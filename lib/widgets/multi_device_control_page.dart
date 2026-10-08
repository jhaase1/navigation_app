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
import '../services/backup/app_fault.dart';
import '../services/backup/backup_controller.dart';
import '../services/mock/mock_roland_service.dart';
import '../services/mock/mock_panasonic_service.dart';
import '../services/device_config_store.dart';
import '../services/height_range_store.dart';
import '../services/operator_store.dart';
import '../services/people_store.dart';
import '../services/lineup_lease.dart';
import '../services/position_store.dart';
import '../services/service_store.dart';
import '../utils/device_feedback.dart';
import 'backup/backup_status_pill.dart';
import 'backup/google_sign_in_banner.dart';
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

  /// How the switcher is named in device faults.
  static const _switcherName = 'Roland';

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
  final _lineupLease = LineupLease();

  // One key for both layouts, so "Not now" survives connecting a device.
  final _signInBannerKey = GlobalKey();

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
        if (up) {
          _showResponse('${camera.name} is back');
          _backup.clearDeviceFault(FaultDomain.camera, _cameraFaultId(camera));
        } else {
          _showFailure('${camera.name} not responding');
          _backup.reportDeviceFault(AppFault.device(
              FaultDomain.camera,
              _cameraFaultId(camera),
              '${camera.name} is not answering. Shots on it will fail until '
              'it comes back.'));
        }
      },
    )..start();
    _lineupLease.start();
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
      // Renamed or removed, nothing would ever clear it again.
      _backup.clearDeviceFault(FaultDomain.camera, _cameraFaultId(c));
      // A connect still dialling for a replaced camera is now stale.
      _cameraConnectGeneration.remove(c);
      c.isConnected.value = false;
      _closeCameraService(c);
      c.dispose();
    }
    setState(() {
      _rolandIpController.text = rolandIp;
      _releaseRoland();
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

  void _showFailure(String message) {
    if (mounted) showDeviceResponse(context, message, failed: true);
  }

  /// Keeps the Live badge truthful: follow the switcher's link both ways —
  /// down when it drops underneath us, up again when it reconnects on its own.
  void _watchRolandLink(RolandServiceAbstract service) {
    _rolandLinkSub?.cancel();
    _rolandLinkSub = service.connectionChanges.listen((up) {
      if (!mounted || !identical(_rolandService, service)) return;
      if (up == _rolandConnected.value) return;
      setState(() => _rolandConnected.value = up);
      if (up) {
        _showResponse('Roland reconnected');
        _backup.clearDeviceFault(FaultDomain.roland, _switcherName);
      } else {
        _showFailure('Roland connection lost. Reconnecting…');
        _backup.reportDeviceFault(AppFault.device(FaultDomain.roland,
            _switcherName, 'The switcher is not connected. Macros will fail.'));
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
    // A switcher that reboots or loses its cable mid-service comes back
    // without anyone touching Settings.
    service.setAutoReconnect(true);
    return service;
  }

  /// Bumped by every Connect and every let-go. A connect still dialling when
  /// it changes is stale: whatever it returns is hung up, never installed —
  /// otherwise a Demo switch, an IP change or a second Connect made while it
  /// dialled would be overridden when it finished, or leave an orphan.
  int _rolandConnectGeneration = 0;

  /// Deliberately lets go of the switcher, including one still connecting.
  /// The link watcher is cancelled first so our own disconnect is not
  /// reported as a lost connection. Safe to call when nothing is connected.
  ///
  /// Called whether or not the link is up: a session whose link dropped is
  /// still trying to reconnect, and only this stops it.
  void _releaseRoland({bool clearFault = true}) {
    _rolandConnectGeneration++;
    _rolandConnecting.value = false;
    // Let go on purpose: nothing is wrong, so nothing stays on the pill.
    // Not when about to connect again — if that fails, the switcher is
    // still unreachable and the pill must keep saying so.
    if (clearFault) _backup.clearDeviceFault(FaultDomain.roland, _switcherName);
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
    _lineupLease.dispose();
    _rolandService.disconnect();
    _rolandIpController.dispose();
    for (final camera in _panasonicCameras) {
      _closeCameraService(camera);
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
      // A session that dropped is still reconnecting on its own: end it
      // before opening another, or two would fight over the switcher.
      _releaseRoland(clearFault: false);
      _rolandConnecting.value = true;
      _rolandConnectionError.value = '';
    });
    final generation = _rolandConnectGeneration;
    bool stale() => !mounted || generation != _rolandConnectGeneration;

    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (stale()) return;
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
      if (stale() || _mockMode) {
        // Let go of, or superseded, while dialling: nobody else will ever
        // close this session.
        await service.disconnect();
        return;
      }
      setState(() {
        _rolandService = service;
        _watchRolandLink(service);
        _backup.clearDeviceFault(FaultDomain.roland, _switcherName);
        _rolandConnected.value = true;
        _rolandConnecting.value = false;
        _rolandConnectionError.value = '';
      });
    } catch (e) {
      if (stale()) return;
      setState(() {
        _rolandConnecting.value = false;
        _rolandConnectionError.value = e.toString();
      });
    }
  }

  /// Names a camera in device faults. The address keeps two cameras that
  /// share a name apart: one coming back must not clear the other's fault.
  static String _cameraFaultId(PanasonicCameraConfig camera) =>
      '${camera.name} (${camera.ipController.text})';

  /// Per camera, bumped by every Connect and every let-go — the camera
  /// counterpart of [_rolandConnectGeneration]. A camera connect still
  /// dialling when it changes is discarded, never installed.
  final Map<PanasonicCameraConfig, int> _cameraConnectGeneration = {};

  /// Ends [camera]'s service. Every Connect builds a new one for the same
  /// address; an old one left running kept sending its queued recalls,
  /// racing the new connection's.
  static void _closeCameraService(PanasonicCameraConfig camera) {
    unawaited(camera.service?.dispose());
    camera.service = null;
  }

  /// Lets go of [camera] whether or not it reads connected. A camera the
  /// monitor had marked down still holds its real service and is still
  /// watched; skipping it let the monitor bring it back, live, in Demo.
  void _releaseCamera(PanasonicCameraConfig camera, {bool clearFault = true}) {
    _cameraConnectGeneration[camera] =
        (_cameraConnectGeneration[camera] ?? 0) + 1;
    if (clearFault) {
      _backup.clearDeviceFault(FaultDomain.camera, _cameraFaultId(camera));
    }
    _cameraHealth.forget(camera);
    camera.isConnecting.value = false;
    camera.isConnected.value = false;
    // No service at all, not a Demo stand-in: anything that forgets to check
    // the connected flag then fails as not connected instead of "recalling"
    // presets on a fake while the real camera sits dead.
    _closeCameraService(camera);
  }

  Future<void> _connectPanasonic(int cameraIndex) async {
    if (cameraIndex >= _panasonicCameras.length) return;
    final camera = _panasonicCameras[cameraIndex];

    if (camera.isConnected.value) {
      setState(() {
        _releaseCamera(camera);
        camera.connectionError.value = '';
      });
      return;
    }

    setState(() {
      // Not a deliberate let-go: if this Connect fails the camera is still
      // unreachable, and the pill must keep saying so.
      _releaseCamera(camera, clearFault: false);
      camera.isConnecting.value = true;
      camera.connectionError.value = '';
    });
    final generation = _cameraConnectGeneration[camera];
    bool stale() =>
        !mounted || generation != _cameraConnectGeneration[camera];

    if (_mockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (stale()) return;
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
      if (stale() || _mockMode) {
        // Let go of, or superseded, while dialling: nobody else will ever
        // close this service.
        unawaited(service.dispose());
        return;
      }
      // Already "connected" again, so the monitor will never report it back.
      _backup.clearDeviceFault(FaultDomain.camera, _cameraFaultId(camera));
      setState(() {
        camera.service = service;
        camera.isConnected.value = true;
        camera.isConnecting.value = false;
        camera.connectionError.value = '';
      });
    } catch (e) {
      if (stale()) return;
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
                _releaseRoland();
                for (final camera in _panasonicCameras) {
                  // A changed mode is a fresh start for every camera.
                  _releaseCamera(camera);
                }
              });
              // Every device was just let go of. The badge and the offline
              // banner live on the page, not the dialog: without this they
              // kept reading Live until something else rebuilt the page.
              setState(() {});
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
            onFailure: _showFailure,
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
      body: Column(
        children: [
          GoogleSignInBanner(key: _signInBannerKey, controller: _backup),
          Expanded(
            child: DefaultTabController(
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
                          onFailure: _showFailure,
                        ),
                        OperatorPanel(
                          operator: _activeOperator,
                          rolandService: _rolandService,
                          rolandConnected: _rolandConnected,
                          rolandIpController: _rolandIpController,
                          cameras: _panasonicCameras,
                          onResponse: _showResponse,
                          onFailure: _showFailure,
                          onServicesChanged: _loadServices,
                        ),
                        PositionsTab(
                          cameras: _panasonicCameras,
                          positions: _positions,
                          people: _people,
                          heightRanges: _heightRanges,
                          onResponse: _showResponse,
                          onFailure: _showFailure,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
