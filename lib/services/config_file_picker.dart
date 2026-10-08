import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Where configuration exports go and imports come from.
///
/// The operator always chooses the location through the platform's own
/// dialog, which inside the macOS App Sandbox is also what grants the app
/// access to a folder they can find in Finder — a typed `$HOME/Documents`
/// path resolves inside `~/Library/Containers/...` instead.
abstract class ConfigFilePicker {
  /// Asks where to save, writes [contents] there and returns a location to
  /// show the operator, or null if they cancelled.
  Future<String?> save(String suggestedName, String contents);

  /// Asks for a configuration file and returns its contents, or null if
  /// they cancelled.
  Future<String?> open();
}

class NativeConfigFilePicker implements ConfigFilePicker {
  const NativeConfigFilePicker();

  @override
  Future<String?> save(String suggestedName, String contents) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export Configuration',
      fileName: suggestedName,
      bytes: utf8.encode(contents),
      mimeType: 'application/json',
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }

  @override
  Future<String?> open() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Import Configuration',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (files.isEmpty) return null;
    // Read through the plugin rather than by path: on Android and iOS the
    // pick can be a content URI with no file path at all.
    return utf8.decode(await files.first.readAsBytes());
  }
}
