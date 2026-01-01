import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';

class PanasonicPresetsTab extends StatefulWidget {
  final List<PanasonicCameraConfig> panasonicCameras;
  final bool mockMode;
  final ValueChanged<String> onPanasonicResponse;
  final String panasonicResponse;

  const PanasonicPresetsTab({
    super.key,
    required this.panasonicCameras,
    required this.mockMode,
    required this.onPanasonicResponse,
    required this.panasonicResponse,
  });

  @override
  State<PanasonicPresetsTab> createState() => _PanasonicPresetsTabState();
}

class _PanasonicPresetsTabState extends State<PanasonicPresetsTab> {
  int _selectedCameraIndex = 0;
  int _selectedPresetNum = 1;
  String _presetName = '';
  String _presetSpeed = '100';

  @override
  void initState() {
    super.initState();
    for (var camera in widget.panasonicCameras) {
      camera.isConnected.addListener(_update);
      camera.isConnecting.addListener(_update);
      camera.connectionError.addListener(_update);
    }
  }

  @override
  void dispose() {
    for (var camera in widget.panasonicCameras) {
      camera.isConnected.removeListener(_update);
      camera.isConnecting.removeListener(_update);
      camera.connectionError.removeListener(_update);
    }
    super.dispose();
  }

  void _update() => setState(() {});

  PanasonicCameraConfig? get _selectedCamera =>
      widget.panasonicCameras.isEmpty ? null : widget.panasonicCameras[_selectedCameraIndex];

  bool get _panasonicConnected => _selectedCamera?.isConnected.value ?? false;

  Future<void> _recallPreset() async {
    if (widget.mockMode) {
      widget.onPanasonicResponse('Mock: Recalled preset $_selectedPresetNum on ${_selectedCamera?.name}');
      return;
    }
    if (_selectedCamera?.service == null) return;
    try {
      final response = await _selectedCamera!.service!.recallPreset(_selectedPresetNum);
      widget.onPanasonicResponse('Recall: $response');
    } catch (e) {
      widget.onPanasonicResponse('Error: ${e.toString()}');
    }
  }

  Future<void> _savePreset() async {
    if (widget.mockMode) {
      widget.onPanasonicResponse('Mock: Saved preset $_selectedPresetNum on ${_selectedCamera?.name}');
      return;
    }
    if (_selectedCamera?.service == null) return;
    try {
      final response = await _selectedCamera!.service!.savePreset(_selectedPresetNum);
      widget.onPanasonicResponse('Saved: $response');
    } catch (e) {
      widget.onPanasonicResponse('Error: ${e.toString()}');
    }
  }

  Future<void> _deletePreset() async {
    if (widget.mockMode) {
      widget.onPanasonicResponse('Mock: Deleted preset $_selectedPresetNum on ${_selectedCamera?.name}');
      return;
    }
    if (_selectedCamera?.service == null) return;
    try {
      final response = await _selectedCamera!.service!.deletePreset(_selectedPresetNum);
      widget.onPanasonicResponse('Deleted: $response');
    } catch (e) {
      widget.onPanasonicResponse('Error: ${e.toString()}');
    }
  }

  Future<void> _setPresetSpeed() async {
    if (widget.mockMode) {
      widget.onPanasonicResponse('Mock: Set preset speed to $_presetSpeed on ${_selectedCamera?.name}');
      return;
    }
    if (_selectedCamera?.service == null) return;
    try {
      final response = await _selectedCamera!.service!.setPresetSpeed(_presetSpeed);
      widget.onPanasonicResponse('Speed set: $response');
    } catch (e) {
      widget.onPanasonicResponse('Error: ${e.toString()}');
    }
  }

  Future<void> _savePresetName() async {
    if (widget.mockMode) {
      widget.onPanasonicResponse('Mock: Saved preset name "$_presetName" for preset $_selectedPresetNum on ${_selectedCamera?.name}');
      return;
    }
    if (_selectedCamera?.service == null) return;
    try {
      final response = await _selectedCamera!.service!.savePresetName(_selectedPresetNum, _presetName);
      widget.onPanasonicResponse('Name saved: $response');
    } catch (e) {
      widget.onPanasonicResponse('Error: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if any camera is connected
    final hasConnectedCamera = widget.panasonicCameras.any((c) => c.isConnected.value);

    if (!hasConnectedCamera) {
      return const Center(child: Text('Connect to a Panasonic camera first'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Panasonic Preset Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Camera Selection
            Row(
              children: [
                const Text('Select Camera: '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedCameraIndex,
                  items: List.generate(widget.panasonicCameras.length, (index) {
                    final camera = widget.panasonicCameras[index];
                    return DropdownMenuItem(
                      value: index,
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: camera.isConnected.value ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(camera.name),
                        ],
                      ),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCameraIndex = value);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!_panasonicConnected)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  'Selected camera "${_selectedCamera?.name}" is not connected.',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              )
            else ...[
            // Preset Selection
            Row(
              children: [
                const Text('Preset Number: '),
                SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final num = int.tryParse(value);
                      if (num != null && num >= 0 && num <= 99) {
                        setState(() => _selectedPresetNum = num);
                      }
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '$_selectedPresetNum',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Slider(
                    value: _selectedPresetNum.toDouble(),
                    min: 0,
                    max: 99,
                    divisions: 99,
                    label: '$_selectedPresetNum',
                    onChanged: (v) => setState(() => _selectedPresetNum = v.toInt()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preset Name
            const Text('Preset Name', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _presetName = v),
                    decoration: const InputDecoration(
                      labelText: 'Name (max 15 chars)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _savePresetName,
                  child: const Text('Save Name'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preset Speed
            const Text('Preset Speed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _presetSpeed = v),
                    controller: TextEditingController(text: _presetSpeed),
                    decoration: const InputDecoration(
                      labelText: 'Speed (001-999)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _setPresetSpeed,
                  child: const Text('Set Speed'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preset Actions
            const Text('Preset Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _recallPreset,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Recall'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _savePreset,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _deletePreset,
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Response Display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Response:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(widget.panasonicResponse.isEmpty ? 'Waiting for command...' : widget.panasonicResponse),
                ],
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }
}