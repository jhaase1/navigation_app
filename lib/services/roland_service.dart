import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';

class RolandService {
  final String host;
  final int port;
  Socket? _socket;
  final StreamController<String> _responseController = StreamController<String>.broadcast();
  Stream<String> get responseStream => _responseController.stream;
  final Queue<String> _commandQueue = Queue<String>();
  bool _isProcessing = false;

  RolandService({required this.host, this.port = 8023});

  Future<void> connect() async {
    try {
      _socket = await Socket.connect(host, port);
      _socket!.listen(
        (data) => _handleResponse(utf8.decode(data)),
        onError: (error) => _responseController.addError('Socket error: $error'),
        onDone: () => disconnect(),
      );
    } catch (e) {
      throw Exception('Connection failed: $e');
    }
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
    _responseController.close();
  }

  Future<void> _sendCommand(String command) async {
    _commandQueue.add(command);
    await _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    while (_commandQueue.isNotEmpty) {
      String cmd = _commandQueue.removeFirst();
      if (_socket == null) throw Exception('Not connected');
      _socket!.write('$cmd\n');
      await _socket!.flush();
    }
    _isProcessing = false;
  }

  void _handleResponse(String response) {
    // Basic parsing: emit raw response
    _responseController.add(response.trim());
  }

  // VIDEO Commands
  Future<void> cut() => _sendCommand('CUT;');

  Future<void> auto() => _sendCommand('ATO;');

  Future<void> setProgram(int inputIndex) => _sendCommand('PGM:INPUT${inputIndex + 1};');

  Future<void> setPreview(int inputIndex) => _sendCommand('PST:INPUT${inputIndex + 1};');

  Future<void> setFaderLevel(int level) => _sendCommand('VFL:$level;');

  Future<void> getFaderLevel() => _sendCommand('QVFL;');

  Future<void> getProgram() => _sendCommand('QPGM;');

  Future<void> getPreview() => _sendCommand('QPST;');

  // PinP Commands
  Future<void> setPinPSource(int pinpIndex, String source) => _sendCommand('PIS:PinP$pinpIndex,$source;');

  Future<void> getPinPSource(int pinpIndex) => _sendCommand('QPIS:PinP$pinpIndex;');

  Future<void> setPinPPosition(int pinpIndex, int h, int v) => _sendCommand('PIP:PinP$pinpIndex,$h,$v;');

  Future<void> getPinPPosition(int pinpIndex) => _sendCommand('QPIP:PinP$pinpIndex;');

  Future<void> setPinPPgm(int pinpIndex, bool on) => _sendCommand('PPS:PinP$pinpIndex,${on ? 'ON' : 'OFF'};');

  Future<void> getPinPPgm(int pinpIndex) => _sendCommand('QPPS:PinP$pinpIndex;');

  Future<void> setPinPPvw(int pinpIndex, bool on) => _sendCommand('PPW:PinP$pinpIndex,${on ? 'ON' : 'OFF'};');

  Future<void> getPinPPvw(int pinpIndex) => _sendCommand('QPPW:PinP$pinpIndex;');

  // CONTROL Commands
  Future<void> executeMacro(int macro) => _sendCommand('MCREX:$macro;');

  // SYSTEM Commands
  Future<void> getVersion() => _sendCommand('VER;');

  // CAMERA Commands
  Future<void> setPanTilt(int cameraIndex, String pan, String tilt) => _sendCommand('CAMPT:CAMERA$cameraIndex,$pan,$tilt;');

  Future<void> setPanTiltSpeed(int cameraIndex, int speed) => _sendCommand('CAMPTS:CAMERA$cameraIndex,$speed;');

  Future<void> getPanTiltSpeed(int cameraIndex) => _sendCommand('QCAMPTS:CAMERA$cameraIndex;');

  Future<void> setZoom(int cameraIndex, String direction) => _sendCommand('CAMZM:CAMERA$cameraIndex,$direction;');

  Future<void> resetZoom(int cameraIndex) => _sendCommand('CAMZMR:CAMERA$cameraIndex;');

  Future<void> setFocus(int cameraIndex, String direction) => _sendCommand('CAMFC:CAMERA$cameraIndex,$direction;');

  Future<void> setAutoFocus(int cameraIndex, bool on) => _sendCommand('CAMAFC:CAMERA$cameraIndex,${on ? 'ON' : 'OFF'};');

  Future<void> getAutoFocus(int cameraIndex) => _sendCommand('QCAMAFC:CAMERA$cameraIndex;');

  Future<void> setAutoExposure(int cameraIndex, bool on) => _sendCommand('CAMAEP:CAMERA$cameraIndex,${on ? 'ON' : 'OFF'};');

  Future<void> getAutoExposure(int cameraIndex) => _sendCommand('QCAMAEP:CAMERA$cameraIndex;');

  Future<void> recallPreset(int cameraIndex, int preset) => _sendCommand('CAMPR:CAMERA$cameraIndex,PRESET$preset;');

  Future<void> getCurrentPreset(int cameraIndex) => _sendCommand('QCAMPR:CAMERA$cameraIndex;');
}