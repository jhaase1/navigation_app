/// Abstract base class for Panasonic service implementations
abstract class PanasonicServiceAbstract {
  /// Asks the camera something cheap. Completes if it answered; throws if
  /// it did not. Implementations without a real camera always answer.
  Future<void> probe() async {}

  /// Lets go of the camera for good: commands still waiting fail, and
  /// nothing more is sent. Implementations without a real camera hold
  /// nothing to let go of.
  Future<void> dispose() async {}

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

  /// Gets preset name
  Future<String> getPresetName(int preset);

  /// Checks which presets have been saved
  /// [range] The range selector (0-2, each representing 40 presets)
  /// Returns a 40-bit hex string indicating which presets are saved
  Future<String> getPresetEntries(int range);

  /// Gets the status of all presets (0-99) indicating which ones are saved
  /// Returns a Map where the key is the preset number (0-99) and the value is true
  /// if the preset is saved, false otherwise
  Future<Map<int, bool>> getAllPresetStatuses();
}
