import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Saved server for the whole app. Blank keeps the QA host.
class ApiHost {
  ApiHost._();

  static const _key = 'custom_api_url';
  static String _custom = '';

  static String get base {
    final value = _custom.trim();
    if (value.isEmpty) return AppConstants.qaBaseUrl;
    return value;
  }

  /// Address shown in Configure Custom API. QA until the user saves another.
  static String get saved => base;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _custom = normalize(prefs.getString(_key) ?? '') ?? '';
  }

  /// Empty input clears the custom server. A bad address returns null.
  static String? normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    var value = trimmed;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  static Future<bool> save(String raw) async {
    final next = normalize(raw);
    if (next == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final stored = next.isEmpty || _same(next, AppConstants.qaBaseUrl) ? '' : next;
    _custom = stored;
    if (stored.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, stored);
    }
    return true;
  }

  static bool _same(String left, String right) {
    return left.replaceAll(RegExp(r'/+$'), '').toLowerCase() ==
        right.replaceAll(RegExp(r'/+$'), '').toLowerCase();
  }
}
