import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers who is filling each participant role, per service, and which
/// service the Service tab last had open, so the day's volunteer lineup
/// survives tab switches, operator changes and the OS killing the app.
///
/// This is day-of operating state, not configuration: it is deliberately
/// outside [RestoreJournal]'s keys and writes without going through
/// ConfigMutationNotifier, so assigning a reader never marks the backup
/// dirty, never travels to another machine, and is never rolled back by an
/// import.
class LineupStore {
  /// Prefix for per-service lineups: `service_lineup_<serviceId>` holds a
  /// JSON object of participantId → personId.
  static const keyPrefix = 'service_lineup_';

  /// The service the Service tab last had selected. Deliberately not under
  /// [keyPrefix], so no service id can collide with it.
  static const selectedServiceKey = 'service_tab_selected_service';

  static String _key(String serviceId) => '$keyPrefix$serviceId';

  /// Returns participantId → personId for [serviceId]; empty if none saved.
  static Future<Map<String, String>> load(String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(serviceId));
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v as String));
  }

  /// Replaces the lineup for [serviceId]. Unassigned (null) roles are
  /// dropped, and an empty lineup removes the key entirely.
  static Future<void> save(
      String serviceId, Map<String, String?> assignments) async {
    final prefs = await SharedPreferences.getInstance();
    final assigned = {
      for (final e in assignments.entries)
        if (e.value != null) e.key: e.value!,
    };
    if (assigned.isEmpty) {
      await prefs.remove(_key(serviceId));
    } else {
      await prefs.setString(_key(serviceId), jsonEncode(assigned));
    }
  }

  static Future<String?> loadSelectedServiceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(selectedServiceKey);
  }

  static Future<void> saveSelectedServiceId(String? serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (serviceId == null) {
      await prefs.remove(selectedServiceKey);
    } else {
      await prefs.setString(selectedServiceKey, serviceId);
    }
  }
}
