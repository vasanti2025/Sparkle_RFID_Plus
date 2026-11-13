import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> saveSession(UserModel user);

  Future<UserModel?> readSession();

  Future<void> clearSession();

  Future<void> saveRememberedUsername(String username);

  Future<void> clearRememberedUsername();

  Future<String?> readRememberedUsername();

  Future<void> saveRememberedPassword(String password);

  Future<void> clearRememberedPassword();

  Future<String?> readRememberedPassword();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  const AuthLocalDataSourceImpl(this._preferences, this._secure);

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secure;

  static const _secureUserKey = 'auth_user';
  static const _legacyTokenKey = 'auth_token';
  static const _legacySessionKey = 'auth_session';
  static const _legacyUserKey = 'auth_user';
  static const _legacyLoggedInKey = 'auth_logged_in';
  static const _usernameKey = 'remembered_username';
  static const _passwordKey = 'remembered_password';

  @override
  Future<void> saveSession(UserModel user) async {
    await _secure.write(key: _secureUserKey, value: jsonEncode(user.toJson()));
    await _wipeLegacySecrets();
  }

  @override
  Future<UserModel?> readSession() async {
    final stored = await _secure.read(key: _secureUserKey);
    final user = _decode(stored) ?? await _migrateLegacySession();
    if (user == null || user.token.isEmpty || user.username.isEmpty) {
      return null;
    }
    if (!_tokenUsable(user.token)) {
      await clearSession();
      return null;
    }
    return user;
  }

  @override
  Future<void> clearSession() async {
    await _secure.delete(key: _secureUserKey);
    await _wipeLegacySecrets();
  }

  @override
  Future<void> saveRememberedUsername(String username) async {
    await _preferences.setString(_usernameKey, username);
  }

  @override
  Future<void> clearRememberedUsername() async {
    await _preferences.remove(_usernameKey);
    await clearRememberedPassword();
  }

  @override
  Future<String?> readRememberedUsername() async {
    final username = _preferences.getString(_usernameKey);
    if (username == null || username.isEmpty) return null;
    return username;
  }

  @override
  Future<void> saveRememberedPassword(String password) async {
    await _secure.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clearRememberedPassword() async {
    await _secure.delete(key: _passwordKey);
  }

  @override
  Future<String?> readRememberedPassword() async {
    final password = await _secure.read(key: _passwordKey);
    if (password == null || password.isEmpty) return null;
    return password;
  }

  Future<UserModel?> _migrateLegacySession() async {
    final legacy = _decode(_preferences.getString(_legacyUserKey));
    if (legacy == null || legacy.token.isEmpty) {
      await _wipeLegacySecrets();
      return null;
    }
    await saveSession(legacy);
    return legacy;
  }

  UserModel? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return UserModel.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> _wipeLegacySecrets() async {
    await _preferences.remove(_legacyTokenKey);
    await _preferences.remove(_legacySessionKey);
    await _preferences.remove(_legacyUserKey);
    await _preferences.remove(_legacyLoggedInKey);
  }

  bool _tokenUsable(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return false;
      final exp = decoded['exp'];
      if (exp is! num) return true;
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      return DateTime.now().toUtc().isBefore(
        expiry.subtract(const Duration(seconds: 30)),
      );
    } catch (_) {
      return false;
    }
  }
}
