import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/person.dart';
import '../models/role.dart';
import '../models/scene.dart';
import '../models/service_order.dart';
import 'people_store.dart';
import 'role_store.dart';
import 'scene_store.dart';
import 'service_order_store.dart';

class ConfigBundle {
  final List<Scene> scenes;
  final List<Person> people;
  final List<Role> roles;
  final List<ServiceOrder> orders;

  /// Preset/macro names keyed by device storage key (camera IP or `roland_<ip>`),
  /// then by item index string → custom name.
  final Map<String, Map<String, String>> presetNames;

  /// Item visibility keyed by device storage key, then item index string →
  /// visibility name (matches [ItemVisibility.name]).
  final Map<String, Map<String, String>> visibilities;

  const ConfigBundle({
    required this.scenes,
    required this.people,
    required this.roles,
    required this.orders,
    this.presetNames = const {},
    this.visibilities = const {},
  });

  Map<String, dynamic> toJson() => {
        'scenes': scenes.map((s) => s.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'roles': roles.map((r) => r.toJson()).toList(),
        'serviceOrders': orders.map((o) => o.toJson()).toList(),
        if (presetNames.isNotEmpty) 'presetNames': presetNames,
        if (visibilities.isNotEmpty) 'visibilities': visibilities,
      };

  factory ConfigBundle.fromJson(Map<String, dynamic> json) => ConfigBundle(
        scenes: (json['scenes'] as List<dynamic>? ?? [])
            .map((s) => Scene.fromJson(s as Map<String, dynamic>))
            .toList(),
        people: (json['people'] as List<dynamic>? ?? [])
            .map((p) => Person.fromJson(p as Map<String, dynamic>))
            .toList(),
        roles: (json['roles'] as List<dynamic>? ?? [])
            .map((r) => Role.fromJson(r as Map<String, dynamic>))
            .toList(),
        orders: (json['serviceOrders'] as List<dynamic>? ?? [])
            .map((o) => ServiceOrder.fromJson(o as Map<String, dynamic>))
            .toList(),
        presetNames: _parseStringStringMaps(json['presetNames']),
        visibilities: _parseStringStringMaps(json['visibilities']),
      );

  static Map<String, Map<String, String>> _parseStringStringMaps(dynamic raw) {
    if (raw is! Map<String, dynamic>) return {};
    return raw.map((deviceKey, inner) {
      if (inner is! Map<String, dynamic>) {
        return MapEntry(deviceKey, <String, String>{});
      }
      return MapEntry(
        deviceKey,
        inner.map((k, v) => MapEntry(k, v as String)),
      );
    });
  }

  static const _presetPrefix = 'preset_names_';
  static const _visibilityPrefix = 'item_visibility_';

  static Future<ConfigBundle> fromStores() async {
    final results = await Future.wait([
      SceneStore.loadAll(),
      PeopleStore.loadAll(),
      RoleStore.loadAll(),
      ServiceOrderStore.loadAll(),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final presetNames = <String, Map<String, String>>{};
    final visibilities = <String, Map<String, String>>{};

    for (final key in prefs.getKeys()) {
      if (key.startsWith(_presetPrefix)) {
        final deviceKey = key.substring(_presetPrefix.length);
        final raw = prefs.getString(key);
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          presetNames[deviceKey] =
              decoded.map((k, v) => MapEntry(k, v as String));
        }
      } else if (key.startsWith(_visibilityPrefix)) {
        final deviceKey = key.substring(_visibilityPrefix.length);
        final raw = prefs.getString(key);
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          visibilities[deviceKey] =
              decoded.map((k, v) => MapEntry(k, v as String));
        }
      }
    }

    return ConfigBundle(
      scenes: results[0] as List<Scene>,
      people: results[1] as List<Person>,
      roles: results[2] as List<Role>,
      orders: results[3] as List<ServiceOrder>,
      presetNames: presetNames,
      visibilities: visibilities,
    );
  }

  Future<void> saveToStores() async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      SceneStore.saveAll(scenes),
      PeopleStore.saveAll(people),
      RoleStore.saveAll(roles),
      ServiceOrderStore.saveAll(orders),
    ]);

    for (final entry in presetNames.entries) {
      await prefs.setString(
          '$_presetPrefix${entry.key}', jsonEncode(entry.value));
    }
    for (final entry in visibilities.entries) {
      await prefs.setString(
          '$_visibilityPrefix${entry.key}', jsonEncode(entry.value));
    }
  }

  /// Suggested default export path using the platform Documents folder.
  /// Returns just the filename on web (file I/O is not supported there).
  static String suggestedExportPath() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final filename = 'nav_config_$stamp.json';
    if (kIsWeb) return filename;
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) return '$home\\Documents\\$filename';
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) return '$home/Documents/$filename';
    }
    return filename;
  }

  /// Writes this bundle to [path] as indented JSON. Throws on I/O error.
  static Future<void> writeToPath(String path, ConfigBundle bundle) {
    if (kIsWeb) {
      return Future.error(
          UnsupportedError('File export is not supported on web'));
    }
    return File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle.toJson()),
    );
  }

  /// Reads and parses a bundle from [path]. Throws [FormatException] if the
  /// content is not a valid configuration object.
  static Future<ConfigBundle> readFromPath(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('File import is not supported on web');
    }
    final content = await File(path).readAsString();
    final json = jsonDecode(content);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Not a valid configuration file');
    }
    return ConfigBundle.fromJson(json);
  }
}
