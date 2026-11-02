import '../../../../core/constants/app_strings.dart';
import '../../../../core/error/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login({
    required String username,
    required String password,
  });
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  const AuthRemoteDataSourceImpl();

  @override
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      throw const ServerException(AppStrings.usernameAndPasswordRequired);
    }
    return UserModel(id: trimmed, username: trimmed);
  }
}
