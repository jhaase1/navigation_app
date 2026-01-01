/// Abstract base class for Panasonic service implementations
abstract class PanasonicServiceAbstract {
  /// Recalls a preset
  Future<String> recallPreset(int preset);

  /// Saves a preset
  Future<String> savePreset(int preset);

  /// Deletes a preset
  Future<String> deletePreset(int preset);

  /// Sets preset speed
  Future<String> setPresetSpeed(String speed);

  /// Saves preset name
  Future<String> savePresetName(int preset, String name);
}