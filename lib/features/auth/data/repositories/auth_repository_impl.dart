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
      if (rememberMe) {
        await localDataSource.cacheUser(user);
      } else {
        await localDataSource.clear();
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
}
