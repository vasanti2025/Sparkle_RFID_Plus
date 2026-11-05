import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../error/exceptions.dart';
import '../session/app_session.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await _send(path, body, timeout);
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Raw JSON for large catalogues. Decode it off the UI isolate.
  Future<String> postRaw(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    return (await _send(path, body, timeout)).body;
  }

  Future<http.Response> _send(
    String path,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final uri = Uri.parse('${AppConstants.qaBaseUrl}$path');
    try {
      final token = AppSession.token;
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ServerException('QA API ${response.statusCode}');
      }
      return response;
    } on ServerException {
      rethrow;
    } catch (error) {
      throw ServerException(error.toString());
    }
  }
}
