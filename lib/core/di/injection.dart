import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login.dart';

class Injection {
  Injection._();

  static late final Login login;

  static Future<void> init() async {
    const remote = AuthRemoteDataSourceImpl();
    const local = AuthLocalDataSourceImpl();
    const AuthRepository repository = AuthRepositoryImpl(
      remoteDataSource: remote,
      localDataSource: local,
    );
    login = Login(repository);
  }
}
