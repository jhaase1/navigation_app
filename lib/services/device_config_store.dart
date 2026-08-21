import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CameraEntry {
  final String name;
  final String ip;
  const CameraEntry({required this.name, required this.ip});
  Map<String, dynamic> toJson() => {'name': name, 'ip': ip};
  factory CameraEntry.fromJson(Map<String, dynamic> j) =>
      CameraEntry(name: j['name'] as String, ip: j['ip'] as String);
}

class DeviceConfigStore {
  static const _rolandIpKey = 'roland_ip';
  static const _camerasKey = 'panasonic_cameras';

  /// Set via `flutter run --dart-define=MOCK_RIG=true`
  /// (tools/mock_server/dev.sh does this automatically), so a dev build
  /// defaults to tools/mock_server/run.py's addresses instead of the real
  /// church network, regardless of whatever real-device IPs a previous,
  /// non-mock run of this same build saved to SharedPreferences.
  static const bool mockRig = bool.fromEnvironment('MOCK_RIG');

  static String rolandIpFor({bool mock = mockRig}) =>
      mock ? '127.0.0.1' : '10.0.1.20';

  static List<CameraEntry> camerasFor({bool mock = mockRig}) => mock
      ? const [
          CameraEntry(name: 'Camera 1', ip: '127.0.0.2'),
          CameraEntry(name: 'Camera 2', ip: '127.0.0.3'),
          CameraEntry(name: 'Camera 3', ip: '127.0.0.4'),
        ]
      : const [
          CameraEntry(name: 'Camera 1', ip: '10.0.1.10'),
          CameraEntry(name: 'Camera 2', ip: '10.0.1.11'),
          CameraEntry(name: 'Camera 3', ip: '10.0.1.12'),
        ];

  static String get defaultRolandIp => rolandIpFor();
  static List<CameraEntry> get defaultCameras => camerasFor();

  static Future<String> loadRolandIp({bool mock = mockRig}) async {
    if (mock) return rolandIpFor(mock: true);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rolandIpKey) ?? rolandIpFor(mock: false);
  }

  static Future<List<CameraEntry>> loadCameras({bool mock = mockRig}) async {
    if (mock) return camerasFor(mock: true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_camerasKey);
    if (raw == null) return camerasFor(mock: false);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CameraEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(String rolandIp, List<CameraEntry> cameras) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_rolandIpKey, rolandIp),
      prefs.setString(
          _camerasKey, jsonEncode(cameras.map((c) => c.toJson()).toList())),
    ]);
  }
}
