import 'package:flutter/material.dart';
import 'services/roland_service.dart';
import 'services/panasonic_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roland V-60HD Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RolandControlPage(
        panasonicIp: '10.0.1.21',
      ),
    );
  }
}

class RolandControlPage extends StatefulWidget {
  final String panasonicIp;
  const RolandControlPage({super.key, this.panasonicIp = '10.0.1.10'});

  @override
  State<RolandControlPage> createState() => _RolandControlPageState();
}

class _RolandControlPageState extends State<RolandControlPage> {
  // Roland
  final TextEditingController _rolandIpController = TextEditingController(text: '10.0.1.20');
  RolandService? _rolandService;
  bool _rolandConnected = false;
  bool _rolandConnecting = false;
  String _rolandResponse = '';
  String _rolandConnectionError = '';

  // Panasonic
  final TextEditingController _panasonicIpController = TextEditingController(text: '10.0.1.10');
  PanasonicService? _panasonicService;
  bool _panasonicConnected = false;
  bool _panasonicConnecting = false;
  String _panasonicResponse = '';
  String _panasonicConnectionError = '';
  int _selectedPresetNum = 1;
  String _presetName = '';
  String _presetSpeed = '100';

  @override
  void initState() {
    super.initState();
  }

  // PinP state
  int _selectedPinP = 1;
  String _pinpSource = 'HDMI1';
  double _pinpH = 0.0;
  double _pinpV = 0.0;
  bool _pinpPgm = false;
  bool _pinpPvw = false;

  @override
  void dispose() {
    _rolandService?.disconnect();
    _rolandIpController.dispose();
    _panasonicIpController.dispose();
    super.dispose();
  }

  // PinP methods
  void _setPinPSource() => _rolandService?.setPinPSource('PinP${_selectedPinP + 1}', _pinpSource);
  void _getPinPSource() => _rolandService?.getPinPSource('PinP${_selectedPinP + 1}');
  void _setPinPPosition() => _rolandService?.setPinPPosition('PinP${_selectedPinP + 1}', _pinpH.toInt(), _pinpV.toInt());
  void _getPinPPosition() => _rolandService?.getPinPPosition('PinP${_selectedPinP + 1}');
  void _setPinPPgm() => _rolandService?.setPinPPgm('PinP${_selectedPinP + 1}', _pinpPgm);
  void _getPinPPgm() => _rolandService?.getPinPPgm('PinP${_selectedPinP + 1}');
  void _setPinPPvw() => _rolandService?.setPinPPvw('PinP${_selectedPinP + 1}', _pinpPvw);
  void _getPinPPvw() => _rolandService?.getPinPPvw('PinP${_selectedPinP + 1}');

  // Panasonic Preset Methods
  Future<void> _recallPreset() async {
    if (_panasonicService == null) return;
    try {
      final response = await _panasonicService!.recallPreset(_selectedPresetNum);
      setState(() => _panasonicResponse = 'Recall: $response');
    } catch (e) {
      setState(() => _panasonicResponse = 'Error: ${e.toString()}');
    }
  }

  Future<void> _savePreset() async {
    if (_panasonicService == null) return;
    try {
      final response = await _panasonicService!.savePreset(_selectedPresetNum);
      setState(() => _panasonicResponse = 'Saved: $response');
    } catch (e) {
      setState(() => _panasonicResponse = 'Error: ${e.toString()}');
    }
  }

  Future<void> _deletePreset() async {
    if (_panasonicService == null) return;
    try {
      final response = await _panasonicService!.deletePreset(_selectedPresetNum);
      setState(() => _panasonicResponse = 'Deleted: $response');
    } catch (e) {
      setState(() => _panasonicResponse = 'Error: ${e.toString()}');
    }
  }

  Future<void> _setPresetSpeed() async {
    if (_panasonicService == null) return;
    try {
      final response = await _panasonicService!.setPresetSpeed(_presetSpeed);
      setState(() => _panasonicResponse = 'Speed set: $response');
    } catch (e) {
      setState(() => _panasonicResponse = 'Error: ${e.toString()}');
    }
  }

