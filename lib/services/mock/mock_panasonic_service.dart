import '../abstract/panasonic_service_abstract.dart';

/// Mock implementation of Panasonic service for testing and development
class MockPanasonicService extends PanasonicServiceAbstract {
  @override
  Future<String> recallPreset(int preset) async {
    // await Future.delayed(const Duration(milliseconds: 200));
    return 'Mock: Recalled preset $preset';
  }

  @override
  Future<String> savePreset(int preset) async {
    // await Future.delayed(const Duration(milliseconds: 200));
    return 'Mock: Saved preset $preset';
  }

  @override
  Future<String> deletePreset(int preset) async {
    // await Future.delayed(const Duration(milliseconds: 200));
    return 'Mock: Deleted preset $preset';
  }

  @override
  Future<String> setPresetSpeed(String speed) async {
    // await Future.delayed(const Duration(milliseconds: 100));
    return 'Mock: Set preset speed to $speed';
  }

  @override
  Future<String> savePresetName(int preset, String name) async {
    // await Future.delayed(const Duration(milliseconds: 150));
    return 'Mock: Saved preset name "$name" for preset $preset';
  }

  @override
  Future<String> getPresetName(int preset) async {
    // await Future.delayed(const Duration(milliseconds: 100));
    return 'Preset $preset';
  }

  @override
  Future<String> getPresetEntries(int range) async {
    // await Future.delayed(const Duration(milliseconds: 100));
    // Return a mock 40-bit hex string (10 characters)
    // For testing, return different patterns for different ranges
    switch (range) {
      case 0:
        return 'AAAAAAAAAA'; // Mock: alternating pattern
      case 1:
        return '5555555555'; // Mock: alternating pattern
      case 2:
        return 'FFFFF00000'; // Mock: first 20 presets saved
      default:
        throw ArgumentError('Range must be 0-2');
    }
  }

  @override
  Future<Map<int, bool>> getAllPresetStatuses() async {
    // await Future.delayed(const Duration(milliseconds: 300));
    // Mock implementation: return a map with some presets saved
    final Map<int, bool> statuses = {};
    for (int i = 0; i < 100; i++) {
      // Mock: presets 0-9, 20-29, 50-59, 80-89 are saved
      statuses[i] = (i < 10) ||
          (i >= 20 && i < 30) ||
          (i >= 50 && i < 60) ||
          (i >= 80 && i < 90);
    }
    return statuses;
  }
}
