import 'dart:async';
import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/abstract/roland_service_abstract.dart';

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
  final Map<int, Map<int, String>> _cameraPresetNames = {}; // cameraIndex -> {presetNum -> name}
  final Map<int, Map<int, bool>> _cameraPresetAvailability = {}; // cameraIndex -> {presetNum -> available}
  final Map<int, String> _macroNames = {};
  bool _loadingPresets = false;
  bool _loadingMacros = false;
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
    if (widget.cameras[cameraIndex].isConnected.value && _selectedDeviceIndex == cameraIndex + 1) {
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



  Future<void> _fetchMacroNames() async {
    if (widget.rolandService == null || widget.rolandConnected?.value != true) return;
    setState(() => _loadingMacros = true);
    _macroNames.clear();
    const int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final futures = List.generate(maxItems, (i) => widget.rolandService!.macroExists(i + 1));
        final existsList = await Future.wait(futures);
        for (int i = 0; i < existsList.length; i++) {
          if (existsList[i]) {
            _macroNames[i + 1] = 'Macro ${i + 1}';
          }
        }
        if (mounted) {
          setState(() {
            _loadingMacros = false;
          });
        }
        return; // Success, exit
      } catch (e) {
        String errorMessage;
        if (e is TimeoutException) {
          errorMessage = 'Network timeout while checking macro existence (attempt $attempt/$maxRetries)';
        } else if (e.toString().contains('connection') || e.toString().contains('socket')) {
          errorMessage = 'Connection error while checking macro existence (attempt $attempt/$maxRetries)';
        } else {
          errorMessage = 'Device error while checking macro existence: $e (attempt $attempt/$maxRetries)';
        }
        if (attempt == maxRetries) {
          widget.onResponse(errorMessage);
        } else {
          await Future.delayed(const Duration(seconds: 1)); // Wait before retry
        }
      }
    }
    if (mounted) {
      setState(() => _loadingMacros = false);
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

    setState(() => _loadingPresets = true);

    try {
      // Fetch preset availability first
      final availability = await camera.service!.getAllPresetStatuses();

      // Fetch preset names only for available presets
      final presetNames = <int, String>{};
      const int maxRetries = 3;
      for (final entry in availability.entries) {
        if (!entry.value) continue; // Skip unavailable presets
        final presetIndex = entry.key;
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            final name = await camera.service!.getPresetName(presetIndex);
            presetNames[presetIndex] = name;
            break; // Success, exit retry loop
          } catch (e) {
            String errorMessage;
            if (e is TimeoutException) {
              errorMessage = 'Network timeout while fetching preset name for $presetIndex (attempt $attempt/$maxRetries)';
            } else if (e.toString().contains('connection') || e.toString().contains('socket')) {
              errorMessage = 'Connection error while fetching preset name for $presetIndex (attempt $attempt/$maxRetries)';
            } else {
              errorMessage = 'Device error while fetching preset name for $presetIndex: $e (attempt $attempt/$maxRetries)';
            }
            if (attempt == maxRetries) {
              widget.onResponse(errorMessage);
            } else {
              await Future.delayed(const Duration(seconds: 1)); // Wait before retry
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _cameraPresetNames[cameraIndex] = presetNames;
          _cameraPresetAvailability[cameraIndex] = Map.from(availability);
        });
      }
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
    final deviceOptions = ['Roland'] + widget.cameras.map((c) => c.name).toList();
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
              isSelected: List.generate(deviceOptions.length, (i) => i == _selectedDeviceIndex),
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
              children: deviceOptions.map((name) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(name),
              )).toList(),
            ),
            const SizedBox(height: 16),
            if (isRolandSelected) ...[
              Row(
                children: [
                  const Text('Select Macro:'),
                  if (_loadingMacros) ...[
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
              Expanded(
                child: GridView.count(
                  crossAxisCount: 5,
                  childAspectRatio: 3.0,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: _macroNames.entries
                      .map((entry) {
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
                            onPressed: widget.rolandConnected?.value == true ? () => _executeRolandMacro(macro) : null,
                            child: Text(name),
                          ),
                        );
                      })
                      .toList(),
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
                  final camera = widget.cameras[cameraIndex];
                  final presetNames = _cameraPresetNames[cameraIndex] ?? {};
                  final presetAvailability = _cameraPresetAvailability[cameraIndex] ?? {};
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
                      children: availablePresets
                          .map((entry) {
                            final preset = entry.key + 1; // Convert 0-based to 1-based for display
                            final name = presetNames[preset];
                            return Tooltip(
                              message: name ?? '$preset',
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                onPressed: camera.isConnected.value ? () => _executeCameraPreset(preset) : null,
                                child: Text(name ?? '$preset'),
                              ),
                            );
                          })
                          .toList(),
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