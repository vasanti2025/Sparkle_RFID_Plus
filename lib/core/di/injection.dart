import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login.dart';
import '../../features/quotation/data/datasources/quotation_remote_data_source.dart';
import '../../features/quotation/data/repositories/quotation_repository_impl.dart';
import '../../features/quotation/domain/repositories/quotation_repository.dart';
import '../../features/settings/data/datasources/settings_local_data_source.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/presentation/settings_controller.dart';
import '../network/api_client.dart';

class Injection {
  Injection._();

  static late final Login login;
  static late final SettingsController settings;
  static late final QuotationRepository quotations;

  static Future<void> init() async {
    const remote = AuthRemoteDataSourceImpl();
    const local = AuthLocalDataSourceImpl();
    const AuthRepository repository = AuthRepositoryImpl(
      remoteDataSource: remote,
      localDataSource: local,
    );
    login = Login(repository);
    settings = SettingsController(
      SettingsRepositoryImpl(SettingsLocalDataSource()),
    );
    await settings.load();
    quotations = QuotationRepositoryImpl(
      QuotationRemoteDataSource(ApiClient()),
    );
  }
}
