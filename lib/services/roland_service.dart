import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:developer' as dev;

/// Custom exception for Roland service errors.
class RolandException implements Exception {
  final String message;
  RolandException(this.message);

  @override
  String toString() => 'RolandException: $message';
}

/// Enums for camera directions.
enum PanDirection { left, stop, right }
enum TiltDirection { down, stop, up }
enum ZoomDirection { wideFast, wideSlow, stop, teleSlow, teleFast }
enum FocusDirection { near, stop, far }

/// Response models for parsed responses.
class FaderLevelResponse {
  final int level;
  FaderLevelResponse(this.level);
}

class ProgramResponse {
  final String source;
  final String? input;
  ProgramResponse(this.source, this.input);
}

class PinPPositionResponse {
  final int h;
  final int v;
  PinPPositionResponse(this.h, this.v);
}

class VersionResponse {
  final String model;
  final String version;
  VersionResponse(this.model, this.version);
}

class PanTiltSpeedResponse {
  final int speed;
  PanTiltSpeedResponse(this.speed);
}

class PresetResponse {
  final String preset;
  PresetResponse(this.preset);
}

/// Service for communicating with Roland V-160HD device.
/// 
/// This service provides methods to control various aspects of the Roland V-160HD
/// video mixer via TCP socket commands. It supports VIDEO, PinP, CONTROL, SYSTEM,
/// CAMERA, AUDIO, METER, and DSK commands as per the official documentation.
/// 
/// Example usage:
/// ```dart
/// final service = RolandService(host: '192.168.1.100');
/// await service.connect();
/// await service.setProgram(0); // Set program to INPUT1
/// await service.setFaderLevel(1024); // Set fader to mid-level
/// service.disconnect();
/// ```
class RolandService {
  static const int defaultPort = 8023;
  static const int maxFaderLevel = 2047;
  static const int minFaderLevel = 0;
  static const int maxInputIndex = 19; // INPUT1-20
  static const int minInputIndex = 0;
  static const int maxPinPIndex = 3; // PinP1-4
  static const int minPinPIndex = 0;
  static const int maxCameraIndex = 15; // CAMERA1-16
  static const int minCameraIndex = 0;
  static const int maxMacro = 100;
  static const int minMacro = 1;
  static const int maxPreset = 10;
  static const int minPreset = 1;
  static const int maxPanTiltSpeed = 24;
  static const int minPanTiltSpeed = 1;

  // Additional constants for new commands
  static const int maxAudioLevel = 100; // 10.0 dB
  static const int minAudioLevel = -800; // -80.0 dB
  static const int maxTransitionTime = 40; // 4.0 sec
  static const int minTransitionTime = 0;
  static const int maxDskLevel = 255;
  static const int minDskLevel = 0;
  static const int maxAuxBus = 2; // AUX1-3 (0-2)
  static const int minAuxBus = 0;
  static const int maxSplit = 1; // SPLIT1-2 (0-1)
  static const int minSplit = 0;
  static const int maxMemory = 30;
  static const int minMemory = 1;

  final String host;
  final int port;
  Socket? _socket;
  final StreamController<dynamic> _responseController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get responseStream => _responseController.stream;
  final Queue<Completer<void>> _ackCompleters = Queue<Completer<void>>();
  final Queue<String> _commandQueue = Queue<String>();
  bool _isProcessing = false;
  bool _isConnected = false;

  /// Creates a new RolandService instance.
  RolandService({required this.host, this.port = defaultPort});

  /// Helper to build commands.
  String _buildCommand(String cmd, [List<String>? params]) {
    if (params == null || params.isEmpty) return '$cmd;';
    return '$cmd:${params.join(',')};';
  }

