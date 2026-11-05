import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/error/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login({required String username, required String password});
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConstants.qaBaseUrl,
              connectTimeout: const Duration(seconds: 25),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 25),
              contentType: Headers.jsonContentType,
            ),
          );

  final Dio _dio;

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        AppConstants.loginPath,
        data: {'username': username, 'password': password},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return UserModel.fromLoginJson(data);
      }
      if (data is Map) {
        return UserModel.fromLoginJson(Map<String, dynamic>.from(data));
      }
      throw const ServerException(AppStrings.loginFailed);
    } on ServerException {
      rethrow;
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  Exception _fromDio(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const NetworkException(AppStrings.connectionTimedOut);
    }
    if (error.type == DioExceptionType.connectionError) {
      return const NetworkException();
    }
    final data = error.response?.data;
    if (data is Map) {
      final message = UserModel.messageOf(Map<String, dynamic>.from(data));
      if (message != null) return ServerException(message);
    }
    if (data is String && data.trim().isNotEmpty) {
      return ServerException(data.trim());
    }
    return const ServerException(AppStrings.loginFailed);
  }
}
