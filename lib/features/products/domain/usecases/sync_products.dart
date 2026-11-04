import '../../../auth/domain/entities/user.dart';
import '../entities/product_sync_progress.dart';
import '../repositories/product_repository.dart';

class SyncProducts {
  const SyncProducts(this.repository);

  final ProductRepository repository;

  Stream<ProductSyncProgress> call(User user) => repository.syncProducts(user);
}
