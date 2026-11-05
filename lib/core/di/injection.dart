import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/get_remembered_username.dart';
import '../../features/auth/domain/usecases/login.dart';
import '../../features/quotation/data/datasources/quotation_remote_data_source.dart';
import '../../features/quotation/data/repositories/quotation_repository_impl.dart';
import '../../features/quotation/domain/repositories/quotation_repository.dart';
import '../../features/settings/data/datasources/settings_local_data_source.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/presentation/settings_controller.dart';
import '../network/api_client.dart';
import '../../features/auth/domain/usecases/restore_session.dart';
import '../../features/auth/domain/usecases/sign_out.dart';
import '../../features/products/data/datasources/product_local_data_source.dart';
import '../../features/products/data/datasources/product_remote_data_source.dart';
import '../../features/products/data/repositories/product_repository_impl.dart';
import '../../features/products/domain/repositories/product_repository.dart';
import '../../features/products/domain/usecases/restore_stored_records.dart';
import '../../features/products/domain/usecases/search_stored_records.dart';
import '../../features/products/domain/usecases/sync_products.dart';
import '../../features/products/presentation/product_sync_controller.dart';

class Injection {
  Injection._();

  static bool ready = false;
  static late final Login login;
  static late final SettingsController settings;
  static late final QuotationRepository quotations;
  static late final GetRememberedUsername rememberedUsername;
  static late final RestoreSession restoreSession;
  static late final SignOut signOut;
  static late final ProductSyncController productSync;
  static late final SearchStoredRecords searchStoredRecords;
  static late final RestoreStoredRecords restoreStoredRecords;

  static Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();
    final remote = AuthRemoteDataSourceImpl();
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        resetOnError: true,
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    final local = AuthLocalDataSourceImpl(preferences, secure);
    final AuthRepository repository = AuthRepositoryImpl(
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
    rememberedUsername = GetRememberedUsername(repository);
    restoreSession = RestoreSession(repository);
    signOut = SignOut(repository);
    final ProductRepository products = ProductRepositoryImpl(
      remoteDataSource: ProductRemoteDataSourceImpl(),
      localDataSource: ProductLocalDataSourceImpl(),
    );
    productSync = ProductSyncController(SyncProducts(products));
    searchStoredRecords = SearchStoredRecords(products);
    restoreStoredRecords = RestoreStoredRecords(products);
    ready = true;
  }
}
