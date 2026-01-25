/// Abstract base class for Roland service implementations
abstract class RolandServiceAbstract {
  /// Performs a cut transition
  Future<void> cut();

  /// Performs an auto transition
  Future<void> auto({String? input, int? time});

  /// Sets the program input
  Future<void> setProgram(String input);

  /// Sets the preview input
  Future<void> setPreview(String input);

  /// Executes a macro
  Future<void> executeMacro(int macro);

  /// Sets the PinP source
  Future<void> setPinPSource(String pinp, String source);

  /// Gets the PinP source
  Future<void> getPinPSource(String pinp);

  /// Sets the PinP position
  Future<void> setPinPPosition(String pinp, int h, int v);

  /// Gets the PinP position
  Future<void> getPinPPosition(String pinp);

  /// Sets the PinP size
  Future<void> setPinPSize(String pinp, int size);

  /// Gets the PinP size
  Future<void> getPinPSize(String pinp);

  /// Sets PinP on program
  Future<void> setPinPPgm(String pinp, bool on);

  /// Gets PinP on program status
  Future<void> getPinPPgm(String pinp);

  /// Sets PinP on preview
  Future<void> setPinPPvw(String pinp, bool on);

  /// Gets PinP on preview status
  Future<void> getPinPPvw(String pinp);

  /// Gets a macro name
  Future<String> getMacroName(int macro);

  /// Checks if a macro exists
  Future<bool> macroExists(int macro);

  /// Disconnects from the device
  Future<void> disconnect();

  /// Disposes the service and closes streams
  Future<void> dispose();
}
