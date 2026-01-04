import 'dart:async';
import '../abstract/roland_service_abstract.dart';
import '../roland_service.dart';

/// Mock implementation of Roland service for testing and development
class MockRolandService extends RolandServiceAbstract {
  final StreamController<dynamic> _responseController = StreamController<dynamic>.broadcast();
  
  Stream<dynamic> get responseStream => _responseController.stream;
  @override
  Future<void> cut() async {
    // Simulate network delay
    // await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> auto({String? input, int? time}) async {
    // await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> setProgram(String input) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> setPreview(String input) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> executeMacro(int macro) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> setPinPSource(String pinp, String source) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> getPinPSource(String pinp) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> setPinPPosition(String pinp, int h, int v) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> getPinPPosition(String pinp) async {
    await Future.delayed(const Duration(milliseconds: 50));
    // Emit mock response with some default position values
    _responseController.add(PinPPositionResponse(pinp, 100, 200));
  }

  @override
  Future<void> setPinPPgm(String pinp, bool on) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> getPinPPgm(String pinp) async {
    await Future.delayed(const Duration(milliseconds: 50));
    // Emit mock response
    _responseController.add(PinPProgramResponse(pinp, 'ON'));
  }

  @override
  Future<void> setPinPPvw(String pinp, bool on) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> getPinPPvw(String pinp) async {
    await Future.delayed(const Duration(milliseconds: 50));
    // Emit mock response
    _responseController.add(PinPPreviewResponse(pinp, 'ON'));
  }

  @override
  Future<String> getMacroName(int macro) async {
    // Remove delay for tests to avoid timer issues
    // await Future.delayed(const Duration(milliseconds: 50));
    return 'Macro $macro';
  }

  @override
  Future<bool> macroExists(int macro) async {
    // For mock, assume macros 1-10 exist
    return macro >= 1 && macro <= 10;
  }

  @override
  Future<void> disconnect() async {
    _responseController.close();
  }
}