  /// Connects to the Roland device.
  Future<void> connect() async {
    try {
      dev.log('Connecting to $host:$port');
      _socket = await Socket.connect(host, port).timeout(const Duration(seconds: 10));
      _isConnected = true;
      _socket!.listen(
        (data) => _handleResponse(utf8.decode(data)),
        onError: (error) {
          dev.log('Socket error: $error');
          _isConnected = false;
          _responseController.addError(RolandException('Socket error: $error'));
          _responseController.close();
        },
        onDone: () {
          dev.log('Socket closed');
          _isConnected = false;
          disconnect();
        },
      );
      dev.log('Connected successfully');
    } catch (e) {
      dev.log('Connection failed: $e');
      throw RolandException('Connection failed: $e');
    }
  }

  /// Disconnects from the Roland device.
  void disconnect() {
    dev.log('Disconnecting');
    _socket?.close();
    _socket = null;
    _isConnected = false;
    _responseController.close();
    // Complete any pending acks with error
    while (_ackCompleters.isNotEmpty) {
      _ackCompleters.removeFirst().completeError(RolandException('Disconnected'));
    }
  }

  Future<void> _sendCommand(String command) async {
    if (!_isConnected) throw RolandException('Not connected');
    final completer = Completer<void>();
    _ackCompleters.add(completer);
    _commandQueue.add(command);
    await _processQueue();
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      throw RolandException('Command timeout: $command');
    });
  }

  Future<void> _processQueue() async {
    if (_isProcessing || !_isConnected) return;
    _isProcessing = true;
    while (_commandQueue.isNotEmpty && _isConnected) {
      String cmd = _commandQueue.removeFirst();
      dev.log('Sending command: $cmd');
      _socket!.write(cmd);
      await _socket!.flush().timeout(const Duration(seconds: 5));
    }
    _isProcessing = false;
  }

  void _handleResponse(String response) {
    final trimmed = response.trim();
    dev.log('Received response: $trimmed');
    if (trimmed.endsWith(';ACK;') || trimmed == 'ACK;') {
      // Complete the next pending ACK
      if (_ackCompleters.isNotEmpty) {
        _ackCompleters.removeFirst().complete();
      }
      // Parse the response
      final parsed = _parseResponse(trimmed);
      if (parsed != null) {
        _responseController.add(parsed);
      }
    } else if (trimmed.contains('NACK') || trimmed.contains('ERROR')) {
      // Handle errors
      if (_ackCompleters.isNotEmpty) {
        _ackCompleters.removeFirst().completeError(RolandException('Command failed: $trimmed'));
      }
    } else {
      // Raw response for unparsed
      _responseController.add(trimmed);
    }
  }

  dynamic _parseResponse(String response) {
    // Remove ;ACK;
    final clean = response.replaceAll(';ACK;', '').replaceAll('ACK;', '');
    final parts = clean.split(':');
    if (parts.length < 2) return null;
    final cmd = parts[0];
    final params = parts[1].split(',');
    switch (cmd) {
      case 'VFL':
        return FaderLevelResponse(int.parse(params[0]));
      case 'PGM':
        return ProgramResponse(params[0], params.length > 1 ? params[1] : null);
      case 'PIP':
        return PinPPositionResponse(int.parse(params[1]), int.parse(params[2]));
      case 'VER':
        return VersionResponse(params[0], params[1]);
      case 'CAMPTS':
        return PanTiltSpeedResponse(int.parse(params[1]));
      case 'CAMPR':
        return PresetResponse(params[1]);
      // Add more as needed
      default:
        return null;
    }
  }

  // VIDEO Commands
  /// Performs a cut transition.
  Future<void> cut() => _sendCommand(_buildCommand('CUT'));

  /// Performs an auto transition.
  Future<void> auto() => _sendCommand(_buildCommand('ATO'));

  /// Sets the program input (0-19 for INPUT1-20).
  Future<void> setProgram(int inputIndex) {
    if (inputIndex < minInputIndex || inputIndex > maxInputIndex) {
      throw ArgumentError('inputIndex must be between $minInputIndex and $maxInputIndex');
    }
    return _sendCommand(_buildCommand('PGM', ['INPUT${inputIndex + 1}']));
  }

  /// Sets the preview input (0-19 for INPUT1-20).
  Future<void> setPreview(int inputIndex) {
    if (inputIndex < minInputIndex || inputIndex > maxInputIndex) {
      throw ArgumentError('inputIndex must be between $minInputIndex and $maxInputIndex');
    }
    return _sendCommand(_buildCommand('PST', ['INPUT${inputIndex + 1}']));
  }

  /// Sets the video fader level (0-2047).
  Future<void> setFaderLevel(int level) {
    if (level < minFaderLevel || level > maxFaderLevel) {
      throw ArgumentError('level must be between $minFaderLevel and $maxFaderLevel');
    }
    return _sendCommand(_buildCommand('VFL', [level.toString()]));
  }

  /// Gets the current video fader level.
  Future<void> getFaderLevel() => _sendCommand(_buildCommand('QVFL'));

  /// Gets the current program input.
  Future<void> getProgram() => _sendCommand(_buildCommand('QPGM'));

  /// Gets the current preview input.
  Future<void> getPreview() => _sendCommand(_buildCommand('QPST'));

  /// Sets the transition type.
  Future<void> setTransitionType(String type) => _sendCommand(_buildCommand('TRS', [type]));

  /// Gets the transition type.
  Future<void> getTransitionType() => _sendCommand(_buildCommand('QTRS'));

  /// Sets the transition time (0-40 for 0.0-4.0 sec).
  Future<void> setTransitionTime(String type, int time) {
    if (time < minTransitionTime || time > maxTransitionTime) {
      throw ArgumentError('time must be between $minTransitionTime and $maxTransitionTime');
    }
    return _sendCommand(_buildCommand('TIM', [type, time.toString()]));
  }

  /// Gets the transition time.
  Future<void> getTransitionTime(String type) => _sendCommand(_buildCommand('QTIM', [type]));

  // PinP Commands
  /// Sets the PinP source (0-3 for PinP1-4).
  Future<void> setPinPSource(int pinpIndex, String source) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('PIS', ['PinP${pinpIndex + 1}', source]));
  }

  /// Gets the PinP source (0-3 for PinP1-4).
  Future<void> getPinPSource(int pinpIndex) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('QPIS', ['PinP${pinpIndex + 1}']));
  }

  /// Sets the PinP position (0-3 for PinP1-4, h/v -1000 to 1000).
  Future<void> setPinPPosition(int pinpIndex, int h, int v) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    if (h < -1000 || h > 1000 || v < -1000 || v > 1000) {
      throw ArgumentError('h and v must be between -1000 and 1000');
    }
    return _sendCommand(_buildCommand('PIP', ['PinP${pinpIndex + 1}', h.toString(), v.toString()]));
  }

  /// Gets the PinP position (0-3 for PinP1-4).
  Future<void> getPinPPosition(int pinpIndex) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('QPIP', ['PinP${pinpIndex + 1}']));
  }

  /// Sets PinP on program (0-3 for PinP1-4).
  Future<void> setPinPPgm(int pinpIndex, bool on) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('PPS', ['PinP${pinpIndex + 1}', on ? 'ON' : 'OFF']));
  }

  /// Gets PinP on program status (0-3 for PinP1-4).
  Future<void> getPinPPgm(int pinpIndex) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('QPPS', ['PinP${pinpIndex + 1}']));
  }

  /// Sets PinP on preview (0-3 for PinP1-4).
  Future<void> setPinPPvw(int pinpIndex, bool on) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('PPW', ['PinP${pinpIndex + 1}', on ? 'ON' : 'OFF']));
  }

  /// Gets PinP on preview status (0-3 for PinP1-4).
  Future<void> getPinPPvw(int pinpIndex) {
    if (pinpIndex < minPinPIndex || pinpIndex > maxPinPIndex) {
      throw ArgumentError('pinpIndex must be between $minPinPIndex and $maxPinPIndex');
    }
    return _sendCommand(_buildCommand('QPPW', ['PinP${pinpIndex + 1}']));
  }

  // CONTROL Commands
  /// Executes a macro (1-100).
  Future<void> executeMacro(int macro) {
    if (macro < minMacro || macro > maxMacro) {
      throw ArgumentError('macro must be between $minMacro and $maxMacro');
    }
    return _sendCommand(_buildCommand('MCREX', [macro.toString()]));
  }

  // SYSTEM Commands
  /// Gets the device version.
  Future<void> getVersion() => _sendCommand(_buildCommand('VER'));

  // CAMERA Commands
  /// Sets pan and tilt for camera (0-15 for CAMERA1-16).
  Future<void> setPanTilt(int cameraIndex, PanDirection pan, TiltDirection tilt) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    final panStr = pan.name.toUpperCase();
    final tiltStr = tilt.name.toUpperCase();
    return _sendCommand(_buildCommand('CAMPT', ['CAMERA${cameraIndex + 1}', panStr, tiltStr]));
  }

  /// Sets pan/tilt speed for camera (0-15 for CAMERA1-16, 1-24).
  Future<void> setPanTiltSpeed(int cameraIndex, int speed) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    if (speed < minPanTiltSpeed || speed > maxPanTiltSpeed) {
      throw ArgumentError('speed must be between $minPanTiltSpeed and $maxPanTiltSpeed');
    }
    return _sendCommand(_buildCommand('CAMPTS', ['CAMERA${cameraIndex + 1}', speed.toString()]));
  }

  /// Gets pan/tilt speed for camera (0-15 for CAMERA1-16).
  Future<void> getPanTiltSpeed(int cameraIndex) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('QCAMPTS', ['CAMERA${cameraIndex + 1}']));
  }

  /// Sets zoom for camera (0-15 for CAMERA1-16).
  Future<void> setZoom(int cameraIndex, ZoomDirection direction) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    final dirStr = direction.name.replaceAll('tele', 'TELE_').replaceAll('wide', 'WIDE_').toUpperCase();
    return _sendCommand(_buildCommand('CAMZM', ['CAMERA${cameraIndex + 1}', dirStr]));
  }

  /// Resets zoom for camera (0-15 for CAMERA1-16).
  Future<void> resetZoom(int cameraIndex) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('CAMZMR', ['CAMERA${cameraIndex + 1}']));
  }

  /// Sets focus for camera (0-15 for CAMERA1-16).
  Future<void> setFocus(int cameraIndex, FocusDirection direction) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    final dirStr = direction.name.toUpperCase();
    return _sendCommand(_buildCommand('CAMFC', ['CAMERA${cameraIndex + 1}', dirStr]));
  }

  /// Sets auto focus for camera (0-15 for CAMERA1-16).
  Future<void> setAutoFocus(int cameraIndex, bool on) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('CAMAFC', ['CAMERA${cameraIndex + 1}', on ? 'ON' : 'OFF']));
  }

  /// Gets auto focus status for camera (0-15 for CAMERA1-16).
  Future<void> getAutoFocus(int cameraIndex) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('QCAMAFC', ['CAMERA${cameraIndex + 1}']));
  }

  /// Sets auto exposure for camera (0-15 for CAMERA1-16).
  Future<void> setAutoExposure(int cameraIndex, bool on) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('CAMAEP', ['CAMERA${cameraIndex + 1}', on ? 'ON' : 'OFF']));
  }

  /// Gets auto exposure status for camera (0-15 for CAMERA1-16).
  Future<void> getAutoExposure(int cameraIndex) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('QCAMAEP', ['CAMERA${cameraIndex + 1}']));
  }

  /// Recalls preset for camera (0-15 for CAMERA1-16, 1-10).
  Future<void> recallPreset(int cameraIndex, int preset) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    if (preset < minPreset || preset > maxPreset) {
      throw ArgumentError('preset must be between $minPreset and $maxPreset');
    }
    return _sendCommand(_buildCommand('CAMPR', ['CAMERA${cameraIndex + 1}', 'PRESET$preset']));
  }

  /// Gets current preset for camera (0-15 for CAMERA1-16).
  Future<void> getCurrentPreset(int cameraIndex) {
    if (cameraIndex < minCameraIndex || cameraIndex > maxCameraIndex) {
      throw ArgumentError('cameraIndex must be between $minCameraIndex and $maxCameraIndex');
    }
    return _sendCommand(_buildCommand('QCAMPR', ['CAMERA${cameraIndex + 1}']));
  }

  // AUDIO Commands
  /// Sets audio input level.
  Future<void> setAudioInputLevel(String input, int level) {
    if (level < minAudioLevel || level > maxAudioLevel) {
      throw ArgumentError('level must be between $minAudioLevel and $maxAudioLevel');
    }
    return _sendCommand(_buildCommand('IAL', [input, level.toString()]));
  }

  /// Gets audio input level.
  Future<void> getAudioInputLevel(String input) {
    return _sendCommand(_buildCommand('QIAL', [input]));
  }

  /// Sets audio output level.
  Future<void> setAudioOutputLevel(String output, int level) {
    if (level < minAudioLevel || level > maxAudioLevel) {
      throw ArgumentError('level must be between $minAudioLevel and $maxAudioLevel');
    }
    return _sendCommand(_buildCommand('OAL', [output, level.toString()]));
  }

  /// Gets audio output level.
  Future<void> getAudioOutputLevel(String output) {
    return _sendCommand(_buildCommand('QOAL', [output]));
  }

  // METER Commands
  /// Sets auto-transmit for audio level meter.
  Future<void> setMeterAutoTransmit(bool on) {
    return _sendCommand(_buildCommand('MTRSW', [on ? 'ON' : 'OFF']));
  }

  /// Gets audio level meter.
  Future<void> getAudioLevelMeter(String mode) {
    return _sendCommand(_buildCommand('MTRLV', [mode]));
  }

  // DSK Commands
  /// Sets DSK fill source.
  Future<void> setDskSource(int dskIndex, String source) {
    if (dskIndex < 0 || dskIndex > 1) {
      throw ArgumentError('dskIndex must be 0 or 1');
    }
    return _sendCommand(_buildCommand('DSS', ['DSK${dskIndex + 1}', source]));
  }

  /// Gets DSK fill source.
  Future<void> getDskSource(int dskIndex) {
    if (dskIndex < 0 || dskIndex > 1) {
      throw ArgumentError('dskIndex must be 0 or 1');
    }
    return _sendCommand(_buildCommand('QDSS', ['DSK${dskIndex + 1}']));
  }

  /// Sets DSK level.
  Future<void> setDskLevel(int dskIndex, int level) {
    if (dskIndex < 0 || dskIndex > 1) {
      throw ArgumentError('dskIndex must be 0 or 1');
    }
    if (level < minDskLevel || level > maxDskLevel) {
      throw ArgumentError('level must be between $minDskLevel and $maxDskLevel');
    }
    return _sendCommand(_buildCommand('KYL', ['DSK${dskIndex + 1}', level.toString()]));
  }

  /// Gets DSK level.
  Future<void> getDskLevel(int dskIndex) {
    if (dskIndex < 0 || dskIndex > 1) {
      throw ArgumentError('dskIndex must be 0 or 1');
    }
    return _sendCommand(_buildCommand('QKYL', ['DSK${dskIndex + 1}']));
  }

  // CONTROL Commands
  /// Recalls scene memory.
  Future<void> recallMemory(int memory) {
    if (memory < minMemory || memory > maxMemory) {
      throw ArgumentError('memory must be between $minMemory and $maxMemory');
    }
    return _sendCommand(_buildCommand('MEM', ['MEMORY$memory']));
  }

  /// Gets selected scene memory.
  Future<void> getMemory() {
    return _sendCommand(_buildCommand('QMEM'));
  }
}