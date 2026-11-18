import 'package:flutter/foundation.dart';

import '../domain/entities/app_preferences.dart';
import '../domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;
  AppPreferences preferences = AppPreferences.empty;

  bool get enablePos => preferences.enablePos;

  bool get localWifiMode => preferences.localWifiMode;

  String get language => preferences.language;

  String get sheetUrl => preferences.sheetUrl;

  Future<void> load() async {
    preferences = await _repository.load();
    notifyListeners();
  }

  Future<void> setEnablePos(bool value) async {
    preferences = preferences.copyWith(enablePos: value);
    notifyListeners();
    await _repository.save(preferences);
  }

  Future<void> setLocalWifiMode(bool value) async {
    preferences = preferences.copyWith(localWifiMode: value);
    notifyListeners();
    await _repository.save(preferences);
  }

  Future<void> setLanguage(String value) async {
    final language = value == 'hi' || value == 'ar' ? value : 'en';
    preferences = preferences.copyWith(language: language);
    notifyListeners();
    await _repository.save(preferences);
  }

  Future<void> setSheetUrl(String value) async {
    preferences = preferences.copyWith(sheetUrl: value.trim());
    notifyListeners();
    await _repository.save(preferences);
  }
}
