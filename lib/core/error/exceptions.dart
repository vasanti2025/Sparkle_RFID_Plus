import '../constants/app_strings.dart';

class ServerException implements Exception {
  const ServerException([this.message = AppStrings.serverError]);

  final String message;
}

class CacheException implements Exception {
  const CacheException([this.message = AppStrings.cacheError]);

  final String message;
}

class NetworkException implements Exception {
  const NetworkException([this.message = AppStrings.noInternet]);

  final String message;
}
