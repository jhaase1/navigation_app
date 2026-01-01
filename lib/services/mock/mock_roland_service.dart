import '../abstract/roland_service_abstract.dart';

/// Mock implementation of Roland service for testing and development
class MockRolandService extends RolandServiceAbstract {
  @override
  Future<void> cut() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> auto({String? input, int? time}) async {
    await Future.delayed(const Duration(milliseconds: 100));
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
  }

  @override
  Future<void> setPinPPgm(String pinp, bool on) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> getPinPPgm(String pinp) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> setPinPPvw(String pinp, bool on) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> getPinPPvw(String pinp) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> disconnect() async {
  }
}