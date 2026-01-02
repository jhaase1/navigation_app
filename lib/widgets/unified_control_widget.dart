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

  @override
  void initState() {
    super.initState();
    if (_selectedDeviceIndex == 0) {
      _fetchMacroNames();
    }
  }

  @override
  void dispose() {
    super.dispose();
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

  Future<void> _fetchNames({
    required Future<String> Function(int) fetcher,
    required Map<int, String> namesMap,
    required void Function(bool) setLoading,
  }) async {
    setLoading(true);
    namesMap.clear();
    const int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final futures = List.generate(maxItems, (i) => fetcher(i));
        final names = await Future.wait(futures);
        if (mounted) {
          setState(() {
            for (int i = 0; i < names.length; i++) {
              namesMap[i + 1] = names[i];
            }
          });
        }
        return; // Success, exit
      } catch (e) {
        String errorMessage;
        if (e is TimeoutException) {
          errorMessage = 'Network timeout while fetching names (attempt $attempt/$maxRetries)';
        } else if (e.toString().contains('connection') || e.toString().contains('socket')) {
          errorMessage = 'Connection error while fetching names (attempt $attempt/$maxRetries)';
        } else {
          errorMessage = 'Device error while fetching names: $e (attempt $attempt/$maxRetries)';
        }
        if (attempt == maxRetries) {
          widget.onResponse(errorMessage);
        } else {
          await Future.delayed(const Duration(seconds: 1)); // Wait before retry
        }
      }
    }
    if (mounted) {
      setLoading(false);
    }
  }

  Future<void> _fetchMacroNames() async {
    if (widget.rolandService == null || widget.rolandConnected?.value != true) return;
    await _fetchNames(
      fetcher: (i) => widget.rolandService!.getMacroName(i + 1),
      namesMap: _macroNames,
      setLoading: (bool value) => setState(() => _loadingMacros = value),
    );
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
    if (camera.service == null) return;

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
                  children: List.generate(maxItems, (i) {
                    final macro = i + 1;
                    final name = _macroNames[macro];
                    return Tooltip(
                      message: name ?? '$macro',
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
                        child: Text(name ?? '$macro'),
                      ),
                    );
                  }),
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