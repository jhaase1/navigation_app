import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/role.dart';

class RoleStore {
  static const String _key = 'roles';

  static Future<List<Role>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Role.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<Role> roles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(roles.map((r) => r.toJson()).toList()));
  }
}
