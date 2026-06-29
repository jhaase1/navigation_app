import 'dart:async';
import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/preset_name_store.dart';

class UnifiedControlWidget extends StatefulWidget {
  final RolandServiceAbstract? rolandService;
  final ValueNotifier<bool>? rolandConnected;
  final List<PanasonicCameraConfig> cameras;
  final ValueChanged<String> onResponse;

  const UnifiedControlWidget({
    super.key,
    required this.rolandService,
    required this.rolandConnected,
    required this.cameras,
    required this.onResponse,
  });

  @override
  State<UnifiedControlWidget> createState() => _UnifiedControlWidgetState();
}

class _UnifiedControlWidgetState extends State<UnifiedControlWidget> {
  static const int maxItems = 100;
  int _selectedDeviceIndex = 0; // 0 = Roland, 1+ = cameras
  final Map<int, Map<int, String>> _cameraPresetNames =
      {}; // cameraIndex -> {presetNum -> name}
  final Map<int, Map<int, bool>> _cameraPresetAvailability =
      {}; // cameraIndex -> {presetNum -> available}
  final Map<int, String> _macroNames = {};
  bool _loadingPresets = false;
  final List<VoidCallback> _cameraListeners = [];

  @override
  void initState() {
    super.initState();
    if (_selectedDeviceIndex == 0) {
      _fetchMacroNames();
    }
    widget.rolandConnected?.addListener(_onRolandConnectionChanged);
    _setupCameraListeners();
  }

  @override
  void dispose() {
    widget.rolandConnected?.removeListener(_onRolandConnectionChanged);
    _removeCameraListeners();
    super.dispose();
  }

  void _setupCameraListeners() {
    _cameraListeners.clear();
    for (int i = 0; i < widget.cameras.length; i++) {
      _cameraListeners.add(() => _onCameraConnectionChanged(i));
      widget.cameras[i].isConnected.addListener(_cameraListeners[i]);
    }
  }

  void _removeCameraListeners() {
    for (int i = 0; i < widget.cameras.length; i++) {
      widget.cameras[i].isConnected.removeListener(_cameraListeners[i]);
    }
    _cameraListeners.clear();
  }

  void _onRolandConnectionChanged() {
    if (widget.rolandConnected?.value == true && _selectedDeviceIndex == 0) {
      _fetchMacroNames();
    }
  }

  void _onCameraConnectionChanged(int cameraIndex) {
    if (widget.cameras[cameraIndex].isConnected.value &&
        _selectedDeviceIndex == cameraIndex + 1) {
      _fetchPresetData();
    }
  }

  Future<void> _executeRolandMacro(int macro) async {
    if (widget.rolandService == null || widget.rolandConnected?.value != true) {
      widget.onResponse('Roland not connected');
      return;
    }
    try {
      await widget.rolandService!.executeMacro(macro);
      widget.onResponse('Executed Roland macro $macro');
    } catch (e) {
      widget.onResponse('Error executing macro: $e');
    }
  }

  void _fetchMacroNames() {
    if (widget.rolandService == null || widget.rolandConnected?.value != true) {
      return;
    }
    final names = <int, String>{};
    for (int i = 1; i <= maxItems; i++) {
      names[i] = 'Macro $i';
    }
    if (mounted) {
      setState(() => _macroNames
        ..clear()
        ..addAll(names));
    }
  }

  Future<void> _executeCameraPreset(int preset) async {
    final cameraIndex = _selectedDeviceIndex - 1;
    if (cameraIndex < 0 || cameraIndex >= widget.cameras.length) {
      widget.onResponse('No camera selected');
      return;
    }
    final camera = widget.cameras[cameraIndex];
    if (camera.service == null) {
      widget.onResponse('Camera ${camera.name} not connected');
      return;
    }
    try {
      final response = await camera.service!.recallPreset(preset);
      widget.onResponse('Camera ${camera.name}: $response');
    } catch (e) {
      widget.onResponse('Error recalling preset: $e');
    }
  }

  Future<void> _fetchPresetData() async {
    final cameraIndex = _selectedDeviceIndex - 1;
    if (cameraIndex < 0 || cameraIndex >= widget.cameras.length) return;

    final camera = widget.cameras[cameraIndex];
    if (camera.service == null) {
      setState(() => _loadingPresets = false);
      return;
    }

    // Show all 100 presets immediately, trim after verification
    setState(() {
      _loadingPresets = true;
      _cameraPresetAvailability[cameraIndex] =
          {for (int i = 0; i < 100; i++) i: true};
    });

    try {
      // Verify which presets actually exist using 3 requests
      final statuses = await camera.service!
          .getAllPresetStatuses()
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _cameraPresetAvailability[cameraIndex] = statuses;
        });
      }

      final names = await PresetNameStore.loadAll(camera.ipController.text);
      if (mounted) {
        setState(() {
          _cameraPresetNames[cameraIndex] = names;
        });
      }
    } on TimeoutException {
      // Camera unreachable — keep all 100 shown
    } catch (e) {
      widget.onResponse('Error fetching preset data: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingPresets = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceOptions =
        ['Roland'] + widget.cameras.map((c) => c.name).toList();
    final isRolandSelected = _selectedDeviceIndex == 0;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unified Control',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ToggleButtons(
              isSelected: List.generate(
                  deviceOptions.length, (i) => i == _selectedDeviceIndex),
              onPressed: (index) {
                setState(() {
                  _selectedDeviceIndex = index;
                });
                if (index == 0) {
                  _fetchMacroNames();
                } else {
                  _fetchPresetData();
                }
              },
              children: deviceOptions
                  .map((name) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(name),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            if (isRolandSelected) ...[
              const Text('Select Macro:'),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 5,
                  childAspectRatio: 3.0,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: _macroNames.entries.map((entry) {
                    final macro = entry.key;
                    final name = entry.value;
                    return Tooltip(
                      message: name,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: widget.rolandConnected?.value == true
                            ? () => _executeRolandMacro(macro)
                            : null,
                        child: Text(name),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  const Text('Select Preset:'),
                  if (_loadingPresets) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final cameraIndex = _selectedDeviceIndex - 1;
                  final presetNames = _cameraPresetNames[cameraIndex] ?? {};
                  final presetAvailability =
                      _cameraPresetAvailability[cameraIndex] ?? {};
                  final availablePresets = presetAvailability.entries
                      .where((entry) => entry.value)
                      .toList();

                  if (availablePresets.isEmpty && !_loadingPresets) {
                    return const Expanded(
                      child: Center(
                        child: Text(
                          'No saved presets available',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  return Expanded(
                    child: GridView.count(
                      crossAxisCount: 5,
                      childAspectRatio: 3.0,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      children: availablePresets.map((entry) {
                        final presetIndex = entry.key; // 0-based for recall
                        final displayNum = entry.key + 1; // 1-based for display
                        final name = presetNames[presetIndex];
                        return Tooltip(
                          message: name ?? '$displayNum',
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () => _executeCameraPreset(presetIndex),
                            child: Text(name ?? '$displayNum'),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
