import 'package:flutter/foundation.dart';

import '../domain/entities/app_preferences.dart';
import '../domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;
  AppPreferences preferences = AppPreferences.empty;

  bool get enablePos => preferences.enablePos;

  Future<void> load() async {
    preferences = await _repository.load();
    notifyListeners();
  }

  Future<void> setEnablePos(bool value) async {
    preferences = preferences.copyWith(enablePos: value);
    notifyListeners();
    await _repository.save(preferences);
  }
}