  Future<void> _savePresetName() async {
    if (_panasonicService == null) return;
    try {
      final response = await _panasonicService!.savePresetName(_selectedPresetNum, _presetName);
      setState(() => _panasonicResponse = 'Name saved: $response');
    } catch (e) {
      setState(() => _panasonicResponse = 'Error: ${e.toString()}');
    }
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

  Future<void> _connectPanasonic() async {
    if (_panasonicConnected) {
      setState(() {
        _panasonicConnected = false;
        _panasonicService = null;
        _panasonicConnectionError = '';
      });
      return;
    }

    setState(() {
      _panasonicConnecting = true;
      _panasonicConnectionError = '';
    });

    try {
      final service = PanasonicService(ipAddress: _panasonicIpController.text);
      setState(() {
        _panasonicService = service;
        _panasonicConnected = true;
        _panasonicConnecting = false;
        _panasonicConnectionError = '';
      });
    } catch (e) {
      setState(() {
        _panasonicConnecting = false;
        _panasonicConnectionError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roland V-160HD Control'),

      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Roland Connection
                  const Text('Roland V-160HD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rolandIpController,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_rolandConnected && !_rolandConnecting,
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: _rolandConnecting ? null : _connectRoland,
                        style: FilledButton.styleFrom(
                          backgroundColor: _rolandConnected ? Colors.red : null,
                        ),
                        child: _rolandConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_rolandConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                  if (_rolandConnectionError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Connection failed. Check IP address and try again.',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Panasonic Connection
                  const Text('Panasonic Camera', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _panasonicIpController,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !_panasonicConnected && !_panasonicConnecting,
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: _panasonicConnecting ? null : _connectPanasonic,
                        style: FilledButton.styleFrom(
                          backgroundColor: _panasonicConnected ? Colors.red : null,
                        ),
                        child: _panasonicConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_panasonicConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                  if (_panasonicConnectionError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Connection failed. Check IP address and try again.',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                  _buildBasicTab(),
                  _buildPinPTab(),
                  _buildPanasonicPresetsTab(),
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

  Widget _buildBasicTab() {
    if (!_rolandConnected) return const Center(child: Text('Connect to Roland device first'));
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Transitions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _rolandService?.cut(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('CUT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _rolandService?.auto(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('AUTO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          const Text('Program Select (PGM)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ActionChip(
                label: Text('Input ${index + 1}'),
                onPressed: () => _rolandService?.setProgram('INPUT${index + 1}'),
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('Preview Select (PST)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ActionChip(
                label: Text('Input ${index + 1}'),
                backgroundColor: Colors.green.shade50,
                onPressed: () => _rolandService?.setPreview('INPUT${index + 1}'),
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('Macros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ElevatedButton(
                onPressed: () => _rolandService?.executeMacro(index + 1),
                child: Text('Macro ${index + 1}'),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPinPTab() {
    if (!_rolandConnected) return const Center(child: Text('Connect to Roland device first'));
    final sources = ['HDMI1', 'HDMI2', 'HDMI3', 'HDMI4', 'HDMI5', 'HDMI6', 'HDMI7', 'HDMI8', 'SDI1', 'SDI2', 'SDI3', 'SDI4', 'SDI5', 'SDI6', 'SDI7', 'SDI8', 'STILL1', 'STILL2', 'STILL3', 'STILL4', 'STILL5', 'STILL6', 'STILL7', 'STILL8', 'STILL9', 'STILL10', 'STILL11', 'STILL12', 'STILL13', 'STILL14', 'STILL15', 'STILL16', 'INPUT1', 'INPUT2', 'INPUT3', 'INPUT4', 'INPUT5', 'INPUT6', 'INPUT7', 'INPUT8', 'INPUT9', 'INPUT10', 'INPUT11', 'INPUT12', 'INPUT13', 'INPUT14', 'INPUT15', 'INPUT16', 'INPUT17', 'INPUT18', 'INPUT19', 'INPUT20'];
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PinP Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('PinP: '),
                DropdownButton<int>(
                  value: _selectedPinP,
                  items: List.generate(4, (i) => DropdownMenuItem(value: i+1, child: Text('PinP${i+1}'))),
                  onChanged: (v) => setState(() => _selectedPinP = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Source: '),
                DropdownButton<String>(
                  value: _pinpSource,
                  items: sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _pinpSource = v!),
                ),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setPinPSource, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPSource, child: const Text('Get')),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Position'),
            Slider(
              value: _pinpH,
              min: -1000,
              max: 1000,
              label: 'H: ${_pinpH.toInt()}',
              onChanged: (v) => setState(() => _pinpH = v),
            ),
            Slider(
              value: _pinpV,
              min: -1000,
              max: 1000,
              label: 'V: ${_pinpV.toInt()}',
              onChanged: (v) => setState(() => _pinpV = v),
            ),
            Row(
              children: [
                ElevatedButton(onPressed: _setPinPPosition, child: const Text('Set Position')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPPosition, child: const Text('Get Position')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('PGM: '),
                Switch(value: _pinpPgm, onChanged: (v) => setState(() => _pinpPgm = v)),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setPinPPgm, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPPgm, child: const Text('Get')),
              ],
            ),
            Row(
              children: [
                const Text('PVW: '),
                Switch(value: _pinpPvw, onChanged: (v) => setState(() => _pinpPvw = v)),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _setPinPPvw, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _getPinPPvw, child: const Text('Get')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanasonicPresetsTab() {
    if (!_panasonicConnected) {
      return const Center(child: Text('Connect to Panasonic camera first'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Panasonic Preset Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
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
                  Text(_panasonicResponse.isEmpty ? 'Waiting for command...' : _panasonicResponse),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
