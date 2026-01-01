import 'dart:async';
import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../services/abstract/roland_service_abstract.dart';

class UnifiedControlWidget extends StatefulWidget {
  final RolandServiceAbstract? rolandService;
  final List<PanasonicCameraConfig> cameras;
  final ValueChanged<String> onResponse;

  const UnifiedControlWidget({
    super.key,
    required this.rolandService,
    required this.cameras,
    required this.onResponse,
  });

  @override
  State<UnifiedControlWidget> createState() => _UnifiedControlWidgetState();
}

class _UnifiedControlWidgetState extends State<UnifiedControlWidget> {
  static const int maxItems = 100;
  int _selectedDeviceIndex = 0; // 0 = Roland, 1+ = cameras
  final Map<int, String> _presetNames = {};
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
    if (widget.rolandService == null) {
      widget.onResponse('Roland service not available');
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
    if (widget.rolandService == null) return;
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

  Future<void> _fetchPresetNames() async {
    final cameraIndex = _selectedDeviceIndex - 1;
    if (cameraIndex < 0 || cameraIndex >= widget.cameras.length) return;

    final camera = widget.cameras[cameraIndex];
    if (camera.service == null) return;

    await _fetchNames(
      fetcher: (i) => camera.service!.getPresetName(i),
      namesMap: _presetNames,
      setLoading: (bool value) => setState(() => _loadingPresets = value),
    );
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
                  _fetchPresetNames();
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
                        onPressed: () => _executeRolandMacro(macro),
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
              Expanded(
                child: GridView.count(
                  crossAxisCount: 5,
                  childAspectRatio: 3.0,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: List.generate(maxItems, (i) {
                    final preset = i + 1;
                    final name = _presetNames[preset];
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
                        onPressed: () => _executeCameraPreset(preset),
                        child: Text(name ?? '$preset'),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}