import 'package:flutter/material.dart';

class PinPTab extends StatefulWidget {
  final bool rolandConnected;
  final bool mockMode;
  final ValueChanged<String> onRolandResponse;

  const PinPTab({
    super.key,
    required this.rolandConnected,
    required this.mockMode,
    required this.onRolandResponse,
  });

  @override
  State<PinPTab> createState() => _PinPTabState();
}

class _PinPTabState extends State<PinPTab> {
  int _selectedPinP = 1;
  String _pinpSource = 'HDMI1';
  double _pinpH = 0.0;
  double _pinpV = 0.0;
  bool _pinpPgm = false;
  bool _pinpPvw = false;

  void _setPinPSource() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: Set PinP${_selectedPinP + 1} source to $_pinpSource');
    } else {
      // TODO: Implement real PinP source set
    }
  }

  void _getPinPSource() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: PinP${_selectedPinP + 1} source = $_pinpSource');
    } else {
      // TODO: Implement real PinP source get
    }
  }

  void _setPinPPosition() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: Set PinP${_selectedPinP + 1} position H=${_pinpH.toInt()} V=${_pinpV.toInt()}');
    } else {
      // TODO: Implement real PinP position set
    }
  }

  void _getPinPPosition() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: PinP${_selectedPinP + 1} position H=${_pinpH.toInt()} V=${_pinpV.toInt()}');
    } else {
      // TODO: Implement real PinP position get
    }
  }

  void _setPinPPgm() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: Set PinP${_selectedPinP + 1} PGM = $_pinpPgm');
    } else {
      // TODO: Implement real PinP PGM set
    }
  }

  void _getPinPPgm() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: PinP${_selectedPinP + 1} PGM = $_pinpPgm');
    } else {
      // TODO: Implement real PinP PGM get
    }
  }

  void _setPinPPvw() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: Set PinP${_selectedPinP + 1} PVW = $_pinpPvw');
    } else {
      // TODO: Implement real PinP PVW set
    }
  }

  void _getPinPPvw() {
    if (widget.mockMode) {
      widget.onRolandResponse('Mock: PinP${_selectedPinP + 1} PVW = $_pinpPvw');
    } else {
      // TODO: Implement real PinP PVW get
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.rolandConnected) return const Center(child: Text('Connect to Roland device first'));
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
}