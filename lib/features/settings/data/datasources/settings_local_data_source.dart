import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_preferences.dart';

class SettingsLocalDataSource {
  static const _enablePos = 'enable_pos';
  static const _localWifi = 'local_wifi_mode';
  static const _language = 'app_language';
  static const _sheetUrl = 'sheet_url';

  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('client_code');
    await prefs.remove('user_id');
    final language = prefs.getString(_language) ?? 'en';
    return AppPreferences(
      enablePos: prefs.getBool(_enablePos) ?? false,
      localWifiMode: prefs.getBool(_localWifi) ?? false,
      language: language == 'hi' || language == 'ar' ? language : 'en',
      sheetUrl: prefs.getString(_sheetUrl) ?? '',
    );
  }

  Future<void> save(AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enablePos, preferences.enablePos);
    await prefs.setBool(_localWifi, preferences.localWifiMode);
    await prefs.setString(_language, preferences.language);
    await prefs.setString(_sheetUrl, preferences.sheetUrl);
  }
}
