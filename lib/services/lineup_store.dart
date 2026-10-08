import 'dart:convert';

import 'package:flutter/foundation.dart';
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
///
/// It also expires. Services run several times a week, so a lineup that
/// simply persisted would walk Saturday's readers into Sunday's Mass and aim
/// their cues at the wrong people. Everything here lives [leaseLength] past
/// its last save or [renew]; [LineupLease] renews it while the app is on
/// screen. It also never outlives the local day it was saved, since a Mac
/// left on with the app open stays on screen and would renew it forever.
class LineupStore {
  /// Prefix for per-service lineups: `service_lineup_<serviceId>` holds a
  /// JSON object of participantId → personId.
  static const keyPrefix = 'service_lineup_';

  /// The service the Service tab last had selected. Deliberately not under
  /// [keyPrefix], so no service id can collide with it.
  static const selectedServiceKey = 'service_tab_selected_service';

  /// When the stored lineup lapses, as epoch milliseconds. Deliberately not
  /// under [keyPrefix].
  static const leaseKey = 'lineup_lease_expires_at';

  static const leaseLength = Duration(minutes: 20);

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Bumped when [renew] finds a stored lineup lapsed and deletes it, so a
  /// Service tab still on screen can drop its own copy. Only renewal
  /// announces, so the tab renews before every change it saves: a save that
  /// found the lapse itself would re-store the stale roles still on screen.
  static final ValueNotifier<int> expirations = ValueNotifier(0);

  static String _key(String serviceId) => '$keyPrefix$serviceId';

  // Every operation below checks the lease and changes what is stored
  // without awaiting in between. SharedPreferences updates its in-memory
  // copy synchronously, so no other operation — the renewal timer, say — can
  // slip between the check and the change and, for instance, delete a lease
  // a save had just taken. Only writing to disk is awaited.

  /// Whether a lease running until [until] (epoch milliseconds) still
  /// holds. It lapses [leaseLength] after it was last taken, and at the
  /// first local midnight after that: the time it was taken is [until] less
  /// [leaseLength], and it must be today. Renewal is the only way to extend
  /// it and needs a lease that still holds, so no chain of renewals carries
  /// a lineup out of the day it was saved.
  static bool _holds(int until) {
    final at = now().toLocal();
    if (at.millisecondsSinceEpoch > until) return false;
    final taken = DateTime.fromMillisecondsSinceEpoch(until)
        .subtract(leaseLength);
    return taken.year == at.year &&
        taken.month == at.month &&
        taken.day == at.day;
  }

  /// Deletes everything stored here if the lease has lapsed, or was never
  /// taken, and returns the pending writes; null if the lease still holds.
  static List<Future<bool>>? _expireIfDue(SharedPreferences prefs,
      {bool announce = false}) {
    final until = prefs.getInt(leaseKey);
    if (until != null && _holds(until)) return null;
    final stale = prefs
        .getKeys()
        .where((k) => k.startsWith(keyPrefix) || k == selectedServiceKey)
        .toList();
    final writes = [
      for (final k in stale) prefs.remove(k),
      prefs.remove(leaseKey),
    ];
    if (announce && stale.isNotEmpty) expirations.value++;
    return writes;
  }

  static Future<bool> _extend(SharedPreferences prefs) =>
      prefs.setInt(leaseKey, now().add(leaseLength).millisecondsSinceEpoch);

  /// Keeps a live lineup for another [leaseLength]. Returns false — and
  /// leaves it gone — if it had already lapsed: renewing never revives.
  static Future<bool> renew() async {
    final prefs = await SharedPreferences.getInstance();
    final expired = _expireIfDue(prefs, announce: true);
    if (expired != null) {
      await Future.wait(expired);
      return false;
    }
    await _extend(prefs);
    return true;
  }

  /// Returns participantId → personId for [serviceId]; empty if none saved.
  static Future<Map<String, String>> load(String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final expired = _expireIfDue(prefs);
    if (expired != null) {
      await Future.wait(expired);
      return {};
    }
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
    await Future.wait([
      ...?_expireIfDue(prefs),
      if (assigned.isEmpty)
        prefs.remove(_key(serviceId))
      else
        prefs.setString(_key(serviceId), jsonEncode(assigned)),
      _extend(prefs),
    ]);
  }

  static Future<String?> loadSelectedServiceId() async {
    final prefs = await SharedPreferences.getInstance();
    final expired = _expireIfDue(prefs);
    if (expired != null) {
      await Future.wait(expired);
      return null;
    }
    return prefs.getString(selectedServiceKey);
  }

  static Future<void> saveSelectedServiceId(String? serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      ...?_expireIfDue(prefs),
      if (serviceId == null)
        prefs.remove(selectedServiceKey)
      else
        prefs.setString(selectedServiceKey, serviceId),
      _extend(prefs),
    ]);
  }
}
