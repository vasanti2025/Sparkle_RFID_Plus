import '../../../auth/domain/entities/user.dart';
import '../../domain/entities/product_sync_progress.dart';
import '../../domain/entities/stored_record.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_local_data_source.dart';
import '../datasources/product_remote_data_source.dart';

class ProductRepositoryImpl implements ProductRepository {
  const ProductRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  final ProductRemoteDataSource remoteDataSource;
  final ProductLocalDataSource localDataSource;

  @override
  Stream<ProductSyncProgress> syncProducts(User user) async* {
    final directory = await localDataSource.syncDirectory();
    await for (final event in remoteDataSource.sync(
      token: user.token,
      clientCode: user.clientCode,
      roleId: user.roleId,
      branchIds: user.roleId == 1 || user.branchId <= 0
          ? const <int>[]
          : <int>[user.branchId],
      directory: directory,
    )) {
      if (event.failed) {
        yield event;
        return;
      }
      if (!event.completed) {
        final fraction = event.fraction;
        yield ProductSyncProgress(
          message: event.message,
          fraction: fraction == null ? null : fraction * 0.8,
          received: event.received,
          total: event.total,
        );
        continue;
      }
      yield* localDataSource.storeDownloaded(directory);
    }
  }

  @override
  Future<List<StoredRecord>> searchStored({
    String kind = StoredRecord.kindProduct,
    String query = '',
    int limit = 50,
    int offset = 0,
  }) {
    return localDataSource.search(
      kind: kind,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<StoredRecord>> restoreStored({
    String kind = StoredRecord.kindProduct,
    int limit = 100,
    int offset = 0,
  }) {
    return localDataSource.search(kind: kind, limit: limit, offset: offset);
  }

  @override
  Future<int> storedCount({String kind = StoredRecord.kindProduct}) {
    return localDataSource.count(kind: kind);
  }
}
