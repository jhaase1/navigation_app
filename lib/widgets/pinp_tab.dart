import 'package:flutter/material.dart';
import 'dart:async';
import '../services/abstract/roland_service_abstract.dart';
import '../services/roland_service.dart';

class PinPTab extends StatefulWidget {
  final ValueNotifier<bool> rolandConnected;
  final ValueChanged<String> onRolandResponse;
  final RolandServiceAbstract? rolandService;

  const PinPTab({
    super.key,
    required this.rolandConnected,
    required this.onRolandResponse,
    required this.rolandService,
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

  StreamSubscription<dynamic>? _responseSubscription;

  @override
  void initState() {
    super.initState();
    widget.rolandConnected.addListener(_update);
    _responseSubscription = (widget.rolandService is RolandService)
        ? (widget.rolandService as RolandService)
            .responseStream
            .listen((response) {
            if (response is PinPProgramResponse &&
                response.pinp == 'PinP$_selectedPinP') {
              setState(() => _pinpPgm = response.status == 'ON');
            } else if (response is PinPPreviewResponse &&
                response.pinp == 'PinP$_selectedPinP') {
              setState(() => _pinpPvw = response.status == 'ON');
            }
          })
        : null;
    _startPolling();
  }

  @override
  void dispose() {
    widget.rolandConnected.removeListener(_update);
    _responseSubscription?.cancel();
    _stopPolling();
    super.dispose();
  }

  Timer? _pollTimer;

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.rolandConnected.value && widget.rolandService != null) {
        _getPinPPgm();
        _getPinPPvw();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
  }

  void _update() => setState(() {});

  void _setPinPSource() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!
            .setPinPSource('PinP$_selectedPinP', _pinpSource);
        widget
            .onRolandResponse('Set PinP$_selectedPinP source to $_pinpSource');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _getPinPSource() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.getPinPSource('PinP$_selectedPinP');
        widget.onRolandResponse('Requested PinP$_selectedPinP source');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _setPinPPosition() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.setPinPPosition(
            'PinP$_selectedPinP', _pinpH.toInt(), _pinpV.toInt());
        widget.onRolandResponse(
            'Set PinP$_selectedPinP position H=${_pinpH.toInt()} V=${_pinpV.toInt()}');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _getPinPPosition() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.getPinPPosition('PinP$_selectedPinP');
        widget.onRolandResponse('Requested PinP$_selectedPinP position');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _setPinPPgm() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.setPinPPgm('PinP$_selectedPinP', _pinpPgm);
        widget.onRolandResponse('Set PinP$_selectedPinP PGM = $_pinpPgm');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _getPinPPgm() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.getPinPPgm('PinP$_selectedPinP');
        widget.onRolandResponse('Requested PinP$_selectedPinP PGM');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _setPinPPvw() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.setPinPPvw('PinP$_selectedPinP', _pinpPvw);
        widget.onRolandResponse('Set PinP$_selectedPinP PVW = $_pinpPvw');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  void _getPinPPvw() async {
    if (widget.rolandService != null) {
      try {
        await widget.rolandService!.getPinPPvw('PinP$_selectedPinP');
        widget.onRolandResponse('Requested PinP$_selectedPinP PVW');
      } catch (e) {
        widget.onRolandResponse('Error: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.rolandConnected.value)
    {
      return const Center(child: Text('Connect to Roland device first'));
    }
    final sources = [
      'HDMI1',
      'HDMI2',
      'HDMI3',
      'HDMI4',
      'HDMI5',
      'HDMI6',
      'HDMI7',
      'HDMI8',
      'SDI1',
      'SDI2',
      'SDI3',
      'SDI4',
      'SDI5',
      'SDI6',
      'SDI7',
      'SDI8',
      'STILL1',
      'STILL2',
      'STILL3',
      'STILL4',
      'STILL5',
      'STILL6',
      'STILL7',
      'STILL8',
      'STILL9',
      'STILL10',
      'STILL11',
      'STILL12',
      'STILL13',
      'STILL14',
      'STILL15',
      'STILL16',
      'INPUT1',
      'INPUT2',
      'INPUT3',
      'INPUT4',
      'INPUT5',
      'INPUT6',
      'INPUT7',
      'INPUT8',
      'INPUT9',
      'INPUT10',
      'INPUT11',
      'INPUT12',
      'INPUT13',
      'INPUT14',
      'INPUT15',
      'INPUT16',
      'INPUT17',
      'INPUT18',
      'INPUT19',
      'INPUT20'
    ];
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PinP Control',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('PinP: '),
                DropdownButton<int>(
                  value: _selectedPinP,
                  items: List.generate(
                      4,
                      (i) => DropdownMenuItem(
                          value: i + 1, child: Text('PinP${i + 1}'))),
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
                  items: sources
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _pinpSource = v!),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                    onPressed: _setPinPSource, child: const Text('Set')),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _getPinPSource, child: const Text('Get')),
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
                ElevatedButton(
                    onPressed: _setPinPPosition,
                    child: const Text('Set Position')),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _getPinPPosition,
                    child: const Text('Get Position')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('PGM: '),
                Switch(
                    value: _pinpPgm,
                    onChanged: (v) {
                      setState(() => _pinpPgm = v);
                      _setPinPPgm();
                    }),
              ],
            ),
            Row(
              children: [
                const Text('PVW: '),
                Switch(
                    value: _pinpPvw,
                    onChanged: (v) {
                      setState(() => _pinpPvw = v);
                      _setPinPPvw();
                    }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
