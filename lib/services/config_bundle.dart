import 'dart:convert';
import 'dart:io';

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

  const ConfigBundle({
    required this.scenes,
    required this.people,
    required this.roles,
    required this.orders,
  });

  Map<String, dynamic> toJson() => {
        'scenes': scenes.map((s) => s.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'roles': roles.map((r) => r.toJson()).toList(),
        'serviceOrders': orders.map((o) => o.toJson()).toList(),
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
      );

  static Future<ConfigBundle> fromStores() async {
    final results = await Future.wait([
      SceneStore.loadAll(),
      PeopleStore.loadAll(),
      RoleStore.loadAll(),
      ServiceOrderStore.loadAll(),
    ]);
    return ConfigBundle(
      scenes: results[0] as List<Scene>,
      people: results[1] as List<Person>,
      roles: results[2] as List<Role>,
      orders: results[3] as List<ServiceOrder>,
    );
  }

  Future<void> saveToStores() => Future.wait([
        SceneStore.saveAll(scenes),
        PeopleStore.saveAll(people),
        RoleStore.saveAll(roles),
        ServiceOrderStore.saveAll(orders),
      ]).then((_) {});

  /// Suggested default export path using the platform Documents folder.
  static String suggestedExportPath() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final filename = 'nav_config_$stamp.json';
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
  static Future<void> writeToPath(String path, ConfigBundle bundle) =>
      File(path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle.toJson()),
      );

  /// Reads and parses a bundle from [path]. Throws [FormatException] if the
  /// content is not a valid configuration object.
  static Future<ConfigBundle> readFromPath(String path) async {
    final content = await File(path).readAsString();
    final json = jsonDecode(content);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Not a valid configuration file');
    }
    return ConfigBundle.fromJson(json);
  }
}
