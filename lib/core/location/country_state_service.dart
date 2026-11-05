import 'dart:convert';

import 'package:http/http.dart' as http;

/// Countries and states from the public Countries Now API.
class CountryStateService {
  CountryStateService._();

  static const _countriesUrl = 'https://countriesnow.space/api/v0.1/countries/iso';
  static const _statesUrl = 'https://countriesnow.space/api/v0.1/countries/states/q';
  static const _statesPostUrl = 'https://countriesnow.space/api/v0.1/countries/states';

  static List<String>? _countriesCache;
  static final Map<String, List<String>> _statesCache = {};

  static Future<List<String>> fetchCountries() async {
    if (_countriesCache != null && _countriesCache!.isNotEmpty) {
      return List<String>.from(_countriesCache!);
    }
    final response = await http.get(Uri.parse(_countriesUrl)).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Countries API ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['error'] == true) {
      throw Exception('Countries API error');
    }
    final data = decoded['data'];
    if (data is! List) throw Exception('Countries API missing data');
    final names = <String>[];
    for (final row in data) {
      if (row is! Map) continue;
      final name = '${row['name'] ?? ''}'.trim();
      if (name.isNotEmpty) names.add(name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _countriesCache = names;
    return List<String>.from(names);
  }

  static Future<List<String>> fetchStates(String country) async {
    final key = country.trim();
    if (key.isEmpty) return const [];
    final cached = _statesCache[key];
    if (cached != null) return List<String>.from(cached);

    http.Response response;
    try {
      final uri = Uri.parse(_statesUrl).replace(queryParameters: {'country': key});
      response = await http.get(uri).timeout(const Duration(seconds: 25));
    } catch (_) {
      response = await http
          .post(
            Uri.parse(_statesPostUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'country': key}),
          )
          .timeout(const Duration(seconds: 25));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('States API ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['error'] == true) {
      throw Exception('States API error');
    }
    final data = decoded['data'];
    final raw = data is Map ? data['states'] : data;
    final names = <String>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) {
          final name = '${row['name'] ?? ''}'.trim();
          if (name.isNotEmpty) names.add(name);
        } else if (row is String && row.trim().isNotEmpty) {
          names.add(row.trim());
        }
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _statesCache[key] = names;
    return List<String>.from(names);
  }
}
