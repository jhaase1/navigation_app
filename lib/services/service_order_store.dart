import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/service_order.dart';

class ServiceOrderStore {
  static const String _key = 'service_orders';

  static Future<List<ServiceOrder>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ServiceOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAll(List<ServiceOrder> orders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(orders.map((o) => o.toJson()).toList()));
  }
}
