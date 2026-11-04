import '../entities/app_preferences.dart';

abstract class SettingsRepository {
  Future<AppPreferences> load();

  Future<void> save(AppPreferences preferences);
}
