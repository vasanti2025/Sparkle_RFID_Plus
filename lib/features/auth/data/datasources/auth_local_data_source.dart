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

  Future<void> saveSessionCredentials({
    required String username,
    required String password,
  });

  Future<({String username, String password})?> readSessionCredentials();

  Future<void> saveRememberedPassword(String password);

  Future<void> clearRememberedPassword();

  Future<String?> readRememberedPassword();

  Future<void> saveSessionCredentials({
    required String username,
    required String password,
  });

  Future<({String username, String password})?> readSessionCredentials();
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
  static const _blobKey = 'auth_session_blob';
  static const _loggedInKey = 'auth_keep_signed_in';
  static const _sessionUserKey = 'auth_session_username';
  static const _sessionPassKey = 'auth_session_password';

  @override
  Future<void> saveSession(UserModel user) async {
    final encoded = jsonEncode(user.toJson());
    await _preferences.setString(_blobKey, encoded);
    await _preferences.setBool(_loggedInKey, true);
    try {
      await _secure.write(key: _secureUserKey, value: encoded);
    } catch (_) {}
    await _wipeLegacySecrets();
  }

  @override
  Future<UserModel?> readSession() async {
    if (_preferences.getBool(_loggedInKey) == false) return null;
    String? secureValue;
    try {
      secureValue = await _secure.read(key: _secureUserKey);
    } catch (_) {}
    final user = _decode(secureValue) ??
        _decode(_preferences.getString(_blobKey)) ??
        await _migrateLegacySession();
    if (user == null || user.token.isEmpty || user.username.isEmpty) {
      return null;
    }
    if (_preferences.getBool(_loggedInKey) != true) {
      await _preferences.setBool(_loggedInKey, true);
      await _preferences.setString(_blobKey, jsonEncode(user.toJson()));
    }
    return user;
  }

  @override
  Future<void> clearSession() async {
    await _preferences.setBool(_loggedInKey, false);
    await _preferences.remove(_blobKey);
    await _preferences.remove(_sessionUserKey);
    await _preferences.remove(_sessionPassKey);
    try {
      await _secure.delete(key: _secureUserKey);
    } catch (_) {}
    await _wipeLegacySecrets();
  }

  @override
  Future<void> saveRememberedUsername(String username) async {
    await _preferences.setString(_usernameKey, username);
  }

  @override
  Future<void> clearRememberedUsername() async {
    await _preferences.remove(_usernameKey);
  }

  @override
  Future<String?> readRememberedUsername() async {
    final username = _preferences.getString(_usernameKey);
    if (username == null || username.isEmpty) return null;
    return username;
  }

  @override
  Future<void> saveRememberedPassword(String password) async {
    await _preferences.setString(_passwordKey, password);
  }

  @override
  Future<void> clearRememberedPassword() async {
    await _preferences.remove(_passwordKey);
  }

  @override
  Future<String?> readRememberedPassword() async {
    final password = _preferences.getString(_passwordKey);
    if (password == null || password.isEmpty) return null;
    return password;
  }

  @override
  Future<void> saveSessionCredentials({
    required String username,
    required String password,
  }) async {
    await _preferences.setString(_sessionUserKey, username);
    await _preferences.setString(_sessionPassKey, password);
  }

  @override
  Future<({String username, String password})?> readSessionCredentials() async {
    if (_preferences.getBool(_loggedInKey) == false) return null;
    final username = _preferences.getString(_sessionUserKey) ?? '';
    final password = _preferences.getString(_sessionPassKey) ?? '';
    if (username.isEmpty || password.isEmpty) return null;
    return (username: username, password: password);
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

}

/// A token stays usable until its expiry is known and already past.
/// Decode failures do not sign the user out.
bool authTokenUsable(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return true;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return true;
    final exp = decoded['exp'];
    final seconds = exp is num ? exp.toInt() : int.tryParse('$exp');
    if (seconds == null) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );
    return DateTime.now().toUtc().isBefore(
      expiry.subtract(const Duration(seconds: 30)),
    );
  } catch (_) {
    return true;
  static const _passwordKey = 'remembered_password';
  static const _blobKey = 'auth_session_blob';
  static const _loggedInKey = 'auth_keep_signed_in';
  static const _sessionUserKey = 'auth_session_username';
  static const _sessionPassKey = 'auth_session_password';
    final encoded = jsonEncode(user.toJson());
    await _preferences.setString(_blobKey, encoded);
    await _preferences.setBool(_loggedInKey, true);
    try {
      await _secure.write(key: _secureUserKey, value: encoded);
    } catch (_) {}
    if (_preferences.getBool(_loggedInKey) == false) return null;
    String? secureValue;
    try {
      secureValue = await _secure.read(key: _secureUserKey);
    } catch (_) {}
    final user = _decode(secureValue) ??
        _decode(_preferences.getString(_blobKey)) ??
        await _migrateLegacySession();
    if (_preferences.getBool(_loggedInKey) != true) {
      await _preferences.setBool(_loggedInKey, true);
      await _preferences.setString(_blobKey, jsonEncode(user.toJson()));
    await _preferences.setBool(_loggedInKey, false);
    await _preferences.remove(_blobKey);
    await _preferences.remove(_sessionUserKey);
    await _preferences.remove(_sessionPassKey);
    try {
      await _secure.delete(key: _secureUserKey);
    } catch (_) {}
  @override
  Future<void> saveRememberedPassword(String password) async {
    await _preferences.setString(_passwordKey, password);
  }

  @override
  Future<void> clearRememberedPassword() async {
    await _preferences.remove(_passwordKey);
  }

  @override
  Future<String?> readRememberedPassword() async {
    final password = _preferences.getString(_passwordKey);
    if (password == null || password.isEmpty) return null;
    return password;
  }

  @override
  Future<void> saveSessionCredentials({
    required String username,
    required String password,
  }) async {
    await _preferences.setString(_sessionUserKey, username);
    await _preferences.setString(_sessionPassKey, password);
  }

  @override
  Future<({String username, String password})?> readSessionCredentials() async {
    if (_preferences.getBool(_loggedInKey) == false) return null;
    final username = _preferences.getString(_sessionUserKey) ?? '';
    final password = _preferences.getString(_sessionPassKey) ?? '';
    if (username.isEmpty || password.isEmpty) return null;
    return (username: username, password: password);
  }

}

/// A token stays usable until its expiry is known and already past.
/// Decode failures do not sign the user out.
bool authTokenUsable(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return true;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return true;
    final exp = decoded['exp'];
    final seconds = exp is num ? exp.toInt() : int.tryParse('$exp');
    if (seconds == null) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );
    return DateTime.now().toUtc().isBefore(
      expiry.subtract(const Duration(seconds: 30)),
    );
  } catch (_) {
    return true;
  }
}
