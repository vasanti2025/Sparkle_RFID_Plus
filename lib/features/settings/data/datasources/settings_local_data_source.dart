import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_preferences.dart';

class SettingsLocalDataSource {
  static const _enablePos = 'enable_pos';
  static const _clientCode = 'client_code';
  static const _userId = 'user_id';

  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      enablePos: prefs.getBool(_enablePos) ?? false,
      clientCode: prefs.getString(_clientCode) ?? '',
      userId: prefs.getString(_userId) ?? '',
    );
  }

  Future<void> save(AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enablePos, preferences.enablePos);
    await prefs.setString(_clientCode, preferences.clientCode);
    await prefs.setString(_userId, preferences.userId);
  }
}
