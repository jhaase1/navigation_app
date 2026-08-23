import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_fault.dart';

/// The machine's name, as the conflict dialog will say it back.
///
/// Getting the DEFAULT right matters more than it looks, because a bad
/// default is worse than none: it looks like a real answer. There is no
/// reliable automatic name on iPad — `Platform.localHostname` returns
/// `"localhost"` since iOS 17, and `UIDevice.current.name` returns a generic
/// `"iPad"` since iOS 16 unless Apple grants an entitlement they gate behind
/// an approval process. So the rule is: propose a candidate, reject it if it
/// is worthless, and otherwise ask once.
class DeviceLabel {
  static const String key = 'backup_device_label';

  /// Names that are not names. Compared lowercase, with a trailing `.local`
  /// stripped first — macOS hostnames arrive as `Studio-Mac-mini.local`.
  static const Set<String> _worthless = {
    'localhost',
    'ipad',
    'iphone',
    'ipod',
    'ipod touch',
    'mac',
    'macbook',
    'macbook pro',
    'macbook air',
    'mac mini',
    'imac',
    'unknown',
  };

  static String _normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.endsWith('.local')) s = s.substring(0, s.length - '.local'.length);
    return s.replaceAll('-', ' ').replaceAll('_', ' ');
  }

  /// Whether two labels name the same machine, under the same normalisation
  /// the collision check uses.
  static bool isSameName(String? a, String? b) =>
      a != null && b != null && _normalize(a) == _normalize(b);

  /// The proposed default, or null when there is nothing worth proposing.
  ///
  /// [namesInUse] are the labels on recent revisions in the store. A candidate
  /// already carried by another machine is rejected too — that is what catches
  /// two Macs sharing a hostname, and two iPads that would both call
  /// themselves the same thing.
  static String? sanitize(
    String? candidate, {
    required Iterable<String> namesInUse,
  }) {
    if (candidate == null) return null;
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return null;
    final normal = _normalize(trimmed);
    if (normal.isEmpty) return null;
    if (_worthless.contains(normal)) return null;
    if (namesInUse.any((n) => _normalize(n) == normal)) return null;
    return trimmed.endsWith('.local')
        ? trimmed.substring(0, trimmed.length - '.local'.length)
        : trimmed;
  }

  /// The machine's own idea of its name. Nothing on iOS: both routes there
  /// return a constant, and a constant is worse than a blank field.
  static String? hostCandidate() =>
      Platform.isIOS ? null : Platform.localHostname;

  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(key);

  static Future<void> save(String label) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, label.trim())) {
      await prefs.reload();
      throw StateError('Could not persist the device name');
    }
  }

  /// For `BackupService.deviceLabel`. Throws rather than inventing one:
  /// an unlabelled machine is honest, a machine labelled `localhost` is not.
  static Future<String> require() async {
    final saved = await load();
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    throw AppFault.backup(
      BackupFailureKind.deviceUnnamed,
      'Name this machine before its first backup, so the other machine can '
      'tell whose settings are whose.',
      operation: 'push',
    );
  }
}
