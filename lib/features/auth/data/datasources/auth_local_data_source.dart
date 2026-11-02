import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheUser(UserModel user);

  Future<UserModel?> getCachedUser();

  Future<void> clear();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  const AuthLocalDataSourceImpl();

  static UserModel? _cached;

  @override
  Future<void> cacheUser(UserModel user) async {
    _cached = user;
  }

  @override
  Future<UserModel?> getCachedUser() async => _cached;

  @override
  Future<void> clear() async {
    _cached = null;
  }
}
