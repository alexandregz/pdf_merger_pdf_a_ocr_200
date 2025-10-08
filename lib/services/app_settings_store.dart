import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class AppSettingsStore {
  static const _kKey = 'app_settings_v1';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kKey);
    if (str == null || str.isEmpty) return const AppSettings();
    try {
      final map = jsonDecode(str) as Map<String, Object?>;
      return AppSettings.fromJson(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(s.toJson()));
  }
}
