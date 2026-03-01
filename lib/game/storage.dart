import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BestStorage {
  static const _key = 'gg_best_100';

  static Future<Map<String, int>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        if (k is String && v is num) out[k] = v.toInt();
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, int> map) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(map));
    } catch (_) {}
  }
}