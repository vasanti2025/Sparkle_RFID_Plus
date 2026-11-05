import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_preferences.dart';

class SettingsLocalDataSource {
  static const _enablePos = 'enable_pos';

  Future<AppPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('client_code');
    await prefs.remove('user_id');
    return AppPreferences(enablePos: prefs.getBool(_enablePos) ?? false);
  }

  Future<void> save(AppPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enablePos, preferences.enablePos);
  }
}
