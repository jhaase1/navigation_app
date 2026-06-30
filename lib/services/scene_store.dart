import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scene.dart';

class SceneStore {
  static const String _key = 'scenes';

  static Future<List<Scene>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Scene.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<Scene> scenes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(scenes.map((s) => s.toJson()).toList()));
  }
}
