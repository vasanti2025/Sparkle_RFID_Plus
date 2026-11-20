import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;

  @override
  Future<Result<User>> login({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    try {
      final user = await remoteDataSource.login(
        username: username,
        password: password,
      );
      await localDataSource.saveSession(user);
      await localDataSource.saveSessionCredentials(
        username: username,
        password: password,
      );
      if (rememberMe) {
        await localDataSource.saveRememberedUsername(username);
        await localDataSource.saveRememberedPassword(password);
      } else {
        await localDataSource.clearRememberedUsername();
        await localDataSource.clearRememberedPassword();
      }
      return Success(user);
    } on ServerException catch (error) {
      return Error(ServerFailure(error.message));
    } on CacheException catch (error) {
      return Error(CacheFailure(error.message));
    } on NetworkException catch (error) {
      return Error(NetworkFailure(error.message));
    }
  }

  @override
  Future<String?> rememberedUsername() {
    return localDataSource.readRememberedUsername();
  }

  @override
  Future<String?> rememberedPassword() {
    return localDataSource.readRememberedPassword();
  }

  @override
  Future<User?> restoreSession() async {
    final user = await localDataSource.readSession();
    if (user != null && authTokenUsable(user.token)) return user;
    final saved = await localDataSource.readSessionCredentials();
    if (saved == null) return user;
    try {
      final fresh = await remoteDataSource.login(
        username: saved.username,
        password: saved.password,
      );
      await localDataSource.saveSession(fresh);
      await localDataSource.saveSessionCredentials(
        username: saved.username,
        password: saved.password,
      );
      return fresh;
    } catch (_) {
      return user;
    }
  }

  @override
  Future<void> signOut() {
    return localDataSource.clearSession();
  }
}
