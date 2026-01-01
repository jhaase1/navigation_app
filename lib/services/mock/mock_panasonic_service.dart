import '../abstract/panasonic_service_abstract.dart';

/// Mock implementation of Panasonic service for testing and development
class MockPanasonicService extends PanasonicServiceAbstract {
  @override
  Future<String> recallPreset(int preset) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return 'Mock: Recalled preset $preset';
  }

  @override
  Future<String> savePreset(int preset) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return 'Mock: Saved preset $preset';
  }

  @override
  Future<String> deletePreset(int preset) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return 'Mock: Deleted preset $preset';
  }

  @override
  Future<String> setPresetSpeed(String speed) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return 'Mock: Set preset speed to $speed';
  }

  @override
  Future<String> savePresetName(int preset, String name) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return 'Mock: Saved preset name "$name" for preset $preset';
  }
}