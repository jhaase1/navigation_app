import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:navigation_app/services/config_file_picker.dart';

final class _PickedFile extends PlatformFile {
  _PickedFile(this.uri, this._bytes);
  @override
  final Uri uri;
  final Uint8List _bytes;
  @override
  String get name => uri.pathSegments.last;
  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);
  @override
  int? lengthSync() => _bytes.length;
  @override
  Future<int?> length() async => _bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => _bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

class _FakePlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  Uri? saveResult;
  List<PlatformFile> pickResult = const [];

  String? savedName;
  Uint8List? savedBytes;
  String? savedMime;
  FileType? pickedType;
  List<String>? pickedExtensions;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    savedMime = mimeType;
    return saveResult;
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickedType = type;
    pickedExtensions = allowedExtensions;
    return pickResult;
  }
}

void main() {
  late _FakePlatform platform;
  const picker = NativeConfigFilePicker();

  setUp(() {
    platform = _FakePlatform();
    FilePickerPlatform.instance = platform;
  });

  group('save', () {
    test('hands the native dialog the name, JSON type and UTF-8 contents',
        () async {
      platform.saveResult = Uri.file('/Users/op/Desktop/nav_config.json');

      await picker.save('nav_config.json', '{"é":1}');

      expect(platform.savedName, 'nav_config.json');
      expect(platform.savedMime, 'application/json');
      expect(utf8.decode(platform.savedBytes!), '{"é":1}');
    });

    test('reports a file location as a plain path', () async {
      final uri = Uri.file('/Users/op/Desktop/nav_config.json');
      platform.saveResult = uri;

      expect(await picker.save('nav_config.json', '{}'), uri.toFilePath());
    });

    test('reports a non-file location as its URI', () async {
      platform.saveResult =
          Uri.parse('content://com.android.providers/document/42');

      expect(await picker.save('nav_config.json', '{}'),
          'content://com.android.providers/document/42');
    });

    test('returns null when the operator cancels', () async {
      platform.saveResult = null;

      expect(await picker.save('nav_config.json', '{}'), isNull);
    });
  });

  group('open', () {
    test('only offers JSON files', () async {
      await picker.open();

      expect(platform.pickedType, FileType.custom);
      expect(platform.pickedExtensions, ['json']);
    });

    test('returns the chosen file decoded as UTF-8', () async {
      platform.pickResult = [
        _PickedFile(Uri.parse('content://docs/7'),
            Uint8List.fromList(utf8.encode('{"é":1}'))),
      ];

      expect(await picker.open(), '{"é":1}');
    });

    test('returns null when the operator cancels', () async {
      platform.pickResult = const [];

      expect(await picker.open(), isNull);
    });
  });
}
